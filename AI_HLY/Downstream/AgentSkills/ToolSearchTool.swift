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
