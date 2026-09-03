import XCTest
@testable import AfterMeet

@MainActor
final class KnowledgeReviewActionsTests: XCTestCase {
    private func prepare() -> (
        store: KnowledgeStore,
        directory: URL,
        source: KnowledgeSourceDocument,
        segment: KnowledgeSourceSegment,
        unit: KnowledgeUnit,
        evidence: KnowledgeUnitSource
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AfterMeet-Review-" + UUID().uuidString)
        let store = KnowledgeStore(database: DB(
            databaseURL: directory.appendingPathComponent("aftermeet.db")))
        let bundle = KnowledgeSegmenter.plainTextSourceBundle(
            content: "甲：确认这条虚构决策。",
            meetingID: "review-meeting",
            observedAt: 10)
        XCTAssertTrue(store.saveSource(
            bundle.document, segments: bundle.segments, meetingTitle: "虚构评审"))
        let unit = KnowledgeUnit(
            id: "review-unit", kind: .decision, canonicalText: "确认虚构决策",
            subject: nil, predicate: nil, objectText: nil, numericValue: nil,
            valueUnit: nil, owner: nil, dueText: nil, validFrom: nil, validTo: nil,
            observedAt: 10, reviewStatus: .candidate, evidenceLevel: .direct,
            conflictStatus: .none, sensitivity: .normal, fingerprint: "review-fp",
            revision: 1, extractorVersion: "v1", promptVersion: "v1", schemaVersion: 1,
            model: "fixture", payloadJSON: "{}", createdAt: 10, updatedAt: 10)
        let evidence = KnowledgeUnitSource(
            unitID: unit.id, segmentID: bundle.segments[0].id,
            evidenceRole: .support, quote: "确认这条虚构决策", weight: 1, verified: false)
        XCTAssertTrue(store.saveUnit(
            unit, evidence: [evidence], projectLinks: [],
            meetingID: bundle.document.meetingID, meetingTitle: "虚构评审"))
        return (store, directory, bundle.document, bundle.segments[0], unit, evidence)
    }

    func testConfirmAtomicallyUpdatesStatusEvidenceAuditAndKeepsFTS() throws {
        let fixture = prepare()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        XCTAssertTrue(fixture.store.confirmUnit(id: fixture.unit.id, at: 20))

        let confirmed = try XCTUnwrap(fixture.store.units().first { $0.id == fixture.unit.id })
        XCTAssertEqual(confirmed.reviewStatus, .confirmed)
        XCTAssertTrue(fixture.store.evidence(unitID: fixture.unit.id).allSatisfy(\.verified))
        let feedback = fixture.store.feedback(
            targetType: "knowledge_unit", targetID: fixture.unit.id)
        XCTAssertEqual(feedback.count, 1)
        XCTAssertEqual(feedback.first?.action, .confirm)
        XCTAssertEqual(fixture.store.search(tokens: ["确认虚构决策"]), [
            DB.KnowledgeFTSHit(docType: "unit", docID: fixture.unit.id)
        ])

        XCTAssertTrue(fixture.store.confirmUnit(id: fixture.unit.id, at: 30))
        XCTAssertEqual(fixture.store.feedback(
            targetType: "knowledge_unit", targetID: fixture.unit.id).count, 1)
    }

    func testEditCreatesRevisionAuditAndFTSWithoutChangingSourceSegment() throws {
        let fixture = prepare()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let segmentBefore = fixture.store.segments(sourceID: fixture.source.id)
        let edits = KnowledgeUnitEdits(
            canonicalText: "修正后的虚构决策",
            subject: "松果计划",
            predicate: "状态",
            objectText: "已修正",
            numericValue: 47,
            valueUnit: "%",
            owner: "甲",
            dueText: "9月15日",
            validFrom: 100,
            validTo: nil)

        XCTAssertTrue(fixture.store.editUnit(
            id: fixture.unit.id,
            edits: edits,
            meetingTitle: "虚构评审",
            reason: "用户修正字段",
            at: 20))

        let edited = try XCTUnwrap(fixture.store.units().first { $0.id == fixture.unit.id })
        XCTAssertEqual(edited.reviewStatus, .edited)
        XCTAssertEqual(edited.revision, 2)
        XCTAssertEqual(edited.canonicalText, "修正后的虚构决策")
        XCTAssertEqual(edited.subject, "松果计划")
        XCTAssertEqual(edited.numericValue, 47)
        XCTAssertEqual(edited.owner, "甲")
        XCTAssertTrue(fixture.store.evidence(unitID: fixture.unit.id).allSatisfy(\.verified))
        XCTAssertEqual(fixture.store.segments(sourceID: fixture.source.id), segmentBefore)
        XCTAssertTrue(fixture.store.search(tokens: ["确认虚构决策"]).isEmpty)
        XCTAssertEqual(fixture.store.search(tokens: ["修正后的虚构决策"]), [
            DB.KnowledgeFTSHit(docType: "unit", docID: fixture.unit.id)
        ])
        let feedback = fixture.store.feedback(
            targetType: "knowledge_unit", targetID: fixture.unit.id)
        XCTAssertEqual(feedback.count, 1)
        XCTAssertEqual(feedback.first?.action, .edit)
        XCTAssertTrue(feedback.first?.beforeJSON?.contains("确认虚构决策") == true)
        XCTAssertTrue(feedback.first?.afterJSON?.contains("修正后的虚构决策") == true)
    }

    func testInvalidEditDoesNotMutateUnitOrAppendFeedback() throws {
        let fixture = prepare()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let invalid = KnowledgeUnitEdits(
            canonicalText: "  ", subject: nil, predicate: nil, objectText: nil,
            numericValue: nil, valueUnit: nil, owner: nil, dueText: nil,
            validFrom: 20, validTo: 10)

        XCTAssertFalse(fixture.store.editUnit(
            id: fixture.unit.id,
            edits: invalid,
            meetingTitle: "虚构评审",
            at: 20))
        XCTAssertEqual(fixture.store.units().first { $0.id == fixture.unit.id }, fixture.unit)
        XCTAssertTrue(fixture.store.feedback(
            targetType: "knowledge_unit", targetID: fixture.unit.id).isEmpty)
    }

    func testMergePreservesBothUnitsCopiesEvidenceAndCreatesAuditRelation() throws {
        let fixture = prepare()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let secondBundle = KnowledgeSegmenter.plainTextSourceBundle(
            content: "乙：确认这条虚构决策。",
            meetingID: "review-meeting-2",
            observedAt: 11)
        XCTAssertTrue(fixture.store.saveSource(
            secondBundle.document, segments: secondBundle.segments, meetingTitle: "第二场虚构评审"))
        let duplicate = KnowledgeUnit(
            id: "review-unit-duplicate", kind: fixture.unit.kind,
            canonicalText: fixture.unit.canonicalText, subject: fixture.unit.subject,
            predicate: fixture.unit.predicate, objectText: fixture.unit.objectText,
            numericValue: nil, valueUnit: nil, owner: nil, dueText: nil,
            validFrom: nil, validTo: nil, observedAt: 11,
            reviewStatus: .confirmed, evidenceLevel: .direct, conflictStatus: .none,
            sensitivity: .normal, fingerprint: fixture.unit.fingerprint, revision: 1,
            extractorVersion: "v2", promptVersion: "v2", schemaVersion: 1,
            model: "fixture", payloadJSON: "{}", createdAt: 11, updatedAt: 11)
        let duplicateEvidence = KnowledgeUnitSource(
            unitID: duplicate.id, segmentID: secondBundle.segments[0].id,
            evidenceRole: .support, quote: "确认这条虚构决策", weight: 1, verified: true)
        XCTAssertTrue(fixture.store.saveUnit(
            duplicate, evidence: [duplicateEvidence], projectLinks: [],
            meetingID: secondBundle.document.meetingID, meetingTitle: "第二场虚构评审"))
        XCTAssertEqual(fixture.store.search(tokens: ["确认虚构决策"]).count, 2)

        XCTAssertTrue(fixture.store.mergeUnits(
            primaryID: fixture.unit.id,
            duplicateID: duplicate.id,
            reason: "测试合并",
            at: 20))

        let units = fixture.store.units()
        XCTAssertEqual(units.count, 2)
        XCTAssertEqual(units.first { $0.id == fixture.unit.id }?.reviewStatus, .confirmed)
        XCTAssertEqual(units.first { $0.id == duplicate.id }?.reviewStatus, .rejected)
        let mergedEvidence = fixture.store.evidence(unitID: fixture.unit.id)
        XCTAssertEqual(Set(mergedEvidence.map(\.segmentID)), Set([
            fixture.segment.id, secondBundle.segments[0].id
        ]))
        XCTAssertTrue(mergedEvidence.allSatisfy(\.verified))
        XCTAssertEqual(fixture.store.search(tokens: ["确认虚构决策"]), [
            DB.KnowledgeFTSHit(docType: "unit", docID: fixture.unit.id)
        ])
        let relation = try XCTUnwrap(fixture.store.relations(unitID: duplicate.id).first)
        XCTAssertEqual(relation.fromUnitID, duplicate.id)
        XCTAssertEqual(relation.toUnitID, fixture.unit.id)
        XCTAssertEqual(relation.relationKind, .sameAs)
        XCTAssertEqual(relation.reviewStatus, .confirmed)
        XCTAssertEqual(fixture.store.feedback(
            targetType: "knowledge_unit", targetID: duplicate.id).map(\.action), [.merge])
        XCTAssertEqual(fixture.store.inboxItems().first { $0.id == fixture.unit.id }?.duplicateCount, 1)
    }

    func testRejectRemovesUnitFromFTSAndRestoreReturnsItToCandidate() throws {
        let fixture = prepare()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        XCTAssertTrue(fixture.store.rejectUnit(
            id: fixture.unit.id, reason: "不适合作为长期知识", at: 20))
        XCTAssertEqual(
            fixture.store.units().first { $0.id == fixture.unit.id }?.reviewStatus,
            .rejected)
        XCTAssertTrue(fixture.store.search(tokens: ["确认虚构决策"]).isEmpty)
        XCTAssertEqual(fixture.store.sources(meetingID: fixture.source.meetingID).count, 1)
        XCTAssertEqual(fixture.store.segments(sourceID: fixture.source.id).count, 1)
        XCTAssertEqual(fixture.store.feedback(
            targetType: "knowledge_unit", targetID: fixture.unit.id).map(\.action), [.reject])

        XCTAssertTrue(fixture.store.rejectUnit(id: fixture.unit.id, at: 21))
        XCTAssertEqual(fixture.store.feedback(
            targetType: "knowledge_unit", targetID: fixture.unit.id).count, 1)
        XCTAssertTrue(fixture.store.restoreUnit(
            id: fixture.unit.id, meetingTitle: "虚构评审", at: 30))

        XCTAssertEqual(
            fixture.store.units().first { $0.id == fixture.unit.id }?.reviewStatus,
            .candidate)
        XCTAssertTrue(fixture.store.evidence(unitID: fixture.unit.id).allSatisfy { !$0.verified })
        XCTAssertEqual(fixture.store.search(tokens: ["确认虚构决策"]), [
            DB.KnowledgeFTSHit(docType: "unit", docID: fixture.unit.id)
        ])
        XCTAssertEqual(fixture.store.feedback(
            targetType: "knowledge_unit", targetID: fixture.unit.id).map(\.action), [.reject, .restore])
    }

    func testAppStoreRejectAndRestoreRefreshFilters() throws {
        let fixture = prepare()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let appStore = AppStore(
            loadPersistedData: false,
            knowledgeEnabledOverride: true,
            knowledgeStore: fixture.store)

        appStore.rejectKnowledgeUnit(id: fixture.unit.id)
        XCTAssertEqual(appStore.knowledgeInboxCount(.pending), 0)
        XCTAssertEqual(appStore.knowledgeInboxCount(.processed), 1)

        appStore.restoreKnowledgeUnit(id: fixture.unit.id)
        XCTAssertEqual(appStore.knowledgeInboxCount(.pending), 1)
        XCTAssertEqual(appStore.knowledgeInboxCount(.processed), 0)
    }

    func testCandidateWithoutSupportEvidenceCannotBeConfirmed() throws {
        let fixture = prepare()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let noEvidence = KnowledgeUnit(
            id: "no-evidence", kind: .fact, canonicalText: "没有证据",
            subject: nil, predicate: nil, objectText: nil, numericValue: nil,
            valueUnit: nil, owner: nil, dueText: nil, validFrom: nil, validTo: nil,
            observedAt: 10, reviewStatus: .candidate, evidenceLevel: .direct,
            conflictStatus: .none, sensitivity: .normal, fingerprint: "no-evidence-fp",
            revision: 1, extractorVersion: "v1", promptVersion: "v1", schemaVersion: 1,
            model: "fixture", payloadJSON: "{}", createdAt: 10, updatedAt: 10)
        XCTAssertTrue(fixture.store.saveUnit(
            noEvidence, evidence: [], projectLinks: [],
            meetingID: "review-meeting", meetingTitle: "虚构评审"))

        XCTAssertFalse(fixture.store.confirmUnit(id: noEvidence.id, at: 20))
        XCTAssertEqual(fixture.store.units().first { $0.id == noEvidence.id }?.reviewStatus, .candidate)
        XCTAssertTrue(fixture.store.feedback(
            targetType: "knowledge_unit", targetID: noEvidence.id).isEmpty)
    }

    func testAppStoreConfirmationRefreshesInboxAndBadge() throws {
        let fixture = prepare()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let appStore = AppStore(
            loadPersistedData: false,
            knowledgeEnabledOverride: true,
            knowledgeStore: fixture.store)
        XCTAssertEqual(appStore.knowledgeAttentionCount, 1)

        appStore.confirmKnowledgeUnit(id: fixture.unit.id)

        XCTAssertEqual(appStore.knowledgeAttentionCount, 0)
        XCTAssertTrue(appStore.visibleKnowledgeInboxItems.isEmpty)
        XCTAssertEqual(appStore.knowledgeInboxCount(.processed), 1)
    }
}
