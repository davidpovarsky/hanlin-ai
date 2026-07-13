//
//  LegacyToolActivityAdapter.swift
//  AI_HLY
//
//  Downstream compatibility adapter. It converts Hanlin's existing persisted
//  reasoning/tool/result fields into the provider-neutral activity timeline
//  without changing the upstream streaming and persistence models.
//

import Foundation

enum LegacyToolActivityAdapter {
    static func blocks(for message: ChatMessages, storedBlocks: [NativeUIBlock]) -> [NativeUIBlock] {
        guard message.role == "assistant" || message.role == "error" else {
            return storedBlocks
        }

        var steps: [NativeUIBlock] = []
        var timelineFootnotes: [String] = []

        for block in storedBlocks {
            if block.type == .activityTimeline {
                steps.append(contentsOf: block.children.isEmpty ? [block] : block.children)
                if let footnote = block.footnote, !footnote.isEmpty {
                    timelineFootnotes.append(footnote)
                }
            } else {
                steps.append(richResultStep(for: block))
            }
        }

        if let reasoning = normalized(message.reasoning), !reasoning.isEmpty {
            steps.insert(
                NativeUIBlock(
                    id: "legacy-reasoning-\(message.id.uuidString)",
                    type: .markdown,
                    title: String(localized: "Reasoned through the request"),
                    body: reasoning,
                    systemImage: "sparkles",
                    activityStatus: message.role == "error" ? .failed : .completed,
                    activityDetailStyle: .markdown,
                    output: reasoning
                ),
                at: 0
            )
        }

        if let toolContent = normalized(message.toolContent), !toolContent.isEmpty {
            let toolName = normalized(message.toolName)
            steps.append(
                NativeUIBlock(
                    id: "legacy-tool-\(message.id.uuidString)",
                    type: .card,
                    title: toolTitle(toolName),
                    body: toolContent,
                    systemImage: toolSystemImage(toolName),
                    activityStatus: message.role == "error" ? .failed : .completed,
                    activityDetailStyle: .markdown,
                    output: toolContent
                )
            )
        }

        if let resources = message.resources, !resources.isEmpty {
            steps.append(
                NativeUIBlock(
                    id: "legacy-search-\(message.id.uuidString)",
                    type: .searchResults,
                    title: searchTitle(engine: message.searchEngine),
                    subtitle: message.searchEngine,
                    systemImage: "globe",
                    items: resources.map {
                        NativeUIListItem(
                            title: $0.title,
                            subtitle: $0.link,
                            url: $0.link,
                            actions: [
                                NativeUIAction(
                                    type: .openURL,
                                    title: String(localized: "Open"),
                                    systemImage: "safari",
                                    url: $0.link
                                )
                            ]
                        )
                    },
                    activityStatus: .completed,
                    activityDetailStyle: .search,
                    queryItems: resources.prefix(6).map(\.title)
                )
            )
        }

        if let codeBlocks = message.codeBlockData {
            for code in codeBlocks {
                let status: NativeUIActivityStatus = code.hasError ? .failed : (code.isRunning ? .running : .completed)
                steps.append(
                    NativeUIBlock(
                        id: "legacy-code-\(code.id.uuidString)",
                        type: code.hasError ? .error : .card,
                        title: code.hasError ? String(localized: "Code execution failed") : String(localized: "Ran code"),
                        subtitle: code.codeType,
                        body: code.output.isEmpty ? nil : code.output,
                        systemImage: "terminal",
                        activityStatus: status,
                        activityDetailStyle: .code,
                        input: code.code,
                        output: code.output.isEmpty ? nil : code.output
                    )
                )
            }
        }

        appendResultSummaries(for: message, to: &steps)

        if message.role == "error", steps.isEmpty {
            let errorText = normalized(message.text) ?? String(localized: "The response failed")
            steps.append(
                NativeUIBlock(
                    id: "legacy-error-\(message.id.uuidString)",
                    type: .error,
                    title: String(localized: "Response failed"),
                    body: errorText,
                    systemImage: "exclamationmark.triangle",
                    activityStatus: .failed,
                    activityDetailStyle: .plain,
                    output: errorText
                )
            )
        }

        steps = deduplicated(steps)
        guard !steps.isEmpty else { return storedBlocks }

        let duration = normalized(message.reasoningTime) ?? timelineFootnotes.first
        let timeline = NativeUIBlock(
            id: "activity-\(message.groupID.uuidString)-\(message.id.uuidString)",
            type: .activityTimeline,
            title: String(localized: "Tool activity"),
            footnote: duration,
            systemImage: "sparkles",
            children: steps,
            activityStatus: aggregateStatus(steps),
            activityDetailStyle: .richResult
        )
        return [timeline]
    }

    static func merging(existing: [NativeUIBlock], appended: [NativeUIBlock]) -> [NativeUIBlock] {
        let all = existing + appended
        var steps: [NativeUIBlock] = []
        var passthrough: [NativeUIBlock] = []
        var footnote: String?

        for block in all {
            if block.type == .activityTimeline {
                steps.append(contentsOf: block.children.isEmpty ? [block] : block.children)
                if let value = block.footnote, !value.isEmpty { footnote = value }
            } else {
                passthrough.append(block)
            }
        }

        guard !steps.isEmpty else { return all }
        steps.append(contentsOf: passthrough.map(richResultStep(for:)))
        steps = deduplicated(steps)

        return [
            NativeUIBlock(
                type: .activityTimeline,
                title: String(localized: "Tool activity"),
                footnote: footnote,
                systemImage: "sparkles",
                children: steps,
                activityStatus: aggregateStatus(steps),
                activityDetailStyle: .richResult
            )
        ]
    }

    private static func appendResultSummaries(for message: ChatMessages, to steps: inout [NativeUIBlock]) {
        if let cards = message.knowledgeCard, !cards.isEmpty {
            steps.append(summaryStep(id: "knowledge-\(message.id)", title: String(localized: "Created knowledge cards"), count: cards.count, image: "rectangle.stack"))
        }
        if let events = message.events, !events.isEmpty {
            steps.append(summaryStep(id: "events-\(message.id)", title: String(localized: "Prepared calendar items"), count: events.count, image: "calendar"))
        }
        if let locations = message.locationsInfo, !locations.isEmpty {
            steps.append(summaryStep(id: "locations-\(message.id)", title: String(localized: "Found locations"), count: locations.count, image: "map"))
        }
        if let routes = message.routeInfos, !routes.isEmpty {
            steps.append(summaryStep(id: "routes-\(message.id)", title: String(localized: "Calculated routes"), count: routes.count, image: "point.topleft.down.to.point.bottomright.curvepath"))
        }
        if let health = message.healthData, !health.isEmpty {
            steps.append(summaryStep(id: "health-\(message.id)", title: String(localized: "Prepared health data"), count: health.count, image: "heart.text.square"))
        }
        if let html = normalized(message.htmlContent), !html.isEmpty {
            steps.append(
                NativeUIBlock(
                    id: "html-\(message.id)",
                    type: .card,
                    title: String(localized: "Generated web content"),
                    subtitle: String(localized: "HTML result"),
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    activityStatus: .completed,
                    activityDetailStyle: .code,
                    output: html
                )
            )
        }
        if let document = normalized(message.document_text), !document.isEmpty {
            steps.append(
                NativeUIBlock(
                    id: "document-\(message.id)",
                    type: .source,
                    title: String(localized: "Read document"),
                    body: document,
                    systemImage: "doc.text.magnifyingglass",
                    activityStatus: .completed,
                    activityDetailStyle: .plain,
                    output: document
                )
            )
        }
    }

    private static func summaryStep(id: String, title: String, count: Int, image: String) -> NativeUIBlock {
        NativeUIBlock(
            id: id,
            type: .card,
            title: title,
            subtitle: String(localized: "\(count) items"),
            systemImage: image,
            activityStatus: .completed,
            activityDetailStyle: .richResult
        )
    }

    private static func richResultStep(for block: NativeUIBlock) -> NativeUIBlock {
        NativeUIBlock(
            id: "result-\(block.id)",
            type: block.type,
            title: block.title ?? String(localized: "Produced a result"),
            subtitle: block.subtitle,
            body: block.body,
            footnote: block.footnote,
            systemImage: block.systemImage ?? "rectangle.stack",
            imageURL: block.imageURL,
            url: block.url,
            items: block.items,
            keyValues: block.keyValues,
            actions: block.actions,
            children: block.children,
            activityStatus: block.activityStatus ?? .completed,
            activityDetailStyle: block.activityDetailStyle ?? .richResult,
            startedAt: block.startedAt,
            completedAt: block.completedAt,
            input: block.input,
            output: block.output,
            queryItems: block.queryItems
        )
    }

    private static func aggregateStatus(_ steps: [NativeUIBlock]) -> NativeUIActivityStatus {
        if steps.contains(where: { $0.activityStatus == .running || $0.activityStatus == .pending }) { return .running }
        if steps.contains(where: { $0.activityStatus == .failed }) { return .failed }
        if steps.contains(where: { $0.activityStatus == .cancelled }) { return .cancelled }
        return .completed
    }

    private static func deduplicated(_ blocks: [NativeUIBlock]) -> [NativeUIBlock] {
        var seen = Set<String>()
        return blocks.filter { block in
            let signature = [block.id, block.title ?? "", block.input ?? "", block.output ?? block.body ?? ""].joined(separator: "|")
            return seen.insert(signature).inserted
        }
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func searchTitle(engine: String?) -> String {
        guard let engine = normalized(engine) else { return String(localized: "Searched for information") }
        return String(localized: "Searched with \(engine)")
    }

    private static func toolTitle(_ name: String?) -> String {
        guard let name else { return String(localized: "Used a tool") }
        return String(localized: "Used \(humanized(name))")
    }

    private static func toolSystemImage(_ name: String?) -> String {
        let lowered = name?.lowercased() ?? ""
        if lowered.contains("search") { return "globe" }
        if lowered.contains("read") || lowered.contains("source") { return "doc.text.magnifyingglass" }
        if lowered.contains("calendar") { return "calendar" }
        if lowered.contains("map") || lowered.contains("route") { return "map" }
        if lowered.contains("calculate") || lowered.contains("math") { return "function" }
        return "gearshape.2"
    }

    private static func humanized(_ value: String) -> String {
        value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}