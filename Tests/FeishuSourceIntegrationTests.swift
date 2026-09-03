import XCTest
@testable import AfterMeet

@MainActor
final class FeishuSourceIntegrationTests: XCTestCase {
    private func realMeeting(id: String) throws -> RealMeeting {
        let object: [String: Any] = [
            "meeting_id": id,
            "title": "虚构飞书评审",
            "dateLabel": "9月2日 周三",
            "durationLabel": "10:00–10:30",
            "participants": 2,
            "organizer": "甲",
            "summary": "合成摘要",
            "keyPoints": [],
            "decisions": [],
            "todos": [],
            "disputes": [],
            "nextAgenda": [],
            "excerpts": [["time": "10:01", "who": "甲", "text": "只有这一条旧摘录"]],
            "blocks": []
        ]
        return try JSONDecoder().decode(
            RealMeeting.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testMeetingVMUsesFullSourceAndSegmentsWithExcerptFallback() throws {
        let meeting = try realMeeting(id: "feishu-vm-fixture")
        let content = "00:01 甲：第一段完整原文\n00:05 乙：第二段只在完整原文里"
        let bundle = KnowledgeSegmenter.feishuSourceBundle(
            content: content,
            meetingID: meeting.meeting_id,
            docToken: "fictional-token",
            observedAt: 10)

        let complete = MeetingVM(
            real: meeting,
            sourceText: bundle.document.fullText,
            sourceSegments: bundle.segments)
        let fallback = MeetingVM(real: meeting)

        XCTAssertEqual(complete.rawTranscript, content)
        XCTAssertEqual(complete.transcript.map(\.who), ["甲", "乙"])
        XCTAssertEqual(complete.transcript.map(\.time), ["0:01", "0:05"])
        XCTAssertTrue(complete.transcriptNote.contains("飞书逐字稿"))
        XCTAssertEqual(fallback.rawTranscript, "只有这一条旧摘录")
        XCTAssertTrue(fallback.transcriptNote.contains("完整逐字稿待同步"))
    }

    func testAppStoreBulkLoadsLatestFeishuSourceAndMeetingFTSIndexesFullText() throws {
        let id = "feishu-integration-" + UUID().uuidString
        let meeting = try realMeeting(id: id)
        let older = KnowledgeSegmenter.feishuSourceBundle(
            content: "00:01 甲：较早的完整原文",
            meetingID: id,
            docToken: "fictional-token",
            observedAt: 10)
        let latestText = "00:01 甲：较新的完整原文\n00:05 乙：独有检索词松针火花"
        let latest = KnowledgeSegmenter.feishuSourceBundle(
            content: latestText,
            meetingID: id,
            docToken: "fictional-token",
            observedAt: 20)
        XCTAssertTrue(KnowledgeStore.shared.saveSource(
            older.document, segments: older.segments, meetingTitle: meeting.title))
        XCTAssertTrue(KnowledgeStore.shared.saveSource(
            latest.document, segments: latest.segments, meetingTitle: meeting.title))
        XCTAssertTrue(RealData.upsert(meeting, sortTs: 20, fullTranscript: latestText))

        let appStore = AppStore(loadPersistedData: true)
        let loaded = try XCTUnwrap(appStore.meetings.first { $0.id == id })

        XCTAssertEqual(loaded.rawTranscript, latestText)
        XCTAssertEqual(loaded.transcript.map(\.who), ["甲", "乙"])
        XCTAssertTrue(DB.shared.searchMeetings(tokens: ["松针火花"]).contains(id))
    }
}
