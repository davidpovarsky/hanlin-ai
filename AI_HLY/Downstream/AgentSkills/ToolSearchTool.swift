import Foundation
import HanlinPlatformContracts

public enum ToolSearchTool {
    public static let toolName = "tool_search"

    public static let schema: [String: Any] = [
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
                        "description": "Maximum number of tools to return (default: 5, max: 10)."
                    ]
                ],
                "required": ["query"]
            ]
        ]
    ]

    public struct Arguments: Decodable, Sendable {
        public let query: String
        public let limit: Int?
    }

    @MainActor
    public static func execute(
        argumentsJSON: String,
        session: AssistantCapabilitySession,
        searchProvider: (String, Int) -> [CanonicalToolSearchRecord]
    ) -> String {
        guard let data = argumentsJSON.data(using: .utf8),
              let args = try? JSONDecoder().decode(Arguments.self, from: data) else {
            return "Error: Invalid arguments for tool_search. Expected JSON with 'query'."
        }

        let query = args.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return "Error: Empty query provided to tool_search."
        }

        let limit = min(max(args.limit ?? 5, 1), 10)
        let results = searchProvider(query, limit)

        guard !results.isEmpty else {
            return "No matching tools found for '\(query)'. Try different keywords or load a relevant skill."
        }

        let aliases = results.map(\.alias)
        session.exposeTools(aliases: aliases)

        var response = "Found \(results.count) matching tool(s). These are now exposed and ready to call:\n\n"
        for item in results {
            response += "- `\(item.alias)`: \(item.title) — \(item.summary) [source: \(item.source)]\n"
        }

        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
