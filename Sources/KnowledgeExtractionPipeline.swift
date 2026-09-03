import Foundation

protocol KnowledgeExtractionClient: Sendable {
    func complete(systemPrompt: String,
                  userPrompt: String,
                  maxTokens: Int) async throws -> String
}

struct RefineKnowledgeExtractionClient: KnowledgeExtractionClient {
    func complete(systemPrompt: String,
                  userPrompt: String,
                  maxTokens: Int) async throws -> String {
        try await Task.detached(priority: .utility) {
            try Refine.chatOnce(system: systemPrompt, user: userPrompt, maxTokens: maxTokens)
        }.value
    }
}

struct KnowledgeMeetingMetadata: Sendable {
    let title: String
    let dateLabel: String?
}

struct KnowledgeExtractionPipeline {
    private let store: KnowledgeStore
    private let client: any KnowledgeExtractionClient
    private let meetingMetadata: @Sendable (String) -> KnowledgeMeetingMetadata
    private let includeRestrictedForCurrentRun: Bool
    private let modelName: String
    private let clock: @Sendable () -> TimeInterval

    init(store: KnowledgeStore = .shared,
         client: any KnowledgeExtractionClient = RefineKnowledgeExtractionClient(),
         meetingMetadata: @escaping @Sendable (String) -> KnowledgeMeetingMetadata = {
             KnowledgeMeetingMetadata(title: $0, dateLabel: nil)
         },
         includeRestrictedForCurrentRun: Bool = false,
         modelName: String = Refine.model,
         clock: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSince1970 }) {
        self.store = store
        self.client = client
        self.meetingMetadata = meetingMetadata
        self.includeRestrictedForCurrentRun = includeRestrictedForCurrentRun
        self.modelName = modelName
        self.clock = clock
    }

    func execute(_ job: KnowledgeExtractionJob) async throws -> Int {
        guard job.extractorVersion == KnowledgeExtractionPrompt.extractorVersion else {
            throw KnowledgeExtractionError.permanent("抽取器版本不匹配")
        }
        guard let source = store.sources().first(where: { $0.id == job.sourceID }) else {
            throw KnowledgeExtractionError.permanent("知识来源不存在")
        }
        guard source.contentHash == job.inputHash else {
            throw KnowledgeExtractionError.permanent("知识来源内容已变化，请重新排队")
        }
        guard KnowledgePrivacyPolicy.maySendToCloud(
            source.sensitivity,
            includeRestrictedForCurrentRequest: includeRestrictedForCurrentRun)
        else {
            throw KnowledgeExtractionError.permanent("敏感来源未获得本次处理授权")
        }
        let segments = store.segments(sourceID: source.id)
        guard !segments.isEmpty else {
            throw KnowledgeExtractionError.permanent("知识来源没有可处理片段")
        }
        let chunks = KnowledgeExtractionChunker.chunks(from: segments)
        guard job.cursor <= chunks.count else {
            throw KnowledgeExtractionError.permanent("任务断点超出当前分块范围")
        }
        if job.cursor == chunks.count { return chunks.count }
        let metadata = meetingMetadata(source.meetingID)

        for chunk in chunks.dropFirst(job.cursor) {
            try Task.checkCancellation()
            let prompt = KnowledgeExtractionPrompt.userPrompt(
                sourceHash: source.contentHash,
                chunkIndex: chunk.index,
                meetingTitle: metadata.title,
                meetingDate: metadata.dateLabel,
                segments: chunk.segments,
                coreSegmentIDs: chunk.coreSegmentIDs)
            let started = clock()
            var outputCharacters = 0
            var candidateCount = 0
            var acceptedCount = 0
            var invalidEvidenceCount = 0
            do {
                let raw = try await client.complete(
                    systemPrompt: KnowledgeExtractionPrompt.system,
                    userPrompt: prompt,
                    maxTokens: 4_000)
                outputCharacters = raw.count
                let envelope: KnowledgeExtractionEnvelope
                do {
                    envelope = try KnowledgeExtractionSchema.decode(
                        raw,
                        expectedSourceHash: source.contentHash,
                        expectedChunkIndex: chunk.index)
                } catch {
                    throw KnowledgeExtractionError.invalidResponse(error.localizedDescription)
                }
                candidateCount = envelope.units.count
                let validation = KnowledgeEvidenceValidator.validate(
                    envelope,
                    chunk: chunk,
                    expectedSourceID: source.id)
                invalidEvidenceCount = validation.issues.count
                let projects = store.projects(includeArchived: true)
                let existingUnits = store.units()
                let commits = validation.accepted.map { validated -> KnowledgeUnitCommit in
                    let normalized = KnowledgeCandidateNormalizer.normalize(
                        validated,
                        sourceSensitivity: source.sensitivity,
                        observedAt: source.endedAt ?? source.createdAt)
                    return KnowledgeCandidateMaterializer.materialize(
                        validated: validated,
                        normalized: normalized,
                        source: source,
                        chunkIndex: chunk.index,
                        meetingTitle: metadata.title,
                        existingProjects: projects,
                        existingUnits: existingUnits,
                        extractorVersion: job.extractorVersion,
                        model: modelName,
                        now: clock())
                }
                acceptedCount = commits.count
                guard store.commitChunk(
                    commits,
                    jobID: job.id,
                    nextCursor: chunk.index + 1,
                    now: clock()) else {
                    throw KnowledgeExtractionError.transient("知识块事务提交失败")
                }
                _ = store.appendExtractionDiagnostic(KnowledgeExtractionDiagnostic(
                    id: UUID().uuidString.lowercased(),
                    jobID: job.id,
                    sourceID: source.id,
                    chunkIndex: chunk.index,
                    inputCharacters: prompt.count,
                    outputCharacters: outputCharacters,
                    candidateCount: candidateCount,
                    acceptedCount: acceptedCount,
                    invalidEvidenceCount: invalidEvidenceCount,
                    durationMS: elapsedMilliseconds(since: started),
                    retryCount: max(0, job.attempt - 1),
                    outcome: candidateCount > 0 && acceptedCount == 0 ? .rejected : .completed,
                    errorCode: nil,
                    createdAt: clock()))
            } catch {
                _ = store.appendExtractionDiagnostic(KnowledgeExtractionDiagnostic(
                    id: UUID().uuidString.lowercased(),
                    jobID: job.id,
                    sourceID: source.id,
                    chunkIndex: chunk.index,
                    inputCharacters: prompt.count,
                    outputCharacters: outputCharacters,
                    candidateCount: candidateCount,
                    acceptedCount: acceptedCount,
                    invalidEvidenceCount: invalidEvidenceCount,
                    durationMS: elapsedMilliseconds(since: started),
                    retryCount: max(0, job.attempt - 1),
                    outcome: diagnosticOutcome(for: error, job: job),
                    errorCode: errorCode(for: error),
                    createdAt: clock()))
                throw error
            }
        }
        return chunks.count
    }

    private func elapsedMilliseconds(since start: TimeInterval) -> Int {
        max(0, Int(((clock() - start) * 1_000).rounded()))
    }

    private func diagnosticOutcome(for error: Error,
                                   job: KnowledgeExtractionJob) -> KnowledgeExtractionDiagnosticOutcome {
        let decision = KnowledgeRetryPolicy.decision(for: error, job: job, now: 0)
        return decision.state == .retry ? .retry : .failed
    }

    private func errorCode(for error: Error) -> String {
        if error is CancellationError { return "cancelled" }
        guard let extractionError = error as? KnowledgeExtractionError else { return "client_error" }
        switch extractionError {
        case .invalidResponse: return "invalid_response"
        case .transient: return "transient"
        case .rateLimited: return "rate_limited"
        case .permanent: return "permanent"
        case .cancelled: return "cancelled"
        }
    }
}
