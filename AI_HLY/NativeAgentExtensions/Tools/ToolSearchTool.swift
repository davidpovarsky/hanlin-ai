//
//  ToolSearchTool.swift
//  AI_HLY
//
//  Always-available tiny tool. It searches the app's native tool catalog and requests
//  deferred schema loading for the next model step.
//

import Foundation

struct ToolSearchTool: NativeTool {
    static let toolName = "tool_search"
    let name = ToolSearchTool.toolName

    var catalogEntry: NativeToolCatalogEntry {
        NativeToolCatalogEntry(
            name: name,
            title: "Tool Search",
            summary: "Search the app native tool catalog and load relevant tool schemas for the next step.",
            categories: ["system", "tool_discovery"],
            keywords: ["tool", "search", "discover", "schema", "capability"],
            examples: ["Find a tool that can search Jewish texts", "Find a tool for Wikipedia", "Find a calculator tool"]
        )
    }

    func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(
            name: name,
            description: "Search the app's native tool catalog. Use this when the current task may require a native app tool whose schema is not currently available. The app will load matching tool schemas in the next model step.",
            parameters: NativeToolSchema.object(
                properties: [
                    "query": NativeToolSchema.string(description: "What capability/tool you need, described in natural language."),
                    "intent": NativeToolSchema.string(description: "Optional short intent label, e.g. jewish_text_search, encyclopedia_lookup, calculation."),
                    "max_results": NativeToolSchema.number(description: "Maximum matching tools to load. Keep small, usually 3-5.", minimum: 1, maximum: 8)
                ],
                required: ["query"]
            )
        )
    }

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        do {
            let arguments = try NativeToolJSON.dictionary(from: argumentsJSON)
            let query = try NativeToolJSON.requiredString(arguments, "query")
            let intent = NativeToolJSON.optionalString(arguments, "intent")
            let maxResults = NativeToolJSON.int(arguments, "max_results", default: 5)

            let hits = NativeToolCatalog.shared.search(query: query, intent: intent, maxResults: maxResults)
            if hits.isEmpty {
                return NativeToolResult(
                    modelText: "No matching native tools were found for query: \(query). Continue without a native tool or ask the user for clarification.",
                    uiBlocks: [NativeUIBlock(type: .error, title: "No tools found", body: query, systemImage: "magnifyingglass")]
                )
            }

            let names = hits.map { $0.entry.name }
            let lines = hits.map { hit in
                "- \(hit.entry.name): \(hit.entry.summary)"
            }.joined(separator: "\n")

            let items = hits.map { hit in
                NativeUIListItem(
                    title: hit.entry.title,
                    subtitle: hit.entry.name,
                    body: hit.entry.summary
                )
            }

            let block = NativeUIBlock(
                type: .searchResults,
                title: "Native tools found",
                subtitle: "Schemas will be loaded for the next model step.",
                systemImage: "wrench.and.screwdriver",
                items: items
            )

            return NativeToolResult(
                modelText: "Matching native tools found. Their full schemas will be available in the next model step. Available tools:\n\(lines)",
                userText: "Found \(hits.count) relevant native tool(s).",
                uiBlocks: [block],
                deferredToolNames: names
            )
        } catch {
            return NativeToolResult(
                modelText: "tool_search failed: \(error.localizedDescription)",
                uiBlocks: [NativeUIBlock(type: .error, title: "Tool search failed", body: error.localizedDescription)]
            )
        }
    }
}
