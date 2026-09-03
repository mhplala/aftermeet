import XCTest
@testable import AfterMeet

private actor WorkerGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var entered = false

    func wait() async {
        entered = true
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

final class KnowledgeExtractionWorkerTests: XCTestCase {
    private enum FixtureError: LocalizedError {
        case failed
        var errorDescription: String? { "fixture operation failed" }
    }

    private func makeStore() -> (KnowledgeStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AfterMeet-Worker-" + UUID().uuidString)
        return (KnowledgeStore(database: DB(
            databaseURL: directory.appendingPathComponent("aftermeet.db"))), directory)
    }

    private func source(in store: KnowledgeStore,
                        meetingID: String,
                        text: String) -> KnowledgeSourceDocument {
        let bundle = KnowledgeSegmenter.plainTextSourceBundle(
            content: text, meetingID: meetingID, observedAt: 1)
        XCTAssertTrue(store.saveSource(bundle.document, segments: bundle.segments, meetingTitle: meetingID))
        return bundle.document
    }

    private func enqueue(in store: KnowledgeStore,
                         source: KnowledgeSourceDocument,
                         now: TimeInterval) -> KnowledgeExtractionJob {
        guard case .enqueued(let job) = KnowledgeJobPlanner.planExtraction(
            for: source, store: store, enabled: true, now: now) else {
            XCTFail("expected job")
            fatalError()
        }
        return job
    }

    func testAtomicClaimNeverReturnsSameRunningJobTwice() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstSource = source(in: store, meetingID: "meeting-1", text: "第一份普通内容。")
        let secondSource = source(in: store, meetingID: "meeting-2", text: "第二份普通内容。")
        let firstJob = enqueue(in: store, source: firstSource, now: 1)
        let secondJob = enqueue(in: store, source: secondSource, now: 2)

        let firstClaim = try XCTUnwrap(store.claimNextJob(now: 10, leaseDuration: 60))
        let secondClaim = try XCTUnwrap(store.claimNextJob(now: 10, leaseDuration: 60))

        XCTAssertEqual(firstClaim.id, firstJob.id)
        XCTAssertEqual(secondClaim.id, secondJob.id)
        XCTAssertNotEqual(firstClaim.id, secondClaim.id)
        XCTAssertEqual(firstClaim.state, .running)
        XCTAssertEqual(firstClaim.attempt, 1)
        XCTAssertEqual(firstClaim.leaseUntil, 70)
        XCTAssertNil(store.claimNextJob(now: 10, leaseDuration: 60))
    }

    func testExpiredLeaseRecoversAndFutureRetryWaits() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = source(in: store, meetingID: "meeting-1", text: "等待恢复的普通内容。")
        let job = enqueue(in: store, source: source, now: 1)
        let first = try XCTUnwrap(store.claimNextJob(now: 10, leaseDuration: 5))
        XCTAssertEqual(first.id, job.id)

        let recovered = try XCTUnwrap(store.claimNextJob(now: 20, leaseDuration: 5))
        XCTAssertEqual(recovered.id, job.id)
        XCTAssertEqual(recovered.attempt, 2)
        XCTAssertEqual(recovered.state, .running)
        XCTAssertTrue(store.transitionJob(
            id: job.id, state: .retry, cursor: 2,
            nextRetryAt: 100, lastError: "temporary", now: 21))
        XCTAssertNil(store.claimNextJob(now: 99, leaseDuration: 5))
        XCTAssertEqual(store.claimNextJob(now: 100, leaseDuration: 5)?.id, job.id)
    }

    func testLeaseRenewalOnlyTouchesRunningJobs() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = source(in: store, meetingID: "meeting-1", text: "续租普通内容。")
        let job = enqueue(in: store, source: source, now: 1)
        _ = try XCTUnwrap(store.claimNextJob(now: 10, leaseDuration: 5))

        XCTAssertTrue(store.renewJobLease(id: job.id, now: 12, leaseDuration: 10))
        XCTAssertEqual(store.jobs().first { $0.id == job.id }?.leaseUntil, 22)
        XCTAssertTrue(store.transitionJob(id: job.id, state: .done, cursor: 1, now: 13))
        XCTAssertFalse(store.renewJobLease(id: job.id, now: 14, leaseDuration: 10))
    }

    func testActorAllowsOnlyOneOperationAndHeartbeatRenewsLease() async throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = source(in: store, meetingID: "meeting-1", text: "worker普通内容。")
        let job = enqueue(in: store, source: source, now: Date().timeIntervalSince1970)
        let gate = WorkerGate()
        let worker = KnowledgeExtractionWorker(
            store: store,
            leaseDuration: 1,
            heartbeatIntervalNanoseconds: 5_000_000)
        let firstTask = Task {
            await worker.runNext { claimed in
                XCTAssertEqual(claimed.id, job.id)
                await gate.wait()
                return 3
            }
        }
        for _ in 0..<50 {
            if await gate.entered { break }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        let claimedBeforeHeartbeat = try XCTUnwrap(store.jobs().first { $0.id == job.id })
        try await Task.sleep(nanoseconds: 20_000_000)
        let renewed = try XCTUnwrap(store.jobs().first { $0.id == job.id })

        let secondRan = await worker.runNext { _ in XCTFail("second operation must not run"); return 0 }
        XCTAssertFalse(secondRan)
        XCTAssertGreaterThan(renewed.updatedAt, claimedBeforeHeartbeat.updatedAt)
        XCTAssertGreaterThan(renewed.leaseUntil ?? 0, claimedBeforeHeartbeat.leaseUntil ?? 0)

        await gate.release()
        let firstRan = await firstTask.value
        XCTAssertTrue(firstRan)
        let finished = try XCTUnwrap(store.jobs().first { $0.id == job.id })
        XCTAssertEqual(finished.state, .done)
        XCTAssertEqual(finished.cursor, 3)
        XCTAssertNil(finished.leaseUntil)
    }

    func testPendingCancelAndManualRetryResetAttempt() async throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = source(in: store, meetingID: "meeting-cancel", text: "取消普通内容。")
        let job = enqueue(in: store, source: source, now: 1)
        let worker = KnowledgeExtractionWorker(store: store, clock: { 20 })

        let cancelledPending = await worker.cancel(jobID: job.id)
        XCTAssertTrue(cancelledPending)
        XCTAssertEqual(store.jobs().first { $0.id == job.id }?.state, .cancelled)
        XCTAssertNil(store.claimNextJob(now: 30, leaseDuration: 10))
        let retried = await worker.retry(jobID: job.id)
        XCTAssertTrue(retried)
        let reset = try XCTUnwrap(store.jobs().first { $0.id == job.id })
        XCTAssertEqual(reset.state, .pending)
        XCTAssertEqual(reset.attempt, 0)
        XCTAssertNil(reset.nextRetryAt)
    }

    func testRunningCancellationCancelsOperationAndCannotBeOverwrittenByCompletion() async throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = source(in: store, meetingID: "meeting-running-cancel", text: "运行中取消内容。")
        let job = enqueue(in: store, source: source, now: Date().timeIntervalSince1970)
        let worker = KnowledgeExtractionWorker(store: store)
        let task = Task {
            await worker.runNext { _ in
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return 99
            }
        }
        for _ in 0..<50 {
            if store.jobs().first(where: { $0.id == job.id })?.state == .running { break }
            try await Task.sleep(nanoseconds: 2_000_000)
        }

        let cancelResult = await worker.cancel(jobID: job.id)
        let taskResult = await task.value
        XCTAssertTrue(cancelResult)
        XCTAssertTrue(taskResult)
        let cancelled = try XCTUnwrap(store.jobs().first { $0.id == job.id })
        XCTAssertEqual(cancelled.state, .cancelled)
        XCTAssertNotEqual(cancelled.cursor, 99)
        XCTAssertNil(cancelled.leaseUntil)
    }

    func testOperationFailureReleasesLeaseAndRecordsError() async throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = source(in: store, meetingID: "meeting-1", text: "失败普通内容。")
        let job = enqueue(in: store, source: source, now: 1)
        let worker = KnowledgeExtractionWorker(store: store)

        let ran = await worker.runNext { _ in throw FixtureError.failed }
        XCTAssertTrue(ran)
        let failed = try XCTUnwrap(store.jobs().first { $0.id == job.id })
        XCTAssertEqual(failed.state, .failed)
        XCTAssertEqual(failed.lastError, "fixture operation failed")
        XCTAssertNil(failed.leaseUntil)
    }
}
