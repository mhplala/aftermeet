import Foundation

enum KnowledgeFeatureFlags {
    private static let enabledKey = "knowledgeEnabled"
    private static let automaticBackfillKey = "knowledgeAutomaticHistoricalBackfill"

    static var isEnabled: Bool { isEnabled(in: .standard) }
    static var automaticHistoricalBackfillEnabled: Bool {
        automaticHistoricalBackfillEnabled(in: .standard)
    }

    static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: enabledKey) == nil ? true : defaults.bool(forKey: enabledKey)
    }

    static func setEnabled(_ enabled: Bool, in defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: enabledKey)
    }

    static func automaticHistoricalBackfillEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: automaticBackfillKey) == nil
            ? false
            : defaults.bool(forKey: automaticBackfillKey)
    }

    static func setAutomaticHistoricalBackfillEnabled(
        _ enabled: Bool,
        in defaults: UserDefaults = .standard
    ) {
        defaults.set(enabled, forKey: automaticBackfillKey)
    }
}
