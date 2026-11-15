import CryptoKit
import Foundation
import HanlinAgentCore
import HanlinChatCore
import HanlinHostContracts
import HanlinPlatformContracts

/// Projects existing application tool authority into the SDK. Every effect still passes through
/// the original adapter, NativeToolBridge/MCP policies, OS permission and original result callbacks.
@MainActor
final class HanlinAppHostIntegration: HanlinHostIntegration, HanlinHostCapabilitySource, HanlinHostInteractionSource {
    nonisolated let apiVersion = HanlinAPIVersion(major: 1, minor: 1)
    let identity: HanlinHostSession
    var toolAdapter: HanlinAISDKToolAdapter?
    private let store: HanlinAppConversationStore
    private let isCurrent: @MainActor @Sendable () -> Bool
    private var validationPlans: [Data: HanlinHostSchemaValidation] = [:]
    private var definitions: [String: HanlinAISDKToolDefinition] = [:]
    private var executions: [HanlinToolInvocationID: Task<HanlinAISDKToolExecutionOutput, Error>] = [:]

    init(identity: HanlinHostSession, store: HanlinAppConversationStore,
         isCurrent: @escaping @MainActor @Sendable () -> Bool) {
        self.identity = identity; self.store = store; self.isCurrent = isCurrent
    }

    func context(for session: HanlinHostSession) async throws -> HanlinHostContext {
        guard isCurrent(), session == identity else { throw HanlinHostError.staleContext }
        _ = try store.requireOriginalConversation()
        return identity.context
    }

    func catalog(for context: HanlinHostContext) async throws -> HanlinHostCatalog {
        guard context == identity.context else { throw HanlinHostError.staleContext }
        _ = try await self.context(for: identity)
        let available = try toolAdapter?.allToolDefinitions().sorted { $0.name < $1.name } ?? []
        guard Set(available.map(\.name)).count == available.count else { throw HanlinHostError.duplicateAlias }
        let tools = try available.map { definition -> HanlinHostTool in
            let source = toolAdapter?.preparedTools.authority.toolDescriptor(for: definition.name)
            let isMeta = [LoadSkillTool.toolName, ReadSkillResourceTool.toolName, ToolSearchTool.toolName,
                ReadToolResultTool.toolName, ToolSchemaDecorator.reportProgressName].contains(definition.name)
            guard source != nil || isMeta else { throw HanlinHostError.unknownTool }
            // Meta tools already have one implementation in the same adapter. Give that existing
            // implementation a stable canonical identity; do not create another meta-tool registry.
            let logical = try source?.logicalID ?? HanlinLogicalToolID(
                providerInstanceID: .init(validating: "hanlin.meta"), localToolID: .init(validating: definition.name))
            let revision = try source?.descriptorRevision ?? HanlinDescriptorRevision(1)
            let input = try HanlinJSONSchemaDocument.decodeCanonicalJSON(definition.inputSchemaData, defaultDialect: .draft2020_12)
            let descriptor = try HanlinToolDescriptor(logicalID: logical, descriptorRevision: revision,
                owner: source?.owner ?? .system, title: source?.title ?? .init(["en": definition.name]),
                summary: source?.summary ?? .init(["en": definition.description]), inputSchema: input,
                outputSchema: source?.outputSchema, capabilities: source?.capabilities ?? [],
                risk: source?.risk ?? .read, presentation: source?.presentation ?? .init())
            // The legacy shadow catalog currently labels general native/legacy tools .read.
            // That is not an authoritative no-mutation promise (e.g. manage_calendar can write).
            // Only these existing metadata/progress implementations are proven business-read-only.
            return .init(route: .init(alias: definition.name, logicalToolID: logical, descriptorRevision: revision),
                descriptor: descriptor, writeGuarantee: isMeta ? .readOnly : .hostManagedMutation,
                originalInputSchemaJSON: definition.inputSchemaData)
        }
        // JSON dictionaries must be canonical before hashing or unchanged schemas spuriously
        // change the catalog generation. No process-random Hasher is used for public revision.
        let canonicalTools = try tools.map { tool in HanlinJSONValue.object([
            "alias": .string(tool.route.alias),
            // Definition bytes are emitted with sorted keys at the existing declaration boundary.
            // Bind their exact numeric/key content too; the portable descriptor may be lossy.
            "originalSchemaBase64": .string(tool.originalInputSchemaJSON?.base64EncodedString() ?? ""),
            "descriptor": try HanlinJSONValue.decodeCanonicalJSON(JSONEncoder().encode(tool.descriptor))
        ]) }
        let digestInput = try HanlinJSONValue.array(canonicalTools).canonicalJSONData()
        let value = SHA256.hash(data: digestInput).prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        definitions = Dictionary(uniqueKeysWithValues: available.map { ($0.name, $0) })
        let catalog = HanlinHostCatalog(apiVersion: apiVersion, revision: .init(value), context: context, tools: tools)
        try catalog.validate()
        return catalog
    }

    func prepareStep(_ step: Int, session: HanlinHostSession) async throws -> HanlinHostStepPreparation {
        _ = try await context(for: session)
        guard let toolAdapter else { return .init(activeAliases: []) }
        let prepared = await toolAdapter.prepareStep(stepNumber: step)
        _ = try await context(for: session)
        return .init(activeAliases: prepared.activeToolAliases, skillIDs: prepared.loadedSkillIDs,
            instructions: prepared.loadedSkillInstructions)
    }

    @MainActor private final class ExecutionObservation {
        var outcome: NativeToolExecutionOutcome?
        var enteredExecutor = false
        var denial: HanlinPlatformError?
        var progress: UInt64 = 0
    }

    func execute(_ invocation: HanlinHostInvocation,
                 progress: @escaping @Sendable (HanlinToolProgressEvent) async -> Void) async throws -> HanlinHostExecutionResult {
        let entry: HanlinHostTool
        let definition: HanlinAISDKToolDefinition
        let original: Data
        let deadline: Date
        do {
            _ = try await context(for: invocation.session)
            guard invocation.expectedRevision == nil else { throw HanlinHostError.unsupportedConditionalWrite }
            let current = try await catalog(for: invocation.session.context)
            guard current.revision == invocation.request.routingTableRevision,
                  let found = current.tools.first(where: { $0.route.alias == invocation.request.aliasUsed }),
                  found.route.logicalToolID == invocation.request.logicalToolID,
                  found.route.descriptorRevision == invocation.request.descriptorRevision,
                  let foundDefinition = definitions[invocation.request.aliasUsed],
                  let expiry = invocation.request.deadline, expiry > Date(),
                  let bytes = invocation.originalArgumentsJSON else { throw HanlinHostError.staleContext }
            entry = found; definition = foundDefinition; deadline = expiry; original = bytes
            // External MCP schemas currently reach this app through an already parsed String/Any
            // dictionary. Re-encoding cannot prove original numeric/key fidelity. Keep this path
            // explicitly unavailable until the original upstream schema boundary is retained.
            if let backend = toolAdapter?.preparedTools.authority.resolution(alias: entry.route.alias)?.backend,
               case .mcp = backend { throw HanlinHostSchemaValidation.Failure.unsupportedSchema }
            let plan: HanlinHostSchemaValidation
            if let cached = validationPlans[definition.inputSchemaData] { plan = cached }
            else {
                plan = try HanlinHostSchemaValidation(schemaJSON: definition.inputSchemaData)
                if validationPlans.count >= 8 { validationPlans.removeAll() }
                validationPlans[definition.inputSchemaData] = plan
            }
            try plan.validate(argumentsJSON: original)
            try HanlinHostSchemaValidation.requireSameValue(originalJSON: original,
                projectedJSON: invocation.request.arguments.canonicalJSONData())
            // Audit the exact existing metadata extraction now and again immediately before the
            // original executor. No replacement metadata parser or alternate business value exists.
            let extraction = ToolInvocationMetadataExtractor.extract(from: String(decoding: original, as: UTF8.self))
            try HanlinHostSchemaValidation.requireSameValue(originalJSON: original,
                projectedJSON: Data(extraction.sanitizedArgumentsJSON.utf8), removingMetadataKeys: [
                    ToolSchemaDecorator.progressSummaryKey, ToolSchemaDecorator.resultPresentationKey])
            _ = try await context(for: invocation.session)
            try Task.checkCancellation()
            guard deadline > Date() else { throw HanlinHostError.staleContext }
        } catch { return noDispatch(invocation, error: error) }
        let observation = ExecutionObservation()
        let callID = invocation.providerCallID
        let adapter = toolAdapter
        adapter?.sdkOutcomeHandlers[callID] = { outcome in observation.outcome = outcome }
        adapter?.sdkPreDispatchHandlers[callID] = { [weak self] actualArguments in
            do {
                try Task.checkCancellation()
                guard let self, self.isCurrent(), invocation.session == self.identity, deadline > Date() else {
                    throw HanlinHostError.staleContext
                }
                _ = try self.store.requireOriginalConversation()
                try self.requireOriginalRoute(entry, definition: definition, adapter: adapter)
                try HanlinHostSchemaValidation.requireSameValue(originalJSON: original,
                    projectedJSON: Data(actualArguments.utf8), removingMetadataKeys: [
                        ToolSchemaDecorator.progressSummaryKey, ToolSchemaDecorator.resultPresentationKey])
                observation.enteredExecutor = true
            } catch {
                observation.denial = Self.preDispatchError(error)
                throw error
            }
        }
        adapter?.sdkProgressHandlers[callID] = { message in
            observation.progress += 1
            if let event = try? HanlinToolProgressEvent(invocationID: invocation.request.id,
                sequence: observation.progress, timestamp: .now, message: message) {
                Task { await progress(event) }
            }
        }
        defer {
            adapter?.sdkOutcomeHandlers[callID] = nil
            adapter?.sdkProgressHandlers[callID] = nil
            adapter?.sdkPreDispatchHandlers[callID] = nil
            executions[invocation.request.id] = nil
        }
        let arguments = String(decoding: original, as: UTF8.self)
        let task = Task {
            try Task.checkCancellation()
            _ = try await context(for: invocation.session)
            try Task.checkCancellation()
            guard deadline > Date() else { throw HanlinHostError.staleContext }
            try requireOriginalRoute(entry, definition: definition, adapter: adapter)
            // Metadata tools have no prepared business executor; their existing implementation
            // is read-only. All general operations mark entry at the adapter's actual boundary.
            if entry.writeGuarantee == .readOnly { observation.enteredExecutor = true }
            return try await definition.execute(arguments, callID)
        }
        executions[invocation.request.id] = task
        let output: HanlinAISDKToolExecutionOutput
        do {
            output = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
        } catch {
            if !observation.enteredExecutor { return noDispatch(invocation, error: error) }
            let uncertain = entry.writeGuarantee != .readOnly
            return .init(result: .init(invocationID: invocation.request.id, logicalToolID: invocation.request.logicalToolID,
                outcome: .failed(.init(code: .nativeFailure, userMessage: uncertain
                    ? "The operation outcome is uncertain. Do not retry automatically." : "The host operation failed.")),
                completedAt: .now), effectState: uncertain ? .uncertain : .confirmedNoEffect,
                context: invocation.session.context, reconciliationReference: uncertain ? invocation.request.id.rawValue : nil)
        }
        if let denial = observation.denial { return noDispatch(invocation, error: denial) }
        let effect: HanlinHostEffectState
        if entry.writeGuarantee == .readOnly { effect = .confirmedNoEffect }
        else {
            // A nonempty string or lack of thrown error is not an effect receipt.
            switch observation.outcome {
            case .succeeded?: effect = .confirmedCommitted
            case .invalidArguments?, .rejectedByCapability?, .rejectedByAvailability?: effect = .confirmedNoEffect
            default: effect = .uncertain
            }
        }
        let outcome: HanlinToolOutcome = output.isError
            ? .failed(.init(code: .nativeFailure, userMessage: output.modelText))
            : .completed([.text(output.modelText)])
        return .init(result: .init(invocationID: invocation.request.id, logicalToolID: invocation.request.logicalToolID,
            outcome: outcome, completedAt: .now), effectState: effect, context: invocation.session.context,
            reconciliationReference: effect == .uncertain ? invocation.request.id.rawValue : output.resultReference)
    }

    private func requireOriginalRoute(_ entry: HanlinHostTool, definition: HanlinAISDKToolDefinition,
                                      adapter: HanlinAISDKToolAdapter?) throws {
        guard let adapter, toolAdapter === adapter,
              let current = try adapter.allToolDefinitions().first(where: { $0.name == entry.route.alias }),
              current.inputSchemaData == definition.inputSchemaData else { throw HanlinHostError.staleContext }
        if let descriptor = adapter.preparedTools.authority.toolDescriptor(for: entry.route.alias) {
            guard descriptor.logicalID == entry.route.logicalToolID,
                  descriptor.descriptorRevision == entry.route.descriptorRevision else { throw HanlinHostError.staleContext }
        } else {
            guard entry.route.logicalToolID.providerInstanceID.rawValue == "hanlin.meta",
                  entry.writeGuarantee == .readOnly else { throw HanlinHostError.staleContext }
        }
    }

    private static func preDispatchError(_ error: Error) -> HanlinPlatformError {
        if let error = error as? HanlinPlatformError { return error }
        let code: HanlinErrorCode
        switch error {
        case is CancellationError: code = .cancelled
        case HanlinHostSchemaValidation.Failure.invalidArguments: code = .invalidArguments
        case HanlinHostSchemaValidation.Failure.lossyProjection: code = .schemaProjectionWidensInput
        case HanlinHostSchemaValidation.Failure.inputTooLarge: code = .sizeLimitExceeded
        case HanlinHostSchemaValidation.Failure.unsupportedSchema: code = .unsupportedSchemaKeyword
        default: code = .operationUnavailable
        }
        return .init(code: code, userMessage: "The original operation input or context could not be verified. No operation was dispatched.")
    }

    private func noDispatch(_ invocation: HanlinHostInvocation, error: Error) -> HanlinHostExecutionResult {
        .init(result: .init(invocationID: invocation.request.id, logicalToolID: invocation.request.logicalToolID,
            outcome: .failed(Self.preDispatchError(error)), completedAt: .now), effectState: .notDispatched,
            context: invocation.session.context)
    }

    func cancel(_ invocation: HanlinToolInvocationID) async { executions[invocation]?.cancel() }

    func prepareInteraction(_ request: HanlinHostInteractionRequest) async throws -> HanlinHostInteractionContinuation {
        _ = try await context(for: request.origin.session)
        let arguments = try request.arguments.canonicalJSONData()
        guard !request.actionID.isEmpty, request.actionID.utf8.count <= 512, arguments.count <= 1_048_576 else {
            throw HanlinHostError.invalidArguments
        }
        // User input for a new canonical model turn; no native tool is invoked here.
        return .init(userMessage: "The user activated the displayed action \(request.actionID). User-provided action data: "
            + String(decoding: arguments, as: UTF8.self))
    }

    func open(_ destination: HanlinHostDestination) async throws -> HanlinHostNavigationResult {
        // Native tool navigation stays inside the original application's existing executor.
        // This adapter has no scene-mount acknowledgement and cannot invent successful navigation.
        _ = try await context(for: identity)
        throw HanlinHostError.unsupportedProviderCapability
    }
}
