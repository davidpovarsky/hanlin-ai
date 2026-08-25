import HanlinPlatformContracts
@testable import HanlinScriptingApplicationRuntime
import Foundation
import Testing

@Suite("Scripting application runtime", .serialized)
struct HanlinScriptingApplicationRuntimeTests {
    @MainActor
    @Test("Compiles and renders independently of the application target")
    func rendersIndependently() throws {
        let packageID = try HanlinInstalledPackageID(validating: "fast-runtime-test")
        let session = try HanlinScriptingApplicationSession(
            installedPackageID: packageID,
            program: #"Navigation.present({ element: createElement(Text, null, "Ready") });"#,
            filename: "compiled/index.js",
            storageAllowed: false
        )
        defer { session.dispose() }

        #expect(session.model.root.kind == .text)
        #expect(session.model.root.properties["text"] == .string("Ready"))
    }

    @Test("Decodes bounded Assistant requests and emits Web-compatible chunks")
    func assistantNativePayloads() throws {
        let request = try HanlinScriptingAssistantPayloadDecoder.decode(#"""
        {
          "kind": "streaming",
          "systemPrompt": "Be concise",
          "messages": [{"role":"user","content":"Hello"}],
          "provider": {"custom":"https://assistant.example/v1"},
          "modelId": "test-model"
        }
        """#)
        #expect(request.kind == .streaming)
        #expect(request.provider == .custom("https://assistant.example/v1"))
        #expect(request.modelID == "test-model")
        #expect(request.messagesJSON != nil)

        let usage = try HanlinScriptingAssistantChunk.usage(.init(
            totalCost: nil,
            cacheReadTokens: 4,
            inputTokens: 7,
            outputTokens: 3
        )).nativeObject()
        #expect(usage["type"] as? String == "usage")
        let content = try #require(usage["content"] as? [String: Any])
        #expect(content["inputTokens"] as? Int == 7)

        let structured = try HanlinScriptingAssistantChunk.structuredJSON(
            Data(#"{"answer":"verified"}"#.utf8)
        ).nativeObject()
        #expect(structured["type"] as? String == "structured")
        #expect((structured["content"] as? [String: Any])?["answer"] as? String == "verified")
    }
}
