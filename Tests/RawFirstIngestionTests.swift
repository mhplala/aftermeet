import XCTest
@testable import AfterMeet

private actor NoteRefinerGate {
    enum GateError: LocalizedError {
        case forcedFailure
        var errorDescription: String? { "forced test failure" }
    }

    private var continuation: CheckedContinuation<RefinedNote, Error>?
    private var failedBeforeWait = false

    func wait() async throws -> RefinedNote {
        if failedBeforeWait { throw GateError.forcedFailure }
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func fail() {
        if let continuation {
            self.continuation = nil
            continuation.resume(throwing: GateError.forcedFailure)
        } else {
            failedBeforeWait = true
        }
    }
}

@MainActor
final class RawFirstIngestionTests: XCTestCase {
    func testPendingMeetingIsRecoveredOnNextStoreInitialization() async throws {
        let timestamp = 4_100_000_000 + TimeInterval(Int.random(in: 1...100_000))
        let meetingID = "live-\(Int(timestamp))"
        let pending = StoredLiveMeeting(
            id: meetingID,
            title: "未命名会议",
            timestamp: timestamp,
            durationSec: 60,
            transcript: "甲：这是一段等待恢复的合成转写。",
            note: .processing())
        XCTAssertTrue(LiveStore.append(pending))

        let store = AppStore(loadPersistedData: true, noteRefiner: { _ in
            RefinedNote(
                title: "恢复成功会议",
                todos: [],
                blocks: [NoteBlock(type: "summary", text: "恢复后的合成摘要")])
        })
        for _ in 0..<50 {
            if LiveStore.load().first(where: { $0.id == meetingID })?.note.blocks?
                .contains(where: { $0.type == "summary" }) == true { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        let recovered = try XCTUnwrap(LiveStore.load().first { $0.id == meetingID })
        XCTAssertEqual(recovered.title, "恢复成功会议")
        XCTAssertTrue(recovered.note.blocks?.contains { $0.type == "summary" } == true)
        XCTAssertFalse(recovered.note.blocks?.contains { $0.type == "refinePending" } == true)
        XCTAssertFalse(store.regenPending.contains(meetingID))
        XCTAssertFalse(store.refining)
    }

    func testRawMeetingAndSourceExistBeforeRefinerFinishesAndSurviveFailure() async throws {
        let gate = NoteRefinerGate()
        let store = AppStore(
            knowledgeEnabledOverride: true,
            noteRefiner: { _ in try await gate.wait() })
        let endedAt = 4_000_000_000 + TimeInterval(Int.random(in: 1...100_000))
        let meetingID = "live-\(Int(endedAt))"
        let transcript = "甲：先保存原文。 乙：模型稍后再处理。"
        let capture = CapturedTranscript(
            text: transcript,
            segments: [
                CapturedSegment(
                    id: "capture:0", ordinal: 0, text: "甲：先保存原文。", speaker: nil,
                    startMS: 0, endMS: 800, timingQuality: .exact),
                CapturedSegment(
                    id: "capture:1", ordinal: 1, text: "乙：模型稍后再处理。", speaker: nil,
                    startMS: 800, endMS: 1_600, timingQuality: .exact)
            ],
            transcriptionMode: .cloud,
            sessionID: "raw-first-" + UUID().uuidString,
            startedAt: endedAt - 2,
            endedAt: endedAt,
            durationSec: 2,
            transcriptPath: "/tmp/raw-first.txt",
            segmentSidecarPath: "/tmp/raw-first.segments.jsonl")
        let jobCountBefore = KnowledgeStore.shared.jobs().count

        store.ingestLive(capture: capture, capturedName: "虚构原文优先会议")

        let inMemory = try XCTUnwrap(store.meetings.first { $0.id == meetingID })
        XCTAssertEqual(inMemory.rawTranscript, transcript)
        XCTAssertTrue(inMemory.blocks.contains { $0.type == "refinePending" })
        let persistedBeforeRefine = try XCTUnwrap(LiveStore.load().first { $0.id == meetingID })
        XCTAssertEqual(persistedBeforeRefine.transcript, transcript)
        XCTAssertTrue(persistedBeforeRefine.note.blocks?.contains { $0.type == "refinePending" } == true)
        let source = try XCTUnwrap(KnowledgeStore.shared.sources(meetingID: meetingID).first)
        XCTAssertEqual(source.fullText, transcript)
        XCTAssertEqual(KnowledgeStore.shared.segments(sourceID: source.id).count, 2)
        let jobs = KnowledgeStore.shared.jobs()
        XCTAssertEqual(jobs.count, jobCountBefore + 1)
        let extractionJob = try XCTUnwrap(jobs.first { $0.sourceID == source.id })
        XCTAssertEqual(extractionJob.state, .pending)

        await gate.fail()
        for _ in 0..<50 {
            if LiveStore.load().first(where: { $0.id == meetingID })?.note.blocks?
                .contains(where: { $0.type == "refineFailed" }) == true { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        let persistedAfterFailure = try XCTUnwrap(LiveStore.load().first { $0.id == meetingID })
        XCTAssertEqual(persistedAfterFailure.transcript, transcript)
        XCTAssertTrue(persistedAfterFailure.note.blocks?.contains { $0.type == "refineFailed" } == true)
        XCTAssertFalse(store.refining)
        XCTAssertEqual(KnowledgeStore.shared.sources(meetingID: meetingID).first?.fullText, transcript)
    }
}
