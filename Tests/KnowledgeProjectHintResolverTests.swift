import XCTest
@testable import AfterMeet

final class KnowledgeProjectHintResolverTests: XCTestCase {
    private func project(id: String,
                         name: String,
                         aliases: [String] = [],
                         status: KnowledgeProjectStatus = .active) -> KnowledgeProject {
        KnowledgeProject(
            id: id,
            name: name,
            normalizedName: name.replacingOccurrences(of: " ", with: "").lowercased(),
            aliases: aliases,
            status: status,
            createdAt: 1,
            updatedAt: 1)
    }

    func testExactNameAndAliasCreateCandidateModelLinksOnly() {
        let projects = [
            project(id: "project-pine", name: "松果计划", aliases: ["松果"]),
            project(id: "project-kite", name: "纸鸢项目", aliases: ["Kite"])
        ]

        let links = KnowledgeProjectHintResolver.candidateLinks(
            hints: [" 松果计划 ", "KITE", "松果", "完全未知项目"],
            unitID: "unit-1",
            existingProjects: projects)

        XCTAssertEqual(links.map(\.projectID), ["project-pine", "project-kite"])
        XCTAssertTrue(links.allSatisfy { $0.unitID == "unit-1" })
        XCTAssertTrue(links.allSatisfy { $0.assignmentSource == .model })
        XCTAssertTrue(links.allSatisfy { $0.reviewStatus == .candidate })
        XCTAssertTrue(links.allSatisfy { $0.role == "related" })
    }

    func testUnknownAndArchivedHintsDoNotCreateLinks() {
        let projects = [project(
            id: "project-archived", name: "旧项目", aliases: ["旧别名"], status: .archived)]

        let links = KnowledgeProjectHintResolver.candidateLinks(
            hints: ["不存在的新项目", "旧项目", "旧别名"],
            unitID: "unit-1",
            existingProjects: projects)

        XCTAssertTrue(links.isEmpty)
        XCTAssertEqual(projects.count, 1)
    }

    func testAmbiguousAliasIsNotAutoAssigned() {
        let projects = [
            project(id: "project-a", name: "北方计划", aliases: ["北极星"]),
            project(id: "project-b", name: "星光计划", aliases: ["北极星"])
        ]

        let links = KnowledgeProjectHintResolver.candidateLinks(
            hints: ["北极星"], unitID: "unit-1", existingProjects: projects)

        XCTAssertTrue(links.isEmpty)
    }

    func testFormattingNormalizationDoesNotUseFuzzyContainment() {
        let projects = [project(id: "project-studio", name: "Live Studio", aliases: [])]

        XCTAssertEqual(KnowledgeProjectHintResolver.candidateLinks(
            hints: ["live-studio"], unitID: "unit-1", existingProjects: projects).count, 1)
        XCTAssertTrue(KnowledgeProjectHintResolver.candidateLinks(
            hints: ["Live Studio 增长"], unitID: "unit-1", existingProjects: projects).isEmpty)
    }
}
