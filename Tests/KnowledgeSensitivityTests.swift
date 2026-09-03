import XCTest
@testable import AfterMeet

final class KnowledgeSensitivityTests: XCTestCase {
    func testPersonnelTopicsAreRestrictedWhileProductOneVOneStaysNormal() {
        XCTAssertEqual(
            KnowledgeSensitivityClassifier.classify(title: "团队绩效校准", content: "普通正文"),
            .restricted)
        XCTAssertEqual(
            KnowledgeSensitivityClassifier.classify(title: "普通项目周会", content: "讨论候选人的面试反馈"),
            .restricted)
        XCTAssertEqual(
            KnowledgeSensitivityClassifier.classify(title: "直播1v1玩法", content: "讨论产品转化率"),
            .normal)
    }

    func testPrivacyPolicyKeepsRestrictedDataLocalAndRequiresPerRequestCloudOptIn() {
        XCTAssertEqual(KnowledgePrivacyPolicy.propagated(source: .restricted, candidate: .normal), .restricted)
        XCTAssertEqual(KnowledgePrivacyPolicy.propagated(source: .normal, candidate: .restricted), .restricted)
        XCTAssertEqual(KnowledgePrivacyPolicy.propagated(source: .normal, candidate: nil), .normal)
        XCTAssertTrue(KnowledgePrivacyPolicy.mayPersistAndSearchLocally(.restricted))
        XCTAssertFalse(KnowledgePrivacyPolicy.maySendToCloud(.restricted))
        XCTAssertTrue(KnowledgePrivacyPolicy.maySendToCloud(
            .restricted, includeRestrictedForCurrentRequest: true))
        XCTAssertTrue(KnowledgePrivacyPolicy.maySendToCloud(.normal))
    }

    func testFeishuBundleClassifiesFromTitleAndContentUnlessExplicitlyOverridden() {
        let automatic = KnowledgeSegmenter.feishuSourceBundle(
            content: "00:01 甲：讨论晋升安排",
            meetingID: "sensitive-feishu",
            docToken: "fictional-token",
            title: "普通同步",
            observedAt: 10)
        let overridden = KnowledgeSegmenter.feishuSourceBundle(
            content: "00:01 甲：讨论晋升安排",
            meetingID: "sensitive-feishu-override",
            docToken: "fictional-token",
            title: "普通同步",
            observedAt: 10,
            sensitivity: .normal)

        XCTAssertEqual(automatic.document.sensitivity, .restricted)
        XCTAssertEqual(overridden.document.sensitivity, .normal)
    }

    func testManualSensitivityChangeIsAtomicAndAppendOnlyAudited() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AfterMeet-Sensitivity-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = KnowledgeStore(database: DB(
            databaseURL: directory.appendingPathComponent("aftermeet.db")))
        let bundle = KnowledgeSegmenter.plainTextSourceBundle(
            content: "虚构的普通会议正文。",
            meetingID: "sensitivity-meeting",
            sourceKind: .archive,
            observedAt: 10,
            sensitivity: .normal)
        XCTAssertTrue(store.saveSource(
            bundle.document, segments: bundle.segments, meetingTitle: "普通会议"))

        XCTAssertTrue(store.setSourceSensitivity(
            id: bundle.document.id,
            sensitivity: .restricted,
            reason: "用户确认包含敏感信息",
            at: 20))
        XCTAssertEqual(
            store.sources(meetingID: "sensitivity-meeting").first?.sensitivity,
            .restricted)
        let events = store.feedback(targetType: "source_document", targetID: bundle.document.id)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.action, .edit)
        XCTAssertTrue(events.first?.beforeJSON?.contains("normal") == true)
        XCTAssertTrue(events.first?.afterJSON?.contains("restricted") == true)

        XCTAssertTrue(store.setSourceSensitivity(
            id: bundle.document.id,
            sensitivity: .restricted,
            reason: "重复点击不应新增事件",
            at: 30))
        XCTAssertEqual(
            store.feedback(targetType: "source_document", targetID: bundle.document.id).count,
            1)
        XCTAssertFalse(store.search(tokens: ["虚构"]).isEmpty)
        XCTAssertFalse(store.setSourceSensitivity(
            id: "missing-source",
            sensitivity: .restricted,
            at: 40))
        XCTAssertTrue(store.diagnostics().isClean)
    }
}
