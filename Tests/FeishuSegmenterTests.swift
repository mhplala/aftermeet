import XCTest
@testable import AfterMeet

final class FeishuSegmenterTests: XCTestCase {
    func testParsesTimestampFirstSpeakerFirstAndUserNameFormats() throws {
        let content = """
        # 虚构飞书逐字稿
        [00:01] **甲**：第一句
        第一段的补充说明
        **乙** 00:05: 第二句
        [user-name=丙 00:08] 第三句
        00:12 丁：第四句
        """

        let bundle = KnowledgeSegmenter.feishuSourceBundle(
            content: content,
            meetingID: "feishu-parser-1",
            docToken: "fictional-token",
            observedAt: 10)

        XCTAssertEqual(bundle.segments.map(\.speaker), ["甲", "乙", "丙", "丁"])
        XCTAssertEqual(bundle.segments.map(\.startMS), [1_000, 5_000, 8_000, 12_000])
        XCTAssertEqual(bundle.segments.map(\.endMS), [5_000, 8_000, 12_000, 12_000])
        XCTAssertTrue(bundle.segments[0].text.contains("第一句"))
        XCTAssertTrue(bundle.segments[0].text.contains("补充说明"))
        XCTAssertEqual(bundle.segments.map(\.ordinal), [0, 1, 2, 3])
        XCTAssertTrue(bundle.segments.allSatisfy { $0.metadataJSON.contains("feishu-markdown") })
    }

    func testThreePartTimestampConvertsHoursMinutesSeconds() throws {
        let content = "[01:02:03] 甲：跨小时的句子"
        let segment = try XCTUnwrap(KnowledgeSegmenter.feishuSourceBundle(
            content: content,
            meetingID: "feishu-parser-2",
            docToken: "fictional-token",
            observedAt: 10).segments.first)

        XCTAssertEqual(segment.startMS, 3_723_000)
        XCTAssertEqual(segment.endMS, 3_723_000)
        XCTAssertEqual(segment.speaker, "甲")
    }

    func testUnknownMarkdownFallsBackWithoutDroppingText() throws {
        let content = """
        # 格式未知
        这是一段没有时间戳和说话人的正文。
        下一行仍然必须被保留。
        """
        let bundle = KnowledgeSegmenter.feishuSourceBundle(
            content: content,
            meetingID: "feishu-parser-fallback",
            docToken: "fictional-token",
            observedAt: 10)
        let segment = try XCTUnwrap(bundle.segments.first)

        XCTAssertEqual(bundle.segments.count, 1)
        XCTAssertNil(segment.speaker)
        XCTAssertNil(segment.startMS)
        XCTAssertNil(segment.endMS)
        XCTAssertEqual(segment.charStart, 0)
        XCTAssertEqual(segment.charEnd, content.count)
        XCTAssertTrue(segment.text.contains("下一行仍然必须被保留"))
        XCTAssertTrue(segment.metadataJSON.contains("feishu-fallback"))
    }

    func testMetadataLookingTimestampDoesNotBecomeSpeaker() throws {
        let content = "会议时间 14:30\n正文没有发言结构"
        let segment = try XCTUnwrap(KnowledgeSegmenter.feishuSourceBundle(
            content: content,
            meetingID: "feishu-parser-metadata",
            docToken: "fictional-token",
            observedAt: 10).segments.first)

        XCTAssertNil(segment.speaker)
        XCTAssertNil(segment.startMS)
        XCTAssertTrue(segment.text.contains("会议时间"))
    }
}
