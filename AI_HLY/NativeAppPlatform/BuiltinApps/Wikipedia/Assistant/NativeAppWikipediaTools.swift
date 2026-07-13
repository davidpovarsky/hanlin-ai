import Foundation

struct WikipediaAssistantSearchTool: NativeTool {
    let service: NativeAppWikipediaSearchService
    let name = "wikipedia_search"

    var catalogEntry: NativeToolCatalogEntry {
        NativeToolCatalogEntry(
            name: name,
            title: String(localized: "Wikipedia Search"),
            summary: "Search Wikipedia through the same Core service used by the full mini app.",
            categories: ["encyclopedia", "knowledge", "wikipedia", "native app"],
            keywords: ["wikipedia", "encyclopedia", "article", "person", "place", "ויקיפדיה"],
            examples: ["Search Wikipedia for Maimonides", "Find articles about SwiftUI"]
        )
    }

    func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(
            name: name,
            description: "Search Wikipedia using the compiled Wikipedia native app Core.",
            parameters: NativeToolSchema.object(
                properties: [
                    "query": NativeToolSchema.string(description: "Search query."),
                    "language": NativeToolSchema.string(description: "Wikipedia language code, e.g. en or he."),
                    "limit": NativeToolSchema.number(description: "Maximum results, 1-20.", minimum: 1, maximum: 20)
                ],
                required: ["query"]
            )
        )
    }

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        let object = NativeAppJSON.decodeObject(from: argumentsJSON)
        let query = NativeAppJSON.string(object, "query")
        let language = NativeAppJSON.string(object, "language", default: context.isHebrew ? "he" : "en")
        let limit = max(1, min(NativeAppJSON.int(object, "limit", default: 5), 20))
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return NativeToolResult(modelText: "Missing Wikipedia query.", uiBlocks: [NativeUIBlock(type: .error, title: "Missing query")])
        }
        do {
            let results = try await service.search(query: query, limit: limit, languageCode: language)
            let items = results.map { result in
                NativeUIListItem(
                    id: result.id,
                    title: result.title,
                    subtitle: "Wikipedia (\(result.languageCode))",
                    body: result.description,
                    url: result.url?.absoluteString,
                    actions: [
                        NativeUIAction(type: .openURL, title: "Open", systemImage: "safari", url: result.url?.absoluteString),
                        NativeUIAction(type: .copyText, title: "Copy Title", systemImage: "doc.on.doc", text: result.title),
                        NativeUIAction(type: .openAppRoute, title: "Open in Wikipedia App", systemImage: "arrow.up.forward.app", route: .wikipediaArticle(title: result.title, languageCode: result.languageCode), presentationStyle: .fullScreen)
                    ]
                )
            }
            let modelText = results.isEmpty
                ? "No Wikipedia results found for: \(query)"
                : results.map { "- \($0.title): \($0.description)" }.joined(separator: "\n")
            return NativeToolResult(
                modelText: modelText,
                userText: results.isEmpty ? "No Wikipedia results found." : "Found \(results.count) Wikipedia result(s).",
                uiBlocks: [NativeUIBlock(type: .searchResults, title: "Wikipedia results", subtitle: query, items: items)]
            )
        } catch {
            return NativeToolResult(
                modelText: "Wikipedia search failed: \(error.localizedDescription)",
                uiBlocks: [NativeUIBlock(type: .error, title: "Wikipedia search failed", body: error.localizedDescription)]
            )
        }
    }
}

struct WikipediaAssistantSummaryTool: NativeTool {
    let service: NativeAppWikipediaSummaryService
    let name = "wikipedia_get_summary"

    var catalogEntry: NativeToolCatalogEntry {
        NativeToolCatalogEntry(
            name: name,
            title: String(localized: "Wikipedia Summary"),
            summary: "Load a Wikipedia article summary through the same Core service used by the full mini app.",
            categories: ["encyclopedia", "knowledge", "wikipedia", "native app"],
            keywords: ["summary", "article", "page", "תקציר"],
            examples: ["Get a Wikipedia summary for Jerusalem", "Summarize Ada Lovelace"]
        )
    }

    func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(
            name: name,
            description: "Load a Wikipedia summary using the compiled Wikipedia native app Core.",
            parameters: NativeToolSchema.object(
                properties: [
                    "title": NativeToolSchema.string(description: "Wikipedia article title."),
                    "language": NativeToolSchema.string(description: "Wikipedia language code, e.g. en or he.")
                ],
                required: ["title"]
            )
        )
    }

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        let object = NativeAppJSON.decodeObject(from: argumentsJSON)
        let title = NativeAppJSON.string(object, "title")
        let language = NativeAppJSON.string(object, "language", default: context.isHebrew ? "he" : "en")
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return NativeToolResult(modelText: "Missing Wikipedia title.")
        }
        do {
            let summary = try await service.summary(title: title, languageCode: language)
            return NativeToolResult(
                modelText: "Wikipedia summary for \(summary.title):\n\(summary.extract)",
                userText: summary.extract,
                uiBlocks: [
                    NativeUIBlock(
                        type: .wikipediaSummary,
                        title: summary.title,
                        subtitle: summary.description,
                        body: summary.extract,
                        imageURL: summary.thumbnailURL?.absoluteString,
                        url: summary.url?.absoluteString,
                        actions: [
                            NativeUIAction(type: .openURL, title: "Open", systemImage: "safari", url: summary.url?.absoluteString),
                            NativeUIAction(type: .copyText, title: "Copy Summary", systemImage: "doc.on.doc", text: summary.extract),
                            NativeUIAction(type: .openAppRoute, title: "Open in Wikipedia App", systemImage: "arrow.up.forward.app", route: .wikipediaArticle(title: summary.title, languageCode: language), presentationStyle: .fullScreen)
                        ]
                    )
                ]
            )
        } catch {
            return NativeToolResult(
                modelText: "Wikipedia summary failed: \(error.localizedDescription)",
                uiBlocks: [NativeUIBlock(type: .error, title: "Wikipedia summary failed", body: error.localizedDescription)]
            )
        }
    }
}
