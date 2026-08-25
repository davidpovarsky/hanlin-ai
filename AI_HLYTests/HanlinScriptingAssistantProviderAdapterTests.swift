import Foundation
import Testing
@testable import AI_Hanlin

@Suite("Scripting Assistant configured provider adapter")
struct HanlinScriptingAssistantProviderAdapterTests {
    @Test("Converts Scripting required flags into provider JSON Schema")
    func schemaConversion() throws {
        let source: [String: Any] = [
            "type": "object",
            "description": "Draft",
            "properties": [
                "subject": ["type": "string", "description": "Subject", "required": true],
                "body": ["type": "string", "description": "Body"],
            ],
        ]
        let converted = try #require(
            HanlinScriptingAssistantProviderAdapter.providerSchema(source) as? [String: Any]
        )
        #expect(converted["required"] as? [String] == ["subject"])
        #expect(converted["additionalProperties"] as? Bool == false)
        let properties = try #require(converted["properties"] as? [String: Any])
        #expect((properties["body"] as? [String: Any])?["required"] == nil)
    }

    @Test("Maps text, reasoning, and usage from Chat Completions SSE objects")
    func streamChunks() throws {
        let chunks = try HanlinScriptingAssistantProviderAdapter.chunks(from: [
            "choices": [["delta": ["content": "answer", "reasoning_content": "checked"]]],
            "usage": [
                "prompt_tokens": 7,
                "completion_tokens": 3,
                "prompt_tokens_details": ["cached_tokens": 2],
            ],
        ])
        #expect(chunks.count == 3)
        guard case let .reasoning(reasoning) = chunks[0],
              case let .text(text) = chunks[1],
              case let .usage(usage) = chunks[2] else {
            Issue.record("Unexpected Assistant chunk ordering")
            return
        }
        #expect(reasoning == "checked")
        #expect(text == "answer")
        #expect(usage.inputTokens == 7)
        #expect(usage.outputTokens == 3)
        #expect(usage.cacheReadTokens == 2)
    }

    @Test("Accepts bounded JSON and strips provider markdown fences")
    func structuredContent() throws {
        let data = try #require(HanlinScriptingAssistantProviderAdapter.structuredData(from: """
        ```json
        {"subject":"Hello","body":"World"}
        ```
        """))
        let value = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: String]
        )
        #expect(value == ["body": "World", "subject": "Hello"])
        #expect(HanlinScriptingAssistantProviderAdapter.structuredData(from: "not-json") == nil)
    }
}
