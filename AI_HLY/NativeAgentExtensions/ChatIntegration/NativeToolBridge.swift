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
        let duration = Date().timeIntervalSince(startedAt)

        let activityStep = NativeUIBlock(
            type: result.uiBlocks.contains(where: { $0.type == .searchResults }) ? .searchResults : .card,
            title: activityTitle(for: name),
            subtitle: argumentsSummary(argumentsJSON),
            body: result.modelText,
            systemImage: activitySystemImage(for: name),
            children: result.uiBlocks
        )

        result.uiBlocks = [
            NativeUIBlock(
                type: .activityTimeline,
                title: String(localized: "Tool activity"),
                footnote: formattedDuration(duration),
                systemImage: "sparkles",
                children: [activityStep]
            )
        ]
        return result
    }

    private static func activityTitle(for toolName: String) -> String {
        let lowered = toolName.lowercased()
        if lowered.contains("search") { return String(localized: "Searched for information") }
        if lowered.contains("source") || lowered.contains("read") { return String(localized: "Read source") }
        if lowered.contains("calculate") { return String(localized: "Calculated result") }
        return String(localized: "Used \(humanized(toolName))")
    }

    private static func activitySystemImage(for toolName: String) -> String {
        let lowered = toolName.lowercased()
        if lowered.contains("search") { return "globe" }
        if lowered.contains("source") || lowered.contains("read") { return "doc.text.magnifyingglass" }
        if lowered.contains("calculate") { return "function" }
        return "gearshape.2"
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
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}
