import Foundation
@preconcurrency import LLM

/// Keeps the legacy LLM.swift 1.x callback at a Sendable boundary while all
/// mutable stream processing remains serialized on the app's main actor.
@MainActor
enum LocalLLMStreamingAdapter {
    static func consume(
        _ llm: LLM,
        prompt: String,
        onDelta: (String) -> Bool
    ) async {
        let (stream, continuation) = AsyncStream.makeStream(of: String.self)
        llm.update = { @Sendable delta in
            if let delta {
                continuation.yield(delta)
            } else {
                continuation.finish()
            }
        }

        let generation = Task { @MainActor in
            await llm.respond(to: prompt)
            continuation.finish()
        }
        for await delta in stream where !onDelta(delta) {
            llm.stop()
            break
        }
        await generation.value
        llm.update = { _ in }
    }
}
