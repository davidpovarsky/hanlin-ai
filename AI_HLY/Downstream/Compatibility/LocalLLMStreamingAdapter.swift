import Foundation
@preconcurrency import LLM

@MainActor
struct LocalLLMStreamDriver {
    let setUpdate: (@escaping @Sendable (String?) -> Void) -> Void
    let respond: @MainActor (String) async -> Void
    let stop: @MainActor () -> Void

    init(_ llm: LLM) {
        self.setUpdate = { callback in
            llm.update = callback
        }
        self.respond = { prompt in
            await llm.respond(to: prompt)
        }
        self.stop = {
            llm.stop()
        }
    }

    init(
        setUpdate: @escaping (@escaping @Sendable (String?) -> Void) -> Void,
        respond: @escaping @MainActor (String) async -> Void,
        stop: @escaping @MainActor () -> Void
    ) {
        self.setUpdate = setUpdate
        self.respond = respond
        self.stop = stop
    }
}

/// Keeps the legacy LLM.swift 1.x callback at a Sendable boundary while all
/// mutable stream processing remains serialized on the app's main actor.
@MainActor
enum LocalLLMStreamingAdapter {
    static func consume(
        _ llm: LLM,
        prompt: String,
        onDelta: (String) -> Bool
    ) async {
        await consume(driver: LocalLLMStreamDriver(llm), prompt: prompt, onDelta: onDelta)
    }

    static func consume(
        driver: LocalLLMStreamDriver,
        prompt: String,
        onDelta: (String) -> Bool
    ) async {
        let (stream, continuation) = AsyncStream.makeStream(of: String.self)
        driver.setUpdate { @Sendable delta in
            if let delta {
                continuation.yield(delta)
            } else {
                continuation.finish()
            }
        }

        let generation = Task { @MainActor in
            await driver.respond(prompt)
            continuation.finish()
        }
        for await delta in stream where !onDelta(delta) {
            driver.stop()
            break
        }
        await generation.value
        driver.setUpdate { _ in }
    }
}
