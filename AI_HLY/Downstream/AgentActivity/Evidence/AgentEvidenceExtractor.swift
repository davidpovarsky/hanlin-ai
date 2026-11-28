import Foundation

enum AgentEvidenceExtractor {
    static func extract(
        call: AgentToolCall,
        result: AgentToolResult,
        sequence: Int?
    ) -> [AgentEvidenceItem] {
        guard !result.isError else { return [] }

        var items = result.evidenceItems.map { candidate in
            var candidate = candidate
            candidate.toolCallID = candidate.toolCallID ?? call.id
            candidate.toolName = candidate.toolName ?? call.name
            candidate.sequence = candidate.sequence ?? sequence
            return candidate
        }
        guard let fallbackKind = supportedKind(for: call.name) else { return items }
        items += evidence(
            from: result.richResultBlocks,
            toolName: call.name,
            toolCallID: call.id,
            sequence: sequence,
            fallbackKind: fallbackKind
        )
        return items
    }

    static func evidence(
        from sources: [AgentActivitySource],
        toolName: String? = nil,
        toolCallID: String? = nil,
        sequence: Int? = nil
    ) -> [AgentEvidenceItem] {
        sources.compactMap { source in
            guard !source.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || source.url?.isEmpty == false
                    || source.reference?.isEmpty == false else { return nil }
            let kind = kind(forURL: source.url, fallback: .webPage)
            return AgentEvidenceItem(
                kind: kind,
                toolCallID: toolCallID,
                toolName: toolName,
                sequence: sequence,
                title: source.displayTitle,
                subtitle: source.domain,
                url: source.url,
                reference: source.reference,
                externalID: kind == .wikipediaArticle ? source.reference : nil,
                wasReturnedToModel: true
            )
        }
    }

    static func calendarItems(
        _ values: [EventItem],
        toolName: String,
        toolCallID: String
    ) -> [AgentEvidenceItem] {
        values.compactMap { item in
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            let isReminder = item.type.lowercased() == "reminder"
            let timestamp = isReminder ? item.dueDate : item.startDate
            let externalID = [
                item.calendarIdentifier,
                item.type,
                title,
                timestamp.map { String($0.timeIntervalSince1970) }
            ]
            .compactMap { $0 }
            .joined(separator: ":")
            return AgentEvidenceItem(
                kind: isReminder ? .reminder : .calendarEvent,
                toolCallID: toolCallID,
                toolName: toolName,
                title: title,
                subtitle: item.location,
                externalID: externalID,
                snippet: shortSnippet(item.notes),
                timestamp: timestamp,
                wasReturnedToModel: true
            )
        }
    }

    static func kind(forURL value: String?, fallback: AgentEvidenceKind) -> AgentEvidenceKind {
        guard let url = value.flatMap(URL.init(string:)),
              let host = url.host()?.lowercased() else { return fallback }
        if host.contains("wikipedia.org") { return .wikipediaArticle }
        if host.contains("sefaria.org") { return .sefariaSource }
        if host == "github.com" || host.hasSuffix(".github.com") {
            let components = url.pathComponents.filter { $0 != "/" }
            if components.contains("commit") { return .githubCommit }
            if components.contains("blob") || components.contains("tree") { return .githubFile }
            return .githubRepository
        }
        return fallback
    }

    private static func supportedKind(for toolName: String) -> AgentEvidenceKind? {
        let normalized = toolName.lowercased()
        if normalized.contains("wikipedia") { return .wikipediaArticle }
        if normalized.contains("sefaria") { return .sefariaSource }
        if normalized.contains("github") { return .githubRepository }
        if normalized.contains("document") { return .document }
        if normalized.contains("file") { return .file }
        return nil
    }

    private static func evidence(
        from blocks: [NativeUIBlock],
        toolName: String,
        toolCallID: String,
        sequence: Int?,
        fallbackKind: AgentEvidenceKind
    ) -> [AgentEvidenceItem] {
        blocks.flatMap { block -> [AgentEvidenceItem] in
            guard block.type != .error else { return [] }
            var result: [AgentEvidenceItem] = []
            if block.type != .searchResults,
               let root = evidence(
                    title: block.title,
                    subtitle: block.subtitle,
                    snippet: block.body,
                    url: block.url,
                    externalID: nil,
                    reference: reference(
                        title: block.title,
                        subtitle: block.subtitle,
                        identifier: nil,
                        toolName: toolName
                    ),
                    toolName: toolName,
                    toolCallID: toolCallID,
                    sequence: sequence,
                    fallbackKind: fallbackKind
               ) {
                result.append(root)
            }
            result += block.items.compactMap { item in
                evidence(
                    title: item.title,
                    subtitle: item.subtitle,
                    snippet: item.body,
                    url: item.url,
                    externalID: item.id,
                    reference: reference(
                        title: item.title,
                        subtitle: item.subtitle,
                        identifier: item.id,
                        toolName: toolName
                    ),
                    toolName: toolName,
                    toolCallID: toolCallID,
                    sequence: sequence,
                    fallbackKind: fallbackKind
                )
            }
            result += evidence(
                from: block.children,
                toolName: toolName,
                toolCallID: toolCallID,
                sequence: sequence,
                fallbackKind: fallbackKind
            )
            return result
        }
    }

    private static func evidence(
        title: String?,
        subtitle: String?,
        snippet: String?,
        url: String?,
        externalID: String?,
        reference: String?,
        toolName: String,
        toolCallID: String,
        sequence: Int?,
        fallbackKind: AgentEvidenceKind
    ) -> AgentEvidenceItem? {
        guard let title = nonempty(title),
              nonempty(url) != nil || nonempty(reference) != nil || nonempty(externalID) != nil else {
            return nil
        }
        let kind = kind(forURL: url, fallback: fallbackKind)
        return AgentEvidenceItem(
            kind: kind,
            toolCallID: toolCallID,
            toolName: toolName,
            sequence: sequence,
            title: title,
            subtitle: subtitle,
            url: url,
            reference: reference,
            externalID: externalID,
            snippet: shortSnippet(snippet),
            wasReturnedToModel: true
        )
    }

    private static func reference(
        title: String?,
        subtitle: String?,
        identifier: String?,
        toolName: String
    ) -> String? {
        guard toolName.lowercased().contains("sefaria") else { return nil }
        return nonempty(subtitle) ?? nonempty(identifier) ?? nonempty(title)
    }

    private static func shortSnippet(_ value: String?) -> String? {
        nonempty(value).map { String($0.prefix(280)) }
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
