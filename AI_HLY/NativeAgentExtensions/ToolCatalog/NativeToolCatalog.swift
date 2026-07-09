//
//  NativeToolCatalog.swift
//  AI_HLY
//
//  Registry and lightweight catalog search for deferred native tool loading.
//

import Foundation

@MainActor
final class NativeToolCatalog {
    static let shared = NativeToolCatalog()

    private var toolsByName: [String: NativeTool] = [:]
    private var didRegisterBuiltins = false

    private init() {}

    func ensureBuiltinsRegistered() {
        guard !didRegisterBuiltins else { return }
        didRegisterBuiltins = true
        register(ToolSearchTool())
        register(SefariaSearchTool())
        register(SefariaSourceTool())
        register(WikipediaSearchTool())
        register(WikipediaSummaryTool())
        register(QuickCalculateTool())
    }

    func register(_ tool: NativeTool) {
        toolsByName[tool.name] = tool
    }

    func tool(named name: String) -> NativeTool? {
        ensureBuiltinsRegistered()
        return toolsByName[name]
    }

    func allEntries(excludingToolSearch: Bool = true) -> [NativeToolCatalogEntry] {
        ensureBuiltinsRegistered()
        return toolsByName.values
            .map(\.catalogEntry)
            .filter { excludingToolSearch ? $0.name != ToolSearchTool.toolName : true }
            .sorted { $0.name < $1.name }
    }

    func schemas(for names: [String]) -> [[String: Any]] {
        ensureBuiltinsRegistered()
        var seen = Set<String>()
        return names.compactMap { name in
            guard name != ToolSearchTool.toolName, !seen.contains(name), let tool = toolsByName[name] else {
                return nil
            }
            seen.insert(name)
            return tool.openAIToolSchema()
        }
    }

    func search(query: String, intent: String? = nil, maxResults: Int = 5) -> [NativeToolSearchHit] {
        ensureBuiltinsRegistered()
        let normalizedQuery = normalize(query + " " + (intent ?? ""))
        let terms = tokenize(normalizedQuery)
        guard !terms.isEmpty else { return [] }

        let hits = allEntries(excludingToolSearch: true).compactMap { entry -> NativeToolSearchHit? in
            let searchable = normalize(entry.compactCatalogText)
            var score = 0
            var matched: [String] = []

            for term in terms {
                guard term.count > 1 else { continue }
                if searchable.contains(term) {
                    matched.append(term)
                    score += 10
                    if entry.name.lowercased().contains(term) { score += 20 }
                    if entry.title.lowercased().contains(term) { score += 12 }
                    if entry.categories.contains(where: { normalize($0).contains(term) }) { score += 12 }
                    if entry.keywords.contains(where: { normalize($0).contains(term) }) { score += 14 }
                    if entry.examples.contains(where: { normalize($0).contains(term) }) { score += 8 }
                }
            }

            return score > 0 ? NativeToolSearchHit(entry: entry, score: score, matchedTerms: Array(Set(matched)).sorted()) : nil
        }

        return hits.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.entry.name < rhs.entry.name
        }
        .prefix(max(1, min(maxResults, 8)))
        .map { $0 }
    }

    private func normalize(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
    }

    private func tokenize(_ text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .flatMap { part -> [String] in
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { return [] }
                return [trimmed]
            }
            .filter { !stopWords.contains($0) }
    }

    private var stopWords: Set<String> {
        ["the", "and", "for", "with", "that", "this", "from", "about", "into", "what", "who", "how", "של", "את", "על", "עם", "מה", "מי", "איך", "זה", "זו"]
    }
}
