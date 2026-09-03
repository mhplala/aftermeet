import Foundation

struct KnowledgeEvaluationSuite: Codable, Equatable {
    static let currentVersion = 1

    let version: Int
    let questions: [KnowledgeEvaluationQuestion]

    static let empty = KnowledgeEvaluationSuite(version: currentVersion, questions: [])
}

struct KnowledgeEvaluationQuestion: Codable, Equatable, Identifiable {
    enum Capability: String, Codable, CaseIterable {
        case singleMeeting = "single_meeting"
        case crossMeeting = "cross_meeting"
        case temporal = "temporal"
        case knowledgeUpdate = "knowledge_update"
        case actionClosure = "action_closure"
        case insufficientEvidence = "insufficient_evidence"
    }

    let id: String
    let capability: Capability
    let question: String
    let expectedAnswerContains: [String]
    let expectedMeetingIDs: [String]
    let mustCite: Bool
    let shouldRefuse: Bool
}

enum KnowledgeEvaluationStore {
    static var defaultURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AfterMeet")
        return directory.appendingPathComponent("knowledge-evaluation.json")
    }

    /// Missing is a valid empty state. A malformed private suite is surfaced so evaluation cannot
    /// silently run against zero questions and report a misleading success.
    static func load(from url: URL = defaultURL) throws -> KnowledgeEvaluationSuite {
        guard FileManager.default.fileExists(atPath: url.path) else { return .empty }
        let data = try Data(contentsOf: url)
        let suite = try JSONDecoder().decode(KnowledgeEvaluationSuite.self, from: data)
        guard suite.version == KnowledgeEvaluationSuite.currentVersion else {
            throw NSError(
                domain: "KnowledgeEvaluation",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unsupported evaluation suite version \(suite.version)"])
        }
        return suite
    }
}
