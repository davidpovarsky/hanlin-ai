//
//  WikipediaSummaryTool.swift
//  AI_HLY
//

import Foundation

struct WikipediaSummaryTool: NativeTool {
    let name = "wikipedia_get_summary"

    var catalogEntry: NativeToolCatalogEntry {
        NativeToolCatalogEntry(
            name: name,
            title: "Wikipedia Summary",
            summary: "Load a concise Wikipedia page summary by article title and render a native summary card.",
            categories: ["encyclopedia", "web_knowledge", "wikipedia"],
            keywords: ["wikipedia", "summary", "article", "page", "תקציר", "ערך"],
            examples: ["Get Wikipedia summary for Jerusalem", "Load summary for Albert Einstein", "תקציר ויקיפדיה על ירושלים"]
        )
    }

    func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(
            name: name,
            description: "Get a concise Wikipedia page summary by title.",
            parameters: NativeToolSchema.object(
                properties: [
                    "title": NativeToolSchema.string(description: "Wikipedia article title."),
                    "language": NativeToolSchema.string(description: "Wikipedia language code, e.g. en, he. Default en or he according to user locale.")
                ],
                required: ["title"]
            )
        )
    }

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        do {
            let arguments = try NativeToolJSON.dictionary(from: argumentsJSON)
            let title = try NativeToolJSON.requiredString(arguments, "title")
            let language = NativeToolJSON.optionalString(arguments, "language") ?? (context.isHebrew ? "he" : "en")
            let encodedTitle = title.replacingOccurrences(of: " ", with: "_").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
            guard let url = URL(string: "https://\(language).wikipedia.org/api/rest_v1/page/summary/\(encodedTitle)") else {
                throw URLError(.badURL)
            }

            let (data, _) = try await URLSession.shared.data(from: url)
            let summary = try JSONDecoder().decode(WikipediaSummaryResponse.self, from: data)
            let pageURL = summary.content_urls?.desktop?.page ?? WikipediaSearchTool.pageURL(language: language, title: summary.title ?? title)
            let extract = summary.extract ?? ""

            let block = NativeUIBlock(
                type: .wikipediaSummary,
                title: summary.title ?? title,
                subtitle: summary.description,
                body: extract,
                systemImage: "globe",
                imageURL: summary.thumbnail?.source,
                url: pageURL,
                actions: [
                    NativeUIAction(type: .openURL, title: "Open", systemImage: "safari", url: pageURL),
                    NativeUIAction(type: .copyText, title: "Copy summary", systemImage: "doc.on.doc", text: extract)
                ]
            )

            return NativeToolResult(
                modelText: "Wikipedia summary for \(summary.title ?? title):\n\(extract)",
                userText: extract,
                uiBlocks: [block]
            )
        } catch {
            return NativeToolResult(
                modelText: "Wikipedia summary failed: \(error.localizedDescription)",
                uiBlocks: [NativeUIBlock(type: .error, title: "Wikipedia summary failed", body: error.localizedDescription, systemImage: "exclamationmark.triangle")]
            )
        }
    }
}

private struct WikipediaSummaryResponse: Codable {
    let title: String?
    let description: String?
    let extract: String?
    let thumbnail: WikipediaThumbnailSummary?
    let content_urls: WikipediaContentURLs?
}

private struct WikipediaThumbnailSummary: Codable {
    let source: String?
}

private struct WikipediaContentURLs: Codable {
    let desktop: WikipediaContentURL?
    let mobile: WikipediaContentURL?
}

private struct WikipediaContentURL: Codable {
    let page: String?
}
