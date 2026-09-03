import Foundation

enum KnowledgeExtractionError: LocalizedError, Sendable {
    case transient(String)
    case rateLimited(String, retryAfter: TimeInterval?)
    case invalidResponse(String)
    case permanent(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .transient(let message), .invalidResponse(let message), .permanent(let message):
            return message
        case .rateLimited(let message, _):
            return message
        case .cancelled:
            return "任务已取消"
        }
    }
}

struct KnowledgeRetryDecision: Equatable, Sendable {
    let state: KnowledgeExtractionJobState
    let nextRetryAt: TimeInterval?
    let message: String
}

enum KnowledgeRetryPolicy {
    static let maximumTransientAttempts = 5
    static let maximumInvalidResponseAttempts = 2

    static func decision(for error: Error,
                         job: KnowledgeExtractionJob,
                         now: TimeInterval) -> KnowledgeRetryDecision {
        if error is CancellationError {
            return KnowledgeRetryDecision(state: .cancelled, nextRetryAt: nil, message: "任务已取消")
        }
        if let error = error as? KnowledgeExtractionError {
            switch error {
            case .cancelled:
                return KnowledgeRetryDecision(state: .cancelled, nextRetryAt: nil, message: "任务已取消")
            case .permanent(let message):
                return KnowledgeRetryDecision(state: .failed, nextRetryAt: nil, message: message)
            case .invalidResponse(let message):
                return retryOrFail(
                    message: message,
                    job: job,
                    now: now,
                    maximumAttempts: maximumInvalidResponseAttempts,
                    baseDelay: 2)
            case .transient(let message):
                return retryOrFail(
                    message: message,
                    job: job,
                    now: now,
                    maximumAttempts: maximumTransientAttempts,
                    baseDelay: 5)
            case .rateLimited(let message, let retryAfter):
                guard job.attempt < maximumTransientAttempts else {
                    return KnowledgeRetryDecision(state: .failed, nextRetryAt: nil, message: message)
                }
                let delay = retryAfter.map { max(1, $0) }
                    ?? backoffDelay(job: job, baseDelay: 10)
                return KnowledgeRetryDecision(state: .retry, nextRetryAt: now + delay, message: message)
            }
        }
        if let urlError = error as? URLError,
           [URLError.timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
            .dnsLookupFailed, .notConnectedToInternet, .resourceUnavailable]
            .contains(urlError.code) {
            return retryOrFail(
                message: urlError.localizedDescription,
                job: job,
                now: now,
                maximumAttempts: maximumTransientAttempts,
                baseDelay: 5)
        }
        let lower = error.localizedDescription.lowercased()
        if lower.contains("429") || lower.contains("timeout") || lower.contains("网络")
            || lower.contains("temporar") {
            return retryOrFail(
                message: error.localizedDescription,
                job: job,
                now: now,
                maximumAttempts: maximumTransientAttempts,
                baseDelay: 5)
        }
        return KnowledgeRetryDecision(
            state: .failed,
            nextRetryAt: nil,
            message: error.localizedDescription)
    }

    private static func retryOrFail(message: String,
                                    job: KnowledgeExtractionJob,
                                    now: TimeInterval,
                                    maximumAttempts: Int,
                                    baseDelay: TimeInterval) -> KnowledgeRetryDecision {
        guard job.attempt < maximumAttempts else {
            return KnowledgeRetryDecision(state: .failed, nextRetryAt: nil, message: message)
        }
        return KnowledgeRetryDecision(
            state: .retry,
            nextRetryAt: now + backoffDelay(job: job, baseDelay: baseDelay),
            message: message)
    }

    private static func backoffDelay(job: KnowledgeExtractionJob,
                                     baseDelay: TimeInterval) -> TimeInterval {
        let exponent = max(0, min(job.attempt - 1, 6))
        let base = min(300, baseDelay * pow(2, Double(exponent)))
        let checksum = job.id.utf8.reduce(0) { ($0 + Int($1)) % 21 }
        let jitter = Double(checksum) / 100
        return base * (1 + jitter)
    }
}

actor KnowledgeExtractionWorker {
    typealias Operation = @Sendable (KnowledgeExtractionJob) async throws -> Int

    private let store: KnowledgeStore
    private let leaseDuration: TimeInterval
    private let heartbeatIntervalNanoseconds: UInt64
    private let clock: @Sendable () -> TimeInterval
    private var executing = false
    private var currentJobID: String?
    private var currentOperation: Task<Int, Error>?

    init(store: KnowledgeStore = .shared,
         leaseDuration: TimeInterval = 60,
         heartbeatIntervalNanoseconds: UInt64 = 10_000_000_000,
         clock: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSince1970 }) {
        self.store = store
        self.leaseDuration = leaseDuration
        self.heartbeatIntervalNanoseconds = heartbeatIntervalNanoseconds
        self.clock = clock
    }

    func runNext(allowedJobIDs: Set<String>? = nil,
                 operation: @escaping Operation) async -> Bool {
        guard !executing else { return false }
        executing = true
        defer { executing = false }
        guard let job = store.claimNextJob(
            now: clock(),
            leaseDuration: leaseDuration,
            allowedJobIDs: allowedJobIDs) else {
            return false
        }
        currentJobID = job.id
        let operationTask = Task { try await operation(job) }
        currentOperation = operationTask

        let heartbeat = Task { [store, leaseDuration, heartbeatIntervalNanoseconds, clock] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: heartbeatIntervalNanoseconds) }
                catch { break }
                guard !Task.isCancelled else { break }
                _ = store.renewJobLease(
                    id: job.id,
                    now: clock(),
                    leaseDuration: leaseDuration)
            }
        }
        defer {
            heartbeat.cancel()
            currentOperation = nil
            currentJobID = nil
        }

        do {
            let cursor = try await operationTask.value
            if store.jobs().first(where: { $0.id == job.id })?.state == .cancelled { return true }
            return store.transitionJob(
                id: job.id,
                state: .done,
                cursor: max(job.cursor, cursor),
                now: clock())
        } catch {
            if store.jobs().first(where: { $0.id == job.id })?.state == .cancelled { return true }
            let persistedCursor = store.jobs().first(where: { $0.id == job.id })?.cursor ?? job.cursor
            let decision = KnowledgeRetryPolicy.decision(for: error, job: job, now: clock())
            return store.transitionJob(
                id: job.id,
                state: decision.state,
                cursor: persistedCursor,
                nextRetryAt: decision.nextRetryAt,
                lastError: String(decision.message.prefix(500)),
                now: clock())
        }
    }

    func cancel(jobID: String) -> Bool {
        guard let job = store.jobs().first(where: { $0.id == jobID }),
              [.pending, .running, .retry, .failed].contains(job.state) else { return false }
        if currentJobID == jobID { currentOperation?.cancel() }
        return store.transitionJob(
            id: jobID,
            state: .cancelled,
            cursor: job.cursor,
            lastError: "任务已取消",
            now: clock())
    }

    func retry(jobID: String) -> Bool {
        store.resetJobForRetry(id: jobID, now: clock())
    }

    func isRunning() -> Bool { executing }
}
