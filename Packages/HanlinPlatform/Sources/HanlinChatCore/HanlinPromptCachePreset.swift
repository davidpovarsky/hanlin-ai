import Foundation

/// Model-level preferences only. Scoped resource references and diagnostic
/// response IDs deliberately have no preset and are never copied into settings.
public enum HanlinPromptCachePreset: String, CaseIterable, Hashable, Sendable {
    case automatic
    case providerDefault
    case noExplicitCaching
    case anthropicOneHour
    case openAITwentyFourHours
    case openAIExplicitThirtyMinutes
    case openAIExplicitTwelveHours

    /// Nil is the historical automatic behavior, avoiding a forced migration.
    public var policy: HanlinPromptCachePolicy? {
        switch self {
        case .automatic: nil
        case .providerDefault: .providerDefault
        case .noExplicitCaching: .noExplicitCaching
        case .anthropicOneHour: .init(anthropicTTL: .oneHour)
        case .openAITwentyFourHours:
            .init(openAI: .init(retention: .twentyFourHours))
        case .openAIExplicitThirtyMinutes:
            .init(openAI: .init(mode: .explicit, ttl: .thirtyMinutes))
        case .openAIExplicitTwelveHours:
            .init(openAI: .init(mode: .explicit, ttl: .twelveHours))
        }
    }

    /// Unknown/custom policies remain distinct. Views must preserve them unless
    /// the user explicitly chooses a replacement; do not coerce them to defaults.
    public static func matching(_ policy: HanlinPromptCachePolicy?) -> Self? {
        if policy == nil || policy == .automatic { return .automatic }
        return allCases.first { $0.policy == policy }
    }

    public static func available(
        company: String?,
        apiType: String?,
        endpoint: URL?,
        modelID: String
    ) -> [Self] {
        var result: [Self] = [.automatic, .providerDefault, .noExplicitCaching]
        let company = company?.uppercased() ?? ""
        let dialect = apiType?.lowercased() ?? ""
        guard company != "LOCAL", company != "APPLE", dialect != "apple-on-device" else {
            return []
        }
        if company == "ANTHROPIC" || dialect.contains("anthropic") {
            result.append(.anthropicOneHour)
            return result
        }
        // Mirrors native provider routing. OpenAI-compatible gateways and plan
        // transport do not acquire native OpenAI controls from a model name.
        guard company == "OPENAI", endpoint?.scheme?.lowercased() == "https",
              endpoint?.host?.lowercased() == "api.openai.com",
              endpoint?.user == nil, endpoint?.password == nil,
              endpoint?.port == nil || endpoint?.port == 443,
              ["openai", "openai-response", "openai-responses"].contains(dialect) else {
            return result
        }

        let model = restoreBaseModelName(from: modelID).lowercased()
        if supportsExtendedRetention(model) {
            result.append(.openAITwentyFourHours)
        }
        if ["openai-response", "openai-responses"].contains(dialect),
           supportsExplicitCaching(model) {
            result.append(contentsOf: [.openAIExplicitThirtyMinutes, .openAIExplicitTwelveHours])
        }
        return result
    }

    // Reviewed against https://developers.openai.com/api/docs/guides/prompt-caching
    // on 2026-11-24. Legacy extended retention and modern minimum TTL differ.
    private static func supportsExtendedRetention(_ model: String) -> Bool {
        let names = [
            "gpt-5.5", "gpt-5.5-pro", "gpt-5.4", "gpt-5.2",
            "gpt-5.1-codex-max", "gpt-5.1", "gpt-5.1-codex",
            "gpt-5.1-codex-mini", "gpt-5.1-chat-latest",
            "gpt-5", "gpt-5-codex", "gpt-4.1"
        ]
        return names.contains { name in
            if model == name { return true }
            guard model.hasPrefix(name + "-") else { return false }
            let suffix = String(model.dropFirst(name.count + 1))
            // Permit official dated snapshots, not similarly named mini/nano or
            // arbitrary variants that have no documented 24-hour capability.
            return suffix.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
        }
    }

    private static func supportsExplicitCaching(_ model: String) -> Bool {
        let pieces = model.split(separator: "-", omittingEmptySubsequences: false)
        guard pieces.count >= 2, pieces[0] == "gpt" else { return false }
        let version = pieces[1].split(separator: ".", omittingEmptySubsequences: false)
        guard !version.isEmpty, version.count <= 2,
              version.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }),
              let major = Int(version[0]) else { return false }
        let minor: Int
        if version.count == 2 {
            guard let value = Int(version[1]) else { return false }
            minor = value
        } else {
            minor = 0
        }
        // Current documented GPT-5.6+ / GPT-6 families. Future major families
        // need an explicit maintenance review before offering paid TTL presets.
        return (major == 5 && minor >= 6) || major == 6
    }
}
