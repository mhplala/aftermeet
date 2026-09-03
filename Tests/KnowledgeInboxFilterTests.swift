import XCTest
@testable import AfterMeet

final class KnowledgeInboxFilterTests: XCTestCase {
    private func source(id: String, kind: KnowledgeSourceKind, meetingID: String) -> KnowledgeSourceDocument {
        KnowledgeSourceDocument(
            id: id, meetingID: meetingID, sourceKind: kind, locator: nil,
            fullText: "fixture", contentHash: "hash-\(id)", sourceRevision: 1,
            startedAt: nil, endedAt: nil, language: nil, sensitivity: .normal,
            metadataJSON: "{}", createdAt: 1, updatedAt: 1)
    }

    private func item(id: String,
                      kind: KnowledgeKind,
                      status: KnowledgeReviewStatus = .candidate,
                      conflict: KnowledgeConflictStatus = .none,
                      owner: String? = nil,
                      observedAt: TimeInterval,
                      fingerprint: String,
                      duplicateCount: Int = 1,
                      sourceKind: KnowledgeSourceKind = .liveCloud,
                      evidenceLevel: KnowledgeEvidenceLevel = .direct) -> KnowledgeInboxItem {
        let unit = KnowledgeUnit(
            id: id, kind: kind, canonicalText: id, subject: nil, predicate: nil,
            objectText: nil, numericValue: nil, valueUnit: nil, owner: owner,
            dueText: nil, validFrom: nil, validTo: nil, observedAt: observedAt,
            reviewStatus: status, evidenceLevel: evidenceLevel, conflictStatus: conflict,
            sensitivity: .normal, fingerprint: fingerprint, revision: 1,
            extractorVersion: "v1", promptVersion: "v1", schemaVersion: 1,
            model: "fixture", payloadJSON: "{}", createdAt: 1, updatedAt: 1)
        return KnowledgeInboxItem(
            unit: unit, evidence: [],
            sources: [source(id: "source-\(id)", kind: sourceKind, meetingID: "meeting-\(id)")],
            projectLinks: [], duplicateCount: duplicateCount)
    }

    func testStateFiltersAndValueFirstSorting() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let items = [
            item(id: "fact", kind: .fact, observedAt: 999_000, fingerprint: "fact"),
            item(id: "action-missing", kind: .action, observedAt: 998_000,
                 fingerprint: "dup", duplicateCount: 2),
            item(id: "action-owned", kind: .action, owner: "甲", observedAt: 997_000,
                 fingerprint: "dup", duplicateCount: 2),
            item(id: "decision", kind: .decision, observedAt: 996_000, fingerprint: "decision"),
            item(id: "conflict", kind: .risk, conflict: .pending,
                 observedAt: 995_000, fingerprint: "conflict"),
            item(id: "processed", kind: .fact, status: .confirmed,
                 observedAt: 994_000, fingerprint: "processed")
        ]

        let pending = AppStore.filterKnowledgeInbox(
            items, state: .pending, kind: nil, source: nil, date: .all, now: now)
        let conflicts = AppStore.filterKnowledgeInbox(
            items, state: .conflicts, kind: nil, source: nil, date: .all, now: now)
        let missing = AppStore.filterKnowledgeInbox(
            items, state: .missingOwner, kind: nil, source: nil, date: .all, now: now)
        let duplicates = AppStore.filterKnowledgeInbox(
            items, state: .duplicates, kind: nil, source: nil, date: .all, now: now)
        let processed = AppStore.filterKnowledgeInbox(
            items, state: .processed, kind: nil, source: nil, date: .all, now: now)

        XCTAssertEqual(pending.map(\.id), ["decision", "action-missing", "action-owned", "conflict", "fact"])
        XCTAssertEqual(conflicts.map(\.id), ["conflict"])
        XCTAssertEqual(missing.map(\.id), ["action-missing"])
        XCTAssertEqual(duplicates.map(\.id), ["action-missing", "action-owned"])
        XCTAssertEqual(processed.map(\.id), ["processed"])
    }

    func testKindSourceAndDateFiltersCompose() {
        let now = Date(timeIntervalSince1970: 10_000_000)
        let recent = now.timeIntervalSince1970 - 86_400
        let old = now.timeIntervalSince1970 - 100 * 86_400
        let items = [
            item(id: "recent-feishu-action", kind: .action, observedAt: recent,
                 fingerprint: "a", sourceKind: .feishu),
            item(id: "old-feishu-action", kind: .action, observedAt: old,
                 fingerprint: "b", sourceKind: .feishu),
            item(id: "recent-live-fact", kind: .fact, observedAt: recent,
                 fingerprint: "c", sourceKind: .liveCloud)
        ]

        let filtered = AppStore.filterKnowledgeInbox(
            items,
            state: .pending,
            kind: .action,
            source: .feishu,
            date: .last7Days,
            now: now)

        XCTAssertEqual(filtered.map(\.id), ["recent-feishu-action"])
    }

    func testDirectEvidenceSortsBeforeInferredWithinSameKindAndTime() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let items = [
            item(id: "inferred", kind: .decision, observedAt: 900_000,
                 fingerprint: "a", evidenceLevel: .inferred),
            item(id: "direct", kind: .decision, observedAt: 900_000,
                 fingerprint: "b", evidenceLevel: .direct)
        ]

        let result = AppStore.filterKnowledgeInbox(
            items, state: .pending, kind: nil, source: nil, date: .all, now: now)

        XCTAssertEqual(result.map(\.id), ["direct", "inferred"])
    }
}
