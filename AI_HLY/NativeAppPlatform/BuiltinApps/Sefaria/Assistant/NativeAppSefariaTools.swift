import Foundation

struct SefariaAssistantSearchTool: NativeTool {
    let service: NativeAppSefariaSearchService
    let name = "sefaria_search"

    var catalogEntry: NativeToolCatalogEntry {
        NativeToolCatalogEntry(
            name: name,
            title: String(localized: "Search Texts"),
            summary: String(localized: "Search topics, phrases and references"),
            categories: ["knowledge", "jewish texts", "sefaria", "native app"],
            keywords: ["torah", "talmud", "tanakh", "halacha", "source", "מקור", "ספריא"],
            examples: ["Search Sefaria for hashavat aveidah", "Find a Jewish source about charity"],
            presentationProfile: .modernNative(
                toolName: name,
                kind: .search,
                systemImage: "book.closed",
                runningTitle: "Searching Sefaria",
                completedTitle: "Searched Sefaria",
                visibleArgumentKeys: ["query"],
                evidenceKind: .sefariaSource
            )
        )
    }

    func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(
            name: name,
            description: "Search Sefaria for a topic or phrase. For an exact textual reference, use sefaria_get_source instead. If this tool returns no results, report that fact and do not supply remembered sources as tool results.",
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
                        NativeUIAction(type: .openURL, title: "Open", systemImage: "safari", url: result.url?.absoluteString),
                        NativeUIAction(type: .openAppRoute, title: "Open in Sefaria", systemImage: "arrow.up.forward.app", route: .sefariaSource(ref: result.ref), presentationStyle: .fullScreen)
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

struct SefariaAssistantSourceTool: NativeTool {
    let service: NativeAppSefariaSourceService
    let name = "sefaria_get_source"

    var catalogEntry: NativeToolCatalogEntry {
        NativeToolCatalogEntry(
            name: name,
            title: String(localized: "Get Source"),
            summary: String(localized: "Load exact Hebrew or English source text"),
            categories: ["knowledge", "jewish texts", "sefaria", "native app"],
            keywords: ["source", "reference", "passage", "מקור", "פסוק"],
            examples: ["Open Genesis 1:1", "Get Bava Metzia 21a"],
            presentationProfile: .modernNative(
                toolName: name,
                kind: .read,
                systemImage: "book.closed",
                runningTitle: "Reading a source",
                completedTitle: "Read a source",
                visibleArgumentKeys: ["reference"],
                evidenceKind: .sefariaSource
            )
        )
    }

    func openAIToolSchema() -> [String: Any] {
        NativeToolSchema.function(
            name: name,
            description: "Resolve and load an exact Sefaria textual reference in Hebrew and/or English. Use sefaria_search for topics or phrases. If loading fails, report the tool failure and do not invent the source text.",
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
                            NativeUIAction(type: .openURL, title: "Open", systemImage: "safari", url: source.url?.absoluteString),
                            NativeUIAction(type: .openAppRoute, title: "Open in Sefaria", systemImage: "arrow.up.forward.app", route: .sefariaSource(ref: source.ref), presentationStyle: .fullScreen)
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
