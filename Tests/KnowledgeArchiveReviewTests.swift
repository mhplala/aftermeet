import XCTest
@testable import AfterMeet

@MainActor
final class KnowledgeArchiveReviewTests: XCTestCase {
    private func makeAppStore(noteRefiner: @escaping (String) async throws -> RefinedNote = { _ in
        RefinedNote(title: "导入后的虚构会议", todos: [],
                    blocks: [NoteBlock(type: "summary", text: "合成摘要")])
    }) -> (AppStore, KnowledgeStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AfterMeet-ArchiveReview-" + UUID().uuidString)
        let knowledgeStore = KnowledgeStore(database: DB(
            databaseURL: directory.appendingPathComponent("aftermeet.db")))
        let appStore = AppStore(
            loadPersistedData: false,
            knowledgeEnabledOverride: true,
            knowledgeStore: knowledgeStore,
            noteRefiner: noteRefiner)
        return (appStore, knowledgeStore, directory)
    }

    private func archive(name: String,
                         body: String,
                         start: TimeInterval,
                         end: TimeInterval) -> TranscriptFile {
        TranscriptFile(
            url: URL(fileURLWithPath: "/tmp/\(name).txt"),
            title: name,
            chars: body.count,
            preview: String(body.prefix(40)),
            body: body,
            paragraphs: [body],
            start: Date(timeIntervalSince1970: start),
            end: Date(timeIntervalSince1970: end))
    }

    private func meeting(id: String,
                         title: String,
                         transcript: String,
                         end: TimeInterval) -> StoredLiveMeeting {
        StoredLiveMeeting(
            id: id, title: title, timestamp: end, durationSec: 600,
            transcript: transcript, note: .processing())
    }

    func testScanCreatesReportOnlyAndBindingRequiresExplicitCandidate() throws {
        let (appStore, knowledgeStore, directory) = makeAppStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let body = String(repeating: "重复的普通虚构档案内容。", count: 45)
        let file = archive(name: "ambiguous-archive", body: body, start: 1_000, end: 1_600)
        let meetings = [
            meeting(id: "meeting-a", title: "候选会议 A", transcript: body, end: 1_600),
            meeting(id: "meeting-b", title: "候选会议 B", transcript: body, end: 1_700)
        ]

        let report = appStore.prepareArchiveReview(archives: [file], storedMeetings: meetings)

        XCTAssertEqual(report.ambiguousCount, 1)
        XCTAssertTrue(knowledgeStore.sources().isEmpty)
        XCTAssertTrue(knowledgeStore.jobs().isEmpty)
        let record = try XCTUnwrap(report.records.first)
        XCTAssertFalse(appStore.bindArchiveRecord(record.id, to: "not-a-candidate"))
        XCTAssertTrue(knowledgeStore.sources().isEmpty)

        XCTAssertTrue(appStore.bindArchiveRecord(record.id, to: "meeting-a"))
        let source = try XCTUnwrap(knowledgeStore.sources(meetingID: "meeting-a").first)
        XCTAssertEqual(source.sourceKind, .archive)
        XCTAssertEqual(source.fullText, body)
        XCTAssertEqual(knowledgeStore.jobs().count, 1)
        XCTAssertEqual(knowledgeStore.pilotJobIDs(), Set(knowledgeStore.jobs().map(\.id)))
        XCTAssertEqual(knowledgeStore.feedback(
            targetType: "source_document", targetID: source.id).map(\.action), [.relate])
        XCTAssertEqual(appStore.archiveReviewSession?.report.ambiguousCount, 0)
        XCTAssertEqual(appStore.archiveReviewSession?.report.matchedCount, 1)
        XCTAssertFalse(appStore.meetings.contains { $0.id == "meeting-a" })
    }

    func testOrphanCreatesMeetingSourceAndJobOnlyAfterExplicitImport() async throws {
        let (appStore, knowledgeStore, directory) = makeAppStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let body = String(repeating: "孤立的普通虚构档案内容。", count: 45)
        let end = 4_300_000_000 + TimeInterval(Int.random(in: 1...100_000))
        let file = archive(name: "orphan-archive", body: body, start: end - 600, end: end)
        let report = appStore.prepareArchiveReview(archives: [file], storedMeetings: [])
        let record = try XCTUnwrap(report.records.first)
        let expectedMeetingID = "live-\(Int(end))"

        XCTAssertEqual(record.status, .orphan)
        XCTAssertTrue(knowledgeStore.sources().isEmpty)
        XCTAssertTrue(knowledgeStore.jobs().isEmpty)

        let imported = await appStore.importArchiveRecordAsMeeting(record.id)
        XCTAssertTrue(imported)

        XCTAssertTrue(appStore.meetings.contains { $0.id == expectedMeetingID })
        let source = try XCTUnwrap(knowledgeStore.sources(meetingID: expectedMeetingID).first)
        XCTAssertEqual(source.sourceKind, .archive)
        XCTAssertEqual(source.fullText, body)
        XCTAssertEqual(knowledgeStore.jobs().first?.sourceID, source.id)
        XCTAssertEqual(appStore.archiveReviewSession?.report.orphanCount, 0)
        XCTAssertEqual(appStore.archiveReviewSession?.report.matchedCount, 1)
    }

    func testSensitiveOrphanImportsLocallyWithoutQueuingCloudExtraction() async throws {
        let (appStore, knowledgeStore, directory) = makeAppStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let body = String(repeating: "这是一场虚构绩效校准会议。", count: 45)
        let end = 4_400_000_000 + TimeInterval(Int.random(in: 1...100_000))
        let file = archive(name: "sensitive-orphan", body: body, start: end - 600, end: end)
        let record = try XCTUnwrap(appStore.prepareArchiveReview(
            archives: [file], storedMeetings: []).records.first)

        let imported = await appStore.importArchiveRecordAsMeeting(record.id)
        XCTAssertTrue(imported)

        let source = try XCTUnwrap(knowledgeStore.sources().first)
        XCTAssertEqual(source.sensitivity, .restricted)
        XCTAssertTrue(knowledgeStore.jobs().isEmpty)
        XCTAssertTrue(KnowledgePrivacyPolicy.mayPersistAndSearchLocally(source.sensitivity))
    }
}
