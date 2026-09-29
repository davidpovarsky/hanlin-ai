import Foundation
import HanlinChatCore
import SwiftData
@testable import AI_Hanlin

public enum ProductionConformanceFixtures {
    public static let secretAPIKey = "CONFORMANCE_SECRET_DO_NOT_LEAK"
    public static let testHost = "conformance.provider"
    public static let endpointURL = "https://\(testHost)/v1/chat/completions"

    public static func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: ChatMessages.self,
            APIKeys.self,
            SearchKeys.self,
            AllModels.self,
            ChatRecords.self,
            UserInfo.self,
            PromptRepo.self,
            KnowledgeRecords.self,
            KnowledgeChunk.self,
            MemoryArchive.self,
            TranslationDic.self,
            ToolKeys.self,
            configurations: configuration
        )
    }

    public static func sseToolCall(
        id: String,
        name: String,
        arguments: [String: Any],
        finishReason: String = "tool_calls"
    ) -> Data {
        let argumentsData = try! JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys])
        let argumentsJSON = String(decoding: argumentsData, as: UTF8.self)
        let payload: [String: Any] = [
            "choices": [[
                "delta": [
                    "role": "assistant",
                    "tool_calls": [[
                        "index": 0,
                        "id": id,
                        "type": "function",
                        "function": ["name": name, "arguments": argumentsJSON]
                    ]]
                ],
                "finish_reason": finishReason
            ]]
        ]
        return sseData(payload)
    }

    public static func sseParallelToolCalls(
        calls: [(id: String, name: String, arguments: [String: Any])]
    ) -> Data {
        var toolDeltas: [[String: Any]] = []
        for (idx, call) in calls.enumerated() {
            let argumentsData = try! JSONSerialization.data(withJSONObject: call.arguments, options: [.sortedKeys])
            toolDeltas.append([
                "index": idx,
                "id": call.id,
                "type": "function",
                "function": ["name": call.name, "arguments": String(decoding: argumentsData, as: UTF8.self)]
            ])
        }
        let payload: [String: Any] = [
            "choices": [[
                "delta": [
                    "role": "assistant",
                    "tool_calls": toolDeltas
                ],
                "finish_reason": "tool_calls"
            ]]
        ]
        return sseData(payload)
    }

    public static func sseFinalAnswer(_ text: String) -> Data {
        sseData([
            "choices": [[
                "delta": ["role": "assistant", "content": text],
                "finish_reason": "stop"
            ]]
        ])
    }

    public static func sseFinishOnly(finishReason: String = "other") -> Data {
        sseData([
            "choices": [[
                "delta": [:],
                "finish_reason": finishReason
            ]]
        ])
    }

    public static func sseData(_ payload: [String: Any]) -> Data {
        let data = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let sse = "data: \(String(decoding: data, as: UTF8.self))\n\ndata: [DONE]\n\n"
        return Data(sse.utf8)
    }
}
