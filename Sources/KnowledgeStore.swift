import Foundation

final class KnowledgeStore {
    static let shared = KnowledgeStore(database: .shared)

    let database: DB

    init(database: DB) {
        self.database = database
    }

    var isAvailable: Bool { database.healthy && database.knowledgeHealthy }
    var unavailableReason: String? { database.storageError ?? database.schemaMigrationError }

    @discardableResult
    func saveSource(_ document: KnowledgeSourceDocument,
                    segments: [KnowledgeSourceSegment],
                    meetingTitle: String) -> Bool {
        database.saveKnowledgeSource(document, segments: segments, meetingTitle: meetingTitle)
    }

    func sources(meetingID: String? = nil) -> [KnowledgeSourceDocument] {
        database.knowledgeSources(meetingID: meetingID)
    }

    func segments(sourceID: String) -> [KnowledgeSourceSegment] {
        database.knowledgeSegments(sourceID: sourceID)
    }

    func allSegments() -> [KnowledgeSourceSegment] {
        database.knowledgeSegments()
    }

    @discardableResult
    func setSourceSensitivity(id: String,
                              sensitivity: KnowledgeSensitivity,
                              reason: String? = nil,
                              at timestamp: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        guard let source = database.knowledgeSources().first(where: { $0.id == id }) else { return false }
        guard source.sensitivity != sensitivity else { return true }
        let before = "{\"sensitivity\":\"\(source.sensitivity.rawValue)\"}"
        let after = "{\"sensitivity\":\"\(sensitivity.rawValue)\"}"
        let feedback = KnowledgeFeedbackEvent(
            id: UUID().uuidString.lowercased(),
            targetType: "source_document",
            targetID: id,
            action: .edit,
            beforeJSON: before,
            afterJSON: after,
            reason: reason,
            actor: "user",
            createdAt: timestamp)
        return database.updateKnowledgeSourceSensitivity(
            id: id,
            sensitivity: sensitivity,
            updatedAt: timestamp,
            feedback: feedback)
    }

    @discardableResult
    func deleteSource(id: String) -> Bool {
        database.deleteKnowledgeSource(id: id)
    }

    @discardableResult
    func resolveConflict(primaryID: String,
                         otherID: String,
                         resolution: KnowledgeConflictResolution,
                         reason: String? = nil,
                         at timestamp: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        guard primaryID != otherID,
              let primary = units().first(where: { $0.id == primaryID }),
              let other = units().first(where: { $0.id == otherID }),
              primary.reviewStatus != .rejected,
              other.reviewStatus != .rejected,
              primary.conflictStatus == .pending || other.conflictStatus == .pending else { return false }
        let feedback = KnowledgeFeedbackEvent(
            id: UUID().uuidString.lowercased(),
            targetType: "knowledge_unit",
            targetID: primaryID,
            action: .relate,
            beforeJSON: "{\"conflict_status\":\"pending\",\"other_id\":\"\(otherID)\"}",
            afterJSON: "{\"conflict_status\":\"resolved\",\"resolution\":\"\(resolution.rawValue)\",\"other_id\":\"\(otherID)\"}",
            reason: reason,
            actor: "user",
            createdAt: timestamp)
        return database.resolveKnowledgeConflict(
            primaryID: primaryID,
            otherID: otherID,
            resolution: resolution,
            feedback: feedback,
            now: timestamp)
    }

    @discardableResult
    func mergeUnits(primaryID: String,
                    duplicateID: String,
                    reason: String? = nil,
                    at timestamp: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        guard primaryID != duplicateID,
              let primary = units().first(where: { $0.id == primaryID }),
              let duplicate = units().first(where: { $0.id == duplicateID }),
              primary.reviewStatus != .rejected,
              duplicate.reviewStatus != .rejected,
              primary.fingerprint == duplicate.fingerprint else { return false }
        let feedback = KnowledgeFeedbackEvent(
            id: UUID().uuidString.lowercased(),
            targetType: "knowledge_unit",
            targetID: duplicateID,
            action: .merge,
            beforeJSON: "{\"review_status\":\"\(duplicate.reviewStatus.rawValue)\"}",
            afterJSON: "{\"merged_into\":\"\(primaryID)\",\"review_status\":\"rejected\"}",
            reason: reason ?? "用户合并重复知识",
            actor: "user",
            createdAt: timestamp)
        return database.mergeKnowledgeUnits(
            primaryID: primaryID,
            duplicateID: duplicateID,
            feedback: feedback,
            now: timestamp)
    }

    @discardableResult
    func rejectUnit(id: String,
                    reason: String? = nil,
                    at timestamp: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        guard let unit = units().first(where: { $0.id == id }) else { return false }
        if unit.reviewStatus == .rejected { return true }
        let feedback = KnowledgeFeedbackEvent(
            id: UUID().uuidString.lowercased(),
            targetType: "knowledge_unit",
            targetID: id,
            action: .reject,
            beforeJSON: "{\"review_status\":\"\(unit.reviewStatus.rawValue)\"}",
            afterJSON: "{\"review_status\":\"rejected\"}",
            reason: reason,
            actor: "user",
            createdAt: timestamp)
        return database.rejectKnowledgeUnit(id: id, feedback: feedback, now: timestamp)
    }

    @discardableResult
    func restoreUnit(id: String,
                     meetingTitle: String,
                     at timestamp: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        guard let item = inboxItems().first(where: { $0.id == id }),
              item.unit.reviewStatus == .rejected,
              let source = item.sources.first else { return false }
        let feedback = KnowledgeFeedbackEvent(
            id: UUID().uuidString.lowercased(),
            targetType: "knowledge_unit",
            targetID: id,
            action: .restore,
            beforeJSON: "{\"review_status\":\"rejected\"}",
            afterJSON: "{\"review_status\":\"candidate\"}",
            reason: nil,
            actor: "user",
            createdAt: timestamp)
        return database.restoreKnowledgeUnit(
            id: id,
            feedback: feedback,
            meetingID: source.meetingID,
            meetingTitle: meetingTitle,
            now: timestamp)
    }

    @discardableResult
    func editUnit(id: String,
                  edits: KnowledgeUnitEdits,
                  meetingTitle: String,
                  reason: String? = nil,
                  at timestamp: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        guard let current = units().first(where: { $0.id == id }),
              current.reviewStatus != .rejected,
              let source = inboxItems().first(where: { $0.id == id })?.sources.first else { return false }
        let canonical = edits.canonicalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !canonical.isEmpty,
              edits.numericValue?.isFinite != false,
              edits.validFrom == nil || edits.validTo == nil || edits.validTo! >= edits.validFrom!
        else { return false }
        func cleaned(_ value: String?) -> String? {
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let normalized = NormalizedKnowledgeCandidate(
            kind: current.kind,
            canonicalText: canonical,
            subject: cleaned(edits.subject),
            predicate: cleaned(edits.predicate),
            objectText: cleaned(edits.objectText),
            numericValue: edits.numericValue,
            valueUnit: edits.numericValue == nil ? nil : cleaned(edits.valueUnit),
            owner: cleaned(edits.owner),
            dueText: cleaned(edits.dueText),
            validFrom: edits.validFrom,
            validTo: edits.validTo,
            evidenceLevel: current.evidenceLevel,
            evidence: [],
            projectHints: [],
            sensitivity: current.sensitivity,
            payloadJSON: current.payloadJSON)
        let updated = KnowledgeUnit(
            id: current.id,
            kind: current.kind,
            canonicalText: normalized.canonicalText,
            subject: normalized.subject,
            predicate: normalized.predicate,
            objectText: normalized.objectText,
            numericValue: normalized.numericValue,
            valueUnit: normalized.valueUnit,
            owner: normalized.owner,
            dueText: normalized.dueText,
            validFrom: normalized.validFrom,
            validTo: normalized.validTo,
            observedAt: current.observedAt,
            reviewStatus: .edited,
            evidenceLevel: current.evidenceLevel,
            conflictStatus: current.conflictStatus,
            sensitivity: current.sensitivity,
            fingerprint: KnowledgeFingerprint.make(for: normalized),
            revision: current.revision + 1,
            extractorVersion: current.extractorVersion,
            promptVersion: current.promptVersion,
            schemaVersion: current.schemaVersion,
            model: current.model,
            payloadJSON: current.payloadJSON,
            createdAt: current.createdAt,
            updatedAt: timestamp)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let before = (try? encoder.encode(current)).flatMap { String(data: $0, encoding: .utf8) }
        let after = (try? encoder.encode(updated)).flatMap { String(data: $0, encoding: .utf8) }
        let feedback = KnowledgeFeedbackEvent(
            id: UUID().uuidString.lowercased(),
            targetType: "knowledge_unit",
            targetID: id,
            action: .edit,
            beforeJSON: before,
            afterJSON: after,
            reason: reason,
            actor: "user",
            createdAt: timestamp)
        return database.editKnowledgeUnit(
            updated,
            feedback: feedback,
            meetingID: source.meetingID,
            meetingTitle: meetingTitle)
    }

    @discardableResult
    func confirmUnit(id: String,
                     at timestamp: TimeInterval = Date().timeIntervalSince1970) -> Bool {
        guard let unit = units().first(where: { $0.id == id }) else { return false }
        if unit.reviewStatus == .confirmed || unit.reviewStatus == .edited { return true }
        guard unit.reviewStatus == .candidate else { return false }
        let feedback = KnowledgeFeedbackEvent(
            id: UUID().uuidString.lowercased(),
            targetType: "knowledge_unit",
            targetID: id,
            action: .confirm,
            beforeJSON: "{\"review_status\":\"candidate\"}",
            afterJSON: "{\"review_status\":\"confirmed\"}",
            reason: nil,
            actor: "user",
            createdAt: timestamp)
        return database.confirmKnowledgeUnit(id: id, feedback: feedback, now: timestamp)
    }

    @discardableResult
    func commitChunk(_ commits: [KnowledgeUnitCommit],
                     jobID: String,
                     nextCursor: Int,
                     now: TimeInterval) -> Bool {
        database.commitKnowledgeChunk(
            commits,
            jobID: jobID,
            nextCursor: nextCursor,
            now: now)
    }

    @discardableResult
    func saveUnit(_ unit: KnowledgeUnit,
                  evidence: [KnowledgeUnitSource],
                  projectLinks: [KnowledgeUnitProject],
                  meetingID: String,
                  meetingTitle: String) -> Bool {
        database.saveKnowledgeUnit(
            unit, evidence: evidence, projectLinks: projectLinks,
            meetingID: meetingID, meetingTitle: meetingTitle)
    }

    func units(statuses: Set<KnowledgeReviewStatus>? = nil,
               kinds: Set<KnowledgeKind>? = nil) -> [KnowledgeUnit] {
        database.knowledgeUnits().filter { unit in
            (statuses == nil || statuses!.contains(unit.reviewStatus))
                && (kinds == nil || kinds!.contains(unit.kind))
        }
    }

    func evidence(unitID: String) -> [KnowledgeUnitSource] {
        database.knowledgeEvidence(unitID: unitID)
    }

    func allEvidence() -> [KnowledgeUnitSource] {
        database.knowledgeEvidence()
    }

    func projectLinks(unitID: String) -> [KnowledgeUnitProject] {
        database.knowledgeProjectLinks(unitID: unitID)
    }

    func allProjectLinks() -> [KnowledgeUnitProject] {
        database.knowledgeProjectLinks()
    }

    func inboxItems() -> [KnowledgeInboxItem] {
        let units = database.knowledgeUnits()
        let evidenceByUnit = Dictionary(grouping: database.knowledgeEvidence(), by: \.unitID)
        let projectLinksByUnit = Dictionary(grouping: database.knowledgeProjectLinks(), by: \.unitID)
        let segmentsByID = Dictionary(uniqueKeysWithValues: database.knowledgeSegments().map { ($0.id, $0) })
        let sourcesByID = Dictionary(uniqueKeysWithValues: database.knowledgeSources().map { ($0.id, $0) })
        let activeUnits = units.filter { $0.reviewStatus != .rejected }
        let duplicateCounts = Dictionary(grouping: activeUnits, by: \.fingerprint).mapValues(\.count)
        return units.map { unit in
            let evidence = evidenceByUnit[unit.id] ?? []
            let contexts = evidence.compactMap { link -> KnowledgeInboxEvidence? in
                guard let segment = segmentsByID[link.segmentID],
                      let source = sourcesByID[segment.sourceID] else { return nil }
                return KnowledgeInboxEvidence(link: link, segment: segment, source: source)
            }
            var seenSourceIDs = Set<String>()
            let sources = contexts.compactMap { context -> KnowledgeSourceDocument? in
                guard seenSourceIDs.insert(context.source.id).inserted else { return nil }
                return context.source
            }
            return KnowledgeInboxItem(
                unit: unit,
                evidence: evidence,
                sources: sources,
                projectLinks: projectLinksByUnit[unit.id] ?? [],
                evidenceContexts: contexts,
                duplicateCount: duplicateCounts[unit.fingerprint] ?? 1)
        }
    }

    @discardableResult
    func saveProject(_ project: KnowledgeProject) -> Bool {
        database.saveKnowledgeProject(project)
    }

    func projects(includeArchived: Bool = false) -> [KnowledgeProject] {
        database.knowledgeProjects().filter { includeArchived || $0.status != .archived }
    }

    @discardableResult
    func saveRelation(_ relation: KnowledgeUnitRelation) -> Bool {
        database.saveKnowledgeRelation(relation)
    }

    func relations(unitID: String) -> [KnowledgeUnitRelation] {
        database.knowledgeRelations(unitID: unitID)
    }

    @discardableResult
    func appendFeedback(_ event: KnowledgeFeedbackEvent) -> Bool {
        database.appendKnowledgeFeedback(event)
    }

    func feedback(targetType: String, targetID: String) -> [KnowledgeFeedbackEvent] {
        database.knowledgeFeedback(targetType: targetType, targetID: targetID)
    }

    func pilotJobIDs() -> Set<String> {
        guard let value = database.kvGet("knowledge_pilot_job_ids"),
              let data = value.data(using: .utf8),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(ids)
    }

    @discardableResult
    func savePilotJobIDs(_ ids: Set<String>) -> Bool {
        guard let data = try? JSONEncoder().encode(ids.sorted()),
              let value = String(data: data, encoding: .utf8) else { return false }
        return database.kvSet("knowledge_pilot_job_ids", value)
    }

    func enqueue(_ job: KnowledgeExtractionJob) -> KnowledgeExtractionJob? {
        if let existing = jobs().first(where: { candidate in
            candidate.sourceID == job.sourceID
                && candidate.jobKind == job.jobKind
                && candidate.inputHash == job.inputHash
                && candidate.extractorVersion == job.extractorVersion
        }) {
            return existing
        }
        if database.saveKnowledgeJob(job) { return job }
        return jobs().first { candidate in
            candidate.sourceID == job.sourceID
                && candidate.jobKind == job.jobKind
                && candidate.inputHash == job.inputHash
                && candidate.extractorVersion == job.extractorVersion
        }
    }

    @discardableResult
    func saveJob(_ job: KnowledgeExtractionJob) -> Bool {
        database.saveKnowledgeJob(job)
    }

    func jobs(states: Set<KnowledgeExtractionJobState>? = nil) -> [KnowledgeExtractionJob] {
        database.knowledgeJobs().filter { states == nil || states!.contains($0.state) }
    }

    @discardableResult
    func appendExtractionDiagnostic(_ diagnostic: KnowledgeExtractionDiagnostic) -> Bool {
        database.appendKnowledgeExtractionDiagnostic(diagnostic)
    }

    func extractionDiagnostics(jobID: String? = nil) -> [KnowledgeExtractionDiagnostic] {
        database.knowledgeExtractionDiagnostics(jobID: jobID)
    }

    func claimNextJob(now: TimeInterval,
                      leaseDuration: TimeInterval,
                      allowedJobIDs: Set<String>? = nil) -> KnowledgeExtractionJob? {
        database.claimNextKnowledgeJob(
            now: now,
            leaseDuration: leaseDuration,
            allowedJobIDs: allowedJobIDs)
    }

    @discardableResult
    func renewJobLease(id: String,
                       now: TimeInterval,
                       leaseDuration: TimeInterval) -> Bool {
        database.renewKnowledgeJobLease(id: id, now: now, leaseDuration: leaseDuration)
    }

    @discardableResult
    func transitionJob(id: String,
                       state: KnowledgeExtractionJobState,
                       cursor: Int,
                       nextRetryAt: TimeInterval? = nil,
                       lastError: String? = nil,
                       now: TimeInterval) -> Bool {
        database.transitionKnowledgeJob(
            id: id,
            state: state,
            cursor: cursor,
            nextRetryAt: nextRetryAt,
            lastError: lastError,
            now: now)
    }

    @discardableResult
    func resetJobForRetry(id: String, now: TimeInterval) -> Bool {
        database.resetKnowledgeJobForRetry(id: id, now: now)
    }

    func diagnostics() -> KnowledgeDatabaseDiagnostics {
        database.knowledgeDiagnostics()
    }

    func search(tokens: [String], limit: Int = 30) -> [DB.KnowledgeFTSHit] {
        database.searchKnowledgeFTS(tokens: tokens, limit: limit)
    }
}
