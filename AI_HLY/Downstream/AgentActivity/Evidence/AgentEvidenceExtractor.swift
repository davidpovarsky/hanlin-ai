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
        guard let descriptor = call.presentationProfile.evidence,
              descriptor.policy != .none else {
            return items
        }
        items += evidence(
            from: result.richResultBlocks,
            toolName: call.name,
            toolCallID: call.id,
            sequence: sequence,
            fallbackKind: descriptor.kind
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
                    || source.url?.isEmpty == false else { return nil }
            let kind = kind(forURL: source.url, fallback: .webPage)
            return AgentEvidenceItem(
                kind: kind,
                toolCallID: toolCallID,
                toolName: toolName,
                sequence: sequence,
                title: source.displayTitle,
                subtitle: source.domain,
                sourceName: source.providerName,
                url: source.url,
                reference: kind == .sefariaSource ? source.title : nil,
                externalID: source.id,
                snippet: shortSnippet(source.snippet),
                wasReturnedToModel: true
            )
        }
    }

    static func calendarItems(
        _ values: [EventItem],
        toolName: String,
        toolCallID: String
    ) -> [AgentEvidenceItem] {
        values.map { item in
            let isReminder = item.type.lowercased() == "reminder"
            let date = isReminder ? item.dueDate : item.startDate
            let externalID = [
                item.calendarIdentifier,
                item.type,
                item.title,
                String(date?.timeIntervalSince1970 ?? 0)
            ]
            .compactMap { $0 }
            .joined(separator: ":")
            return AgentEvidenceItem(
                kind: isReminder ? .reminder : .calendarEvent,
                toolCallID: toolCallID,
                toolName: toolName,
                title: item.title,
                subtitle: item.location,
                externalID: externalID,
                snippet: shortSnippet(item.notes),
                timestamp: date,
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
            if block.type != .searchResults, let root = evidence(
                title: block.title,
                subtitle: block.subtitle,
                snippet: block.body,
                url: block.url,
                externalID: block.id,
                reference: reference(for: block, toolName: toolName),
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
                    reference: reference(for: item, toolName: toolName),
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
            sourceName: nil,
            url: url,
            reference: reference,
            externalID: externalID,
            snippet: shortSnippet(snippet),
            wasReturnedToModel: true
        )
    }

    private static func reference(for block: NativeUIBlock, toolName: String) -> String? {
        guard toolName.lowercased().contains("sefaria") else { return nil }
        return nonempty(block.subtitle) ?? nonempty(block.title)
    }

    private static func reference(for item: NativeUIListItem, toolName: String) -> String? {
        guard toolName.lowercased().contains("sefaria") else { return nil }
        return nonempty(item.subtitle) ?? nonempty(item.id)
    }

    private static func shortSnippet(_ value: String?) -> String? {
        nonempty(value).map { String($0.prefix(280)) }
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
