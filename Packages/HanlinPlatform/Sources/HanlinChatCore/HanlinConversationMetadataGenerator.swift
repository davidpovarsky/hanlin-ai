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
        return try await decodeCompletedStream(stream)
    }

    static func decodeCompletedStream(_ stream: AsyncThrowingStream<HanlinAISDKStreamEvent, Error>) async throws -> Self {
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
                guard reason == "stop" else { throw ResponseError.invalidResponse }
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
