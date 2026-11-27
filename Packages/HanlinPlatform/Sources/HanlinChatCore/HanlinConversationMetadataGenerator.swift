import Foundation

extension HanlinConversationMetadata {
    /// Use the original provider/engine for one bounded text-only response. There
    /// is no tool invocation, auxiliary conversation, or second icon request.
    public static func generate(using engine: HanlinAISDKAgentEngine,
                                historyMessage: String, languageTag: String) async throws -> Self {
        try Task.checkCancellation()
        let stream = try await engine.stream(
            messages: [.init(role: .user, text: String(historyMessage.prefix(12000)))],
            baseSystemPrompt: HanlinConversationMetadataPolicy.instruction(languageTag: languageTag),
            tools: [], maxSteps: 1, prepareStep: { .init(activeToolAliases: []) })
        let providerKind = await engine.providerDescriptor.kind
        return try await decodeCompletedStream(stream, providerKind: providerKind)
    }

    static func decodeCompletedStream(_ stream: AsyncThrowingStream<HanlinAISDKStreamEvent, Error>,
                                      providerKind: HanlinAISDKProviderKind = .openAI) async throws -> Self {
        var text = ""
        var bytes = 0
        var completed = false
        for try await event in stream {
            try Task.checkCancellation()
            switch event {
            case .textDelta(let delta):
                let size = delta.utf8.count
                guard size <= 4096 - bytes else { throw ResponseError.invalidResponse }
                text += delta
                bytes += size
            case .finished(let reason, _):
                let normalized: String
                switch providerKind {
                case .anthropic: normalized = HanlinChatStreamParser.anthropicFinishReason(reason)
                case .google: normalized = HanlinChatStreamParser.geminiFinishReason(reason)
                default: normalized = reason
                }
                guard normalized == "stop" else { throw ResponseError.invalidResponse }
                completed = true
            case .cancelled:
                throw CancellationError()
            default:
                break
            }
        }
        try Task.checkCancellation()
        guard completed else { throw ResponseError.invalidResponse }
        return try decode(text)
    }
}
