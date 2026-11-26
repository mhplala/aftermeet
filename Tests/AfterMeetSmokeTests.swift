import XCTest
@testable import AfterMeet

final class AfterMeetSmokeTests: XCTestCase {
    func testTestTargetLoadsApplicationModule() {
        XCTAssertEqual(AppStore.transcriptFingerprint("alpha beta\ngamma"), "alphabetagamma")
        XCTAssertTrue(AppStore.demoMode)
        XCTAssertTrue(DB.fileURL.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        XCTAssertFalse(DB.fileURL.path.contains("Application Support/AfterMeet"))
    }

    func testTemporaryDatabaseNeverUsesApplicationSupportPath() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AfterMeet-IsolatedDB-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("isolated.db")

        do {
            let database = DB(databaseURL: url)
            XCTAssertTrue(database.healthy)
            XCTAssertEqual(database.databaseURL.standardizedFileURL, url.standardizedFileURL)
            XCTAssertNotEqual(database.databaseURL.standardizedFileURL, DB.fileURL.standardizedFileURL)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testSyntheticFixturesAreBundledAndContainNoUserPaths() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "synthetic-meetings", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let fixtures = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertGreaterThanOrEqual(fixtures.count, 8)
        XCTAssertFalse(text.contains("/Users/"))
        XCTAssertFalse(text.contains("@bytedance"))
        XCTAssertFalse(text.contains("https://"))
    }

    func testMissingPrivateEvaluationSuiteLoadsAsEmpty() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-evaluation-" + UUID().uuidString + ".json")
        XCTAssertEqual(try KnowledgeEvaluationStore.load(from: missing), .empty)
    }

    func testSyntheticEvaluationSuiteDecodes() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "golden-questions.example", withExtension: "json"))
        let suite = try KnowledgeEvaluationStore.load(from: url)

        XCTAssertEqual(suite.version, KnowledgeEvaluationSuite.currentVersion)
        XCTAssertEqual(suite.questions.count, 2)
        XCTAssertTrue(suite.questions.contains { $0.shouldRefuse })
        XCTAssertTrue(suite.questions.allSatisfy { $0.mustCite })
    }

    func testKnowledgeFeatureDefaultsOnButHistoricalBackfillDefaultsOff() throws {
        let suiteName = "AfterMeetTests.Flags." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(KnowledgeFeatureFlags.isEnabled(in: defaults))
        XCTAssertFalse(KnowledgeFeatureFlags.automaticHistoricalBackfillEnabled(in: defaults))

        KnowledgeFeatureFlags.setEnabled(false, in: defaults)
        KnowledgeFeatureFlags.setAutomaticHistoricalBackfillEnabled(true, in: defaults)
        XCTAssertFalse(KnowledgeFeatureFlags.isEnabled(in: defaults))
        XCTAssertTrue(KnowledgeFeatureFlags.automaticHistoricalBackfillEnabled(in: defaults))
    }
}
