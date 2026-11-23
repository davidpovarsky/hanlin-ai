#if canImport(FoundationModels)
import AISDKProvider
import Foundation
import FoundationModels

/// A single native provider step. The existing Hanlin/SwiftAISDK loop owns approval,
/// execution, persistence and the next step. No HostIntegration closure exists here.
/// This candidate is internal and is not selected by the shipping provider factory.
@available(iOS 27.0, macOS 27.0, *)
enum HanlinAppleToolSessionBridge {
    static func stream<Model: FoundationModels.LanguageModel>(
        options: LanguageModelV3CallOptions, model: Model
    ) async throws -> LanguageModelV3StreamResult {
        try Task.checkCancellation()
        if options.abortSignal?() == true { throw CancellationError() }
        guard options.topP == nil, options.topK == nil, options.presencePenalty == nil,
              options.frequencyPenalty == nil, options.seed == nil, options.stopSequences?.isEmpty != false,
              options.responseFormat == nil || options.responseFormat == .text,
              options.providerOptions?.isEmpty != false, options.includeRawChunks != true,
              // The original producer adds User-Agent transport metadata. It is never
              // forwarded to native instructions/history; other headers remain unsupported.
              options.headers?.keys.allSatisfy({ $0.lowercased() == "user-agent" }) != false
              else { throw HanlinAppleProviderError.unsupportedSettings }
        let history = try HanlinAppleToolHistory(options.prompt)
        var names: Set<String> = []
        var tools: [HandoffTool] = []
        guard (options.tools?.count ?? 0) <= 64 else { throw HanlinAppleToolBridgeError.unsupportedSchema }
        for tool in options.tools ?? [] {
            guard case .function(let function) = tool,
                  HanlinAppleToolHistory.validIdentity(function.name),
                  names.insert(function.name).inserted,
                  function.providerOptions?.isEmpty != false,
                  function.inputExamples?.isEmpty != false else {
                throw HanlinAppleToolBridgeError.unsupportedSchema
            }
            let schema = try HanlinAppleToolSchema(function.inputSchema)
            tools.append(.init(name: function.name, description: function.description ?? "",
                parameters: try schema.nativeSchema(name: "HanlinArguments\(tools.count)"), admittedSchema: schema))
        }
        let mode: GenerationOptions.ToolCallingMode
        switch options.toolChoice ?? .auto {
        case .auto: mode = tools.isEmpty ? .disallowed : .allowed
        case .none: mode = .disallowed
        case .required:
            guard !tools.isEmpty else { throw HanlinAppleProviderError.unsupportedTools }
            mode = .required
        case .tool(let name):
            guard let tool = tools.first(where: { $0.name == name }) else { throw HanlinAppleProviderError.unsupportedTools }
            tools = [tool]
            mode = .required
        }
        let admittedTools = tools
        let generation = GenerationOptions(temperature: options.temperature, maximumResponseTokens: options.maxOutputTokens)
        return .init(stream: AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if let abort = options.abortSignal {
                        try await withThrowingTaskGroup(of: Void.self) { group in
                            group.addTask {
                                try await run(model: model, history: history, tools: admittedTools,
                                              mode: mode, generation: generation, continuation: continuation)
                            }
                            group.addTask {
                                while true {
                                    try Task.checkCancellation()
                                    if abort() { throw CancellationError() }
                                    try await Task.sleep(for: .milliseconds(100))
                                }
                            }
                            defer { group.cancelAll() }
                            _ = try await group.next()
                        }
                    } else {
                        try await run(model: model, history: history, tools: admittedTools,
                                      mode: mode, generation: generation, continuation: continuation)
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        })
    }

    private static func run<Model: FoundationModels.LanguageModel>(
        model: Model, history: HanlinAppleToolHistory, tools: [HandoffTool],
        mode: GenerationOptions.ToolCallingMode, generation: GenerationOptions,
        continuation: AsyncThrowingStream<LanguageModelV3StreamPart, Error>.Continuation
    ) async throws {
        let state = HandoffState()
        let profile = NativeProfile(model: model, history: history, tools: tools, state: state)
            .toolCallingMode(mode)
            .transcriptErrorHandlingPolicy(.preserveTranscript)
        let session = LanguageModelSession(profile: profile, history: history.entries)
        let textID = UUID().uuidString
        var deltas = HanlinAppleTextDelta()
        continuation.yield(.streamStart(warnings: []))
        continuation.yield(.textStart(id: textID, providerMetadata: nil))
        do {
            // A framework-required empty trigger is removed by onPrompt before model invocation.
            // historyTransform independently supplies only the validated canonical history.
            // Neither this transient native transcript nor the trigger is persisted in Hanlin.
            for try await snapshot in session.streamResponse(to: Prompt(""), options: generation) {
                try Task.checkCancellation()
                let delta = try deltas.append(snapshot: snapshot.content)
                if !delta.isEmpty { continuation.yield(.textDelta(id: textID, delta: delta, providerMetadata: nil)) }
            }
            try Task.checkCancellation()
            guard await state.triggerWasRemoved, await state.batch == nil else {
                throw HanlinAppleToolBridgeError.invalidHandoff
            }
            continuation.yield(.textEnd(id: textID, providerMetadata: nil))
            continuation.yield(.finish(finishReason: .init(unified: .stop),
                usage: .init(inputTokens: .init(total: nil), outputTokens: .init(total: nil)), providerMetadata: nil))
        } catch {
            try Task.checkCancellation()
            guard isHandoff(error), let batch = await state.batch, mode != .disallowed else { throw error }
            let delta = try deltas.append(snapshot: batch.text)
            if !delta.isEmpty { continuation.yield(.textDelta(id: textID, delta: delta, providerMetadata: nil)) }
            continuation.yield(.textEnd(id: textID, providerMetadata: nil))
            // Every sibling is validated before any call is emitted to the canonical executor.
            for call in batch.calls { continuation.yield(.toolCall(call)) }
            continuation.yield(.finish(finishReason: .init(unified: .toolCalls),
                usage: .init(inputTokens: .init(total: nil), outputTokens: .init(total: nil)), providerMetadata: nil))
        }
    }

    private static func isHandoff(_ error: any Error) -> Bool {
        if error is Handoff { return true }
        if let wrapped = error as? LanguageModelSession.ToolCallError { return wrapped.underlyingError is Handoff }
        return false
    }

    private enum Handoff: Error { case requested }

    /// Public Tool conformance supplies a schema only. Its body cannot perform a host effect.
    private struct HandoffTool: FoundationModels.Tool {
        typealias Arguments = GeneratedContent
        let name: String
        let description: String
        let parameters: GenerationSchema
        let admittedSchema: HanlinAppleToolSchema
        @concurrent func call(arguments: GeneratedContent) async throws -> String {
            throw HanlinAppleToolBridgeError.unexpectedToolExecution
        }
    }

    private struct NativeInstructions: DynamicInstructions {
        let instructions: String?
        let tools: [HandoffTool]
        var body: some DynamicInstructions {
            if let instructions { Instructions(instructions) }
            ForEach(tools, id: \.name) { tool in tool }
        }
    }

    private struct NativeProfile<Model: FoundationModels.LanguageModel>: LanguageModelSession.DynamicProfile {
        @LanguageModelSession.SessionProperty(\.history) private var nativeHistory
        let model: Model
        let canonical: HanlinAppleToolHistory
        let tools: [HandoffTool]
        let state: HandoffState

        init(model: Model, history: HanlinAppleToolHistory, tools: [HandoffTool], state: HandoffState) {
            self.model = model; canonical = history; self.tools = tools; self.state = state
        }

        var body: some LanguageModelSession.DynamicProfile {
            LanguageModelSession.Profile {
                NativeInstructions(instructions: canonical.instructions, tools: tools)
            }
            .model(model)
            .onPrompt { prompt in
                let entries = Array(nativeHistory)
                guard entries.last == .prompt(prompt), Array(entries.dropLast()) == canonical.entries,
                      prompt.segments.allSatisfy({ segment in
                          if case .text(let text) = segment { return text.content.isEmpty }
                          return false
                      }) else { throw HanlinAppleToolBridgeError.invalidHistory }
                nativeHistory.removeLast()
                try await state.removedTrigger()
            }
            .historyTransform { _ in canonical.entries }
            .onToolCall { call in
                try Task.checkCancellation()
                try await state.intercept(call, history: Array(nativeHistory), canonical: canonical, tools: tools)
            }
        }
    }

    private struct Batch: Sendable {
        let text: String
        let calls: [LanguageModelV3ToolCall]
    }

    private actor HandoffState {
        private(set) var triggerWasRemoved = false
        private(set) var batch: Batch?

        func removedTrigger() throws {
            guard !triggerWasRemoved else { throw HanlinAppleToolBridgeError.invalidHistory }
            triggerWasRemoved = true
        }

        func intercept(_ callback: Transcript.ToolCall, history: [Transcript.Entry],
                       canonical: HanlinAppleToolHistory, tools: [HandoffTool]) throws {
            guard triggerWasRemoved, history.count > canonical.entries.count,
                  Array(history.prefix(canonical.entries.count)) == canonical.entries else {
                throw HanlinAppleToolBridgeError.invalidHandoff
            }
            let generated = Array(history.dropFirst(canonical.entries.count))
            guard case .toolCalls(let nativeCalls) = generated.last,
                  !nativeCalls.isEmpty, nativeCalls.count <= 64,
                  nativeCalls.contains(callback) else { throw HanlinAppleToolBridgeError.invalidHandoff }
            var text = ""
            for entry in generated.dropLast() {
                guard case .response(let response) = entry else { throw HanlinAppleToolBridgeError.invalidHandoff }
                for segment in response.segments {
                    guard case .text(let value) = segment else { throw HanlinAppleToolBridgeError.invalidHandoff }
                    text += value.content
                }
            }
            var seen = canonical.callIDs
            let calls = try nativeCalls.map { call -> LanguageModelV3ToolCall in
                guard HanlinAppleToolHistory.validIdentity(call.id), seen.insert(call.id).inserted,
                      call.metadata.isEmpty,
                      let tool = tools.first(where: { $0.name == call.toolName }) else {
                    throw HanlinAppleToolBridgeError.invalidHandoff
                }
                var remaining = 4_096
                let value = try HanlinAppleToolHistory.generatedValue(call.arguments, remaining: &remaining)
                try tool.admittedSchema.validate(arguments: value)
                let normalized = try HanlinAppleToolHistory.normalizedJSON(value)
                // The trusted appleOnDevice engine boundary keeps this normalized even when
                // the producer preserves this JSON String as its own parsed rawInput.
                return .init(toolCallId: call.id, toolName: call.toolName, input: normalized, providerExecuted: false)
            }
            if let batch {
                guard batch.text == text, batch.calls == calls else { throw HanlinAppleToolBridgeError.invalidHandoff }
            } else { batch = .init(text: text, calls: calls) }
            throw Handoff.requested
        }
    }
}
#endif
