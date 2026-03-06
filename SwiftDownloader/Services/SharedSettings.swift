import Foundation

enum URLRuleMatcher {
    static func normalize(_ rule: String) -> String {
        var normalized = rule.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        normalized = normalized.replacingOccurrences(of: "https://", with: "")
        normalized = normalized.replacingOccurrences(of: "http://", with: "")
        normalized = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if normalized.hasPrefix("www.") {
            normalized.removeFirst(4)
        }

        return normalized
    }

    static func normalizedRules(from rules: [String]) -> [String] {
        Array(Set(rules.map(normalize).filter { !$0.isEmpty })).sorted()
    }

    static func matches(url: URL, rules: [String]) -> Bool {
        let normalizedRules = normalizedRules(from: rules)
        guard !normalizedRules.isEmpty, let host = url.host?.lowercased() else { return false }

        return normalizedRules.contains { rule in
            host == rule || host.hasSuffix(".\(rule)")
        }
    }
}

enum SharedSettings {
    private static let suite = UserDefaults(suiteName: Constants.appGroupIdentifier)

    static func syncURLRulesFromStandardDefaults() {
        let rules = UserDefaults.standard.stringArray(forKey: Constants.Keys.urlRules) ?? []
        saveURLRules(rules)
    }

    static func saveURLRules(_ rules: [String]) {
        suite?.set(URLRuleMatcher.normalizedRules(from: rules), forKey: Constants.Keys.urlRules)
    }

    static func urlRules() -> [String] {
        let sharedRules = suite?.stringArray(forKey: Constants.Keys.urlRules) ?? []
        if !sharedRules.isEmpty {
            return sharedRules
        }

        return URLRuleMatcher.normalizedRules(from: UserDefaults.standard.stringArray(forKey: Constants.Keys.urlRules) ?? [])
    }

    static func shouldIntercept(urlString: String) -> Bool {
        guard let url = URL(string: urlString) else { return false }
        return URLRuleMatcher.matches(url: url, rules: urlRules())
    }
}
