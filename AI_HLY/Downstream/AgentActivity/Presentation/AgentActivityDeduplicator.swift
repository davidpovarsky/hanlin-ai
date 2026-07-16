import Foundation

enum AgentActivityDeduplicator {
    static func normalized(_ value: String?) -> String? {
        guard var value else { return nil }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.replacingOccurrences(of: "^(?i)query\\s*:\\s*", with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return value.isEmpty ? nil : value.lowercased()
    }

    static func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { value in
            guard let key = normalized(value), !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    static func uniqueSources(_ values: [AgentActivitySource]) -> [AgentActivitySource] {
        var seen = Set<String>()
        return values.filter { source in
            let key = normalized(source.url ?? source.title) ?? source.id
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }
}
