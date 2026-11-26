import XCTest
@testable import AfterMeet

final class KnowledgeModelsTests: XCTestCase {
    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }

    func testSourceSegmentAndUnitRoundTrip() throws {
        let source = KnowledgeSourceDocument(
            id: "source-1", meetingID: "meeting-1", sourceKind: .liveCloud,
            locator: "/tmp/fixture.txt", fullText: "甲：继续试验。", contentHash: "hash-source",
            sourceRevision: 1, startedAt: 10, endedAt: 20, language: "zh-CN",
            sensitivity: .normal, metadataJSON: "{}", createdAt: 20, updatedAt: 20)
        let segment = KnowledgeSourceSegment(
            id: "segment-1", sourceID: source.id, meetingID: source.meetingID, ordinal: 0,
            speaker: "甲", startMS: 100, endMS: 800, charStart: 0, charEnd: 8,
            text: "甲：继续试验。", contentHash: "hash-segment", metadataJSON: "{}",
            createdAt: 20, updatedAt: 20)
        let unit = KnowledgeUnit(
            id: "unit-1", kind: .decision, canonicalText: "继续试验", subject: "松果计划",
            predicate: "状态", objectText: "继续试验", numericValue: nil, valueUnit: nil,
            owner: nil, dueText: nil, validFrom: 20, validTo: nil, observedAt: 20,
            reviewStatus: .candidate, evidenceLevel: .direct, conflictStatus: .none,
            sensitivity: .normal, fingerprint: "unit-fp", revision: 1,
            extractorVersion: "extract-v1", promptVersion: "prompt-v1", schemaVersion: 1,
            model: "fixture", payloadJSON: "{}", createdAt: 20, updatedAt: 20)

        XCTAssertEqual(try roundTrip(source), source)
        XCTAssertEqual(try roundTrip(segment), segment)
        XCTAssertEqual(try roundTrip(unit), unit)
    }

    func testProjectRelationsFeedbackAndJobRoundTrip() throws {
        let project = KnowledgeProject(
            id: "project-1", name: "松果计划", normalizedName: "松果计划",
            aliases: ["松果"], status: .active, createdAt: 1, updatedAt: 2)
        let sourceLink = KnowledgeUnitSource(
            unitID: "unit-1", segmentID: "segment-1", evidenceRole: .support,
            quote: "继续试验", weight: 1, verified: true)
        let projectLink = KnowledgeUnitProject(
            unitID: "unit-1", projectID: project.id, role: "decision", relevance: 1,
            assignmentSource: .user, reviewStatus: .confirmed)
        let relation = KnowledgeUnitRelation(
            fromUnitID: "unit-2", toUnitID: "unit-1", relationKind: .supersedes,
            reviewStatus: .confirmed, reason: "新会议更新", payloadJSON: "{}", createdAt: 2)
        let feedback = KnowledgeFeedbackEvent(
            id: "feedback-1", targetType: "knowledge_unit", targetID: "unit-1",
            action: .edit, beforeJSON: "{}", afterJSON: "{}", reason: "修正",
            actor: "user", createdAt: 3)
        let job = KnowledgeExtractionJob(
            id: "job-1", sourceID: "source-1", jobKind: .extract, state: .retry,
            inputHash: "hash", extractorVersion: "v1", cursor: 2, attempt: 1,
            nextRetryAt: 4, leaseUntil: nil, lastError: "timeout", createdAt: 1, updatedAt: 3)

        XCTAssertEqual(try roundTrip(project), project)
        XCTAssertEqual(try roundTrip(sourceLink), sourceLink)
        XCTAssertEqual(try roundTrip(projectLink), projectLink)
        XCTAssertEqual(try roundTrip(relation), relation)
        XCTAssertEqual(try roundTrip(feedback), feedback)
        XCTAssertEqual(try roundTrip(job), job)
    }

    func testCitationAnswerAndThreadRoundTripPreservesIdentity() throws {
        let citation = KnowledgeCitation(
            segmentID: "segment-1", meetingID: "meeting-1", meetingTitle: "松果计划评审",
            quote: "继续试验", speaker: "甲", startMS: 100, endMS: 800,
            charStart: 0, charEnd: 4)
        let answer = KnowledgeAnswer(
            answer: "当时决定继续试验。", citations: [citation],
            insufficient: false, conflicts: [])
        let turn = WorkQATurn(id: UUID(), question: "当时怎么决定的？", answer: answer)

        XCTAssertEqual(try roundTrip(answer), answer)
        XCTAssertEqual(try roundTrip(turn), turn)
    }

    func testUnknownFutureJSONFieldDoesNotBreakKnowledgeUnitDecode() throws {
        let unit = KnowledgeUnit(
            id: "unit-future", kind: .fact, canonicalText: "测试事实", subject: nil,
            predicate: nil, objectText: nil, numericValue: nil, valueUnit: nil,
            owner: nil, dueText: nil, validFrom: nil, validTo: nil, observedAt: 1,
            reviewStatus: .candidate, evidenceLevel: .direct, conflictStatus: .none,
            sensitivity: .normal, fingerprint: "future-fp", revision: 1,
            extractorVersion: "v1", promptVersion: "v1", schemaVersion: 1,
            model: "fixture", payloadJSON: "{}", createdAt: 1, updatedAt: 1)
        let encoded = try JSONEncoder().encode(unit)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["futureField"] = ["nested": true]
        let withFutureField = try JSONSerialization.data(withJSONObject: object)

        XCTAssertEqual(try JSONDecoder().decode(KnowledgeUnit.self, from: withFutureField), unit)
    }

    func testEnumRawValuesMatchDatabaseChecks() {
        XCTAssertEqual(KnowledgeSourceKind.liveCloud.rawValue, "live_cloud")
        XCTAssertEqual(KnowledgeKind.openQuestion.rawValue, "open_question")
        XCTAssertEqual(KnowledgeRelationKind.dependsOn.rawValue, "depends_on")
        XCTAssertEqual(KnowledgeExtractionJobState.cancelled.rawValue, "cancelled")
    }
}
