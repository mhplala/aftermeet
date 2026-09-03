import XCTest
@testable import AfterMeet

final class KnowledgeJobPlannerTests: XCTestCase {
    private func makeStore() -> (KnowledgeStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AfterMeet-JobPlanner-" + UUID().uuidString)
        return (KnowledgeStore(database: DB(
            databaseURL: directory.appendingPathComponent("aftermeet.db"))), directory)
    }

    private func persistSource(
        in store: KnowledgeStore,
        meetingID: String = "meeting-1",
        text: String = "虚构普通会议内容。",
        sensitivity: KnowledgeSensitivity = .normal
    ) -> KnowledgeSourceDocument {
        let bundle = KnowledgeSegmenter.plainTextSourceBundle(
            content: text,
            meetingID: meetingID,
            sourceKind: .archive,
            observedAt: 1,
            sensitivity: sensitivity)
        XCTAssertTrue(store.saveSource(
            bundle.document, segments: bundle.segments, meetingTitle: "虚构会议"))
        return bundle.document
    }

    func testSameSourceHashAndVersionEnqueuesExactlyOnce() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = persistSource(in: store)

        let first = KnowledgeJobPlanner.planExtraction(
            for: source, store: store, extractorVersion: "v1", enabled: true, now: 10)
        let second = KnowledgeJobPlanner.planExtraction(
            for: source, store: store, extractorVersion: "v1", enabled: true, now: 20)

        guard case .enqueued(let firstJob) = first else { return XCTFail("expected enqueued") }
        guard case .existing(let secondJob) = second else { return XCTFail("expected existing") }
        XCTAssertEqual(firstJob, secondJob)
        XCTAssertEqual(firstJob.jobKind, .extract)
        XCTAssertEqual(firstJob.state, .pending)
        XCTAssertEqual(store.jobs().count, 1)
    }

    func testExtractorVersionUpgradeCreatesOneReextractJob() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = persistSource(in: store)
        _ = KnowledgeJobPlanner.planExtraction(
            for: source, store: store, extractorVersion: "v1", enabled: true, now: 10)

        let upgraded = KnowledgeJobPlanner.planExtraction(
            for: source, store: store, extractorVersion: "v2", enabled: true, now: 20)
        let repeated = KnowledgeJobPlanner.planExtraction(
            for: source, store: store, extractorVersion: "v2", enabled: true, now: 30)

        guard case .enqueued(let upgradedJob) = upgraded else { return XCTFail("expected reextract") }
        guard case .existing(let repeatedJob) = repeated else { return XCTFail("expected existing") }
        XCTAssertEqual(upgradedJob.jobKind, .reextract)
        XCTAssertEqual(upgradedJob, repeatedJob)
        XCTAssertEqual(store.jobs().count, 2)
    }

    func testNewContentHashCreatesIndependentExtractSource() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = persistSource(in: store, text: "第一版普通内容。")
        let second = persistSource(in: store, text: "第二版普通内容。")

        guard case .enqueued(let firstJob) = KnowledgeJobPlanner.planExtraction(
            for: first, store: store, enabled: true, now: 10) else { return XCTFail() }
        guard case .enqueued(let secondJob) = KnowledgeJobPlanner.planExtraction(
            for: second, store: store, enabled: true, now: 20) else { return XCTFail() }

        XCTAssertEqual(firstJob.jobKind, .extract)
        XCTAssertEqual(secondJob.jobKind, .extract)
        XCTAssertNotEqual(firstJob.sourceID, secondJob.sourceID)
    }

    func testDisabledMissingAndRestrictedSourcesDoNotQueueWithoutConsent() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let normal = persistSource(in: store)
        let restricted = persistSource(
            in: store,
            meetingID: "meeting-sensitive",
            text: "虚构绩效会议内容。",
            sensitivity: .restricted)
        let missing = KnowledgeSegmenter.plainTextSourceBundle(
            content: "未保存来源", meetingID: "missing", observedAt: 1).document

        XCTAssertEqual(KnowledgeJobPlanner.planExtraction(
            for: normal, store: store, enabled: false), .disabled)
        XCTAssertEqual(KnowledgeJobPlanner.planExtraction(
            for: missing, store: store, enabled: true), .sourceNotPersisted)
        XCTAssertEqual(KnowledgeJobPlanner.planExtraction(
            for: restricted, store: store, enabled: true), .restrictedNeedsConsent)
        XCTAssertTrue(store.jobs().isEmpty)

        guard case .enqueued(let consented) = KnowledgeJobPlanner.planExtraction(
            for: restricted,
            store: store,
            enabled: true,
            includeRestrictedForCurrentRequest: true,
            now: 20) else { return XCTFail("expected explicit consent to enqueue") }
        XCTAssertEqual(consented.sourceID, restricted.id)
        XCTAssertEqual(store.jobs().count, 1)
    }
}
