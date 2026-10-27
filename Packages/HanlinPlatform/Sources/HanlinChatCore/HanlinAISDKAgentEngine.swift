import AISDKProvider
import AISDKProviderUtils
import Foundation
import SwiftAISDK

public actor HanlinAISDKAgentEngine {
    public typealias StepPreparation = @MainActor @Sendable (_ stepNumber: Int) async -> HanlinAISDKStepPreparation

    private let configuration: HanlinChatModelConfiguration
    private let resolvedProvider: HanlinAISDKResolvedProvider

    private final class StreamStopper: @unchecked Sendable {
        private let lock = NSLock()
        private var stopClosure: (@Sendable () -> Void)?
        private var isStopped = false

        func setStopper(_ closure: @escaping @Sendable () -> Void) {
            lock.lock()
            defer { lock.unlock() }
            if isStopped {
                closure()
            } else {
                stopClosure = closure
            }
        }

        func stop() {
            lock.lock()
            isStopped = true
            let closure = stopClosure
            stopClosure = nil
            lock.unlock()
            closure?()
        }
    }

    public init(
        configuration: HanlinChatModelConfiguration,
        fetch: FetchFunction? = nil
    ) throws {
        self.configuration = configuration
        self.resolvedProvider = try HanlinAISDKProviderFactory.resolve(
            configuration: configuration,
            fetch: fetch
        )
    }

    init(
        configuration: HanlinChatModelConfiguration,
        model: LanguageModel,
        descriptor: HanlinAISDKProviderDescriptor? = nil,
        providerOptions: ProviderOptions? = nil
    ) {
        self.configuration = configuration
        self.resolvedProvider = HanlinAISDKResolvedProvider(
            model: model,
            descriptor: descriptor ?? HanlinAISDKProviderFactory.descriptor(for: configuration),
            providerOptions: providerOptions
        )
    }

    public var providerDescriptor: HanlinAISDKProviderDescriptor {
        resolvedProvider.descriptor
    }

    public func stream(
        messages: [HanlinAISDKMessage],
        baseSystemPrompt: String?,
        tools definitions: [HanlinAISDKToolDefinition],
        maxSteps: Int? = nil,
        dynamicTools: (@MainActor @Sendable () async -> [HanlinAISDKToolDefinition])? = nil,
        prepareStep: @escaping @MainActor @Sendable () -> HanlinAISDKStepPreparation
    ) throws -> AsyncThrowingStream<HanlinAISDKStreamEvent, Error> {
        try stream(
            messages: messages,
            baseSystemPrompt: baseSystemPrompt,
            tools: definitions,
            maxSteps: maxSteps,
            dynamicTools: dynamicTools,
            prepareStep: { (_: Int) in prepareStep() }
        )
    }

    public func stream(
        messages: [HanlinAISDKMessage],
        baseSystemPrompt: String?,
        tools definitions: [HanlinAISDKToolDefinition],
        maxSteps: Int? = nil,
        dynamicTools: (@MainActor @Sendable () async -> [HanlinAISDKToolDefinition])? = nil,
        prepareStep: @escaping @MainActor @Sendable () async -> HanlinAISDKStepPreparation
    ) throws -> AsyncThrowingStream<HanlinAISDKStreamEvent, Error> {
        try stream(
            messages: messages,
            baseSystemPrompt: baseSystemPrompt,
            tools: definitions,
            maxSteps: maxSteps,
            dynamicTools: dynamicTools,
            prepareStep: { (_: Int) async in await prepareStep() }
        )
    }

    public func stream(
        messages: [HanlinAISDKMessage],
        baseSystemPrompt: String?,
        tools definitions: [HanlinAISDKToolDefinition],
        maxSteps: Int? = nil,
        dynamicTools: (@MainActor @Sendable () async -> [HanlinAISDKToolDefinition])? = nil,
        prepareStep: @escaping StepPreparation
    ) throws -> AsyncThrowingStream<HanlinAISDKStreamEvent, Error> {
        let modelMessages = try Self.modelMessages(from: messages)
        guard !modelMessages.isEmpty else {
            throw HanlinAISDKError.invalidConversation("At least one user or assistant message is required.")
        }
        let initialTools = try Self.makeTools(definitions)
        let settings = CallSettings(
            maxOutputTokens: configuration.maxTokens,
            temperature: configuration.temperature == HanlinChatGenerationDefaults.temperature
                ? nil : configuration.temperature,
            topP: configuration.topP == HanlinChatGenerationDefaults.topP ? nil : configuration.topP,
            maxRetries: 2
        )

        let limit = max(maxSteps ?? 40, 1)

        return AsyncThrowingStream { continuation in
            let stopper = StreamStopper()
            let task = Task {
                do {
                    continuation.yield(.runStarted)
                    var currentMessages = modelMessages
                    var currentDefinitions = definitions
                    var currentTools = initialTools
                    var stepOffset = 0

                    while true {
                        let remainingSteps = max(limit - stepOffset, 1)
                        let currentNames = Set(currentDefinitions.map(\.name))
                        var stopConditions: [StopCondition] = [stepCountIs(remainingSteps)]
                        if let dynamicTools {
                            stopConditions.append { _ in
                                let latest = await dynamicTools()
                                return Set(latest.map(\.name)) != currentNames
                            }
                        }

                        let offsetSnapshot = stepOffset
                        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
                            model: resolvedProvider.model,
                            system: baseSystemPrompt,
                            messages: currentMessages,
                            tools: currentTools,
                            providerOptions: resolvedProvider.providerOptions,
                            prepareStep: { options in
                                let globalStep = offsetSnapshot + options.stepNumber
                                let preparation = await prepareStep(globalStep)
                                continuation.yield(.stepStarted(index: globalStep, preparation: preparation))
                                return PrepareStepResult(
                                    activeTools: preparation.activeToolAliases,
                                    system: Self.systemPrompt(
                                        base: baseSystemPrompt,
                                        loadedInstructions: preparation.loadedSkillInstructions
                                    )
                                )
                            },
                            stopWhen: stopConditions,
                            settings: settings
                        )

                        stopper.setStopper {
                            result.stop()
                        }

                        var localStepIndex = -1
                        var meaningfulEventCount = 0
                        var shouldReloadToolsAndContinue = false

                        for try await part in result.fullStream {
                            try Task.checkCancellation()
                            switch part {
                            case .start:
                                break
                            case .startStep:
                                localStepIndex += 1
                                meaningfulEventCount = 0
                            case .textDelta(_, let text, _):
                                if !text.isEmpty {
                                    meaningfulEventCount += 1
                                    continuation.yield(.textDelta(text))
                                }
                            case .reasoningDelta(_, let text, _):
                                if !text.isEmpty {
                                    meaningfulEventCount += 1
                                    continuation.yield(.reasoningDelta(text))
                                }
                            case .toolInputStart(let id, let name, _, _, _, _):
                                meaningfulEventCount += 1
                                continuation.yield(.toolCallArgumentsStarted(id: id, name: name))
                            case .toolInputDelta(let id, let delta, _):
                                meaningfulEventCount += 1
                                continuation.yield(.toolCallArgumentsDelta(id: id, delta: delta))
                            case .toolCall(let call):
                                meaningfulEventCount += 1
                                continuation.yield(.toolCall(Self.toolCall(from: call)))
                            case .toolResult(let result):
                                meaningfulEventCount += 1
                                let projected = Self.toolResult(from: result)
                                continuation.yield(.toolResult(
                                    callID: result.toolCallId,
                                    name: result.toolName,
                                    modelText: projected.modelText,
                                    resultReference: projected.resultReference,
                                    isError: projected.isError
                                ))
                            case .finishStep(_, let usage, let reason, let rawReason, _):
                                let globalStep = offsetSnapshot + max(localStepIndex, 0)
                                continuation.yield(.stepFinished(
                                    index: globalStep,
                                    finishReason: rawReason ?? reason.rawValue,
                                    usage: Self.usage(from: usage),
                                    meaningfulEventCount: meaningfulEventCount
                                ))
                            case .finish(let reason, let rawReason, let usage):
                                let nextOffset = offsetSnapshot + max(localStepIndex + 1, 1)
                                if reason == .toolCalls,
                                   nextOffset < limit,
                                   let dynamicTools {
                                    let latestDefinitions = await dynamicTools()
                                    if Set(latestDefinitions.map(\.name)) != currentNames {
                                        let completedSteps = try await result.steps
                                        for step in completedSteps {
                                            for msg in step.response.messages {
                                                switch msg {
                                                case .assistant(let assistantMsg):
                                                    currentMessages.append(.assistant(assistantMsg))
                                                case .tool(let toolMsg):
                                                    currentMessages.append(.tool(toolMsg))
                                                }
                                            }
                                        }
                                        currentDefinitions = latestDefinitions
                                        currentTools = try Self.makeTools(latestDefinitions)
                                        stepOffset = nextOffset
                                        shouldReloadToolsAndContinue = true
                                        break
                                    }
                                }
                                continuation.yield(.finished(
                                    reason: rawReason ?? reason.rawValue,
                                    usage: Self.usage(from: usage)
                                ))
                                continuation.finish()
                                return
                            case .abort:
                                continuation.yield(.cancelled)
                                continuation.finish()
                                return
                            case .error(let error):
                                throw error
                            case .toolError(let error):
                                meaningfulEventCount += 1
                                continuation.yield(.toolResult(
                                    callID: error.toolCallId,
                                    name: error.toolName,
                                    modelText: AISDKProvider.getErrorMessage(error.error),
                                    resultReference: nil,
                                    isError: true
                                ))
                            case .source(let source):
                                if case .url(let id, let url, let title, _) = source {
                                    meaningfulEventCount += 1
                                    continuation.yield(.source(id: id, url: url, title: title))
                                }
                            case .file(let file):
                                if let data = Data(base64Encoded: file.base64) {
                                    meaningfulEventCount += 1
                                    continuation.yield(.file(mediaType: file.mediaType, data: data))
                                }
                            case .reasoningFile(let file, _):
                                if let data = Data(base64Encoded: file.base64) {
                                    meaningfulEventCount += 1
                                    continuation.yield(.file(mediaType: file.mediaType, data: data))
                                }
                            case .toolApprovalRequest(let request):
                                meaningfulEventCount += 1
                                continuation.yield(.toolApprovalRequest(
                                    approvalID: request.approvalId,
                                    toolCallID: request.toolCall.toolCallId,
                                    toolName: request.toolCall.toolName
                                ))
                            case .toolOutputDenied(let denied):
                                meaningfulEventCount += 1
                                continuation.yield(.toolOutputDenied(
                                    toolCallID: denied.toolCallId,
                                    toolName: denied.toolName
                                ))
                            case .textStart, .textEnd, .reasoningStart, .reasoningEnd,
                                 .toolInputEnd, .custom, .raw:
                                break
                            }
                        }

                        if !shouldReloadToolsAndContinue {
                            continuation.finish()
                            return
                        }
                    }
                } catch is CancellationError {
                    continuation.yield(.cancelled)
                    continuation.finish(throwing: HanlinChatError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
                stopper.stop()
            }
        }
    }

    private static func makeTools(
        _ definitions: [HanlinAISDKToolDefinition]
    ) throws -> ToolSet {
        try Dictionary(uniqueKeysWithValues: definitions.map { definition in
            let schema: JSONValue
            do {
                schema = try JSONDecoder().decode(JSONValue.self, from: definition.inputSchemaData)
            } catch {
                throw HanlinAISDKError.invalidToolSchema(name: definition.name)
            }
            let rawSchema = Schema<JSONValue>(
                jsonSchemaResolver: { schema },
                validator: { value in
                    do {
                        let converted = try jsonValue(from: value)
                        return .success(value: converted)
                    } catch {
                        return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                    }
                }
            )
            let sdkTool = Tool(
                description: definition.description,
                inputSchema: FlexibleSchema(rawSchema),
                execute: { input, options in
                    let arguments = try jsonString(input)
                    let output = try await definition.execute(arguments, options.toolCallId)
                    return .value(.object([
                        "modelText": .string(output.modelText),
                        "resultReference": output.resultReference.map(JSONValue.string) ?? .null,
                        "isError": .bool(output.isError)
                    ]))
                },
                toModelOutput: { output in
                    let projected = toolResult(from: output)
                    if projected.isError {
                        return .errorText(value: projected.modelText)
                    }
                    return .text(value: projected.modelText)
                }
            )
            return (definition.name, sdkTool)
        })
    }

    private static func systemPrompt(base: String?, loadedInstructions: [String]) -> String? {
        let parts = ([base].compactMap { $0 } + loadedInstructions.map { "### Active Skill Instructions\n\($0)" })
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    private static func modelMessages(from messages: [HanlinAISDKMessage]) throws -> [ModelMessage] {
        messages.compactMap { message in
            switch message.role {
            case .system:
                return nil
            case .assistant:
                let text = message.parts.compactMap { part -> String? in
                    if case .text(let value) = part { return value }
                    return nil
                }.joined(separator: "\n")
                return .assistant(AssistantModelMessage(content: .text(text)))
            case .user:
                if message.parts.count == 1, case .text(let text) = message.parts[0] {
                    return .user(UserModelMessage(content: .text(text)))
                }
                let parts = message.parts.compactMap { part -> UserContentPart? in
                    switch part {
                    case .text(let text):
                        return .text(TextPart(text: text))
                    case .imageURL(let url, let mediaType):
                        return .image(ImagePart(image: .url(url), mediaType: mediaType))
                    case .imageData(let data, let mediaType):
                        return .image(ImagePart(image: .data(data), mediaType: mediaType))
                    }
                }
                return .user(UserModelMessage(content: .parts(parts)))
            }
        }
    }

    private static func toolCall(from call: TypedToolCall) -> HanlinAISDKToolCall {
        HanlinAISDKToolCall(
            id: call.toolCallId,
            name: call.toolName,
            argumentsJSON: (try? jsonString(call.input)) ?? "{}"
        )
    }

    private static func toolResult(from result: TypedToolResult) -> HanlinAISDKToolExecutionOutput {
        toolResult(from: result.output)
    }

    private static func toolResult(from value: JSONValue) -> HanlinAISDKToolExecutionOutput {
        guard case .object(let object) = value else {
            return HanlinAISDKToolExecutionOutput(modelText: (try? jsonString(value)) ?? String(describing: value))
        }
        let modelText: String
        if case .string(let value) = object["modelText"] { modelText = value } else { modelText = "" }
        let reference: String?
        if case .string(let value) = object["resultReference"] { reference = value } else { reference = nil }
        let isError: Bool
        if case .bool(let value) = object["isError"] { isError = value } else { isError = false }
        return HanlinAISDKToolExecutionOutput(modelText: modelText, resultReference: reference, isError: isError)
    }

    private static func usage(from usage: LanguageModelUsage) -> HanlinChatTokenUsage {
        HanlinChatTokenUsage(
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
            reasoningTokens: usage.outputTokenDetails.reasoningTokens,
            cachedInputTokens: usage.inputTokenDetails.cacheReadTokens,
            totalTokens: usage.totalTokens
        )
    }
}

private func jsonString(_ value: JSONValue) throws -> String {
    let data = try JSONEncoder().encode(value)
    return String(decoding: data, as: UTF8.self)
}

private extension TypedToolError {
    var error: Error {
        switch self {
        case .static(let value): value.error
        case .dynamic(let value): value.error
        }
    }
}
