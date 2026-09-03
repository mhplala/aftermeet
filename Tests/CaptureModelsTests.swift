import XCTest
@testable import AfterMeet

final class CaptureModelsTests: XCTestCase {
    func testCaptureModeResolutionCoversAllEngineCombinations() {
        XCTAssertEqual(CaptureTranscriptionMode.resolve(usedCloud: true, usedLocal: false), .cloud)
        XCTAssertEqual(CaptureTranscriptionMode.resolve(usedCloud: false, usedLocal: true), .local)
        XCTAssertEqual(CaptureTranscriptionMode.resolve(usedCloud: true, usedLocal: true), .mixed)
        XCTAssertEqual(CaptureTranscriptionMode.resolve(usedCloud: false, usedLocal: false), .unknown)
    }

    func testCloudRangesRemainMonotonicAcrossSessionTimelineResets() {
        let first = CaptureTimeline.absoluteRange(
            sessionOffsetMS: 0, startMS: 100, endMS: 800)
        let reconnected = CaptureTimeline.absoluteRange(
            sessionOffsetMS: 5_000, startMS: 0, endMS: 700,
            minimumStartMS: first.upperBound)
        let overlappingReconnect = CaptureTimeline.absoluteRange(
            sessionOffsetMS: 5_000, startMS: 0, endMS: 300,
            minimumStartMS: reconnected.upperBound)

        XCTAssertEqual(first, 100...800)
        XCTAssertEqual(reconnected, 5_000...5_700)
        XCTAssertEqual(overlappingReconnect, 5_700...5_700)
    }

    func testApproximateLocalRangeUsesAudioWindowAndNeverExceedsElapsedTime() {
        let first = CaptureTimeline.approximateRange(
            sessionElapsedSec: 8, sampleCount: 128_000, sampleRate: 16_000)
        let second = CaptureTimeline.approximateRange(
            sessionElapsedSec: 10, sampleCount: 32_000, sampleRate: 16_000,
            minimumStartMS: first.upperBound)
        let clamped = CaptureTimeline.approximateRange(
            sessionElapsedSec: 10, sampleCount: 8_000, sampleRate: 16_000,
            minimumStartMS: 11_000)

        XCTAssertEqual(first, 0...8_000)
        XCTAssertEqual(second, 8_000...10_000)
        XCTAssertEqual(clamped, 10_000...10_000)
        XCTAssertLessThanOrEqual(second.upperBound, 10_000)
    }

    func testSidecarPersistsEachFinalizedSegmentAndIgnoresCrashTruncatedTail() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AfterMeet-Sidecar-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("fixture.segments.jsonl")
        try CaptureSidecarStore.create(at: url)
        let first = CapturedSegment(
            id: "session-a:0", ordinal: 0, text: "第一句", speaker: nil,
            startMS: 0, endMS: 500, timingQuality: .exact)
        let second = CapturedSegment(
            id: "session-a:1", ordinal: 1, text: "第二句", speaker: nil,
            startMS: 500, endMS: 1_000, timingQuality: .exact)

        try CaptureSidecarStore.append(
            CapturedSegmentRecord(sessionID: "session-a", segment: first), to: url)
        try CaptureSidecarStore.append(
            CapturedSegmentRecord(sessionID: "session-a", segment: second), to: url)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"truncated\":".utf8))
        try handle.synchronize()
        try handle.close()

        let recovered = try CaptureSidecarStore.load(from: url)
        XCTAssertEqual(recovered.map(\.segment), [first, second])
        XCTAssertEqual(recovered.map(\.sessionID), ["session-a", "session-a"])
    }

    func testCapturedTranscriptRoundTripPreservesSessionAndPaths() throws {
        let segment = CapturedSegment(
            id: "session-a:0", ordinal: 0, text: "测试分句", speaker: nil,
            startMS: 100, endMS: 900, timingQuality: .exact)
        let transcript = CapturedTranscript(
            text: "测试分句", segments: [segment], transcriptionMode: .cloud,
            sessionID: "session-a", startedAt: 10, endedAt: 20, durationSec: 10,
            transcriptPath: "/tmp/fixture.txt", segmentSidecarPath: "/tmp/fixture.segments.jsonl")

        let decoded = try JSONDecoder().decode(
            CapturedTranscript.self, from: JSONEncoder().encode(transcript))

        XCTAssertEqual(decoded, transcript)
        XCTAssertEqual(decoded.segments.first?.id, "session-a:0")
        XCTAssertLessThanOrEqual(decoded.startedAt, decoded.endedAt)
    }

    func testSeparateCaptureResultsKeepIndependentSessionIdentity() {
        let first = CapturedTranscript(
            text: "", segments: [], transcriptionMode: .unknown,
            sessionID: UUID().uuidString, startedAt: 1, endedAt: 1, durationSec: 0,
            transcriptPath: "/tmp/first.txt", segmentSidecarPath: nil)
        let second = CapturedTranscript(
            text: "", segments: [], transcriptionMode: .unknown,
            sessionID: UUID().uuidString, startedAt: 2, endedAt: 2, durationSec: 0,
            transcriptPath: "/tmp/second.txt", segmentSidecarPath: nil)

        XCTAssertNotEqual(first.sessionID, second.sessionID)
        XCTAssertNotEqual(first.transcriptPath, second.transcriptPath)
    }
}
