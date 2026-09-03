import XCTest
@testable import AfterMeet

final class KnowledgeExtractionDiagnosticsTests: XCTestCase {
    func testDiagnosticRoundTripContainsMetricsButNoTranscriptBody() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AfterMeet-ExtractionDiagnostics-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = KnowledgeStore(database: DB(
            databaseURL: directory.appendingPathComponent("aftermeet.db")))
        let bundle = KnowledgeSegmenter.plainTextSourceBundle(
            content: "绝不能出现在诊断记录里的虚构原文。",
            meetingID: "diagnostic-meeting",
            observedAt: 1)
        XCTAssertTrue(store.saveSource(
            bundle.document, segments: bundle.segments, meetingTitle: "虚构会议"))
        guard case .enqueued(let job) = KnowledgeJobPlanner.planExtraction(
            for: bundle.document, store: store, enabled: true, now: 2) else {
            return XCTFail("expected job")
        }
        let diagnostic = KnowledgeExtractionDiagnostic(
            id: "diagnostic-1",
            jobID: job.id,
            sourceID: bundle.document.id,
            chunkIndex: 0,
            inputCharacters: 1_200,
            outputCharacters: 420,
            candidateCount: 7,
            acceptedCount: 5,
            invalidEvidenceCount: 2,
            durationMS: 850,
            retryCount: 1,
            outcome: .completed,
            errorCode: nil,
            createdAt: 3)

        XCTAssertTrue(store.appendExtractionDiagnostic(diagnostic))
        XCTAssertEqual(store.extractionDiagnostics(jobID: job.id), [diagnostic])
        XCTAssertFalse(store.appendExtractionDiagnostic(diagnostic))
        XCTAssertEqual(store.diagnostics().tableCounts["extraction_diagnostics"], 1)

        let encoded = try JSONEncoder().encode(diagnostic)
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        XCTAssertFalse(json.contains("绝不能出现在诊断记录"))
        XCTAssertFalse(json.contains("transcript"))
        XCTAssertFalse(json.contains("quote"))
    }
}
