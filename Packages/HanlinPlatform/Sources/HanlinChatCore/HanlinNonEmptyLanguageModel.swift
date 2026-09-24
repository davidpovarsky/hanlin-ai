import AISDKProvider
import Foundation

/// Retries only an empty provider stream. Tool execution happens above the model layer,
/// so a completed Hanlin tool can never be executed again by this retry.
final class HanlinNonEmptyLanguageModel: LanguageModelV3, @unchecked Sendable {
    let base: any LanguageModelV3

    init(base: any LanguageModelV3) {
        self.base = base
    }

    var provider: String { base.provider }
    var modelId: String { base.modelId }
    var supportedUrls: [String: [NSRegularExpression]] {
        get async throws { try await base.supportedUrls }
    }

    func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        try await base.doGenerate(options: options)
    }

    func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        let first = try await base.doStream(options: options)
        return LanguageModelV3StreamResult(
            stream: retryingEmptyStream(first.stream, options: options),
            request: first.request,
            response: first.response
        )
    }

    private func retryingEmptyStream(
        _ first: AsyncThrowingStream<LanguageModelV3StreamPart, Error>,
        options: LanguageModelV3CallOptions
    ) -> AsyncThrowingStream<LanguageModelV3StreamPart, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var attempt = 0
                    var current = first
                    while attempt < 2 {
                        attempt += 1
                        var meaningful = false
                        for try await part in current {
                            if Self.isMeaningful(part) { meaningful = true }
                            continuation.yield(part)
                        }
                        if meaningful {
                            continuation.finish()
                            return
                        }
                        guard attempt < 2 else {
                            throw HanlinAISDKError.emptyProviderResponse(attempts: attempt)
                        }
                        current = try await base.doStream(options: options).stream
                    }
                } catch is CancellationError {
                    continuation.finish(throwing: HanlinChatError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func isMeaningful(_ part: LanguageModelV3StreamPart) -> Bool {
        switch part {
        case .textDelta(_, let text, _), .reasoningDelta(_, let text, _):
            return !text.isEmpty
        case .toolCall, .toolInputStart, .toolInputDelta, .finish:
            return true
        default:
            return false
        }
    }
}
