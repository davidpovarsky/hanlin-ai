import Foundation

struct NativeAppWikipediaSearchTool: NativeTool {
    let service: WikipediaSearchService
    let name = "app_wikipedia_search"

    var catalogEntry: NativeToolCatalogEntry {
        NativeToolCatalogEntry(
            name: name,
            title: "Wikipedia App Search",
            summary: "Search Wikipedia through the compiled Wikipedia native app module.",
            categories: ["knowledge", "wikipedia", "native app"],
            keywords: ["encyclopedia", "article", "summary", "wiki"],
            examples: ["Search Wikipedia for Maimonides", "Find Wikipedia articles about SwiftUI"]
        )
    }

    func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(
            name: name,
            description: "Search Wikipedia articles using the compiled Wikipedia native app module.",
            parameters: NativeToolSchema.object(
                properties: [
                    "query": NativeToolSchema.string(description: "Wikipedia search query."),
                    "limit": NativeToolSchema.number(description: "Maximum results, 1-10.", minimum: 1, maximum: 10)
                ],
                required: ["query"]
            )
        )
    }

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        let object = NativeAppJSON.decodeObject(from: argumentsJSON)
        let query = NativeAppJSON.string(object, "query")
        let limit = NativeAppJSON.int(object, "limit", default: 5)
        do {
            let results = try await service.search(query: query, limit: limit)
            let items = results.map { result in
                NativeUIListItem(title: result.title, subtitle: result.description, url: result.url?.absoluteString)
            }
            return NativeToolResult(
                modelText: results.map { "- \($0.title): \($0.description)" }.joined(separator: "\n"),
                userText: "Found \(results.count) Wikipedia result(s).",
                uiBlocks: [NativeUIBlock(type: .searchResults, title: "Wikipedia results", subtitle: query, items: items)]
            )
        } catch {
            return NativeToolResult(modelText: "Wikipedia search failed: \(error.localizedDescription)", uiBlocks: [NativeUIBlock(type: .error, title: "Wikipedia search failed", body: error.localizedDescription)])
        }
    }
}

struct NativeAppWikipediaSummaryTool: NativeTool {
    let service: NativeAppWikipediaSummaryService
    let name = "app_wikipedia_summary"

    var catalogEntry: NativeToolCatalogEntry {
        NativeToolCatalogEntry(
            name: name,
            title: "Wikipedia App Summary",
            summary: "Get a Wikipedia article summary through the Wikipedia native app module.",
            categories: ["knowledge", "wikipedia", "native app"],
            keywords: ["summary", "article", "wiki", "encyclopedia"],
            examples: ["Summarize the Wikipedia article Maimonides"]
        )
    }

    func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(
            name: name,
            description: "Get a Wikipedia page summary using the compiled Wikipedia native app module.",
            parameters: NativeToolSchema.object(
                properties: ["title": NativeToolSchema.string(description: "Wikipedia article title.")],
                required: ["title"]
            )
        )
    }

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        let object = NativeAppJSON.decodeObject(from: argumentsJSON)
        let title = NativeAppJSON.string(object, "title")
        do {
            let summary = try await service.summary(title: title)
            return NativeToolResult(
                modelText: "\(summary.title)\n\(summary.extract)",
                userText: summary.title,
                uiBlocks: [NativeUIBlock(type: .wikipediaSummary, title: summary.title, subtitle: summary.description, body: summary.extract, url: summary.url?.absoluteString)]
            )
        } catch {
            return NativeToolResult(modelText: "Wikipedia summary failed: \(error.localizedDescription)", uiBlocks: [NativeUIBlock(type: .error, title: "Wikipedia summary failed", body: error.localizedDescription)])
        }
    }
}
