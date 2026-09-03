import XCTest
@testable import AfterMeet

final class KnowledgeIdentityTests: XCTestCase {
    func testContentHashNormalizesLineEndingsAndUnicodeComposition() {
        let composed = "Café\n第二行"
        let decomposedCRLF = "Cafe\u{301}\r\n第二行"

        XCTAssertEqual(
            KnowledgeIdentity.contentHash(composed),
            KnowledgeIdentity.contentHash(decomposedCRLF))
    }

    func testContentHashDoesNotHideMeaningfulWhitespaceChanges() {
        XCTAssertNotEqual(
            KnowledgeIdentity.contentHash("甲 乙"),
            KnowledgeIdentity.contentHash("甲乙"))
    }

    func testSourceIdentityIgnoresFileLocationAndWallClockTimezone() {
        let hash = KnowledgeIdentity.contentHash("虚构会议原文")
        let first = KnowledgeIdentity.sourceID(
            meetingID: "meeting-1", sourceKind: .liveCloud, contentHash: hash)
        let afterPathOrTimezoneChange = KnowledgeIdentity.sourceID(
            meetingID: "meeting-1", sourceKind: .liveCloud, contentHash: hash)

        XCTAssertEqual(first, afterPathOrTimezoneChange)
        XCTAssertNotEqual(first, KnowledgeIdentity.sourceID(
            meetingID: "meeting-1", sourceKind: .liveLocal, contentHash: hash))
        XCTAssertNotEqual(first, KnowledgeIdentity.sourceID(
            meetingID: "meeting-2", sourceKind: .liveCloud, contentHash: hash))
    }

    func testCapturedTranscriptMapsToStableSourceAndExactCharacterRanges() throws {
        let capture = CapturedTranscript(
            text: "第一句 第二句",
            segments: [
                CapturedSegment(id: "capture:0", ordinal: 0, text: "第一句", speaker: nil,
                                startMS: 0, endMS: 500, timingQuality: .exact),
                CapturedSegment(id: "capture:1", ordinal: 1, text: "第二句", speaker: nil,
                                startMS: 500, endMS: 1_000, timingQuality: .exact)
            ],
            transcriptionMode: .cloud, sessionID: "capture-session", startedAt: 1,
            endedAt: 2, durationSec: 1, transcriptPath: "/tmp/capture.txt",
            segmentSidecarPath: "/tmp/capture.segments.jsonl")

        let first = KnowledgeSegmenter.sourceBundle(from: capture, meetingID: "meeting-1")
        let second = KnowledgeSegmenter.sourceBundle(from: capture, meetingID: "meeting-1")

        XCTAssertEqual(first.document, second.document)
        XCTAssertEqual(first.segments, second.segments)
        XCTAssertEqual(first.document.sourceKind, .liveCloud)
        XCTAssertEqual(first.segments.map(\.charStart), [0, 4])
        XCTAssertEqual(first.segments.map(\.charEnd), [3, 7])
        XCTAssertEqual(first.segments.map(\.startMS), [0, 500])
        XCTAssertTrue(first.document.metadataJSON.contains("capture-session"))
        XCTAssertTrue(first.segments.allSatisfy { $0.metadataJSON.contains("\"rangeMatched\":true") })
    }

    func testMixedAndUnknownCaptureModesMapToSupportedSourceKinds() {
        func capture(_ mode: CaptureTranscriptionMode) -> CapturedTranscript {
            CapturedTranscript(
                text: "文本", segments: [], transcriptionMode: mode, sessionID: "session",
                startedAt: 1, endedAt: 2, durationSec: 1, transcriptPath: "/tmp/x", segmentSidecarPath: nil)
        }

        XCTAssertEqual(
            KnowledgeSegmenter.sourceBundle(from: capture(.mixed), meetingID: "m").document.sourceKind,
            .liveCloud)
        XCTAssertEqual(
            KnowledgeSegmenter.sourceBundle(from: capture(.unknown), meetingID: "m").document.sourceKind,
            .liveLocal)
    }

    func testFeishuSourcePersistsIdempotentlyBeforeAnyMeetingNoteExists() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AfterMeet-FeishuSource-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = DB(databaseURL: directory.appendingPathComponent("aftermeet.db"))
        let store = KnowledgeStore(database: database)
        let first = KnowledgeSegmenter.feishuSourceBundle(
            content: "# 虚构飞书逐字稿\n\n00:00 甲：先保存全文，再生成纪要。",
            meetingID: "feishu-meeting-1",
            docToken: "fictional-doc-token",
            observedAt: 10)

        XCTAssertTrue(store.saveSource(first.document, segments: first.segments, meetingTitle: "虚构飞书会议"))
        XCTAssertTrue(store.saveSource(first.document, segments: first.segments, meetingTitle: "虚构飞书会议"))
        XCTAssertEqual(store.sources(meetingID: "feishu-meeting-1"), [first.document])
        XCTAssertEqual(store.sources(meetingID: "feishu-meeting-1").first?.locator, "fictional-doc-token")
        XCTAssertTrue(database.meetingPayloads(kind: "feishu").isEmpty)

        let changed = KnowledgeSegmenter.feishuSourceBundle(
            content: first.document.fullText + "\n00:20 乙：这是后续新增的一句。",
            meetingID: "feishu-meeting-1",
            docToken: "fictional-doc-token",
            observedAt: 20)
        XCTAssertNotEqual(changed.document.id, first.document.id)
        XCTAssertTrue(store.saveSource(changed.document, segments: [], meetingTitle: "虚构飞书会议"))
        XCTAssertEqual(store.sources(meetingID: "feishu-meeting-1").count, 2)
    }

    func testSegmentIdentityIsStablePerSourceAndOrdinal() {
        let sourceID = KnowledgeIdentity.sourceID(
            meetingID: "meeting-1", sourceKind: .archive,
            contentHash: KnowledgeIdentity.contentHash("原文"))

        XCTAssertEqual(
            KnowledgeIdentity.segmentID(sourceID: sourceID, ordinal: 0),
            KnowledgeIdentity.segmentID(sourceID: sourceID, ordinal: 0))
        XCTAssertNotEqual(
            KnowledgeIdentity.segmentID(sourceID: sourceID, ordinal: 0),
            KnowledgeIdentity.segmentID(sourceID: sourceID, ordinal: 1))
    }
}
