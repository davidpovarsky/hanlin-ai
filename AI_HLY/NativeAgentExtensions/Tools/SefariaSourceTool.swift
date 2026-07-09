//
//  SefariaSourceTool.swift
//  AI_HLY
//

import Foundation

struct SefariaSourceTool: NativeTool {
    let name = "sefaria_get_source"

    var catalogEntry: NativeToolCatalogEntry {
        NativeToolCatalogEntry(
            name: name,
            title: "Sefaria Source",
            summary: "Load a full Jewish text source from Sefaria by reference, including Hebrew and English text when available.",
            categories: ["jewish_texts", "torah", "sources", "religion"],
            keywords: ["sefaria", "source", "reference", "pasuk", "gemara", "מקור", "מראה מקום", "פסוק", "גמרא"],
            examples: ["Load Berakhot 2a", "Get source for Exodus 20:8", "פתח מקור ברכות ב א"]
        )
    }

    func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(
            name: name,
            description: "Load a full Jewish source from Sefaria by textual reference, e.g. 'Berakhot 2a' or 'Exodus 20:8'.",
            parameters: NativeToolSchema.object(
                properties: [
                    "ref": NativeToolSchema.string(description: "Sefaria reference, e.g. 'Berakhot 2a', 'Genesis 1:1', 'Mishneh Torah, Repentance 1:1'.")
                ],
                required: ["ref"]
            )
        )
    }

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        do {
            let arguments = try NativeToolJSON.dictionary(from: argumentsJSON)
            let ref = try NativeToolJSON.requiredString(arguments, "ref")
            let encodedRef = ref.replacingOccurrences(of: " ", with: ".").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ref
            guard let url = URL(string: "https://www.sefaria.org/api/texts/\(encodedRef)?context=0") else {
                throw URLError(.badURL)
            }

            let (data, _) = try await URLSession.shared.data(from: url)
            let source = try Self.parseSource(data: data, fallbackRef: ref)
            let openURL = SefariaSearchTool.sefariaURL(for: source.ref)

            var bodyParts: [String] = []
            if let he = source.hebrewText, !he.isEmpty { bodyParts.append("**עברית**\n\(he)") }
            if let en = source.englishText, !en.isEmpty { bodyParts.append("**English**\n\(en)") }
            let body = bodyParts.joined(separator: "\n\n")

            let block = NativeUIBlock(
                type: .source,
                title: source.heRef ?? source.ref,
                subtitle: source.ref,
                body: body,
                systemImage: "book.closed",
                url: openURL,
                actions: [
                    NativeUIAction(type: .openURL, title: "Open", systemImage: "safari", url: openURL),
                    NativeUIAction(type: .copyText, title: "Copy source", systemImage: "doc.on.doc", text: body)
                ]
            )

            return NativeToolResult(
                modelText: "Sefaria source \(source.ref):\n\(body)",
                userText: body,
                uiBlocks: [block]
            )
        } catch {
            return NativeToolResult(
                modelText: "Sefaria source lookup failed: \(error.localizedDescription)",
                uiBlocks: [NativeUIBlock(type: .error, title: "Sefaria source failed", body: error.localizedDescription, systemImage: "exclamationmark.triangle")]
            )
        }
    }

    private static func parseSource(data: Data, fallbackRef: String) throws -> SefariaSource {
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        guard let root = object as? [String: Any] else {
            return SefariaSource(ref: fallbackRef, heRef: nil, englishText: nil, hebrewText: nil)
        }

        let ref = root["ref"] as? String ?? fallbackRef
        let heRef = root["heRef"] as? String
        let en = flattenText(root["text"])
        let he = flattenText(root["he"])
        return SefariaSource(ref: ref, heRef: heRef, englishText: en, hebrewText: he)
    }

    private static func flattenText(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let strings = value as? [String] { return strings.joined(separator: "\n") }
        if let nested = value as? [Any] {
            let parts = nested.compactMap { flattenText($0) }.filter { !$0.isEmpty }
            return parts.joined(separator: "\n")
        }
        return nil
    }
}

private struct SefariaSource {
    var ref: String
    var heRef: String?
    var englishText: String?
    var hebrewText: String?
}
