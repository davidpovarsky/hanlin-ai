import Foundation

public enum ReadToolResultTool {
    public static let toolName = "read_tool_result"

    public static var schema: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": toolName,
                "description": "Read paginated or sliced content from a stored large tool result using its opaque reference ID.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "reference": [
                            "type": "string",
                            "description": "The opaque reference ID of the stored tool result (e.g. 'ref_...')."
                        ],
                        "offset": [
                            "type": "integer",
                            "description": "The character/byte offset to start reading from (default: 0)."
                        ],
                        "limit": [
                            "type": "integer",
                            "description": "The maximum number of bytes to read (default: 4096, max: 16384)."
                        ]
                    ],
                    "required": ["reference"]
                ]
            ]
        ]
    }

    public struct Arguments: Decodable, Sendable {
        public let reference: String
        public let offset: Int?
        public let limit: Int?
    }

    @MainActor
    public static func execute(
        argumentsJSON: String,
        session: AssistantCapabilitySession
    ) -> String {
        guard let data = argumentsJSON.data(using: .utf8),
              let args = try? JSONDecoder().decode(Arguments.self, from: data) else {
            return "Error: Invalid arguments for read_tool_result. Expected JSON with 'reference'."
        }

        let ref = args.reference.trimmingCharacters(in: .whitespacesAndNewlines)
        let offset = max(0, args.offset ?? 0)
        let limit = min(max(1, args.limit ?? 4096), 16384)

        guard let slice = session.resultStore.read(reference: ref, offset: offset, limit: limit) else {
            return "Error: Tool result reference '\(ref)' not found or has expired."
        }

        var header = "Result slice for `\(ref)` [offset: \(slice.offset), bytes: \(slice.sliceLength)/\(slice.totalLength)]:\n\n"
        header += slice.text
        if slice.hasMore {
            let nextOffset = slice.offset + slice.sliceLength
            header += "\n\n[... \(slice.totalLength - nextOffset) more bytes available. Call `read_tool_result(reference: \"\(ref)\", offset: \(nextOffset))` to read more.]"
        }
        return header
    }
}
