import XCTest
@testable import AfterMeet

final class PlainTextSegmenterTests: XCTestCase {
    private func assertLossless(_ content: String,
                                bundle: KnowledgeSourceBundle,
                                file: StaticString = #filePath,
                                line: UInt = #line) {
        XCTAssertEqual(bundle.segments.map(\.text).joined(), content, file: file, line: line)
        XCTAssertEqual(bundle.segments.first?.charStart, content.isEmpty ? nil : 0, file: file, line: line)
        XCTAssertEqual(bundle.segments.last?.charEnd, content.isEmpty ? nil : content.count, file: file, line: line)
        for index in bundle.segments.indices {
            let segment = bundle.segments[index]
            if index > 0 {
                XCTAssertEqual(bundle.segments[index - 1].charEnd, segment.charStart, file: file, line: line)
            }
            let characters = Array(content)
            XCTAssertEqual(
                segment.text,
                String(characters[segment.charStart..<segment.charEnd]),
                file: file,
                line: line)
        }
    }

    func testChineseTextUsesNaturalBoundariesAndStaysWithinTokenWindow() {
        let content = (0..<180).map { "第\($0)段讨论了虚构项目的进度、风险和下一步行动。" }.joined(separator: "\n")
        let first = KnowledgeSegmenter.plainTextSourceBundle(
            content: content, meetingID: "plain-chinese", observedAt: 10)
        let second = KnowledgeSegmenter.plainTextSourceBundle(
            content: content, meetingID: "plain-chinese", observedAt: 10)

        assertLossless(content, bundle: first)
        XCTAssertGreaterThan(first.segments.count, 1)
        XCTAssertEqual(first.document, second.document)
        XCTAssertEqual(first.segments, second.segments)
        for (index, segment) in first.segments.enumerated() {
            XCTAssertLessThanOrEqual(KnowledgeSegmenter.estimatedTokenCount(segment.text), 600)
            if index < first.segments.count - 1 {
                XCTAssertGreaterThanOrEqual(KnowledgeSegmenter.estimatedTokenCount(segment.text), 250)
                XCTAssertTrue("。！？!?；;\n".contains(segment.text.last!))
            }
        }
    }

    func testLongUnpunctuatedASCIITextHardSplitsWithoutLoss() {
        let content = String(repeating: "abcdefghijklmnop ", count: 500)
        let bundle = KnowledgeSegmenter.plainTextSourceBundle(
            content: content, meetingID: "plain-ascii", observedAt: 10)

        assertLossless(content, bundle: bundle)
        XCTAssertGreaterThan(bundle.segments.count, 1)
        XCTAssertTrue(bundle.segments.allSatisfy {
            KnowledgeSegmenter.estimatedTokenCount($0.text) <= 600
        })
    }

    func testMixedLineEndingsAndWhitespaceRemainByteForCharacterEquivalent() {
        let content = "第一段。\r\nSecond paragraph?\r第三段保留尾部空格。   \n"
        let bundle = KnowledgeSegmenter.plainTextSourceBundle(
            content: content,
            meetingID: "plain-mixed",
            sourceKind: .liveLocal,
            locator: "/tmp/fixture.txt",
            observedAt: 10)

        assertLossless(content, bundle: bundle)
        XCTAssertEqual(bundle.document.fullText, content)
        XCTAssertEqual(bundle.document.sourceKind, .liveLocal)
    }

    func testShortAndEmptyContentHaveHonestShapes() {
        let short = KnowledgeSegmenter.plainTextSourceBundle(
            content: "短文本。", meetingID: "plain-short", observedAt: 10)
        let empty = KnowledgeSegmenter.plainTextSourceBundle(
            content: "", meetingID: "plain-empty", observedAt: 10)

        assertLossless("短文本。", bundle: short)
        XCTAssertEqual(short.segments.count, 1)
        XCTAssertTrue(empty.segments.isEmpty)
        XCTAssertEqual(empty.document.fullText, "")
    }

    func testCaptureWithoutStructuredSegmentsFallsBackToLosslessPlainTextSegments() {
        let text = (0..<140).map { "第\($0)句是捕获结果的合成内容。" }.joined()
        let capture = CapturedTranscript(
            text: text,
            segments: [],
            transcriptionMode: .unknown,
            sessionID: "capture-without-segments",
            startedAt: 1,
            endedAt: 2,
            durationSec: 1,
            transcriptPath: "/tmp/fixture.txt",
            segmentSidecarPath: nil)
        let bundle = KnowledgeSegmenter.sourceBundle(from: capture, meetingID: "capture-fallback")

        assertLossless(text, bundle: bundle)
        XCTAssertFalse(bundle.segments.isEmpty)
        XCTAssertTrue(bundle.segments.allSatisfy { $0.metadataJSON.contains("capture-fallback") })
    }
}
