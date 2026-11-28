import Foundation
import HanlinPlatformContracts

public enum ToolSearchTool {
    public static let toolName = "tool_search"

    public static var schema: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": toolName,
                "description": "Search the canonical tool catalog by keywords, name, or capability. Tools found by this search are automatically exposed and ready for use in subsequent calls.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "query": [
                            "type": "string",
                            "description": "Keywords or phrase describing the tool or capability needed."
                        ],
                        "limit": [
                            "type": "integer",
                            "description": "Maximum number of tools to return (default: 10, max: 50)."
                        ],
                        "offset": [
                            "type": "integer",
                            "description": "Optional zero-based offset for pagination across matching tools (default: 0)."
                        ]
                    ],
                    "required": ["query"]
                ]
            ]
        ]
    }

    public struct Arguments: Decodable, Sendable {
        public let query: String
        public let limit: Int?
        public let offset: Int?
    }

    @MainActor
    public static func execute(
        argumentsJSON: String,
        session: AssistantCapabilitySession,
        searchProvider: (String, Int, Int, Set<String>) -> [CanonicalToolSearchRecord]
    ) -> String {
        guard let data = argumentsJSON.data(using: .utf8),
              let args = try? JSONDecoder().decode(Arguments.self, from: data) else {
            return "Error: Invalid arguments for tool_search. Expected JSON with 'query'."
        }

        let query = args.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return "Error: Empty query provided to tool_search."
        }

        let limit = min(max(args.limit ?? 10, 1), 50)
        let offset = max(args.offset ?? 0, 0)
        let results = searchProvider(query, limit, offset, session.activeSkillToolHints)

        guard !results.isEmpty else {
            if offset > 0 {
                return "No more matching tools found for '\(query)' at offset \(offset)."
            }
            return "No matching tools found for '\(query)'. Try different keywords or load a relevant skill."
        }

        let aliases = results.map(\.alias)
        session.exposeTools(aliases: aliases)

        var response = "Found \(results.count) matching tool(s)"
        if offset > 0 {
            response += " (offset \(offset))"
        }
        response += ". These are now exposed and ready to call:\n\n"
        for item in results {
            response += "- `\(item.alias)`: \(item.title) — \(item.summary) [source: \(item.source)]\n"
        }

        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func userFacingSummary(
        argumentsJSON: String,
        result: String,
        language: String = "zh"
    ) -> String {
        let isZh = language.hasPrefix("zh")
        let isHe = language.hasPrefix("he")
        if result.hasPrefix("Error:") || result.hasPrefix("No ") {
            if isHe {
                return result.replacingOccurrences(of: "No tools found matching", with: "לא נמצאו כלים התואמים ל")
            }
            return result
        }
        let aliasLines = result
            .components(separatedBy: .newlines)
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("- `") }
        let aliases = aliasLines.compactMap { line -> String? in
            guard let firstTick = line.firstIndex(of: "`"),
                  let rest = line[line.index(after: firstTick)...].firstIndex(of: "`") else {
                return nil
            }
            return String(line[line.index(after: firstTick)..<rest])
        }
        if let data = argumentsJSON.data(using: .utf8),
           let args = try? JSONDecoder().decode(Arguments.self, from: data) {
            let query = args.query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !aliases.isEmpty {
                let preview = aliases.prefix(4).joined(separator: ", ")
                if isZh {
                    return "搜索「\(query)」匹配到 \(aliases.count) 个工具：\(preview)"
                } else if isHe {
                    return "בחיפוש '\(query)' נמצאו \(aliases.count) כלים: \(preview)"
                } else {
                    return "Found \(aliases.count) tool(s) for '\(query)': \(preview)"
                }
            }
        }
        let firstLine = result.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if firstLine.isEmpty {
            if isZh {
                return "已完成工具搜索"
            } else if isHe {
                return "חיפוש הכלים הושלם"
            } else {
                return "Completed tool search"
            }
        }
        return firstLine
    }

    @MainActor
    public static func execute(
        argumentsJSON: String,
        session: AssistantCapabilitySession,
        searchProvider: (String, Int, Set<String>) -> [CanonicalToolSearchRecord]
    ) -> String {
        execute(argumentsJSON: argumentsJSON, session: session) { query, limit, offset, hints in
            let all = searchProvider(query, limit + offset, hints)
            if offset < all.count {
                return Array(all.dropFirst(offset).prefix(limit))
            }
            return []
        }
    }

    @MainActor
    public static func execute(
        argumentsJSON: String,
        session: AssistantCapabilitySession,
        searchProvider: (String, Int) -> [CanonicalToolSearchRecord]
    ) -> String {
        execute(argumentsJSON: argumentsJSON, session: session) { query, limit, offset, _ in
            let all = searchProvider(query, limit + offset)
            if offset < all.count {
                return Array(all.dropFirst(offset).prefix(limit))
            }
            return []
        }
    }
}
