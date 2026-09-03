import XCTest
@testable import AfterMeet

@MainActor
final class KnowledgeNavigationTests: XCTestCase {
    func testKnowledgeAttentionBadgeCountsFailedJobsAndHidesWhenDisabled() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AfterMeet-KnowledgeNavigation-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let knowledgeStore = KnowledgeStore(database: DB(
            databaseURL: directory.appendingPathComponent("aftermeet.db")))
        let bundle = KnowledgeSegmenter.plainTextSourceBundle(
            content: "虚构知识导航内容。", meetingID: "nav-meeting", observedAt: 1)
        XCTAssertTrue(knowledgeStore.saveSource(
            bundle.document, segments: bundle.segments, meetingTitle: "虚构会议"))
        guard case .enqueued(let job) = KnowledgeJobPlanner.planExtraction(
            for: bundle.document, store: knowledgeStore, enabled: true, now: 2) else {
            return XCTFail("expected job")
        }
        XCTAssertTrue(knowledgeStore.transitionJob(
            id: job.id, state: .failed, cursor: 0, lastError: "fixture", now: 3))

        let enabled = AppStore(
            loadPersistedData: false,
            knowledgeEnabledOverride: true,
            knowledgeStore: knowledgeStore)
        let disabled = AppStore(
            loadPersistedData: false,
            knowledgeEnabledOverride: false,
            knowledgeStore: knowledgeStore)

        XCTAssertEqual(enabled.knowledgeAttentionCount, 1)
        XCTAssertEqual(enabled.knowledgeBadge, "1")
        XCTAssertEqual(disabled.knowledgeAttentionCount, 0)
        XCTAssertNil(disabled.knowledgeBadge)
    }

    func testEvidenceWindowIncludesNeighborsAndOpensSourceMeeting() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AfterMeet-EvidenceNavigation-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let knowledgeStore = KnowledgeStore(database: DB(
            databaseURL: directory.appendingPathComponent("aftermeet.db")))
        let document = KnowledgeSegmenter.plainTextSourceBundle(
            content: "第一段第二段第三段",
            meetingID: "sample",
            observedAt: 1).document
        let segments = (0..<3).map { index in
            KnowledgeSourceSegment(
                id: KnowledgeIdentity.segmentID(sourceID: document.id, ordinal: index),
                sourceID: document.id,
                meetingID: "sample",
                ordinal: index,
                speaker: index == 1 ? "甲" : nil,
                startMS: index * 1_000,
                endMS: (index + 1) * 1_000,
                charStart: index * 3,
                charEnd: (index + 1) * 3,
                text: ["第一段", "第二段", "第三段"][index],
                contentHash: "hash-\(index)",
                metadataJSON: "{}",
                createdAt: 1,
                updatedAt: 1)
        }
        XCTAssertTrue(knowledgeStore.saveSource(
            document, segments: segments, meetingTitle: "周三产品评审会"))
        let link = KnowledgeUnitSource(
            unitID: "unit-1", segmentID: segments[1].id,
            evidenceRole: .support, quote: "第二段", weight: 1, verified: false)
        let evidence = KnowledgeInboxEvidence(link: link, segment: segments[1], source: document)
        let store = AppStore(
            loadPersistedData: false,
            knowledgeEnabledOverride: true,
            knowledgeStore: knowledgeStore)

        XCTAssertEqual(store.knowledgeEvidenceWindow(for: evidence), segments)
        store.openKnowledgeEvidence(evidence)
        XCTAssertEqual(store.selectedKnowledgeEvidence, evidence)
        store.openKnowledgeEvidenceMeeting(evidence)
        XCTAssertNil(store.selectedKnowledgeEvidence)
        XCTAssertEqual(store.screen, .detail)
        XCTAssertEqual(store.current.id, "sample")
    }

    func testKnowledgeTabSelectionSurvivesNavigation() {
        let store = AppStore()
        store.knowledgeTab = .projects
        store.go(.knowledge)
        store.go(.home)
        store.goBack()

        XCTAssertEqual(store.screen, .knowledge)
        XCTAssertEqual(store.knowledgeTab, .projects)
    }

    func testUnavailableKnowledgeStoreSurfacesReasonWithoutBreakingAppStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AfterMeet-KnowledgeUnavailable-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let unavailableStore = KnowledgeStore(database: DB(databaseURL: directory))

        let store = AppStore(
            loadPersistedData: false,
            knowledgeEnabledOverride: true,
            knowledgeStore: unavailableStore)

        XCTAssertNotNil(store.knowledgeUnavailableReason)
        XCTAssertTrue(store.knowledgeUnits.isEmpty)
        XCTAssertTrue(store.knowledgeProjects.isEmpty)
        XCTAssertTrue(store.knowledgeJobs.isEmpty)
    }

    func testKnowledgeRouteParticipatesInExistingBackStack() {
        let store = AppStore()
        XCTAssertEqual(store.screen, .home)

        store.go(.knowledge)
        XCTAssertEqual(store.screen, .knowledge)
        XCTAssertTrue(store.canGoBack)

        store.goBack()
        XCTAssertEqual(store.screen, .home)
    }
}
