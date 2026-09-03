import XCTest
@testable import AfterMeet

private struct EmptyPilotClient: KnowledgeExtractionClient {
    let delayNanoseconds: UInt64

    func complete(systemPrompt: String,
                  userPrompt: String,
                  maxTokens: Int) async throws -> String {
        if delayNanoseconds > 0 { try await Task.sleep(nanoseconds: delayNanoseconds) }
        func field(_ name: String) -> String {
            let line = userPrompt.split(separator: "\n").first { $0.hasPrefix(name + ":") }!
            return line.dropFirst(name.count + 1).trimmingCharacters(in: .whitespaces)
        }
        let object: [String: Any] = [
            "schema_version": 1,
            "source_hash": field("source_hash"),
            "chunk_index": Int(field("chunk_index"))!,
            "units": []
        ]
        return String(
            data: try JSONSerialization.data(withJSONObject: object),
            encoding: .utf8)!
    }
}

@MainActor
final class KnowledgeBackfillControlTests: XCTestCase {
    private func makeAppStore() -> (AppStore, KnowledgeStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AfterMeet-BackfillControl-" + UUID().uuidString)
        let knowledgeStore = KnowledgeStore(database: DB(
            databaseURL: directory.appendingPathComponent("aftermeet.db")))
        let appStore = AppStore(
            loadPersistedData: false,
            knowledgeEnabledOverride: true,
            knowledgeStore: knowledgeStore)
        return (appStore, knowledgeStore, directory)
    }

    private func meeting(id: String,
                         title: String,
                         timestamp: TimeInterval,
                         characters: Int = 600) -> StoredLiveMeeting {
        StoredLiveMeeting(
            id: id,
            title: title,
            timestamp: timestamp,
            durationSec: 600,
            transcript: String(repeating: "普通虚构会议内容。", count: max(1, characters / 9)),
            note: .processing())
    }

    func testPilotPreparesAtMostLimitAndSkipsSensitiveShortAndExistingJobs() throws {
        let (appStore, knowledgeStore, directory) = makeAppStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let meetings = [
            meeting(id: "normal-new", title: "普通项目周会", timestamp: 40),
            meeting(id: "sensitive", title: "团队绩效校准", timestamp: 30),
            meeting(id: "short", title: "短会", timestamp: 20, characters: 20),
            meeting(id: "normal-old", title: "普通方案评审", timestamp: 10)
        ]

        XCTAssertEqual(appStore.knowledgeBackfillProgress.total, 0)
        XCTAssertTrue(appStore.knowledgeBackfillPaused)
        XCTAssertEqual(appStore.prepareKnowledgePilot(from: meetings, limit: 1), 1)
        XCTAssertEqual(knowledgeStore.sources().map(\.meetingID), ["normal-new"])
        XCTAssertEqual(knowledgeStore.jobs().count, 1)

        XCTAssertEqual(appStore.prepareKnowledgePilot(from: meetings, limit: 10), 1)
        XCTAssertEqual(Set(knowledgeStore.sources().map(\.meetingID)), Set(["normal-new", "normal-old"]))
        XCTAssertEqual(knowledgeStore.jobs().count, 2)
        XCTAssertEqual(appStore.knowledgeBackfillProgress.total, 2)
        XCTAssertEqual(appStore.knowledgeBackfillProgress.waiting, 2)
        XCTAssertTrue(knowledgeStore.sources().allSatisfy { $0.sensitivity == .normal })
    }

    func testQueueWithInjectedClientCompletesAndPersistsProgressAcrossStoreInstances() async throws {
        let (appStore, knowledgeStore, directory) = makeAppStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let meetings = [
            meeting(id: "normal-a", title: "普通周会 A", timestamp: 20),
            meeting(id: "normal-b", title: "普通周会 B", timestamp: 10)
        ]
        XCTAssertEqual(appStore.prepareKnowledgePilot(from: meetings, limit: 10), 2)
        appStore.knowledgeBackfillPaused = false

        await appStore.runKnowledgeQueue(client: EmptyPilotClient(delayNanoseconds: 0))

        XCTAssertFalse(appStore.knowledgeBackfillRunning)
        XCTAssertEqual(appStore.knowledgeBackfillProgress.completed, 2)
        XCTAssertEqual(appStore.knowledgeBackfillProgress.waiting, 0)
        let reopened = AppStore(
            loadPersistedData: false,
            knowledgeEnabledOverride: true,
            knowledgeStore: knowledgeStore)
        XCTAssertEqual(reopened.knowledgeBackfillProgress.total, 2)
        XCTAssertEqual(reopened.knowledgeBackfillProgress.completed, 2)
    }

    func testPilotQueueDoesNotConsumeUnrelatedPendingJob() async throws {
        let (appStore, knowledgeStore, directory) = makeAppStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let unrelatedBundle = KnowledgeSegmenter.plainTextSourceBundle(
            content: String(repeating: "无关普通来源。", count: 60),
            meetingID: "unrelated-meeting",
            observedAt: 1)
        XCTAssertTrue(knowledgeStore.saveSource(
            unrelatedBundle.document,
            segments: unrelatedBundle.segments,
            meetingTitle: "无关来源"))
        guard case .enqueued(let unrelatedJob) = KnowledgeJobPlanner.planExtraction(
            for: unrelatedBundle.document,
            store: knowledgeStore,
            enabled: true,
            now: 1) else { return XCTFail("expected unrelated job") }
        appStore.refreshKnowledgeState()
        XCTAssertEqual(appStore.knowledgeBackfillProgress.total, 0)

        XCTAssertEqual(appStore.prepareKnowledgePilot(from: [
            meeting(id: "pilot-only", title: "试跑会议", timestamp: 10)
        ], limit: 10), 1)
        appStore.knowledgeBackfillPaused = false
        await appStore.runKnowledgeQueue(client: EmptyPilotClient(delayNanoseconds: 0))

        XCTAssertEqual(appStore.knowledgeBackfillProgress.total, 1)
        XCTAssertEqual(appStore.knowledgeBackfillProgress.completed, 1)
        XCTAssertEqual(knowledgeStore.jobs().first { $0.id == unrelatedJob.id }?.state, .pending)
        XCTAssertFalse(knowledgeStore.pilotJobIDs().contains(unrelatedJob.id))
        XCTAssertEqual(knowledgeStore.pilotJobIDs().count, 1)
    }

    func testPauseStopsAfterCurrentSourceAndLeavesRemainingJobPending() async throws {
        let (appStore, _, directory) = makeAppStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let meetings = [
            meeting(id: "pause-a", title: "普通周会 A", timestamp: 20),
            meeting(id: "pause-b", title: "普通周会 B", timestamp: 10)
        ]
        XCTAssertEqual(appStore.prepareKnowledgePilot(from: meetings, limit: 10), 2)
        appStore.knowledgeBackfillPaused = false
        let task = Task {
            await appStore.runKnowledgeQueue(client: EmptyPilotClient(delayNanoseconds: 50_000_000))
        }
        for _ in 0..<100 {
            if appStore.knowledgeBackfillRunning { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }

        appStore.pauseKnowledgeBackfill()
        await task.value

        XCTAssertTrue(appStore.knowledgeBackfillPaused)
        XCTAssertEqual(appStore.knowledgeBackfillProgress.completed, 1)
        XCTAssertEqual(appStore.knowledgeBackfillProgress.waiting, 1)
        XCTAssertEqual(appStore.knowledgeBackfillProgress.running, 0)
    }
}
