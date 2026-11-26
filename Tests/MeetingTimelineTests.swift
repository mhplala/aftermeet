import XCTest
@testable import AfterMeet

@MainActor
final class MeetingTimelineTests: XCTestCase {
    private var directories: [URL] = []
    private func directory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("AfterMeet-Timeline-" + UUID().uuidString)
        directories.append(url)
        return url
    }
    override func tearDown() async throws {
        for directory in directories { try? FileManager.default.removeItem(at: directory) }
        directories = []
    }
    private func segment(_ index: Int, session: String = "a", text: String? = nil) -> CapturedSegment {
        CapturedSegment(id: "\(session):\(index)", ordinal: index,
                        text: text ?? "第\(index)句：先验证桌面版，移动端仍待讨论。",
                        speaker: nil, startMS: index * 1000, endMS: (index + 1) * 1000, timingQuality: .exact)
    }
    private func summary(_ title: String = "首版范围") -> MeetingTimelineSummary {
        MeetingTimelineSummary(title: title, points: ["先验证桌面版。", "移动端仍待讨论。"],
                               currentProgress: "正在确认首版范围，移动端尚未决定。")
    }
    private func store(_ url: URL? = nil) -> MeetingTimelineStore {
        let result = summary()
        return MeetingTimelineStore(directory: url ?? directory(), summarizer: { _ in result })
    }

    func testSilenceAndTooLittleSpeechDoNotCreateRepeatedEmptySummaries() async {
        let store = store()
        store.begin(sessionID: "a", title: "", startedAt: Date())
        store.tick(sessionID: "a", elapsedSec: 500)
        XCTAssertTrue(store.documents["a"]!.chunks.isEmpty)
        store.append(segment(0, text: "嗯"), sessionID: "a")
        store.tick(sessionID: "a", elapsedSec: 600)
        XCTAssertTrue(store.documents["a"]!.chunks.isEmpty)
        store.finish(sessionID: "a")
        await store.waitForSummaries()
        await store.waitForPersistence()
        XCTAssertEqual(store.documents["a"]!.chunks.count, 1)
        XCTAssertEqual(store.documents["a"]!.chunks[0].segmentIDs, ["a:0"])
    }

    func testThreeMinuteWindowSummarizesOnlyFinalizedUncoveredSpeechOnce() async {
        var inputs: [MeetingTimelineSummaryInput] = []
        let result = summary()
        let store = MeetingTimelineStore(directory: directory(), summarizer: { input in inputs.append(input); return result })
        store.begin(sessionID: "a", title: "产品会议", startedAt: Date())
        for i in 0..<10 { store.append(segment(i), sessionID: "a") }
        store.tick(sessionID: "a", elapsedSec: 179)
        XCTAssertTrue(store.documents["a"]!.chunks.isEmpty)
        store.tick(sessionID: "a", elapsedSec: 180)
        store.tick(sessionID: "a", elapsedSec: 185)
        await store.waitForSummaries()
        store.finish(sessionID: "a")
        await store.waitForPersistence()
        XCTAssertEqual(inputs.count, 1)
        XCTAssertEqual(store.documents["a"]!.coveredSegmentCount, 10)
        XCTAssertEqual(store.documents["a"]!.chunks[0].segmentIDs, (0..<10).map { "a:\($0)" })
        XCTAssertTrue(inputs[0].transcript.contains("第0句"))
        XCTAssertTrue(inputs[0].transcript.contains("第9句"))
    }

    func testRawHistoryBeyondSixtyLinesAndTailSurvivesReloadAndMeetingBinding() async {
        let url = directory()
        let store = store(url)
        store.begin(sessionID: "a", title: "产品会议", startedAt: Date())
        for i in 0..<95 { store.append(segment(i), sessionID: "a") }
        store.tick(sessionID: "a", elapsedSec: 180)
        store.append(segment(95, text: "最后补充：下周再定排期。"), sessionID: "a")
        store.finish(sessionID: "a")
        store.bind(sessionID: "a", meetingID: "live-123", title: "最终会议标题")
        await store.waitForSummaries()
        await store.waitForPersistence()
        let reloaded = self.store(url)
        let doc = reloaded.documents["a"]!
        XCTAssertEqual(reloaded.session(forMeetingID: "live-123"), "a")
        XCTAssertEqual(doc.state, .finished)
        XCTAssertEqual(doc.title, "最终会议标题")
        XCTAssertEqual(doc.segments.count, 96)
        XCTAssertEqual(doc.chunks.count, 2)
        XCTAssertEqual(doc.chunks.flatMap(\.segmentIDs), doc.segments.map(\.id))
        XCTAssertEqual(doc.source(for: doc.chunks[0]).first?.text, segment(0).text)
        XCTAssertEqual(doc.source(for: doc.chunks[1]).last?.text, "最后补充：下周再定排期。")
    }

    func testDelayedSummaryCannotOverwriteNewSessionOrOldMeetingTitle() async {
        let result = summary()
        let store = MeetingTimelineStore(directory: directory(), summarizer: { input in
            try await Task.sleep(nanoseconds: 20_000_000)
            return MeetingTimelineSummary(title: input.transcript.contains("第二场") ? "第二场摘要" : "第一场摘要",
                                          points: result.points, currentProgress: result.currentProgress)
        })
        store.begin(sessionID: "a", title: "第一场", startedAt: Date())
        store.append(segment(0, text: "第一场会议内容"), sessionID: "a")
        store.finish(sessionID: "a")
        store.bind(sessionID: "a", meetingID: "live-a", title: "第一场最终标题")
        store.begin(sessionID: "b", title: "第二场", startedAt: Date())
        store.append(segment(0, session: "b", text: "第二场会议内容"), sessionID: "b")
        store.finish(sessionID: "b")
        await store.waitForSummaries()
        await store.waitForPersistence()
        XCTAssertEqual(store.documents["a"]!.chunks[0].summary?.title, "第一场摘要")
        XCTAssertEqual(store.documents["b"]!.chunks[0].summary?.title, "第二场摘要")
        XCTAssertEqual(store.documents["a"]!.title, "第一场最终标题")
        XCTAssertEqual(store.documents["a"]!.meetingID, "live-a")
    }

    func testFailureKeepsSourceAndRetryDoesNotDuplicateChunk() async {
        var attempts = 0
        let result = summary()
        let store = MeetingTimelineStore(directory: directory(), summarizer: { _ in
            attempts += 1
            if attempts == 1 { throw NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "服务暂不可用"]) }
            return result
        })
        store.begin(sessionID: "a", title: "", startedAt: Date())
        store.append(segment(0), sessionID: "a")
        store.finish(sessionID: "a")
        await store.waitForSummaries()
        let id = store.documents["a"]!.chunks[0].id
        XCTAssertEqual(store.documents["a"]!.chunks[0].state, .failed)
        XCTAssertEqual(store.documents["a"]!.source(for: store.documents["a"]!.chunks[0]).count, 1)
        store.retry(sessionID: "a", chunkID: id)
        store.retry(sessionID: "a", chunkID: id)
        await store.waitForSummaries()
        await store.waitForPersistence()
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(store.documents["a"]!.chunks.count, 1)
        XCTAssertEqual(store.documents["a"]!.chunks[0].state, .ready)
    }

    func testRetryingOldFailureDoesNotUseFutureSummaryAsContext() async {
        var inputs: [MeetingTimelineSummaryInput] = []
        let result = summary()
        let store = MeetingTimelineStore(directory: directory(), summarizer: { input in
            inputs.append(input)
            if inputs.count == 1 { throw NSError(domain: "fixture", code: 1) }
            return result
        })
        store.begin(sessionID: "a", title: "", startedAt: Date())
        store.append(segment(0), sessionID: "a")
        store.sealPending(sessionID: "a")
        await store.waitForSummaries()
        store.append(segment(1), sessionID: "a")
        store.sealPending(sessionID: "a")
        await store.waitForSummaries()
        store.retry(sessionID: "a", chunkID: store.documents["a"]!.chunks[0].id)
        await store.waitForSummaries()
        await store.waitForPersistence()
        XCTAssertEqual(inputs.count, 3)
        XCTAssertTrue(inputs[2].previousProgress.isEmpty)
        XCTAssertTrue(inputs[2].recentSummaries.isEmpty)
        XCTAssertFalse(inputs[2].transcript.contains("第1句"))
    }

    func testInterruptedPendingSpeechRemainsAccessibleWithoutAutomaticNetworkCall() async throws {
        let url = directory()
        let store = store(url)
        store.begin(sessionID: "a", title: "未完成的会", startedAt: Date())
        store.append(segment(0), sessionID: "a")
        await store.waitForPersistence()
        var calls = 0
        let result = summary()
        let restored = MeetingTimelineStore(directory: url, summarizer: { _ in calls += 1; return result })
        XCTAssertNil(restored.activeSessionID)
        XCTAssertEqual(restored.unboundDocuments.first?.state, .interrupted)
        XCTAssertEqual(restored.documents["a"]!.pendingSegments.count, 1)
        XCTAssertEqual(calls, 0)
        restored.sealPending(sessionID: "a")
        await restored.waitForSummaries()
        await restored.waitForPersistence()
        XCTAssertEqual(calls, 1)
    }

    func testLargeBacklogIsPartitionedWithoutDroppingOrDuplicatingSource() async {
        let store = store()
        store.begin(sessionID: "a", title: "", startedAt: Date())
        for i in 0..<8 {
            store.append(segment(i, text: String(repeating: "语", count: 2500)), sessionID: "a")
        }
        store.finish(sessionID: "a")
        await store.waitForSummaries()
        await store.waitForPersistence()
        let doc = store.documents["a"]!
        XCTAssertEqual(doc.chunks.flatMap(\.segmentIDs), (0..<8).map { "a:\($0)" })
        XCTAssertTrue(doc.chunks.allSatisfy { doc.source(for: $0).reduce(0) { $0 + $1.text.count } <= 6000 })
    }

    func testCompactViewKeepsThreeVisibleCardsStableUntilReaderRequestsLatest() {
        var browsing = MeetingTimelineBrowsingState()
        browsing.open(["1", "2", "3", "4", "5"], all: false)
        XCTAssertEqual(browsing.visibleIDs, ["3", "4", "5"])
        let updated = ["1", "2", "3", "4", "5", "6", "7"]
        XCTAssertEqual(browsing.unseenCount(updated), 2)
        XCTAssertEqual(browsing.visibleIDs, ["3", "4", "5"])
        browsing.showAll(updated)
        XCTAssertEqual(browsing.visibleIDs, updated)
        XCTAssertEqual(browsing.expandedIDs, Set(["3", "4", "5"]))
        browsing.showLatest(updated)
        XCTAssertTrue(browsing.showsAll)
        XCTAssertEqual(browsing.expandedIDs, Set(["5", "6", "7"]))
    }

    func testFullTimelineShowsEveryTitleWithOnlyLastThreeExpanded() {
        var browsing = MeetingTimelineBrowsingState()
        let ids = (1...20).map(String.init)
        browsing.open(ids, all: true)
        XCTAssertEqual(browsing.visibleIDs, ids)
        XCTAssertEqual(browsing.expandedIDs, Set(["18", "19", "20"]))
        browsing.toggle("1")
        XCTAssertTrue(browsing.expandedIDs.contains("1"))
        XCTAssertEqual(MeetingTimelineStore.time(3_665_000), "1:01:05")
    }
}
