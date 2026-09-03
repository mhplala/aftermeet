import XCTest
@testable import AfterMeet

@MainActor
final class KnowledgeConflictResolutionTests: XCTestCase {
    private func prepare() -> (
        store: KnowledgeStore,
        directory: URL,
        primary: KnowledgeUnit,
        other: KnowledgeUnit
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AfterMeet-Conflict-" + UUID().uuidString)
        let store = KnowledgeStore(database: DB(
            databaseURL: directory.appendingPathComponent("aftermeet.db")))

        func save(id: String, text: String, observedAt: TimeInterval) -> KnowledgeUnit {
            let bundle = KnowledgeSegmenter.plainTextSourceBundle(
                content: "甲：\(text)", meetingID: "meeting-\(id)", observedAt: observedAt)
            XCTAssertTrue(store.saveSource(
                bundle.document, segments: bundle.segments, meetingTitle: "会议 \(id)"))
            let unit = KnowledgeUnit(
                id: id, kind: .fact, canonicalText: text,
                subject: "松果计划", predicate: "状态", objectText: text,
                numericValue: nil, valueUnit: nil, owner: nil, dueText: nil,
                validFrom: observedAt, validTo: nil, observedAt: observedAt,
                reviewStatus: .candidate, evidenceLevel: .direct,
                conflictStatus: .pending, sensitivity: .normal,
                fingerprint: "fp-\(id)", revision: 1,
                extractorVersion: "v1", promptVersion: "v1", schemaVersion: 1,
                model: "fixture", payloadJSON: "{}", createdAt: observedAt, updatedAt: observedAt)
            let evidence = KnowledgeUnitSource(
                unitID: id, segmentID: bundle.segments[0].id,
                evidenceRole: .support, quote: text, weight: 1, verified: false)
            XCTAssertTrue(store.saveUnit(
                unit, evidence: [evidence], projectLinks: [],
                meetingID: bundle.document.meetingID, meetingTitle: "会议 \(id)"))
            return unit
        }

        return (
            store, directory,
            save(id: "new-unit", text: "当前状态是新方案", observedAt: 20),
            save(id: "old-unit", text: "当前状态是旧方案", observedAt: 10))
    }

    func testSupersedesClosesOldValidityAndPreservesBothBodies() throws {
        let fixture = prepare()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        XCTAssertTrue(fixture.store.resolveConflict(
            primaryID: fixture.primary.id,
            otherID: fixture.other.id,
            resolution: .supersedes,
            reason: "新会议已经更新",
            at: 30))

        let primary = try XCTUnwrap(fixture.store.units().first { $0.id == fixture.primary.id })
        let other = try XCTUnwrap(fixture.store.units().first { $0.id == fixture.other.id })
        XCTAssertEqual(primary.canonicalText, fixture.primary.canonicalText)
        XCTAssertEqual(other.canonicalText, fixture.other.canonicalText)
        XCTAssertEqual(primary.conflictStatus, .resolved)
        XCTAssertEqual(other.conflictStatus, .resolved)
        XCTAssertNil(primary.validTo)
        XCTAssertEqual(other.validTo, 30)
        let relation = try XCTUnwrap(fixture.store.relations(unitID: primary.id).first)
        XCTAssertEqual(relation.relationKind, .supersedes)
        XCTAssertEqual(relation.fromUnitID, primary.id)
        XCTAssertEqual(relation.toUnitID, other.id)
        XCTAssertEqual(relation.reviewStatus, .confirmed)
        XCTAssertEqual(fixture.store.feedback(
            targetType: "knowledge_unit", targetID: primary.id).map(\.action), [.relate])
        XCTAssertEqual(fixture.store.search(tokens: ["当前状态"])
            .filter { $0.docType == "unit" }.count, 2)
    }

    func testContradictsPreservesBothValidityRanges() throws {
        let fixture = prepare()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        XCTAssertTrue(fixture.store.resolveConflict(
            primaryID: fixture.primary.id,
            otherID: fixture.other.id,
            resolution: .contradicts,
            at: 30))

        XCTAssertTrue(fixture.store.units().allSatisfy { $0.conflictStatus == .resolved })
        XCTAssertTrue(fixture.store.units().allSatisfy { $0.validTo == nil })
        XCTAssertEqual(
            fixture.store.relations(unitID: fixture.primary.id).first?.relationKind,
            .contradicts)
    }

    func testKeepBothResolvesFlagWithoutInventingRelationOrValidity() throws {
        let fixture = prepare()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        XCTAssertTrue(fixture.store.resolveConflict(
            primaryID: fixture.primary.id,
            otherID: fixture.other.id,
            resolution: .keepBoth,
            at: 30))

        XCTAssertTrue(fixture.store.units().allSatisfy { $0.conflictStatus == .resolved })
        XCTAssertTrue(fixture.store.units().allSatisfy { $0.validTo == nil })
        XCTAssertTrue(fixture.store.relations(unitID: fixture.primary.id).isEmpty)
    }

    func testAppStoreConflictReviewFindsPairAndRefreshesFilter() throws {
        let fixture = prepare()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let appStore = AppStore(
            loadPersistedData: false,
            knowledgeEnabledOverride: true,
            knowledgeStore: fixture.store)
        let item = try XCTUnwrap(appStore.knowledgeInboxItems.first { $0.id == fixture.primary.id })
        appStore.beginConflictReview(item)
        XCTAssertEqual(appStore.conflictKnowledgeReview?.alternatives.map(\.id), [fixture.other.id])

        XCTAssertTrue(appStore.resolveKnowledgeConflict(
            otherID: fixture.other.id,
            resolution: .keepBoth))
        XCTAssertNil(appStore.conflictKnowledgeReview)
        XCTAssertEqual(appStore.knowledgeInboxCount(.conflicts), 0)
    }
}
