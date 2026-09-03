import Foundation

enum KnowledgeJobPlanningResult: Equatable {
    case enqueued(KnowledgeExtractionJob)
    case existing(KnowledgeExtractionJob)
    case disabled
    case restrictedNeedsConsent
    case sourceNotPersisted
    case storeUnavailable
}

enum KnowledgeJobPlanner {
    static func planExtraction(
        for source: KnowledgeSourceDocument,
        store: KnowledgeStore = .shared,
        extractorVersion: String = KnowledgeExtractionPrompt.extractorVersion,
        enabled: Bool = KnowledgeFeatureFlags.isEnabled,
        includeRestrictedForCurrentRequest: Bool = false,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> KnowledgeJobPlanningResult {
        guard enabled else { return .disabled }
        guard store.isAvailable else { return .storeUnavailable }
        guard store.sources().contains(where: { $0.id == source.id }) else { return .sourceNotPersisted }
        guard KnowledgePrivacyPolicy.maySendToCloud(
            source.sensitivity,
            includeRestrictedForCurrentRequest: includeRestrictedForCurrentRequest)
        else { return .restrictedNeedsConsent }

        let sourceJobs = store.jobs().filter { $0.sourceID == source.id }
        if let existing = sourceJobs.first(where: {
            $0.inputHash == source.contentHash && $0.extractorVersion == extractorVersion
        }) {
            return .existing(existing)
        }
        let kind: KnowledgeExtractionJobKind = sourceJobs.isEmpty ? .extract : .reextract
        let jobID = "job-" + String(KnowledgeIdentity.contentHash([
            source.id,
            kind.rawValue,
            source.contentHash,
            extractorVersion
        ].joined(separator: "\u{1F}")).prefix(32))
        let job = KnowledgeExtractionJob(
            id: jobID,
            sourceID: source.id,
            jobKind: kind,
            state: .pending,
            inputHash: source.contentHash,
            extractorVersion: extractorVersion,
            cursor: 0,
            attempt: 0,
            nextRetryAt: nil,
            leaseUntil: nil,
            lastError: nil,
            createdAt: now,
            updatedAt: now)
        guard let persisted = store.enqueue(job) else { return .storeUnavailable }
        return persisted.id == job.id ? .enqueued(persisted) : .existing(persisted)
    }
}
