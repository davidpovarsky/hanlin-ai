import Foundation

enum AgentEvidenceDeduplicator {
    static func canonicalKey(for item: AgentEvidenceItem) -> String {
        switch item.kind {
        case .webPage:
            return normalizedURL(item.url) ?? normalized(item.externalID ?? item.title)
        case .wikipediaArticle:
            return normalizedNonempty(item.externalID)
                ?? normalizedURL(item.url)
                ?? normalized(item.title)
        case .sefariaSource:
            return normalizedReference(item.reference ?? item.externalID ?? item.title)
        case .githubRepository:
            return normalizedGitHubRepository(item.url)
                ?? normalizedNonempty(item.externalID)
                ?? normalized(item.title)
        case .githubFile:
            return normalizedGitHubFile(item.url)
                ?? normalizedNonempty(item.externalID)
                ?? normalized(item.title)
        case .githubCommit:
            return normalizedURL(item.url)
                ?? normalizedNonempty(item.externalID)
                ?? normalized(item.title)
        case .reminder, .calendarEvent, .email, .contact:
            return normalizedNonempty(item.externalID) ?? normalized(item.title)
        case .document, .file:
            return normalizedNonempty(item.externalID)
                ?? normalizedURL(item.url)
                ?? normalized(item.title)
        case .genericItem:
            return normalizedNonempty(item.externalID)
                ?? normalizedURL(item.url)
                ?? normalized(item.title)
        }
    }

    static func stableID(for item: AgentEvidenceItem) -> String {
        "\(item.kind.rawValue):\(canonicalKey(for: item))"
    }

    static func normalizedURL(_ value: String?) -> String? {
        guard let value,
              var components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.host != nil else { return nil }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil
        let trackingNames = Set([
            "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
            "gclid", "fbclid"
        ])
        if let queryItems = components.queryItems {
            let filtered = queryItems.filter { !trackingNames.contains($0.name.lowercased()) }
            components.queryItems = filtered.isEmpty ? nil : filtered
        }
        while components.path.count > 1 && components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        if components.path == "/" { components.path = "" }
        return components.string
    }

    static func normalizedReference(_ value: String?) -> String {
        normalized(value)
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")
    }

    private static func normalizedGitHubRepository(_ value: String?) -> String? {
        guard let url = value.flatMap(URL.init(string:)),
              url.host()?.lowercased() == "github.com" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { return nil }
        return "\(parts[0].lowercased())/\(parts[1].lowercased())"
    }

    private static func normalizedGitHubFile(_ value: String?) -> String? {
        guard let value, let url = URL(string: value),
              url.host()?.lowercased() == "github.com" else { return nil }
        let repository = normalizedGitHubRepository(value) ?? ""
        let lineRange = url.fragment?.lowercased() ?? ""
        return "\(repository):\(url.path.lowercased()):\(lineRange)"
    }

    private static func normalized(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }

    private static func normalizedNonempty(_ value: String?) -> String? {
        let value = normalized(value)
        return value.isEmpty ? nil : value
    }
}
