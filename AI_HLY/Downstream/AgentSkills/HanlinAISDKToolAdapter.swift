import Foundation
import SwiftData
import HanlinPlatformContracts
import HanlinChatCore

/// Adapts canonical Hanlin tools into SDK `HanlinAISDKToolDefinition`s,
/// routing execution through `AssistantToolBridge.PreparedTools`, meta-tools (`LoadSkillTool`,
/// `ToolSearchTool`, `ReadToolResultTool`), and preserving large tool results, UI blocks,
/// diagnostics, and presentation decisions.
@MainActor
final class HanlinAISDKToolAdapter {
    struct Callbacks {
        var onStreamData: ((StreamData) -> Void)?
        var onAgentEvent: ((AgentEvent) -> Void)?
        var onProgressMessage: ((AgentProgressMessage) -> Void)?
        var currentReasoningSummary: (() -> String?)?

        init(
            onStreamData: ((StreamData) -> Void)? = nil,
            onAgentEvent: ((AgentEvent) -> Void)? = nil,
            onProgressMessage: ((AgentProgressMessage) -> Void)? = nil,
            currentReasoningSummary: (() -> String?)? = nil
        ) {
            self.onStreamData = onStreamData
            self.onAgentEvent = onAgentEvent
            self.onProgressMessage = onProgressMessage
            self.currentReasoningSummary = currentReasoningSummary
        }
    }

    let session: AssistantCapabilitySession
    let preparedTools: AssistantToolBridge.PreparedTools
    let catalog: HanlinSkillCatalog
    let modelContext: ModelContext?
    let currentLanguage: String
    let progressSummaryRequired: Bool
    let supportsReportProgress: Bool
    var callbacks: Callbacks
    var reportProgressController: ReportProgressController
    var latestToolProgressSummary: String?
    var diagnosticsRecorder: AgentDiagnosticsRecorder?
    var currentRoundID: UUID?

    init(
        session: AssistantCapabilitySession,
        preparedTools: AssistantToolBridge.PreparedTools,
        catalog: HanlinSkillCatalog = .shared,
        modelContext: ModelContext? = nil,
        currentLanguage: String = "en",
        progressSummaryRequired: Bool = false,
        supportsReportProgress: Bool = false,
        callbacks: Callbacks = Callbacks(),
        reportProgressController: ReportProgressController = ReportProgressController(),
        diagnosticsRecorder: AgentDiagnosticsRecorder? = nil,
        currentRoundID: UUID? = nil
    ) {
        self.session = session
        self.preparedTools = preparedTools
        self.catalog = catalog
        self.modelContext = modelContext
        self.currentLanguage = currentLanguage
        self.progressSummaryRequired = progressSummaryRequired
        self.supportsReportProgress = supportsReportProgress
        self.callbacks = callbacks
        self.reportProgressController = reportProgressController
        self.diagnosticsRecorder = diagnosticsRecorder
        self.currentRoundID = currentRoundID
    }

    /// Evaluates currently active tool aliases for model exposure in the next step.
    func currentActiveToolAliases() -> [String] {
        var aliases: [String] = [
            LoadSkillTool.toolName,
            ToolSearchTool.toolName,
            ReadToolResultTool.toolName
        ]
        if supportsReportProgress {
            aliases.append(ToolSchemaDecorator.reportProgressName)
        }
        for alias in session.exposedToolAliases {
            if preparedTools.authority.schemasByAlias[alias] != nil && !aliases.contains(alias) {
                aliases.append(alias)
            }
        }
        return aliases
    }

    /// Generates step preparation metadata for `HanlinAISDKAgentEngine`.
    func prepareStep() -> HanlinAISDKStepPreparation {
        let active = currentActiveToolAliases()
        let sizes = preparedTools.schemaSizes()
        let visibleBytes = active.reduce(0) { $0 + (sizes[$1] ?? 400) }
        return HanlinAISDKStepPreparation(
            activeToolAliases: active,
            loadedSkillIDs: session.loadedSkillIDs.map(\.rawValue).sorted(),
            loadedSkillInstructions: session.loadedSkillInstructions,
            visibleSchemaBytes: visibleBytes
        )
    }

    /// Builds all available tool definitions for the SDK engine.
    /// Dynamic visibility is managed per step via `prepareStep()`.
    func allToolDefinitions() throws -> [HanlinAISDKToolDefinition] {
        var definitions: [HanlinAISDKToolDefinition] = []

        // 1. load_skill
        definitions.append(try makeLoadSkillDefinition())

        // 2. tool_search
        definitions.append(try makeToolSearchDefinition())

        // 3. read_tool_result
        definitions.append(try makeReadToolResultDefinition())

        // 4. report_progress
        if supportsReportProgress {
            definitions.append(try makeReportProgressDefinition())
        }

        // 5. Canonical tools
        for (alias, rawSchema) in preparedTools.authority.schemasByAlias {
            let profile = preparedTools.presentationProfile(for: alias) ?? ToolPresentationProfileRegistry.resolve(toolName: alias)
            let decoratedSchema = ToolSchemaDecorator.decorate(
                schema: rawSchema,
                profile: profile,
                progressSummaryRequired: progressSummaryRequired
            )
            definitions.append(try makeCanonicalDefinition(alias: alias, schema: decoratedSchema, profile: profile))
        }

        return definitions
    }

    private func makeLoadSkillDefinition() throws -> HanlinAISDKToolDefinition {
        let schema = LoadSkillTool.schema
        let parameters = (schema["function"] as? [String: Any])?["parameters"] as? [String: Any] ?? [:]
        let description = (schema["function"] as? [String: Any])?["description"] as? String ?? ""
        let inputSchemaData = try JSONSerialization.data(withJSONObject: parameters)

        return HanlinAISDKToolDefinition(
            name: LoadSkillTool.toolName,
            description: description,
            inputSchemaData: inputSchemaData,
            execute: { [weak self] argumentsJSON, callID in
                guard let self else {
                    return HanlinAISDKToolExecutionOutput(modelText: "Tool adapter deallocated", isError: true)
                }
                let isZh = self.currentLanguage.hasPrefix("zh")
                self.callbacks.onStreamData?(StreamData(operationalState: isZh ? "加载技能..." : "Loading skill..."))
                let result = await LoadSkillTool.execute(
                    argumentsJSON: argumentsJSON,
                    session: self.session,
                    catalog: self.catalog,
                    schemaSizes: self.preparedTools.schemaSizes()
                )
                self.callbacks.onStreamData?(StreamData(
                    toolContent: result,
                    toolName: LoadSkillTool.toolName,
                    operationalDescription: result
                ))
                return HanlinAISDKToolExecutionOutput(modelText: result)
            }
        )
    }

    private func makeToolSearchDefinition() throws -> HanlinAISDKToolDefinition {
        let schema = ToolSearchTool.schema
        let parameters = (schema["function"] as? [String: Any])?["parameters"] as? [String: Any] ?? [:]
        let description = (schema["function"] as? [String: Any])?["description"] as? String ?? ""
        let inputSchemaData = try JSONSerialization.data(withJSONObject: parameters)

        return HanlinAISDKToolDefinition(
            name: ToolSearchTool.toolName,
            description: description,
            inputSchemaData: inputSchemaData,
            execute: { [weak self] argumentsJSON, callID in
                guard let self else {
                    return HanlinAISDKToolExecutionOutput(modelText: "Tool adapter deallocated", isError: true)
                }
                let isZh = self.currentLanguage.hasPrefix("zh")
                self.callbacks.onStreamData?(StreamData(operationalState: isZh ? "搜索工具..." : "Searching tools..."))
                let result = ToolSearchTool.execute(
                    argumentsJSON: argumentsJSON,
                    session: self.session,
                    searchProvider: { [weak self] q, l in
                        guard let self else { return [] }
                        return self.preparedTools.search(query: q, limit: l, preferredAliases: self.session.activeSkillToolHints)
                    }
                )
                self.callbacks.onStreamData?(StreamData(
                    toolContent: result,
                    toolName: ToolSearchTool.toolName,
                    operationalDescription: result
                ))
                return HanlinAISDKToolExecutionOutput(modelText: result)
            }
        )
    }

    private func makeReadToolResultDefinition() throws -> HanlinAISDKToolDefinition {
        let schema = ReadToolResultTool.schema
        let parameters = (schema["function"] as? [String: Any])?["parameters"] as? [String: Any] ?? [:]
        let description = (schema["function"] as? [String: Any])?["description"] as? String ?? ""
        let inputSchemaData = try JSONSerialization.data(withJSONObject: parameters)

        return HanlinAISDKToolDefinition(
            name: ReadToolResultTool.toolName,
            description: description,
            inputSchemaData: inputSchemaData,
            execute: { [weak self] argumentsJSON, callID in
                guard let self else {
                    return HanlinAISDKToolExecutionOutput(modelText: "Tool adapter deallocated", isError: true)
                }
                let isZh = self.currentLanguage.hasPrefix("zh")
                self.callbacks.onStreamData?(StreamData(operationalState: isZh ? "读取结果..." : "Reading tool result..."))
                let result = ReadToolResultTool.execute(
                    argumentsJSON: argumentsJSON,
                    session: self.session
                )
                self.callbacks.onStreamData?(StreamData(
                    toolContent: result,
                    toolName: ReadToolResultTool.toolName,
                    operationalDescription: result
                ))
                return HanlinAISDKToolExecutionOutput(modelText: result)
            }
        )
    }

    private func makeReportProgressDefinition() throws -> HanlinAISDKToolDefinition {
        let schema = ToolSchemaDecorator.reportProgressSchema()
        let parameters = (schema["function"] as? [String: Any])?["parameters"] as? [String: Any] ?? [:]
        let description = (schema["function"] as? [String: Any])?["description"] as? String ?? ""
        let inputSchemaData = try JSONSerialization.data(withJSONObject: parameters)

        return HanlinAISDKToolDefinition(
            name: ToolSchemaDecorator.reportProgressName,
            description: description,
            inputSchemaData: inputSchemaData,
            execute: { [weak self] argumentsJSON, callID in
                guard let self else {
                    return HanlinAISDKToolExecutionOutput(modelText: "Progress update delivered.")
                }
                let candidate = ToolProgressSummary.reportProgressMessage(from: argumentsJSON)
                if let message = self.reportProgressController.accept(
                    candidate,
                    latestToolSummary: self.latestToolProgressSummary
                ) {
                    let progressMsg = AgentProgressMessage(
                        id: "progress:\(callID)",
                        message: message,
                        source: .model,
                        timestamp: Date()
                    )
                    self.callbacks.onProgressMessage?(progressMsg)
                    self.callbacks.onAgentEvent?(.progressMessage(progressMsg))
                }
                return HanlinAISDKToolExecutionOutput(modelText: "Progress update delivered.")
            }
        )
    }

    private func makeCanonicalDefinition(
        alias: String,
        schema: [String: Any],
        profile: ToolPresentationProfile
    ) throws -> HanlinAISDKToolDefinition {
        let function = schema["function"] as? [String: Any]
        let description = function?["description"] as? String ?? schema["description"] as? String ?? ""
        let parameters = function?["parameters"] as? [String: Any] ?? schema["parameters"] as? [String: Any] ?? ["type": "object", "properties": [:]]
        let inputSchemaData = try JSONSerialization.data(withJSONObject: parameters)

        return HanlinAISDKToolDefinition(
            name: alias,
            description: description,
            inputSchemaData: inputSchemaData,
            execute: { [weak self] argumentsJSON, callID in
                guard let self else {
                    return HanlinAISDKToolExecutionOutput(modelText: "Tool adapter deallocated", isError: true)
                }
                return await self.executeCanonicalTool(
                    alias: alias,
                    callID: callID,
                    argumentsJSON: argumentsJSON,
                    profile: profile
                )
            }
        )
    }

    private func executeCanonicalTool(
        alias: String,
        callID: String,
        argumentsJSON: String,
        profile: ToolPresentationProfile
    ) async -> HanlinAISDKToolExecutionOutput {
        var parsedCall = AgentToolCall.parse(
            id: callID,
            name: alias,
            argumentsJSON: argumentsJSON,
            presentationProfile: profile
        )
        if parsedCall.progressSummary == nil,
           let reasoning = callbacks.currentReasoningSummary?(),
           let providerSummary = ProgressSummarySanitizer.sanitizeProviderReasoningSummary(reasoning) {
            parsedCall.progressSummary = providerSummary
            parsedCall.progressSummarySource = .providerReasoningSummary
        }

        if let recorder = diagnosticsRecorder, let roundID = currentRoundID {
            await recorder.recordToolCall(roundID: roundID, call: parsedCall)
        }

        self.latestToolProgressSummary = parsedCall.progressSummary
        let executionID = "\(callID):execution"
        let executionStart = Date()

        callbacks.onAgentEvent?(.toolCallStarted(parsedCall))
        callbacks.onAgentEvent?(.toolCallCompleted(parsedCall))
        callbacks.onAgentEvent?(.toolExecutionStarted(AgentToolExecution(
            id: executionID,
            callID: callID,
            name: alias,
            startedAt: executionStart
        )))

        let nativeContext = NativeToolExecutionContext(
            localeIdentifier: currentLanguage,
            modelContext: modelContext
        )

        let nativeResult = await preparedTools.execute(
            alias: alias,
            argumentsJSON: parsedCall.sanitizedArgumentsJSON,
            context: nativeContext
        )

        let executionDuration = Date().timeIntervalSince(executionStart)

        guard let result = nativeResult else {
            let errorText = currentLanguage.hasPrefix("zh") ? "工具不存在" : "Tool does not exist"
            callbacks.onAgentEvent?(.toolExecutionFailed(
                id: executionID,
                error: AgentSafeError(message: errorText)
            ))
            callbacks.onStreamData?(StreamData(
                toolContent: errorText,
                toolName: alias,
                operationalDescription: errorText
            ))
            if let recorder = diagnosticsRecorder, let roundID = currentRoundID {
                await recorder.completeToolCall(
                    roundID: roundID,
                    callID: callID,
                    resultForModel: errorText,
                    resultForUser: errorText,
                    duration: executionDuration,
                    outcome: .invalidArguments,
                    error: errorText
                )
            }
            return HanlinAISDKToolExecutionOutput(modelText: errorText, isError: true)
        }

        var modelText = result.modelText
        var userText = result.userText ?? result.modelText
        var resultRef: String? = nil
        var embeddedPayload = result.embeddedPayload

        // Large result store handling
        let shouldStore = result.fullResultPayload != nil
            || (result.isStoreEligible && result.modelText.utf8.count > 1024)
        if shouldStore {
            let payloadToStore = result.fullResultPayload ?? result.modelText
            let mimeType = result.fullResultMIMEType ?? "text/plain"
            if let ref = session.resultStore.store(payloadToStore, mimeType: mimeType) {
                resultRef = ref
                if let currentPayload = embeddedPayload {
                    embeddedPayload = HanlinEmbeddedResultPayload(
                        payload: currentPayload.payload,
                        resultReference: ref,
                        title: currentPayload.title,
                        metadata: currentPayload.metadata,
                        ownerID: currentPayload.ownerID,
                        actions: currentPayload.actions
                    )
                }
                modelText = """
                [Large result stored behind reference: \(ref) (\(payloadToStore.utf8.count) bytes)]
                Summary: \(String(result.modelText.prefix(200)))
                To inspect or paginate this result, call `read_tool_result(reference: "\(ref)", offset: 0, limit: 4096)`.
                """
            } else if modelText.isEmpty, let full = result.fullResultPayload {
                modelText = full
            }
        }

        let presentationDecision = ToolResultPresentationCoordinator.decide(
            call: parsedCall,
            profile: parsedCall.presentationProfile,
            hasPayload: !result.uiBlocks.isEmpty || embeddedPayload != nil
        )

        let isSuccess = result.outcome.isSuccess
        if isSuccess {
            callbacks.onAgentEvent?(.toolExecutionCompleted(
                id: executionID,
                result: AgentToolResult(
                    modelText: modelText,
                    userText: userText,
                    richResultBlocks: result.uiBlocks,
                    evidenceItems: [],
                    hasLegacyPresentationPayload: presentationDecision.shouldPresent
                        && presentationDecision.rendererKind == .legacyExisting,
                    isError: false,
                    semanticOutcome: result.outcome,
                    duration: executionDuration,
                    embeddedResultPayload: embeddedPayload
                )
            ))
        } else {
            callbacks.onAgentEvent?(.toolExecutionFailed(
                id: executionID,
                error: AgentSafeError(message: userText)
            ))
        }

        callbacks.onStreamData?(StreamData(
            toolContent: userText,
            toolName: alias,
            operationalDescription: userText
        ))

        if let recorder = diagnosticsRecorder, let roundID = currentRoundID {
            await recorder.completeToolCall(
                roundID: roundID,
                callID: callID,
                resultForModel: modelText,
                resultForUser: userText,
                duration: executionDuration,
                outcome: result.outcome,
                diagnostics: result.diagnostics,
                error: isSuccess ? nil : userText,
                presentationDecision: presentationDecision
            )
        }

        return HanlinAISDKToolExecutionOutput(
            modelText: modelText,
            resultReference: resultRef,
            isError: !isSuccess
        )
    }
}
