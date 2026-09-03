import XCTest
@testable import AfterMeet

final class KnowledgeRetryPolicyTests: XCTestCase {
    private struct PermanentFixtureError: LocalizedError {
        var errorDescription: String? { "invalid credentials" }
    }

    private func job(attempt: Int) -> KnowledgeExtractionJob {
        KnowledgeExtractionJob(
            id: "job-retry-policy", sourceID: "source-1", jobKind: .extract,
            state: .running, inputHash: "hash", extractorVersion: "v1",
            cursor: 2, attempt: attempt, nextRetryAt: nil, leaseUntil: 200,
            lastError: nil, createdAt: 1, updatedAt: 1)
    }

    func testTransientErrorsUseBoundedBackoffThenBecomeFailed() {
        let first = KnowledgeRetryPolicy.decision(
            for: KnowledgeExtractionError.transient("network timeout"),
            job: job(attempt: 1),
            now: 100)
        let exhausted = KnowledgeRetryPolicy.decision(
            for: KnowledgeExtractionError.transient("network timeout"),
            job: job(attempt: KnowledgeRetryPolicy.maximumTransientAttempts),
            now: 100)

        XCTAssertEqual(first.state, .retry)
        XCTAssertGreaterThanOrEqual(first.nextRetryAt ?? 0, 105)
        XCTAssertLessThanOrEqual(first.nextRetryAt ?? 0, 106)
        XCTAssertEqual(exhausted.state, .failed)
        XCTAssertNil(exhausted.nextRetryAt)
    }

    func testInvalidResponsesHaveLowerRetryLimit() {
        let first = KnowledgeRetryPolicy.decision(
            for: KnowledgeExtractionError.invalidResponse("bad json"),
            job: job(attempt: 1),
            now: 100)
        let second = KnowledgeRetryPolicy.decision(
            for: KnowledgeExtractionError.invalidResponse("bad json"),
            job: job(attempt: 2),
            now: 100)

        XCTAssertEqual(first.state, .retry)
        XCTAssertEqual(second.state, .failed)
    }

    func testRateLimitHonorsExplicitRetryAfter() {
        let decision = KnowledgeRetryPolicy.decision(
            for: KnowledgeExtractionError.rateLimited("429", retryAfter: 30),
            job: job(attempt: 1),
            now: 100)

        XCTAssertEqual(decision.state, .retry)
        XCTAssertEqual(decision.nextRetryAt, 130)
    }

    func testCancellationAndUnknownPermanentErrorsDoNotRetry() {
        let cancelled = KnowledgeRetryPolicy.decision(
            for: CancellationError(), job: job(attempt: 1), now: 100)
        let permanent = KnowledgeRetryPolicy.decision(
            for: PermanentFixtureError(), job: job(attempt: 1), now: 100)

        XCTAssertEqual(cancelled.state, .cancelled)
        XCTAssertEqual(permanent.state, .failed)
        XCTAssertNil(permanent.nextRetryAt)
    }

    func testTransientURLErrorIsRecognized() {
        let decision = KnowledgeRetryPolicy.decision(
            for: URLError(.networkConnectionLost), job: job(attempt: 1), now: 100)

        XCTAssertEqual(decision.state, .retry)
        XCTAssertNotNil(decision.nextRetryAt)
    }
}
