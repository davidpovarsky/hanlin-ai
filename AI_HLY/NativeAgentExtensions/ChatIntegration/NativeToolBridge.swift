//
//  NativeToolBridge.swift
//  AI_HLY
//
//  Single integration surface between the existing APIManager and our separate native tools layer.
//

import Foundation

@MainActor
enum NativeToolBridge {
    static func schemasForRequest(loadedToolNames: [String]) -> [[String: Any]] {
        let catalog = NativeToolCatalog.shared
        catalog.ensureBuiltinsRegistered()

        var schemas: [[String: Any]] = []
        if let toolSearch = catalog.tool(named: ToolSearchTool.toolName) {
            schemas.append(toolSearch.openAIToolSchema())
        }
        schemas.append(contentsOf: catalog.schemas(for: loadedToolNames))
        return schemas
    }

    static func executeIfNativeTool(
        name: String,
        argumentsJSON: String,
        context: NativeToolExecutionContext
    ) async -> NativeToolResult? {
        let catalog = NativeToolCatalog.shared
        catalog.ensureBuiltinsRegistered()
        guard let tool = catalog.tool(named: name) else { return nil }

        let startedAt = Date()
        var result = await tool.execute(argumentsJSON: argumentsJSON, context: context)
        let completedAt = Date()
        let duration = completedAt.timeIntervalSince(startedAt)
        let isFailure = result.uiBlocks.contains(where: { $0.type == .error })

        let activityStep = NativeUIBlock(
            type: result.uiBlocks.contains(where: { $0.type == .searchResults }) ? .searchResults : (isFailure ? .error : .card),
            title: activityTitle(for: name, failed: isFailure),
            subtitle: argumentsSummary(argumentsJSON),
            body: result.userText ?? result.modelText,
            systemImage: activitySystemImage(for: name, failed: isFailure),
            children: result.uiBlocks,
            activityStatus: isFailure ? .failed : .completed,
            activityDetailStyle: detailStyle(for: name, blocks: result.uiBlocks),
            startedAt: startedAt,
            completedAt: completedAt,
            input: prettyJSON(argumentsJSON),
            output: result.modelText,
            queryItems: queryItems(from: argumentsJSON)
        )

        result.uiBlocks = [
            NativeUIBlock(
                type: .activityTimeline,
                title: String(localized: "Tool activity"),
                footnote: formattedDuration(duration),
                systemImage: "sparkles",
                children: [activityStep],
                activityStatus: isFailure ? .failed : .completed,
                activityDetailStyle: .richResult,
                startedAt: startedAt,
                completedAt: completedAt
            )
        ]
        return result
    }

    private static func activityTitle(for toolName: String, failed: Bool) -> String {
        if failed { return String(localized: "Tool failed") }
        let lowered = toolName.lowercased()
        if lowered.contains("search") { return String(localized: "Searched for information") }
        if lowered.contains("source") || lowered.contains("read") { return String(localized: "Read source") }
        if lowered.contains("calculate") { return String(localized: "Calculated result") }
        if lowered.contains("write") || lowered.contains("create") { return String(localized: "Created content") }
        return String(localized: "Used \(humanized(toolName))")
    }

    private static func activitySystemImage(for toolName: String, failed: Bool) -> String {
        if failed { return "exclamationmark.triangle" }
        let lowered = toolName.lowercased()
        if lowered.contains("search") { return "globe" }
        if lowered.contains("source") || lowered.contains("read") { return "doc.text.magnifyingglass" }
        if lowered.contains("calculate") { return "function" }
        if lowered.contains("write") || lowered.contains("create") { return "square.and.pencil" }
        return "gearshape.2"
    }

    private static func detailStyle(for toolName: String, blocks: [NativeUIBlock]) -> NativeUIActivityDetailStyle {
        if blocks.contains(where: { $0.type == .searchResults }) { return .search }
        let lowered = toolName.lowercased()
        if lowered.contains("code") || lowered.contains("script") || lowered.contains("calculate") { return .code }
        if blocks.contains(where: { !$0.keyValues.isEmpty }) { return .keyValue }
        return blocks.isEmpty ? .markdown : .richResult
    }

    private static func argumentsSummary(_ json: String) -> String? {
        guard
            let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let dictionary = object as? [String: Any],
            !dictionary.isEmpty
        else { return nil }

        return dictionary
            .sorted { $0.key < $1.key }
            .prefix(3)
            .map { "\($0.key): \($0.value)" }
            .joined(separator: " · ")
    }

    private static func prettyJSON(_ json: String) -> String {
        guard
            let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
            let string = String(data: pretty, encoding: .utf8)
        else { return json }
        return string
    }

    private static func queryItems(from json: String) -> [String] {
        guard
            let data = json.data(using: .utf8),
            let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }

        let preferredKeys = ["query", "queries", "term", "keyword", "title", "ref"]
        var values: [String] = []
        for key in preferredKeys {
            if let value = dictionary[key] as? String, !value.isEmpty {
                values.append(value)
            } else if let list = dictionary[key] as? [String] {
                values.append(contentsOf: list.filter { !$0.isEmpty })
            }
        }
        return Array(values.prefix(8))
    }

    private static func formattedDuration(_ duration: TimeInterval) -> String {
        if duration < 1 { return String(format: "%.1fs", duration) }
        if duration < 60 { return String(format: "%.0fs", duration) }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return "\(minutes)m \(seconds)s"
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