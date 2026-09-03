import XCTest
@testable import AfterMeet

final class KnowledgeStoreTests: XCTestCase {
    private func makeStore() -> (KnowledgeStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AfterMeet-KnowledgeStore-" + UUID().uuidString)
        let database = DB(databaseURL: directory.appendingPathComponent("aftermeet.db"))
        return (KnowledgeStore(database: database), directory)
    }

    private func source(id: String = "source-1") -> KnowledgeSourceDocument {
        KnowledgeSourceDocument(
            id: id, meetingID: "meeting-1", sourceKind: .liveCloud,
            locator: "/tmp/fixture.txt", fullText: "甲：关键指标增长。乙：继续试验。",
            contentHash: "hash-" + id, sourceRevision: 1, startedAt: 1, endedAt: 10,
            language: "zh-CN", sensitivity: .normal, metadataJSON: "{}",
            createdAt: 10, updatedAt: 10)
    }

    private func segment(id: String = "segment-1", sourceID: String = "source-1") -> KnowledgeSourceSegment {
        KnowledgeSourceSegment(
            id: id, sourceID: sourceID, meetingID: "meeting-1", ordinal: 0,
            speaker: "甲", startMS: 100, endMS: 900, charStart: 0, charEnd: 9,
            text: "甲：关键指标增长。", contentHash: "hash-" + id,
            metadataJSON: "{}", createdAt: 10, updatedAt: 10)
    }

    private func unit(id: String, status: KnowledgeReviewStatus = .candidate) -> KnowledgeUnit {
        KnowledgeUnit(
            id: id, kind: .decision, canonicalText: "继续试验", subject: "松果计划",
            predicate: "状态", objectText: "继续", numericValue: nil, valueUnit: nil,
            owner: nil, dueText: nil, validFrom: 10, validTo: nil, observedAt: 10,
            reviewStatus: status, evidenceLevel: .direct, conflictStatus: .none,
            sensitivity: .normal, fingerprint: "fp-" + id, revision: 1,
            extractorVersion: "extract-v1", promptVersion: "prompt-v1", schemaVersion: 1,
            model: "fixture", payloadJSON: "{}", createdAt: 10, updatedAt: 10)
    }

    func testSourceSaveLoadSearchIdempotenceAndDelete() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = source()
        let firstSegment = segment()

        XCTAssertTrue(store.isAvailable)
        XCTAssertTrue(store.saveSource(document, segments: [firstSegment], meetingTitle: "松果计划评审"))
        XCTAssertTrue(store.saveSource(document, segments: [firstSegment], meetingTitle: "松果计划评审"))
        XCTAssertEqual(store.sources(meetingID: "meeting-1"), [document])
        XCTAssertEqual(store.segments(sourceID: document.id), [firstSegment])
        XCTAssertEqual(store.search(tokens: ["关键指标"]), [
            DB.KnowledgeFTSHit(docType: "segment", docID: firstSegment.id)
        ])

        XCTAssertTrue(store.deleteSource(id: document.id))
        XCTAssertTrue(store.sources(meetingID: "meeting-1").isEmpty)
        XCTAssertTrue(store.segments(sourceID: document.id).isEmpty)
        XCTAssertTrue(store.search(tokens: ["关键指标"]).isEmpty)
    }

    func testUnitSaveIsAtomicAndLoadsEvidenceProjectAndFTS() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = source()
        let firstSegment = segment()
        XCTAssertTrue(store.saveSource(document, segments: [firstSegment], meetingTitle: "松果计划评审"))
        let project = KnowledgeProject(
            id: "project-1", name: "松果计划", normalizedName: "松果计划",
            aliases: ["松果"], status: .active, createdAt: 10, updatedAt: 10)
        XCTAssertTrue(store.saveProject(project))

        let rejectedByTransaction = unit(id: "unit-bad")
        let missingProjectLink = KnowledgeUnitProject(
            unitID: rejectedByTransaction.id, projectID: "missing-project", role: "decision",
            relevance: 1, assignmentSource: .model, reviewStatus: .candidate)
        XCTAssertFalse(store.saveUnit(
            rejectedByTransaction,
            evidence: [KnowledgeUnitSource(
                unitID: rejectedByTransaction.id, segmentID: firstSegment.id,
                evidenceRole: .support, quote: "继续试验", weight: 1, verified: false)],
            projectLinks: [missingProjectLink], meetingID: "meeting-1", meetingTitle: "松果计划评审"))
        XCTAssertFalse(store.units().contains { $0.id == rejectedByTransaction.id })

        let decision = unit(id: "unit-1", status: .confirmed)
        let evidence = KnowledgeUnitSource(
            unitID: decision.id, segmentID: firstSegment.id, evidenceRole: .support,
            quote: "继续试验", weight: 1, verified: true)
        let projectLink = KnowledgeUnitProject(
            unitID: decision.id, projectID: project.id, role: "decision", relevance: 1,
            assignmentSource: .user, reviewStatus: .confirmed)
        XCTAssertTrue(store.saveUnit(
            decision, evidence: [evidence], projectLinks: [projectLink],
            meetingID: "meeting-1", meetingTitle: "松果计划评审"))

        XCTAssertEqual(store.units(statuses: [.confirmed]), [decision])
        XCTAssertEqual(store.evidence(unitID: decision.id), [evidence])
        XCTAssertEqual(store.projectLinks(unitID: decision.id), [projectLink])
        XCTAssertEqual(store.projects(), [project])
        let inbox = try XCTUnwrap(store.inboxItems().first { $0.id == decision.id })
        XCTAssertEqual(inbox.evidenceContexts.first?.segment, firstSegment)
        XCTAssertEqual(inbox.evidenceContexts.first?.source, document)
        XCTAssertEqual(inbox.evidenceContexts.first?.link, evidence)
        XCTAssertEqual(store.search(tokens: ["继续试验"]), [
            DB.KnowledgeFTSHit(docType: "unit", docID: decision.id)
        ])
    }

    func testRelationAndFeedbackRoundTripThroughStore() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = source()
        let firstSegment = segment()
        XCTAssertTrue(store.saveSource(document, segments: [firstSegment], meetingTitle: "松果计划评审"))
        for id in ["unit-old", "unit-new"] {
            XCTAssertTrue(store.saveUnit(
                unit(id: id),
                evidence: [KnowledgeUnitSource(
                    unitID: id, segmentID: firstSegment.id, evidenceRole: .support,
                    quote: "继续试验", weight: 1, verified: false)],
                projectLinks: [], meetingID: "meeting-1", meetingTitle: "松果计划评审"))
        }
        let relation = KnowledgeUnitRelation(
            fromUnitID: "unit-new", toUnitID: "unit-old", relationKind: .supersedes,
            reviewStatus: .candidate, reason: "后续更新", payloadJSON: "{}", createdAt: 11)
        let feedback = KnowledgeFeedbackEvent(
            id: "feedback-1", targetType: "knowledge_unit", targetID: "unit-new",
            action: .confirm, beforeJSON: nil, afterJSON: "{}", reason: nil,
            actor: "user", createdAt: 12)

        XCTAssertTrue(store.saveRelation(relation))
        XCTAssertTrue(store.appendFeedback(feedback))
        XCTAssertEqual(store.relations(unitID: "unit-old"), [relation])
        XCTAssertEqual(store.feedback(targetType: "knowledge_unit", targetID: "unit-new"), [feedback])
        XCTAssertFalse(store.appendFeedback(feedback))
    }

    func testDiagnosticsReportCountsAndFTSConsistencyWithoutContent() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = source()
        let firstSegment = segment()
        XCTAssertTrue(store.saveSource(document, segments: [firstSegment], meetingTitle: "松果计划评审"))

        var diagnostics = store.diagnostics()
        XCTAssertTrue(diagnostics.isClean)
        XCTAssertEqual(diagnostics.schemaVersion, DB.currentSchemaVersion)
        XCTAssertEqual(diagnostics.tableCounts["source_documents"], 1)
        XCTAssertEqual(diagnostics.tableCounts["source_segments"], 1)
        XCTAssertEqual(diagnostics.foreignKeyViolations, 0)
        XCTAssertEqual(diagnostics.orphanReferences, 0)

        XCTAssertTrue(store.database.deleteKnowledgeFTSDoc(docType: "segment", docID: firstSegment.id))
        diagnostics = store.diagnostics()
        XCTAssertEqual(diagnostics.missingFTSRows, 1)
        XCTAssertFalse(diagnostics.isClean)

        XCTAssertTrue(store.database.upsertKnowledgeFTSDoc(DB.KnowledgeFTSDoc(
            docType: "segment", docID: firstSegment.id, meetingID: firstSegment.meetingID,
            projectID: nil, title: "松果计划评审", body: firstSegment.text,
            context: firstSegment.speaker ?? "")))
        XCTAssertTrue(store.database.upsertKnowledgeFTSDoc(DB.KnowledgeFTSDoc(
            docType: "unexpected", docID: "orphan-fts", meetingID: "meeting-1",
            projectID: nil, title: "", body: "孤儿索引", context: "")))
        diagnostics = store.diagnostics()
        XCTAssertEqual(diagnostics.missingFTSRows, 0)
        XCTAssertEqual(diagnostics.orphanFTSRows, 1)
        XCTAssertFalse(diagnostics.isClean)
    }

    func testJobEnqueueUsesStableIdentityAndStateUpdates() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertTrue(store.saveSource(source(), segments: [segment()], meetingTitle: "松果计划评审"))
        let original = KnowledgeExtractionJob(
            id: "job-1", sourceID: "source-1", jobKind: .extract, state: .pending,
            inputHash: "hash-source-1", extractorVersion: "extract-v1", cursor: 0,
            attempt: 0, nextRetryAt: nil, leaseUntil: nil, lastError: nil,
            createdAt: 10, updatedAt: 10)
        let duplicateIdentity = KnowledgeExtractionJob(
            id: "job-2", sourceID: "source-1", jobKind: .extract, state: .pending,
            inputHash: "hash-source-1", extractorVersion: "extract-v1", cursor: 0,
            attempt: 0, nextRetryAt: nil, leaseUntil: nil, lastError: nil,
            createdAt: 11, updatedAt: 11)

        XCTAssertEqual(store.enqueue(original), original)
        XCTAssertEqual(store.enqueue(duplicateIdentity), original)
        XCTAssertEqual(store.jobs().count, 1)

        let running = KnowledgeExtractionJob(
            id: original.id, sourceID: original.sourceID, jobKind: original.jobKind,
            state: .running, inputHash: original.inputHash,
            extractorVersion: original.extractorVersion, cursor: 2, attempt: 1,
            nextRetryAt: nil, leaseUntil: 50, lastError: nil,
            createdAt: original.createdAt, updatedAt: 20)
        XCTAssertTrue(store.saveJob(running))
        XCTAssertEqual(store.jobs(states: [.running]), [running])
    }
}
