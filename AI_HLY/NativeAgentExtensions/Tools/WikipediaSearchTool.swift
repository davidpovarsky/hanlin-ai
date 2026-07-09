//
//  WikipediaSearchTool.swift
//  AI_HLY
//

import Foundation

struct WikipediaSearchTool: NativeTool {
    let name = "wikipedia_search"

    var catalogEntry: NativeToolCatalogEntry {
        NativeToolCatalogEntry(
            name: name,
            title: "Wikipedia Search",
            summary: "Search Wikipedia articles and return compact encyclopedia results with native result cards.",
            categories: ["encyclopedia", "web_knowledge", "wikipedia"],
            keywords: ["wikipedia", "encyclopedia", "wiki", "article", "person", "place", "history", "ויקיפדיה", "ערך", "אנציקלופדיה"],
            examples: ["Search Wikipedia for Maimonides", "Who was Ada Lovelace?", "חפש בויקיפדיה על הרמבם"]
        )
    }

    func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(
            name: name,
            description: "Search Wikipedia for articles. Use when the user asks for general encyclopedia knowledge, people, places, organizations, history or definitions.",
            parameters: NativeToolSchema.object(
                properties: [
                    "query": NativeToolSchema.string(description: "Search query."),
                    "language": NativeToolSchema.string(description: "Wikipedia language code, e.g. en, he, fr. Default en."),
                    "limit": NativeToolSchema.number(description: "Maximum results, usually 3-5.", minimum: 1, maximum: 10)
                ],
                required: ["query"]
            )
        )
    }

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        do {
            let arguments = try NativeToolJSON.dictionary(from: argumentsJSON)
            let query = try NativeToolJSON.requiredString(arguments, "query")
            let language = NativeToolJSON.optionalString(arguments, "language") ?? (context.isHebrew ? "he" : "en")
            let limit = max(1, min(NativeToolJSON.int(arguments, "limit", default: 5), 10))

            var components = URLComponents()
            components.scheme = "https"
            components.host = "\(language).wikipedia.org"
            components.path = "/w/api.php"
            components.queryItems = [
                URLQueryItem(name: "action", value: "query"),
                URLQueryItem(name: "generator", value: "search"),
                URLQueryItem(name: "gsrsearch", value: query),
                URLQueryItem(name: "gsrlimit", value: "\(limit)"),
                URLQueryItem(name: "prop", value: "pageimages|extracts"),
                URLQueryItem(name: "exintro", value: "1"),
                URLQueryItem(name: "explaintext", value: "1"),
                URLQueryItem(name: "exchars", value: "500"),
                URLQueryItem(name: "piprop", value: "thumbnail"),
                URLQueryItem(name: "pithumbsize", value: "240"),
                URLQueryItem(name: "format", value: "json")
            ]

            guard let url = components.url else { throw URLError(.badURL) }
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(WikipediaSearchResponse.self, from: data)
            let pages = response.query?.pages?.values.sorted { ($0.index ?? 0) < ($1.index ?? 0) } ?? []

            if pages.isEmpty {
                return NativeToolResult(
                    modelText: "No Wikipedia results found for \(query).",
                    uiBlocks: [NativeUIBlock(type: .error, title: "No Wikipedia results", body: query, systemImage: "globe")]
                )
            }

            let items = pages.map { page in
                let pageURL = Self.pageURL(language: language, title: page.title)
                return NativeUIListItem(
                    title: page.title,
                    subtitle: "Wikipedia (\(language))",
                    body: page.extract,
                    imageURL: page.thumbnail?.source,
                    url: pageURL,
                    actions: [
                        NativeUIAction(type: .openURL, title: "Open", systemImage: "safari", url: pageURL),
                        NativeUIAction(type: .copyText, title: "Copy title", systemImage: "doc.on.doc", text: page.title)
                    ]
                )
            }

            let modelLines = pages.enumerated().map { index, page in
                "[\(index + 1)] \(page.title): \(page.extract ?? "")"
            }.joined(separator: "\n")

            let block = NativeUIBlock(
                type: .searchResults,
                title: "Wikipedia results",
                subtitle: query,
                systemImage: "globe",
                items: items
            )

            return NativeToolResult(
                modelText: "Wikipedia search results for \(query):\n\(modelLines)",
                userText: "Found \(pages.count) Wikipedia result(s).",
                uiBlocks: [block]
            )
        } catch {
            return NativeToolResult(
                modelText: "Wikipedia search failed: \(error.localizedDescription)",
                uiBlocks: [NativeUIBlock(type: .error, title: "Wikipedia search failed", body: error.localizedDescription, systemImage: "exclamationmark.triangle")]
            )
        }
    }

    static func pageURL(language: String, title: String) -> String {
        let encoded = title.replacingOccurrences(of: " ", with: "_").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
        return "https://\(language).wikipedia.org/wiki/\(encoded)"
    }
}

private struct WikipediaSearchResponse: Codable {
    let query: WikipediaSearchQuery?
}

private struct WikipediaSearchQuery: Codable {
    let pages: [String: WikipediaSearchPage]?
}

private struct WikipediaSearchPage: Codable {
    let pageid: Int?
    let ns: Int?
    let title: String
    let index: Int?
    let extract: String?
    let thumbnail: WikipediaThumbnail?
}

private struct WikipediaThumbnail: Codable {
    let source: String?
    let width: Int?
    let height: Int?
}
