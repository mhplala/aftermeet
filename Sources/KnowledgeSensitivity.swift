import Foundation

enum KnowledgeSensitivityClassifier {
    private static let restrictedTerms = [
        "招聘", "候选人", "面试", "校招", "社招",
        "绩效", "调薪", "薪酬", "晋升", "劝退", "汰换", "离职",
        "人员校准", "人事沟通", "one-on-one", "1:1"
    ]

    static func classify(title: String, content: String) -> KnowledgeSensitivity {
        let haystack = (title + "\n" + content).lowercased()
        return restrictedTerms.contains(where: { haystack.contains($0) }) ? .restricted : .normal
    }
}

enum KnowledgePrivacyPolicy {
    static func propagated(source: KnowledgeSensitivity,
                           candidate: KnowledgeSensitivity?) -> KnowledgeSensitivity {
        source == .restricted || candidate == .restricted ? .restricted : .normal
    }

    static func mayPersistAndSearchLocally(_ sensitivity: KnowledgeSensitivity) -> Bool {
        true
    }

    static func maySendToCloud(_ sensitivity: KnowledgeSensitivity,
                               includeRestrictedForCurrentRequest: Bool = false) -> Bool {
        sensitivity == .normal || includeRestrictedForCurrentRequest
    }
}
