import AISDKProvider
import AISDKProviderUtils
import Foundation
import HanlinPlatformContracts
import SwiftAISDK

public actor HanlinAISDKAgentEngine {
    public typealias ApprovalHandler = @MainActor @Sendable (HanlinAISDKToolApprovalRequest) async throws -> Bool
    public typealias StepPreparation = @MainActor @Sendable (_ stepNumber: Int) async -> HanlinAISDKStepPreparation

    private let configuration: HanlinChatModelConfiguration
    private let telemetry: TelemetrySettings?
    private let resolvedProvider: HanlinAISDKResolvedProvider
    private let resolvesProviderFromConfiguration: Bool

    private final class StreamStopper: @unchecked Sendable {
        private let lock = NSLock()
        private var stopClosure: (@Sendable () -> Void)?
        private var isStopped = false

        var isCancellationRequested: Bool {
            lock.lock()
            defer { lock.unlock() }
            return isStopped
        }

        func setStopper(_ closure: @escaping @Sendable () -> Void) {
            lock.lock()
            let alreadyStopped = isStopped
            if !alreadyStopped {
                stopClosure = closure
            }
            lock.unlock()
            if alreadyStopped {
                closure()
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

    // The stop predicate and the final stream event inspect the live catalog at
    // different times. A transient catalog change must remain a reload decision
    // even when the original tools are available again before finalization.
    private actor ToolReloadDecision {
        private(set) var wasRequested = false

        func observe(_ changed: Bool) -> Bool {
            wasRequested = wasRequested || changed
            return changed
        }
    }

    public init(
        configuration: HanlinChatModelConfiguration,
        fetch: FetchFunction? = nil,
        telemetry: TelemetrySettings? = nil
    ) throws {
        self.configuration = configuration
        self.telemetry = telemetry
        self.resolvesProviderFromConfiguration = true
        self.resolvedProvider = try HanlinAISDKProviderFactory.resolve(
            configuration: configuration,
            fetch: fetch ?? HanlinAISDKProviderFactory.makeFetch(sessionConfiguration: .ephemeral)
        )
    }

    /// Injects a provider into the same production agent loop (including tool and cancellation handling).
    public init(
        configuration: HanlinChatModelConfiguration,
        model: LanguageModel,
        descriptor: HanlinAISDKProviderDescriptor? = nil,
        providerOptions: ProviderOptions? = nil,
        telemetry: TelemetrySettings? = nil
    ) {
        self.configuration = configuration
        self.telemetry = telemetry
        self.resolvesProviderFromConfiguration = false
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
        structuredResponse: HanlinNativeStructuredResponse? = nil,
        responseSchema: Data? = nil,
        requestApproval: ApprovalHandler? = nil,
        cacheScope: HanlinPromptCacheScope? = nil,
        transport: HanlinAISDKTurnTransport? = nil,
        prepareStep: @escaping @MainActor @Sendable () -> HanlinAISDKStepPreparation
    ) throws -> AsyncThrowingStream<HanlinAISDKStreamEvent, Error> {
        try stream(
            messages: messages,
            baseSystemPrompt: baseSystemPrompt,
            tools: definitions,
            maxSteps: maxSteps,
            dynamicTools: dynamicTools,
            structuredResponse: structuredResponse,
            responseSchema: responseSchema,
            requestApproval: requestApproval,
            cacheScope: cacheScope,
            transport: transport,
            prepareStep: { (_: Int) in prepareStep() }
        )
    }

    public func stream(
        messages: [HanlinAISDKMessage],
        baseSystemPrompt: String?,
        tools definitions: [HanlinAISDKToolDefinition],
        maxSteps: Int? = nil,
        dynamicTools: (@MainActor @Sendable () async -> [HanlinAISDKToolDefinition])? = nil,
        structuredResponse: HanlinNativeStructuredResponse? = nil,
        responseSchema: Data? = nil,
        requestApproval: ApprovalHandler? = nil,
        cacheScope: HanlinPromptCacheScope? = nil,
        transport: HanlinAISDKTurnTransport? = nil,
        prepareStep: @escaping @MainActor @Sendable () async -> HanlinAISDKStepPreparation
    ) throws -> AsyncThrowingStream<HanlinAISDKStreamEvent, Error> {
        try stream(
            messages: messages,
            baseSystemPrompt: baseSystemPrompt,
            tools: definitions,
            maxSteps: maxSteps,
            dynamicTools: dynamicTools,
            structuredResponse: structuredResponse,
            responseSchema: responseSchema,
            requestApproval: requestApproval,
            cacheScope: cacheScope,
            transport: transport,
            prepareStep: { (_: Int) async in await prepareStep() }
        )
    }

    public func stream(
        messages: [HanlinAISDKMessage],
        baseSystemPrompt: String?,
        tools definitions: [HanlinAISDKToolDefinition],
        maxSteps: Int? = nil,
        dynamicTools: (@MainActor @Sendable () async -> [HanlinAISDKToolDefinition])? = nil,
        structuredResponse: HanlinNativeStructuredResponse? = nil,
        responseSchema: Data? = nil,
        requestApproval: ApprovalHandler? = nil,
        cacheScope: HanlinPromptCacheScope? = nil,
        transport: HanlinAISDKTurnTransport? = nil,
        runControl: HanlinAISDKRunControl? = nil,
        prepareStep: @escaping StepPreparation
    ) throws -> AsyncThrowingStream<HanlinAISDKStreamEvent, Error> {
        // The engine/agent loop remains shared. A host-supplied transport belongs
        // only to this turn; old streams keep their original immutable callbacks.
        // An injected model owns its transport and must never be replaced by a
        // network provider because a caller supplied per-turn transport options.
        guard transport == nil || resolvesProviderFromConfiguration else {
            throw HanlinAISDKError.invalidConversation("An injected provider owns its transport.")
        }
        let resolvedProvider = try transport.map {
            try HanlinAISDKProviderFactory.resolve(configuration: configuration, fetch: $0.fetch)
        } ?? self.resolvedProvider
        guard structuredResponse == nil || responseSchema == nil else {
            throw HanlinChatError.invalidRequest("Select one structured response contract.")
        }
        let outputSpecification = try structuredResponse?.specification()
            ?? responseSchema.map { try HanlinAISDKJSONOutput.specification(schemaData: $0) }
        let turnProviderOptions = try resolvesProviderFromConfiguration
            ? HanlinAISDKProviderFactory.providerOptions(
                configuration: configuration, kind: resolvedProvider.descriptor.kind,
                cacheScope: cacheScope, validateExplicitReference: true
            ) : resolvedProvider.providerOptions
        try HanlinAISDKProviderFactory.validateCachedContentContext(
            configuration: configuration, kind: resolvedProvider.descriptor.kind,
            hasSystemInstructions: !(baseSystemPrompt ?? "").isEmpty
                || messages.contains { message in
                    message.role == .system && message.parts.contains { part in
                        if case .text(let text) = part { return !text.isEmpty }
                        return false
                    }
                },
            hasTools: !definitions.isEmpty || dynamicTools != nil
        )
        let breakpointOptions = resolvesProviderFromConfiguration
            ? HanlinAISDKProviderFactory.cacheBreakpointOptions(
                configuration: configuration, kind: resolvedProvider.descriptor.kind
            ) : nil
        let telemetry = self.telemetry
        let cacheConfiguration = configuration
        if structuredResponse != nil, !HanlinNativeStructuredResponse.supports(resolvedProvider.descriptor) {
            throw HanlinNativeStructuredResponseError.unsupportedProviderOrModel
        }
        // Native unsupported content must fail before SwiftAISDK prompt conversion can download
        // an image URL. This guard never selects a cloud provider or includes private payloads.
        if resolvedProvider.descriptor.kind == .appleOnDevice {
            guard messages.allSatisfy({ message in
                message.parts.allSatisfy { part in if case .text = part { return true }; return false }
            }) else { throw HanlinAISDKError.nativeUnsupportedContent }
        }
        var modelMessages = try Self.modelMessages(
            from: messages, includeSystemMessages: baseSystemPrompt == nil,
            breakpointOptions: breakpointOptions
        )
        // A legacy base prompt is still authoritative, but a cacheable prefix
        // must be a message block: top-level OpenAI instructions cannot carry
        // breakpoints, and loaded skills must not change the stable block.
        let systemPromptForSDK = breakpointOptions == nil ? baseSystemPrompt : nil
        if let baseSystemPrompt, !baseSystemPrompt.isEmpty, let breakpointOptions {
            modelMessages.insert(.system(SystemModelMessage(
                content: baseSystemPrompt, providerOptions: breakpointOptions
            )), at: 0)
        }
        guard modelMessages.contains(where: { message in
            if case .system = message { return false }
            return true
        }) else {
            throw HanlinAISDKError.invalidConversation("At least one user or assistant message is required.")
        }
        // Plan credentials use the dedicated stateless Responses transport.
        // Ordinary API Responses retains its own inference settings.
        let usesChatGPTPlan = configuration.apiType?.lowercased() == "openai-chatgpt-plan"
        let initialTools = try Self.makeTools(definitions, providerKind: resolvedProvider.descriptor.kind)
        let settings = CallSettings(
            maxOutputTokens: usesChatGPTPlan ? nil : configuration.maxTokens,
            temperature: usesChatGPTPlan ? nil :
                (configuration.temperature == HanlinChatGenerationDefaults.temperature
                    ? nil : configuration.temperature),
            topP: usesChatGPTPlan ? nil :
                (configuration.topP == HanlinChatGenerationDefaults.topP
                    ? nil : configuration.topP),
            maxRetries: usesChatGPTPlan ? 0 : 2
        )

        // nil means run until the model completes, the user cancels or a real error occurs.
        // An explicitly configured budget remains supported and visible to the caller.
        let limit = maxSteps.map { max($0, 1) }

        return AsyncThrowingStream { continuation in
            let stopper = StreamStopper()
            let cancellation = HanlinChatTransportCancellation()
            let streamSettings: CallSettings = {
                guard resolvedProvider.descriptor.kind == .appleOnDevice else { return settings }
                var nativeSettings = settings
                // Producer stop() waits for a pending provider to finish. Give the native
                // bridge this stream's existing stop state so it can cancel that request.
                nativeSettings.abortSignal = { stopper.isCancellationRequested }
                return nativeSettings
            }()
            let task = HanlinChatTransportCancellation.$current.withValue(cancellation) { Task {
                do {
                    continuation.yield(.runStarted)
                    if let structuredResponse {
                        continuation.yield(.structuredResponseStarted(messageID: structuredResponse.messageID,
                            channel: HanlinChatStructuredPart.channel))
                    }
                    var accumulatedUsage = LanguageModelUsage()
                    var currentMessages = modelMessages
                    var currentDefinitions = definitions
                    var currentTools = initialTools
                    var stepOffset = 0
                    var finalVisibleCharacters = 0
                    var hasSuccessfulToolAction = false
                    var structuredParts = HanlinChatStructuredPartSequence()
                    var hasStructuredContent = false
                    var hasDeniedToolAction = false
                    var seenApprovalIDs = Set<String>()
                    var seenApprovalCallIDs = Set<String>()

                    while true {
                        // A final catalog lookup may suspend after the last stream event.
                        // Observe cancellation before constructing another provider task.
                        try Task.checkCancellation()
                        let currentNames = Set(currentDefinitions.map(\.name))
                        let toolReload = ToolReloadDecision()
                        // The pinned SDK replaces an empty list with stepCountIs(1).
                        // An explicit never-stop condition preserves the nil-budget contract.
                        var stopConditions: [StopCondition] = [{ _ in false }]
                        if resolvedProvider.descriptor.kind == .appleOnDevice {
                            // The producer counts invalid-tool errors as completed outputs
                            // and may advance before the outer stream consumes the error.
                            // Stop at its own step boundary so unsupported native numbers
                            // cannot start another provider request, including approval tools.
                            stopConditions.append { steps in
                                guard let lastStep = steps.last else { return false }
                                return lastStep.toolCalls.contains { call in
                                    do {
                                        try Self.validateNativeToolInput(call.input, providerKind: .appleOnDevice)
                                        return false
                                    } catch {
                                        return true
                                    }
                                }
                            }
                        }
                        if let limit {
                            stopConditions.append(stepCountIs(max(limit - stepOffset, 1)))
                        }
                        if let dynamicTools {
                            stopConditions.append { _ in
                                let latest = await dynamicTools()
                                return await toolReload.observe(Set(latest.map(\.name)) != currentNames)
                            }
                        }

                        let offsetSnapshot = stepOffset
                        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
                            model: resolvedProvider.model,
                            system: systemPromptForSDK,
                            messages: currentMessages,
                            tools: currentTools,
                            providerOptions: turnProviderOptions,
                            experimentalOutput: outputSpecification,
                            experimentalTelemetry: telemetry,
                            prepareStep: { options in
                                let globalStep = offsetSnapshot + options.stepNumber
                                let preparation = await prepareStep(globalStep)
                                try HanlinAISDKProviderFactory.validateCachedContentContext(
                                    configuration: cacheConfiguration, kind: resolvedProvider.descriptor.kind,
                                    hasSystemInstructions: preparation.loadedSkillInstructions.contains {
                                        !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    }, hasTools: false
                                )
                                continuation.yield(.stepStarted(index: globalStep, preparation: preparation))
                                return PrepareStepResult(
                                    activeTools: preparation.activeToolAliases,
                                    system: systemPromptForSDK.map {
                                        Self.systemPrompt(base: $0, loadedInstructions: preparation.loadedSkillInstructions) ?? $0
                                    },
                                    messages: systemPromptForSDK == nil
                                        ? Self.messagesWithSkillInstructions(
                                            options.messages, instructions: preparation.loadedSkillInstructions
                                        ) : nil
                                )
                            },
                            stopWhen: stopConditions,
                            settings: streamSettings
                        )

                        stopper.setStopper {
                            result.stop()
                        }

                        var localStepIndex = -1
                        var meaningfulEventCount = 0
                        var shouldReloadToolsAndContinue = false
                        var completeResponseText = ""
                        var citationTextParts: [String: String] = [:]
                        var oversizedCitationParts: Set<String> = []
                        var approvalResponses: [ToolContentPart] = []

                        for try await part in result.fullStream {
                            try Task.checkCancellation()
                            switch part {
                            case .start:
                                break
                            case .startStep:
                                localStepIndex += 1
                                meaningfulEventCount = 0
                                finalVisibleCharacters = 0
                                completeResponseText = ""
                                citationTextParts.removeAll(); oversizedCitationParts.removeAll()
                            case .textDelta(let partID, let text, _):
                                if structuredResponse != nil {
                                    guard text.utf8.count <= 1_048_576 - completeResponseText.utf8.count else {
                                        throw HanlinNativeStructuredResponseError.outputLimitExceeded
                                    }
                                    completeResponseText += text
                                    break
                                }
                                finalVisibleCharacters += text.trimmingCharacters(in: .whitespacesAndNewlines).count
                                if !text.isEmpty {
                                    if !oversizedCitationParts.contains(partID) {
                                        if text.utf8.count <= 1_048_576 - (citationTextParts[partID]?.utf8.count ?? 0) {
                                            citationTextParts[partID, default: ""] += text
                                        } else { citationTextParts.removeValue(forKey: partID); oversizedCitationParts.insert(partID) }
                                    }
                                    meaningfulEventCount += 1
                                    continuation.yield(.textDelta(text))
                                }
                            case .textEnd(let partID, let metadata):
                                guard structuredResponse == nil,
                                      self.resolvedProvider.descriptor.kind == .openAIResponses,
                                      let text = citationTextParts.removeValue(forKey: partID),
                                      case .array(let annotations) = metadata?["openai"]?["annotations"] else { break }
                                let citations = annotations.prefix(256).compactMap { annotation -> HanlinAISDKTextCitation? in
                                    guard case .object(let fields) = annotation,
                                          fields["type"] == .string("url_citation"),
                                          case .number(let start) = fields["start_index"],
                                          case .number(let end) = fields["end_index"],
                                          start.isFinite, end.isFinite, start.rounded() == start, end.rounded() == end,
                                          start >= 0, end > start, end <= Double(text.unicodeScalars.count),
                                          case .string(let url) = fields["url"],
                                          let parsed = URL(string: url), ["https", "http"].contains(parsed.scheme?.lowercased() ?? ""), parsed.host != nil,
                                          case .string(let title) = fields["title"] else { return nil }
                                    return .init(textPartID: partID, text: text, startIndex: Int(start), endIndex: Int(end), url: url, title: title)
                                }
                                if !citations.isEmpty { continuation.yield(.textCitations(citations)) }
                            case .custom(let kind, let metadata):
                                // Native schema mode has one authoritative output path, not an
                                // additional injected custom stream that can bypass final validation.
                                if structuredResponse != nil, kind == HanlinChatStructuredPart.channel {
                                    throw HanlinChatStructuredPartError.unadvertisedChannel
                                }
                                if kind == HanlinChatStructuredPart.channel,
                                   self.resolvedProvider.descriptor.structuredPartChannel != HanlinChatStructuredPart.channel {
                                    throw HanlinChatStructuredPartError.unadvertisedChannel
                                }
                                if let part = try HanlinChatStructuredPart.decodeProviderContent(kind: kind, metadata: metadata),
                                   try structuredParts.admit(part) {
                                    meaningfulEventCount += 1
                                    hasStructuredContent = true
                                    continuation.yield(.structuredPart(part))
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
                                try Self.validateNativeToolInput(call.input, providerKind: resolvedProvider.descriptor.kind)
                                meaningfulEventCount += 1
                                continuation.yield(.toolCall(Self.toolCall(from: call)))
                            case .toolResult(let result):
                                meaningfulEventCount += 1
                                let projected = Self.toolResult(from: result)
                                if !projected.isError { hasSuccessfulToolAction = true }
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
                                accumulatedUsage = addLanguageModelUsage(accumulatedUsage, usage)
                                let nextOffset = offsetSnapshot + max(localStepIndex + 1, 1)
                                if !approvalResponses.isEmpty {
                                    // The SDK owns the exact original request/call/raw-input association.
                                    // Resume by appending its response messages and typed approval answers,
                                    // never by invoking a tool directly or fabricating another model turn.
                                    guard limit.map({ nextOffset < $0 }) ?? true else {
                                        throw HanlinAISDKError.incompleteProviderResponse(reason: "approval-continuation-step-limit")
                                    }
                                    for step in try await result.steps {
                                        for message in step.response.messages {
                                            switch message {
                                            case .assistant(let value): currentMessages.append(.assistant(value))
                                            case .tool(let value): currentMessages.append(.tool(value))
                                            }
                                        }
                                    }
                                    currentMessages.append(.tool(ToolModelMessage(content: approvalResponses)))
                                    stepOffset = nextOffset
                                    shouldReloadToolsAndContinue = true
                                    break
                                }
                                if reason == .toolCalls,
                                   limit.map({ nextOffset < $0 }) ?? true,
                                   let dynamicTools {
                                    let latestDefinitions = await dynamicTools()
                                    let reloadWasRequested = await toolReload.wasRequested
                                    if reloadWasRequested || Set(latestDefinitions.map(\.name)) != currentNames {
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
                                        currentTools = try Self.makeTools(latestDefinitions, providerKind: resolvedProvider.descriptor.kind)
                                        stepOffset = nextOffset
                                        shouldReloadToolsAndContinue = true
                                        break
                                    }
                                }
                                if let structuredResponse {
                                    guard reason == .stop else { throw HanlinNativeStructuredResponseError.incompleteResponse }
                                    let completeParts = try await structuredResponse.decodeComplete(completeResponseText)
                                    for part in completeParts {
                                        try Task.checkCancellation()
                                        guard try structuredParts.admit(part) else { continue }
                                        hasStructuredContent = true
                                        continuation.yield(.structuredPart(part))
                                    }
                                }
                                if responseSchema != nil {
                                    guard reason == .stop else {
                                        throw HanlinAISDKError.incompleteProviderResponse(reason: rawReason ?? reason.rawValue)
                                    }
                                    // The producer validates the final output against the original
                                    // schema. Partial/repaired streaming JSON is never accepted.
                                    _ = try await result.experimentalOutput
                                }
                                guard finalVisibleCharacters > 0 || hasSuccessfulToolAction || hasStructuredContent || hasDeniedToolAction else {
                                    throw HanlinAISDKError.incompleteProviderResponse(reason: rawReason ?? reason.rawValue)
                                }
                                continuation.yield(.finished(
                                    reason: rawReason ?? reason.rawValue,
                                    usage: Self.usage(from: accumulatedUsage)
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
                                let approval = try Self.approvalRequest(from: request, providerKind: resolvedProvider.descriptor.kind)
                                guard seenApprovalIDs.insert(approval.approvalID).inserted,
                                      seenApprovalCallIDs.insert(approval.toolCallID).inserted else {
                                    throw HanlinAISDKError.invalidConversation("Ambiguous tool approval request.")
                                }
                                continuation.yield(.toolApprovalRequest(approval))
                                let allowed = try await requestApproval?(approval) ?? false
                                try Task.checkCancellation()
                                continuation.yield(.toolApprovalResolved(approval, allowed: allowed))
                                if !allowed { hasDeniedToolAction = true }
                                approvalResponses.append(.toolApprovalResponse(ToolApprovalResponse(
                                    approvalId: approval.approvalID, approved: allowed,
                                    reason: allowed ? nil : "Not approved by the user.",
                                    providerExecuted: approval.providerExecuted)))
                            case .toolOutputDenied(let denied):
                                meaningfulEventCount += 1
                                continuation.yield(.toolOutputDenied(
                                    toolCallID: denied.toolCallId,
                                    toolName: denied.toolName
                                ))
                            case .textStart, .reasoningStart, .reasoningEnd,
                                 .toolInputEnd, .raw:
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
            } }
            let stop: @Sendable () -> Void = {
                task.cancel()
                cancellation.cancel()
                stopper.stop()
            }
            runControl?.install(task: task, stop: stop)
            continuation.onTermination = { @Sendable _ in stop() }
        }
    }

    private static func approvalRequest(from request: ToolApprovalRequestOutput,
                                        providerKind: HanlinAISDKProviderKind) throws -> HanlinAISDKToolApprovalRequest {
        let call = request.toolCall
        try validateNativeToolInput(call.input, providerKind: providerKind)
        guard !request.approvalId.isEmpty, request.approvalId.utf8.count <= 512,
              !call.toolCallId.isEmpty, call.toolCallId.utf8.count <= 512,
              !call.toolName.isEmpty, call.toolName.utf8.count <= 512 else {
            throw HanlinAISDKError.invalidConversation("Invalid tool approval identity.")
        }
        let arguments: String
        if let raw = call.rawInput {
            guard raw.toolCallId == call.toolCallId, raw.toolName == call.toolName,
                  raw.json.utf8.count <= ToolCallRawInput.maximumUTF8Bytes,
                  try JSONDecoder().decode(JSONValue.self, from: Data(raw.json.utf8)) == call.input else {
                throw HanlinAISDKError.invalidToolSchema(name: call.toolName)
            }
            arguments = raw.json
        } else { arguments = try jsonString(call.input) }
        guard arguments.utf8.count <= ToolCallRawInput.maximumUTF8Bytes else {
            throw HanlinAISDKError.invalidToolSchema(name: call.toolName)
        }
        return .init(approvalID: request.approvalId, toolCallID: call.toolCallId,
                     toolName: call.toolName, argumentsJSON: arguments,
                     providerExecuted: call.providerExecuted == true)
    }

    /// Defend both execution and approval paths, including injected native providers.
    /// The native adapter also rejects these before emitting any call. Provider metadata
    /// is not an authority to declare original numeric input.
    private static func validateNativeToolInput(_ input: JSONValue,
                                                providerKind: HanlinAISDKProviderKind) throws {
        guard providerKind == .appleOnDevice else { return }
        func containsNumber(_ value: JSONValue) -> Bool {
            switch value {
            case .number: true
            case .array(let values): values.contains(where: containsNumber)
            case .object(let values): values.values.contains(where: containsNumber)
            case .null, .bool, .string: false
            }
        }
        guard !containsNumber(input) else { throw HanlinAISDKError.nativeUnsupportedToolInput }
    }

    private static func makeTools(
        _ definitions: [HanlinAISDKToolDefinition],
        providerKind: HanlinAISDKProviderKind
    ) throws -> ToolSet {
        var aliases = Set<String>()
        for definition in definitions {
            guard aliases.insert(definition.name).inserted else {
                throw HanlinAISDKError.invalidToolSchema(name: definition.name)
            }
        }
        return try Dictionary(uniqueKeysWithValues: definitions.map { definition in
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
                        try validateNativeToolInput(converted, providerKind: providerKind)
                        return .success(value: converted)
                    } catch {
                        return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                    }
                }
            )
            let sdkTool = Tool(
                description: definition.description,
                inputSchema: FlexibleSchema(rawSchema),
                needsApproval: definition.requiresApproval ? .always : nil,
                execute: { input, options in
                    try Task.checkCancellation()
                    try validateNativeToolInput(input, providerKind: providerKind)
                    let arguments: String
                    let provenance: HanlinAISDKToolInputProvenance
                    if let raw = options.rawInput {
                        guard raw.toolCallId == options.toolCallId, raw.toolName == definition.name,
                              raw.json.utf8.count <= ToolCallRawInput.maximumUTF8Bytes,
                              try JSONDecoder().decode(JSONValue.self, from: Data(raw.json.utf8)) == input else {
                            throw HanlinAISDKError.invalidToolSchema(name: definition.name)
                        }
                        arguments = raw.json
                        // The native framework exposes structured GeneratedContent, not original
                        // model JSON tokens. The producer's parsed-string rawInput cannot upgrade
                        // that origin. This decision uses the trusted resolved provider descriptor.
                        provenance = providerKind == .appleOnDevice ? .normalized : .acceptedOriginal
                    } else {
                        arguments = try jsonString(input)
                        provenance = .normalized
                    }
                    let output: HanlinAISDKToolExecutionOutput
                    if let execute = definition.executeWithInputProvenance {
                        output = try await execute(arguments, options.toolCallId, provenance)
                    } else {
                        output = try await definition.execute(arguments, options.toolCallId)
                    }
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

    private static func messagesWithSkillInstructions(
        _ messages: [ModelMessage], instructions: [String]
    ) -> [ModelMessage] {
        guard let text = systemPrompt(base: nil, loadedInstructions: instructions) else { return messages }
        var result = messages
        let index = result.firstIndex { message in
            if case .system = message { return false }
            return true
        } ?? result.endIndex
        result.insert(.system(SystemModelMessage(content: text)), at: index)
        return result
    }

    private static func modelMessages(
        from messages: [HanlinAISDKMessage],
        includeSystemMessages: Bool,
        breakpointOptions: ProviderOptions?
    ) throws -> [ModelMessage] {
        messages.compactMap { message in
            let cacheOptions = message.cacheBreakpoint ? breakpointOptions : nil
            switch message.role {
            case .system:
                guard includeSystemMessages else { return nil }
                let text = message.parts.compactMap { part -> String? in
                    if case .text(let value) = part { return value }
                    return nil
                }.joined(separator: "\n")
                guard !text.isEmpty else { return nil }
                return .system(SystemModelMessage(content: text, providerOptions: cacheOptions))
            case .assistant:
                let text = message.parts.compactMap { part -> String? in
                    if case .text(let value) = part { return value }
                    return nil
                }.joined(separator: "\n")
                if let cacheOptions {
                    return .assistant(AssistantModelMessage(content: .parts([
                        .text(TextPart(text: text, providerOptions: cacheOptions))
                    ])))
                }
                return .assistant(AssistantModelMessage(content: .text(text)))
            case .user:
                if cacheOptions == nil, message.parts.count == 1, case .text(let text) = message.parts[0] {
                    return .user(UserModelMessage(content: .text(text)))
                }
                let parts = message.parts.enumerated().map { index, part -> UserContentPart in
                    let options = index == message.parts.count - 1 ? cacheOptions : nil
                    switch part {
                    case .text(let text):
                        return .text(TextPart(text: text, providerOptions: options))
                    case .imageURL(let url, let mediaType):
                        return .image(ImagePart(image: .url(url), mediaType: mediaType, providerOptions: options))
                    case .imageData(let data, let mediaType):
                        return .image(ImagePart(image: .data(data), mediaType: mediaType, providerOptions: options))
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
            cacheWriteTokens: usage.inputTokenDetails.cacheWriteTokens,
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
