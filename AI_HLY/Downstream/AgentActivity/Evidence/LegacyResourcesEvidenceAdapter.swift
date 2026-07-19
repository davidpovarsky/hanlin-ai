import Foundation

enum LegacyResourcesEvidenceAdapter {
    static func items(
        from resources: [Resource],
        providerName: String?,
        toolName: String? = nil,
        toolCallID: String? = nil,
        sequence: Int? = nil,
        wasReturnedToModel: Bool = true
    ) -> [AgentEvidenceItem] {
        resources.compactMap { resource in
            let title = resolvedTitle(resource.title, url: resource.link)
            guard !title.isEmpty else { return nil }
            let kind = AgentEvidenceExtractor.kind(forURL: resource.link, fallback: .webPage)
            return AgentEvidenceItem(
                kind: kind,
                toolCallID: toolCallID,
                toolName: toolName,
                sequence: sequence,
                title: title,
                subtitle: domain(for: resource.link),
                sourceName: providerName,
                url: nonempty(resource.link),
                reference: kind == .sefariaSource ? title : nil,
                wasReturnedToModel: wasReturnedToModel
            )
        }
    }

    private static func resolvedTitle(_ title: String, url: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return domain(for: url) ?? String(localized: "Source")
    }

    private static func domain(for value: String) -> String? {
        URL(string: value)?.host()
    }

    private static func nonempty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
