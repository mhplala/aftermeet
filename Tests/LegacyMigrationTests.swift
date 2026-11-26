import XCTest
@testable import AfterMeet

final class LegacyMigrationTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AfterMeet-LegacyMigration-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeLiveFixture(to directory: URL) throws {
        let note = RefinedNote(
            title: "虚构旧会议", todos: [],
            blocks: [NoteBlock(type: "summary", text: "这是合成迁移数据。")])
        let meeting = StoredLiveMeeting(
            id: "legacy-live-1", title: "虚构旧会议", timestamp: 123,
            durationSec: 60, transcript: "甲：这是合成迁移数据。", note: note)
        try JSONEncoder().encode([meeting]).write(
            to: directory.appendingPathComponent("live-meetings.json"))
    }

    func testValidLegacyFilesSetCompletionMarker() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeLiveFixture(to: directory)
        try JSONEncoder().encode(["meeting-1": [QATurn(question: "问题", answer: "答案")]])
            .write(to: directory.appendingPathComponent("qa.json"))

        let database = DB(
            databaseURL: directory.appendingPathComponent("aftermeet.db"),
            migrateLegacyJSON: true,
            legacyBaseURL: directory)

        XCTAssertEqual(database.kvGet("migrated_v1"), "1")
        XCTAssertNil(database.legacyMigrationError)
        XCTAssertEqual(database.meetingPayloads(kind: "live").map(\.id), ["legacy-live-1"])
        XCTAssertEqual(database.dictAll("qa", keyCol: "meeting_id", valCol: "turns").count, 1)
    }

    func testPartialFailureDoesNotMarkCompleteAndRetryIsIdempotent() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeLiveFixture(to: directory)
        try Data("not-json".utf8).write(to: directory.appendingPathComponent("qa.json"))
        let databaseURL = directory.appendingPathComponent("aftermeet.db")

        do {
            let failed = DB(
                databaseURL: databaseURL,
                migrateLegacyJSON: true,
                legacyBaseURL: directory)
            XCTAssertNil(failed.kvGet("migrated_v1"))
            XCTAssertTrue(failed.legacyMigrationError?.contains("qa.json") == true)
            XCTAssertEqual(failed.meetingPayloads(kind: "live").map(\.id), ["legacy-live-1"])
        }

        try Data("{}".utf8).write(to: directory.appendingPathComponent("qa.json"))
        do {
            let recovered = DB(
                databaseURL: databaseURL,
                migrateLegacyJSON: true,
                legacyBaseURL: directory)
            XCTAssertEqual(recovered.kvGet("migrated_v1"), "1")
            XCTAssertNil(recovered.legacyMigrationError)
            XCTAssertEqual(recovered.meetingPayloads(kind: "live").map(\.id), ["legacy-live-1"])
            XCTAssertEqual(recovered.searchMeetings(tokens: ["合成迁移数据"]), ["legacy-live-1"])
        }
    }

    func testMalformedLegacyArrayDoesNotSilentlyDropBadRows() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let note = RefinedNote(
            title: "有效行", todos: [],
            blocks: [NoteBlock(type: "summary", text: "有效合成摘要")])
        let valid = StoredLiveMeeting(
            id: "legacy-valid", title: "有效行", timestamp: 1,
            durationSec: 30, transcript: "有效合成转写", note: note)
        let validObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(valid)) as? [String: Any])
        let mixed: [Any] = [validObject, ["id": "broken-row"]]
        try JSONSerialization.data(withJSONObject: mixed).write(
            to: directory.appendingPathComponent("live-meetings.json"))

        let database = DB(
            databaseURL: directory.appendingPathComponent("aftermeet.db"),
            migrateLegacyJSON: true,
            legacyBaseURL: directory)

        XCTAssertNil(database.kvGet("migrated_v1"))
        XCTAssertTrue(database.legacyMigrationError?.contains("live-meetings.json") == true)
        XCTAssertEqual(database.meetingPayloads(kind: "live").map(\.id), ["legacy-valid"])
    }
}
