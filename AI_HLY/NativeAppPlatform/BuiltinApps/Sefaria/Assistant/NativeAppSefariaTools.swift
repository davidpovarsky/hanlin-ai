import Foundation

struct NativeAppSefariaSearchTool: NativeTool {
    let service: NativeAppSefariaSearchService
    let name = "app_sefaria_search"

    var catalogEntry: NativeToolCatalogEntry {
        NativeToolCatalogEntry(
            name: name,
            title: "Sefaria App Search",
            summary: "Search Jewish texts through the same Core service used by the full Sefaria mini app.",
            categories: ["knowledge", "jewish texts", "sefaria", "native app"],
            keywords: ["torah", "talmud", "tanakh", "halacha", "source", "מקור", "ספריא"],
            examples: ["Search Sefaria for hashavat aveidah", "Find a Jewish source about charity"]
        )
    }

    func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(
            name: name,
            description: "Search Sefaria Jewish texts using the compiled Sefaria native app Core.",
            parameters: NativeToolSchema.object(
                properties: [
                    "query": NativeToolSchema.string(description: "Search query, reference, topic, or phrase."),
                    "limit": NativeToolSchema.number(description: "Maximum results, 1-20.", minimum: 1, maximum: 20)
                ],
                required: ["query"]
            )
        )
    }

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        let object = NativeAppJSON.decodeObject(from: argumentsJSON)
        let query = NativeAppJSON.string(object, "query")
        let limit = max(1, min(NativeAppJSON.int(object, "limit", default: 5), 20))
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return NativeToolResult(modelText: "Missing Sefaria query.", uiBlocks: [NativeUIBlock(type: .error, title: "Missing query")])
        }
        do {
            let results = try await service.search(query: query, limit: limit)
            let items = results.map { result in
                NativeUIListItem(
                    id: result.ref,
                    title: result.title,
                    subtitle: result.ref,
                    body: result.snippet,
                    url: result.url?.absoluteString,
                    actions: [
                        NativeUIAction(type: .copyText, title: "Copy Ref", systemImage: "doc.on.doc", text: result.ref),
                        NativeUIAction(type: .openURL, title: "Open", systemImage: "safari", url: result.url?.absoluteString)
                    ]
                )
            }
            let modelText = results.isEmpty
                ? "No Sefaria results found for: \(query)"
                : results.map { "- \($0.ref): \($0.snippet)" }.joined(separator: "\n")
            return NativeToolResult(
                modelText: modelText,
                userText: results.isEmpty ? "No Sefaria results found." : "Found \(results.count) Sefaria result(s).",
                uiBlocks: [NativeUIBlock(type: .searchResults, title: "Sefaria results", subtitle: query, items: items)]
            )
        } catch {
            return NativeToolResult(
                modelText: "Sefaria search failed: \(error.localizedDescription)",
                uiBlocks: [NativeUIBlock(type: .error, title: "Sefaria search failed", body: error.localizedDescription)]
            )
        }
    }
}

struct NativeAppSefariaSourceTool: NativeTool {
    let service: NativeAppSefariaSourceService
    let name = "app_sefaria_get_source"

    var catalogEntry: NativeToolCatalogEntry {
        NativeToolCatalogEntry(
            name: name,
            title: "Sefaria App Source",
            summary: "Load a Sefaria reference through the same Core service used by the full reader.",
            categories: ["knowledge", "jewish texts", "sefaria", "native app"],
            keywords: ["source", "reference", "passage", "מקור", "פסוק"],
            examples: ["Open Genesis 1:1", "Get Bava Metzia 21a"]
        )
    }

    func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(
            name: name,
            description: "Open a Sefaria reference and return text using the compiled Sefaria mini app Core.",
            parameters: NativeToolSchema.object(
                properties: ["ref": NativeToolSchema.string(description: "Sefaria reference, e.g. Genesis 1:1 or Bava Metzia 21a.")],
                required: ["ref"]
            )
        )
    }

    func execute(argumentsJSON: String, context: NativeToolExecutionContext) async -> NativeToolResult {
        let object = NativeAppJSON.decodeObject(from: argumentsJSON)
        let ref = NativeAppJSON.string(object, "ref")
        guard !ref.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return NativeToolResult(modelText: "Missing Sefaria ref.")
        }
        do {
            let source = try await service.source(ref: ref)
            return NativeToolResult(
                modelText: "\(source.ref)\n\(source.combinedText)",
                userText: source.ref,
                uiBlocks: [
                    NativeUIBlock(
                        type: .source,
                        title: source.ref,
                        body: source.combinedText,
                        url: source.url?.absoluteString,
                        actions: [
                            NativeUIAction(type: .copyText, title: "Copy Source", systemImage: "doc.on.doc", text: source.combinedText),
                            NativeUIAction(type: .openURL, title: "Open", systemImage: "safari", url: source.url?.absoluteString)
                        ]
                    )
                ]
            )
        } catch {
            return NativeToolResult(
                modelText: "Sefaria source failed: \(error.localizedDescription)",
                uiBlocks: [NativeUIBlock(type: .error, title: "Sefaria source failed", body: error.localizedDescription)]
            )
        }
    }
}
