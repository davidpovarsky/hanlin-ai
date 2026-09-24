import AISDKProvider
import AISDKProviderUtils
import Foundation
import SwiftAISDK

public actor HanlinAISDKAgentEngine {
    public typealias StepPreparation = @MainActor @Sendable () -> HanlinAISDKStepPreparation

    private let configuration: HanlinChatModelConfiguration
    private let resolvedProvider: HanlinAISDKResolvedProvider

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
        prepareStep: @escaping StepPreparation
    ) throws -> AsyncThrowingStream<HanlinAISDKStreamEvent, Error> {
        let modelMessages = try Self.modelMessages(from: messages)
        guard !modelMessages.isEmpty else {
            throw HanlinAISDKError.invalidConversation("At least one user or assistant message is required.")
        }
        let tools = try Self.makeTools(definitions)
        let settings = CallSettings(
            maxOutputTokens: configuration.maxTokens,
            temperature: configuration.temperature == HanlinChatGenerationDefaults.temperature
                ? nil : configuration.temperature,
            topP: configuration.topP == HanlinChatGenerationDefaults.topP ? nil : configuration.topP,
            maxRetries: 2
        )

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(.runStarted)
                    let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
                        model: resolvedProvider.model,
                        system: baseSystemPrompt,
                        messages: modelMessages,
                        tools: tools,
                        providerOptions: resolvedProvider.providerOptions,
                        prepareStep: { options in
                            let preparation = await prepareStep()
                            continuation.yield(.stepStarted(index: options.stepNumber, preparation: preparation))
                            return PrepareStepResult(
                                activeTools: preparation.activeToolAliases,
                                system: Self.systemPrompt(
                                    base: baseSystemPrompt,
                                    loadedInstructions: preparation.loadedSkillInstructions
                                )
                            )
                        },
                        stopWhen: [stepCountIs(32)],
                        settings: settings
                    )

                    var stepIndex = -1
                    var meaningfulEventCount = 0
                    for try await part in result.fullStream {
                        try Task.checkCancellation()
                        switch part {
                        case .start:
                            break
                        case .startStep:
                            stepIndex += 1
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
                                resultReference: projected.resultReference
                            ))
                        case .finishStep(_, let usage, let reason, let rawReason, _):
                            continuation.yield(.stepFinished(
                                index: max(stepIndex, 0),
                                finishReason: rawReason ?? reason.rawValue,
                                usage: Self.usage(from: usage),
                                meaningfulEventCount: meaningfulEventCount
                            ))
                        case .finish(let reason, let rawReason, let usage):
                            continuation.yield(.finished(
                                reason: rawReason ?? reason.rawValue,
                                usage: Self.usage(from: usage)
                            ))
                        case .abort:
                            continuation.yield(.cancelled)
                        case .error(let error):
                            throw error
                        case .toolError(let error):
                            throw error.error
                        case .textStart, .textEnd, .reasoningStart, .reasoningEnd,
                             .toolInputEnd, .toolOutputDenied, .toolApprovalRequest,
                             .source, .custom, .file, .reasoningFile, .raw:
                            break
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.yield(.cancelled)
                    continuation.finish(throwing: HanlinChatError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
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
            let sdkTool = Tool(
                description: definition.description,
                inputSchema: FlexibleSchema(jsonSchema(schema)),
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
