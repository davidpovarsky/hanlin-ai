import Foundation
import AISDKProvider
import HanlinChatCore
import HanlinHostContracts

public enum HanlinAppleAvailability: String, Sendable {
    case available, deviceNotEligible, intelligenceDisabled, modelNotReady, frameworkUnavailable, unavailable
}

/// Stateless availability projection for the EXISTING picker. Re-read/observe at its lifecycle
/// boundary and before sending. This does not select models or provide a fallback/router.
public enum HanlinAppleOnDeviceProvider {
    public static let modelID = "apple-system-on-device"
    public static let displayName = "Apple Intelligence — On-Device"
    public static let supportsTools = false // Exact-once native tool handoff is intentionally not claimed.

    public static var availability: HanlinAppleAvailability {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available: .available
        case .unavailable(.deviceNotEligible): .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled): .intelligenceDisabled
        case .unavailable(.modelNotReady): .modelNotReady
        case .unavailable: .unavailable
        @unknown default: .unavailable
        }
        #else
        .frameworkUnavailable
        #endif
    }

    public static func configuration() -> HanlinChatModelConfiguration {
        .init(modelID: modelID, displayName: displayName, company: "APPLE", apiType: "apple-on-device",
              endpoint: URL(filePath: "/apple-on-device"), apiKey: "", supportsToolUse: false)
    }

    public static func makeEngine(configuration: HanlinChatModelConfiguration) throws -> HanlinAISDKAgentEngine {
        guard availability == .available else { throw HanlinAppleProviderError.unavailable }
        guard configuration.baseModelID == modelID,
              HanlinAISDKProviderFactory.descriptor(for: configuration).kind == .appleOnDevice,
              !configuration.supportsToolUse, !configuration.supportsReasoning else { throw HanlinAppleProviderError.unsupportedSettings }
        return HanlinAISDKAgentEngine(configuration: configuration, model: .v3(HanlinAppleLanguageModel()),
                                      descriptor: HanlinAISDKProviderFactory.descriptor(for: configuration))
    }
}

#if canImport(FoundationModels)
import FoundationModels
#endif

/// A provider only: no tool execution and no second agent loop. Unsupported native/tool features
/// fail before generation instead of quietly executing through another authority.
public struct HanlinAppleLanguageModel: LanguageModelV3 {
    public let provider = "apple-on-device"
    public let modelId = HanlinAppleOnDeviceProvider.modelID
    public init() {}

    public func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        let stream = try await doStream(options: options).stream
        var text = ""
        for try await part in stream {
            if case .textDelta(_, let delta, _) = part { text += delta }
        }
        return .init(content: [.text(.init(text: text))], finishReason: .init(unified: .stop), usage: .init())
    }

    public func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        guard (options.tools ?? []).isEmpty else { throw HanlinAppleProviderError.unsupportedTools }
        if let choice = options.toolChoice, choice != .auto && choice != .none { throw HanlinAppleProviderError.unsupportedTools }
        guard options.topP == nil, options.topK == nil, options.presencePenalty == nil,
              options.frequencyPenalty == nil, options.seed == nil, (options.stopSequences ?? []).isEmpty,
              options.responseFormat == nil || options.responseFormat == .text,
              options.providerOptions == nil || options.providerOptions?.isEmpty == true,
              options.includeRawChunks != true else { throw HanlinAppleProviderError.unsupportedSettings }
        try Task.checkCancellation()
        if options.abortSignal?() == true { throw CancellationError() }
        guard HanlinAppleOnDeviceProvider.availability == .available else { throw HanlinAppleProviderError.unavailable }
        #if canImport(FoundationModels)
        let generation = GenerationOptions(temperature: options.temperature, maximumResponseTokens: options.maxOutputTokens)
        var history: [Transcript.Entry] = []
        var pendingPrompt: String?
        for message in options.prompt {
            // Keep role boundaries in the native transcript. Never promote old assistant/user text
            // into trusted instructions by concatenating a faux role-tagged system string.
            if let pendingPrompt {
                history.append(.prompt(.init(id: UUID().uuidString, segments: [.text(.init(id: UUID().uuidString, content: pendingPrompt))], options: generation, responseFormat: nil)))
            }
            pendingPrompt = nil
            switch message {
            case .system(let content, _):
                guard history.isEmpty else { throw HanlinAppleProviderError.unsupportedContent }
                history.append(.instructions(.init(id: UUID().uuidString, segments: [.text(.init(id: UUID().uuidString, content: content))], toolDefinitions: [])))
            case .user(let parts, _):
                var texts: [String] = []
                for part in parts { guard case .text(let text) = part else { throw HanlinAppleProviderError.unsupportedContent }; texts.append(text.text) }
                pendingPrompt = texts.joined(separator: "\n")
            case .assistant(let parts, _):
                var texts: [String] = []
                for part in parts { guard case .text(let text) = part else { throw HanlinAppleProviderError.unsupportedContent }; texts.append(text.text) }
                history.append(.response(.init(id: UUID().uuidString, assetIDs: [], segments: [.text(.init(id: UUID().uuidString, content: texts.joined(separator: "\n")))])))
            case .tool: throw HanlinAppleProviderError.unsupportedTools
            }
        }
        guard let prompt = pendingPrompt else { throw HanlinAppleProviderError.unsupportedContent }
        let session = LanguageModelSession(model: .default, transcript: Transcript(entries: history))
        return .init(stream: AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let id = UUID().uuidString
                    continuation.yield(.streamStart(warnings: []))
                    continuation.yield(.textStart(id: id, providerMetadata: nil))
                    var deltas = HanlinAppleTextDelta()
                    for try await snapshot in session.streamResponse(to: prompt, options: generation) {
                        try Task.checkCancellation()
                        if options.abortSignal?() == true { throw CancellationError() }
                        let delta = try deltas.append(snapshot: snapshot.content)
                        if !delta.isEmpty { continuation.yield(.textDelta(id: id, delta: delta, providerMetadata: nil)) }
                    }
                    try Task.checkCancellation()
                    continuation.yield(.textEnd(id: id, providerMetadata: nil))
                    // FoundationModels does not provide the pinned SDK's usage fields here.
                    continuation.yield(.finish(finishReason: .init(unified: .stop), usage: .init(), providerMetadata: nil))
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }, request: nil, response: nil)
        #else
        throw HanlinAppleProviderError.unavailable
        #endif
    }
}
