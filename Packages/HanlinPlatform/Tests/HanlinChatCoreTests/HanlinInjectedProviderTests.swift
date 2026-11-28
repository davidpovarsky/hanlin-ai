import AISDKProvider
import Foundation
import HanlinChatCore
import Testing

private actor NativePreflightSpy {
    var capabilities = 0
    var executions = 0
    func capabilityQueried() { capabilities += 1 }
    func executed() { executions += 1 }
}
private struct NativePreflightModel: LanguageModelV3 {
    let provider = "fixture-native"
    let modelId = "fixture-native"
    let spy: NativePreflightSpy
    var supportedUrls: [String: [NSRegularExpression]] {
        get async throws { await spy.capabilityQueried(); return [:] }
    }
    func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        await spy.executed(); throw HanlinAISDKError.nativeUnsupportedContent
    }
    func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        await spy.executed(); throw HanlinAISDKError.nativeUnsupportedContent
    }
}

@Suite struct HanlinInjectedProviderTests {
    @Test func nativeNonTextRejectedBeforeProviderCapabilityOrDownloadPath() async throws {
        let configuration = HanlinChatModelConfiguration(modelID: "apple-system-on-device", company: "APPLE", apiType: "apple-on-device", endpoint: URL(filePath: "/local"), apiKey: "")
        let spy = NativePreflightSpy()
        let engine = HanlinAISDKAgentEngine(configuration: configuration, model: .v3(NativePreflightModel(spy: spy)))
        // Current public message enum permits text, imageURL and imageData; no file/tool part exists.
        for part in [HanlinAISDKMessagePart.imageURL(URL(string: "https://example.invalid/private-image")!, mediaType: "image/png"), .imageData(Data([0x01]), mediaType: "image/png")] {
            for role in [HanlinAISDKMessage.Role.user, .assistant, .system] {
                do {
                    _ = try await engine.stream(messages: [.init(role: role, parts: [part])], baseSystemPrompt: nil, tools: [], prepareStep: { .init(activeToolAliases: []) })
                    Issue.record("Native non-text content reached the stream")
                } catch let error as HanlinAISDKError {
                    guard case .nativeUnsupportedContent = error else { Issue.record("Unexpected native error"); return }
                }
            }
        }
        #expect(await spy.capabilities == 0)
        #expect(await spy.executions == 0)
    }

    @Test func nativeDescriptorNeverSelectsNetworkProvider() throws {
        let configuration = HanlinChatModelConfiguration(modelID: "apple-system-on-device", company: "APPLE", apiType: "apple-on-device", endpoint: URL(filePath: "/local"), apiKey: "")
        #expect(HanlinAISDKProviderFactory.descriptor(for: configuration).kind == .appleOnDevice)
        #expect(HanlinAISDKProviderFactory.descriptor(for: configuration).baseURL.isFileURL)
        #expect(throws: HanlinAISDKError.self) { try HanlinAISDKAgentEngine(configuration: configuration) }
    }

    @Test func duplicateDefinitionsThrowBeforeDictionaryConstruction() async throws {
        let configuration = HanlinChatModelConfiguration(modelID: "fixture", company: "OPENAI", endpoint: URL(string: "https://api.openai.com/v1")!, apiKey: "fixture-never-sent")
        let engine = try HanlinAISDKAgentEngine(configuration: configuration)
        let definition = HanlinAISDKToolDefinition(name: "duplicate", description: "test", inputSchemaData: Data(#"{"type":"object"}"#.utf8)) { _, _ in .init(modelText: "Must never execute") }
        do {
            _ = try await engine.stream(messages: [.init(role: .user, text: "test")], baseSystemPrompt: nil, tools: [definition, definition], prepareStep: { .init(activeToolAliases: []) })
            Issue.record("Duplicate definitions did not throw")
        } catch let error as HanlinAISDKError {
            guard case .invalidToolSchema("duplicate") = error else { Issue.record("Unexpected SDK error"); return }
        }
    }
}
