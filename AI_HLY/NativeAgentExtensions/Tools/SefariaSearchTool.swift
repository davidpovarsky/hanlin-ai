//
//  SefariaSearchTool.swift
//  AI_HLY
//

import Foundation

struct SefariaSearchTool: NativeTool {
    let name = "sefaria_search"

    var catalogEntry: NativeToolCatalogEntry {
        NativeToolCatalogEntry(
            name: name,
            title: "Sefaria Search",
            summary: "Search Jewish texts including Tanakh, Talmud, Midrash, Halacha, commentaries and Jewish sources using Sefaria.",
            categories: ["jewish_texts", "torah", "sources", "religion"],
            keywords: ["sefaria", "torah", "tanakh", "talmud", "gemara", "mishna", "halacha", "midrash", "rashi", "rambam", "source", "מקור", "גמרא", "משנה", "הלכה", "תורה", "פסוק", "רשי", "רמבם"],
            examples: ["Find a source about hashavat aveidah", "Search Gemara sources about honoring parents", "מצא מקור על השבת אבדה", "חפש בגמרא על כיבוד אב ואם"]
        )
    }

    func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(
            name: name,
            description: "Search Jewish texts in Sefaria. Use for Torah, Tanakh, Talmud, Midrash, Halacha, commentaries and Jewish source lookups.",
            parameters: NativeToolSchema.object(
                properties: [
                    "query": NativeToolSchema.string(description: "Search query in Hebrew or English."),
                    "limit": NativeToolSchema.number(description: "Maximum results, usually 3-8.", minimum: 1, maximum: 10)
                ],
                required: ["query"]
            )
        )
    }

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        do {
            let arguments = try NativeToolJSON.dictionary(from: argumentsJSON)
            let query = try NativeToolJSON.requiredString(arguments, "query")
            let limit = max(1, min(NativeToolJSON.int(arguments, "limit", default: 5), 10))

            var components = URLComponents(string: "https://www.sefaria.org/api/search-wrapper")!
            components.queryItems = [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "size", value: "\(limit)")
            ]
            guard let url = components.url else { throw URLError(.badURL) }

            let (data, _) = try await URLSession.shared.data(from: url)
            let results = try Self.parseSearchResults(data: data, limit: limit)

            if results.isEmpty {
                return NativeToolResult(
                    modelText: "No Sefaria results found for \(query).",
                    uiBlocks: [NativeUIBlock(type: .error, title: "No Sefaria results", body: query, systemImage: "book.closed")]
                )
            }

            let items = results.map { result in
                NativeUIListItem(
                    title: result.title,
                    subtitle: result.reference,
                    body: result.snippet,
                    url: result.url,
                    actions: [
                        NativeUIAction(type: .openURL, title: "Open", systemImage: "safari", url: result.url),
                        NativeUIAction(type: .copyText, title: "Copy reference", systemImage: "doc.on.doc", text: result.reference)
                    ]
                )
            }

            let modelLines = results.enumerated().map { index, result in
                "[\(index + 1)] \(result.reference): \(result.snippet ?? "")"
            }.joined(separator: "\n")

            let block = NativeUIBlock(
                type: .searchResults,
                title: "Sefaria results",
                subtitle: query,
                systemImage: "book.closed",
                items: items
            )

            return NativeToolResult(
                modelText: "Sefaria search results for \(query):\n\(modelLines)",
                userText: "Found \(results.count) Sefaria result(s).",
                uiBlocks: [block]
            )
        } catch {
            return NativeToolResult(
                modelText: "Sefaria search failed: \(error.localizedDescription)",
                uiBlocks: [NativeUIBlock(type: .error, title: "Sefaria search failed", body: error.localizedDescription, systemImage: "exclamationmark.triangle")]
            )
        }
    }

    private static func parseSearchResults(data: Data, limit: Int) throws -> [SefariaSearchResult] {
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        guard let root = object as? [String: Any] else { return [] }

        let rawHits: [[String: Any]]
        if let hits = root["hits"] as? [[String: Any]] {
            rawHits = hits
        } else if let hitsContainer = root["hits"] as? [String: Any], let hits = hitsContainer["hits"] as? [[String: Any]] {
            rawHits = hits
        } else if let results = root["results"] as? [[String: Any]] {
            rawHits = results
        } else {
            rawHits = []
        }

        return rawHits.prefix(limit).compactMap { hit in
            let source = hit["_source"] as? [String: Any]
            let reference = firstString(in: [hit["ref"], hit["reference"], source?["ref"], source?["title"]]) ?? "Sefaria"
            let heRef = firstString(in: [hit["heRef"], source?["heRef"]])
            let title = heRef ?? reference
            let snippet = firstString(in: [hit["snippet"], hit["content"], source?["content"], source?["text"]])
            return SefariaSearchResult(reference: reference, title: title, snippet: snippet, url: sefariaURL(for: reference))
        }
    }

    private static func firstString(in values: [Any?]) -> String? {
        for value in values {
            if let string = value as? String, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return string
            }
            if let array = value as? [String], let string = array.first, !string.isEmpty {
                return string
            }
        }
        return nil
    }

    static func sefariaURL(for reference: String) -> String {
        let path = reference
            .replacingOccurrences(of: " ", with: ".")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? reference
        return "https://www.sefaria.org/\(path)"
    }
}

private struct SefariaSearchResult {
    var reference: String
    var title: String
    var snippet: String?
    var url: String
}
