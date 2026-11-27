import Foundation
import HanlinAgentCore
import HanlinChatCore
import HanlinHostContracts
import HanlinPlatformContracts

/// Original application tool boundary. Implementations provide existing tool
/// definitions and receipt observers; they do not replace dispatch policy.
@MainActor
protocol HanlinOriginalToolSource: AnyObject {
    var catalogGeneration: UUID { get }
    func allToolDefinitions() throws -> [HanlinAISDKToolDefinition]
    func descriptor(for alias: String) -> HanlinToolDescriptor?
    func isMCP(_ alias: String) -> Bool
    func originalMCPInputSchema(for alias: String) -> Data?
    func mcpServerID(for alias: String) -> UUID?
    var sdkProgressHandlers: [String: @MainActor @Sendable (String) -> Void] { get set }
    var sdkPreDispatchHandlers: [String: @MainActor @Sendable (String) throws -> Void] { get set }
    var sdkPreDispatchFailureHandlers: [String: @MainActor @Sendable (Error) -> Void] { get set }
    var sdkOutcomeHandlers: [String: @MainActor @Sendable (NativeToolExecutionOutcome) -> Void] { get set }
}

/// Extracted from HanlinAppHostIntegration. The application and embedding
/// component share exact-schema validation, original scoped consent, dispatch
/// revalidation, cancellation and honest effect receipts in this one owner.
@MainActor
final class HanlinOriginalToolExecution {
    private let source: @MainActor () -> (any HanlinOriginalToolSource)?
    private let context: @MainActor (HanlinHostSession) async throws -> HanlinHostContext
    private let catalog: @MainActor (HanlinHostContext) async throws -> HanlinHostCatalog
    private let definitionForAlias: @MainActor (String) -> HanlinAISDKToolDefinition?
    private let validateCurrent: @MainActor (HanlinHostSession) throws -> Void
    private let confirmInvocation: @MainActor (HanlinHostInvocation, HanlinToolApprovalScope) async -> Bool
    private var validationPlans: [Data: HanlinHostSchemaValidation] = [:]
    private var executions: [HanlinToolInvocationID: Task<HanlinAISDKToolExecutionOutput, Error>] = [:]

    init(source: @escaping @MainActor () -> (any HanlinOriginalToolSource)?,
         context: @escaping @MainActor (HanlinHostSession) async throws -> HanlinHostContext,
         catalog: @escaping @MainActor (HanlinHostContext) async throws -> HanlinHostCatalog,
         definitionForAlias: @escaping @MainActor (String) -> HanlinAISDKToolDefinition?,
         validateCurrent: @escaping @MainActor (HanlinHostSession) throws -> Void,
         confirmInvocation: @escaping @MainActor (HanlinHostInvocation, HanlinToolApprovalScope) async -> Bool) {
        self.source = source; self.context = context; self.catalog = catalog
        self.definitionForAlias = definitionForAlias; self.validateCurrent = validateCurrent
        self.confirmInvocation = confirmInvocation
    }

    @MainActor private final class ExecutionObservation {
        var outcome: NativeToolExecutionOutcome?
        var enteredExecutor = false
        var denial: HanlinPlatformError?
        var progress: UInt64 = 0
    }

    func execute(_ invocation: HanlinHostInvocation,
                 progress: @escaping HanlinHostProgressHandler) async throws -> HanlinHostExecutionResult {
        let entry: HanlinHostTool
        let definition: HanlinAISDKToolDefinition
        let original: Data
        let deadline: Date
        do {
            _ = try await context(invocation.session)
            guard invocation.expectedRevision == nil else { throw HanlinHostError.unsupportedConditionalWrite }
            let current = try await catalog(invocation.session.context)
            guard current.revision == invocation.request.routingTableRevision,
                  let found = current.tools.first(where: { $0.route.alias == invocation.request.aliasUsed }),
                  found.route.logicalToolID == invocation.request.logicalToolID,
                  found.route.descriptorRevision == invocation.request.descriptorRevision,
                  let foundDefinition = definitionForAlias(invocation.request.aliasUsed),
                  let expiry = invocation.request.deadline, expiry > Date(),
                  let bytes = invocation.originalArgumentsJSON else { throw HanlinHostError.staleContext }
            entry = found; definition = foundDefinition; deadline = expiry; original = bytes
            // MCP must retain the schema from its original wire, and the original adapter
            // must prove the provider projection preserves that exact business schema.
            if source()?.isMCP(entry.route.alias) == true,
               source()?.originalMCPInputSchema(for: entry.route.alias) == nil {
                throw HanlinHostSchemaValidation.Failure.unsupportedSchema
            }
            let plan: HanlinHostSchemaValidation
            if let cached = validationPlans[definition.inputSchemaData] { plan = cached }
            else {
                plan = try HanlinHostSchemaValidation(schemaJSON: definition.inputSchemaData)
                if validationPlans.count >= 8 { validationPlans.removeAll() }
                validationPlans[definition.inputSchemaData] = plan
            }
            try plan.validate(argumentsJSON: original)
            try HanlinHostSchemaValidation.requirePortableProjection(
                originalJSON: original, projected: invocation.request.arguments)
            // Audit the exact existing metadata extraction now and again immediately before the
            // original executor. No replacement metadata parser or alternate business value exists.
            let extraction = ToolInvocationMetadataExtractor.extract(from: String(decoding: original, as: UTF8.self))
            if source()?.isMCP(invocation.request.aliasUsed) == true {
                _ = try MCPClientSession.checkedArguments(extraction.sanitizedArgumentsJSON)
            }
            try HanlinHostSchemaValidation.requireSameValue(originalJSON: original,
                projectedJSON: Data(extraction.sanitizedArgumentsJSON.utf8), removingMetadataKeys: [
                    ToolSchemaDecorator.progressSummaryKey, ToolSchemaDecorator.resultPresentationKey])
            _ = try await context(invocation.session)
            try Task.checkCancellation()
            guard deadline > Date() else { throw HanlinHostError.staleContext }
        } catch { return Self.noDispatch(invocation, error: error) }
        let approvalScope: HanlinToolApprovalScope?
        do {
            approvalScope = try HanlinToolApprovalScopeFactory.scope(for: invocation, tool: entry, source: source())
        } catch { return Self.noDispatch(invocation, error: error) }
        if let approvalScope {
            guard await confirmInvocation(invocation, approvalScope) else {
                return Self.noDispatch(invocation, error: HanlinHostError.denied)
            }
            // The sheet can stay open while selection, source, or deadline changes.
            do {
                try Task.checkCancellation()
                _ = try await context(invocation.session)
                guard deadline > Date() else { throw HanlinHostError.staleContext }
                try requireOriginalRoute(entry, definition: definition, source: source())
            } catch { return Self.noDispatch(invocation, error: error) }
        }
        let observation = ExecutionObservation()
        let callID = invocation.providerCallID
        let adapter = source()
        adapter?.sdkOutcomeHandlers[callID] = { outcome in observation.outcome = outcome }
        adapter?.sdkPreDispatchFailureHandlers[callID] = { error in observation.denial = Self.preDispatchError(error) }
        adapter?.sdkPreDispatchHandlers[callID] = { [weak self] actualArguments in
            do {
                try Task.checkCancellation()
                guard let self, deadline > Date() else {
                    throw HanlinHostError.staleContext
                }
                try self.validateCurrent(invocation.session)
                try self.requireOriginalRoute(entry, definition: definition, source: adapter)
                let currentScope = try HanlinToolApprovalScopeFactory.scope(for: invocation, tool: entry, source: adapter)
                guard currentScope == approvalScope else { throw HanlinHostError.staleContext }
                if let currentScope, !HanlinToolApprovalStore.shared.allows(currentScope) {
                    throw HanlinHostError.denied
                }
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
            adapter?.sdkPreDispatchFailureHandlers[callID] = nil
            executions[invocation.request.id] = nil
        }
        let arguments = String(decoding: original, as: UTF8.self)
        let task = Task {
            try Task.checkCancellation()
            _ = try await context(invocation.session)
            try Task.checkCancellation()
            guard deadline > Date() else { throw HanlinHostError.staleContext }
            try requireOriginalRoute(entry, definition: definition, source: adapter)
            // Metadata tools have no prepared business executor; their existing implementation
            // is read-only. All general operations mark entry at the adapter's actual boundary.
            if entry.writeGuarantee == .readOnly { observation.enteredExecutor = true }
            return try await SkillRuntimeAuthorization.$approved.withValue(approvalScope != nil) {
                try await definition.execute(arguments, callID)
            }
        }
        executions[invocation.request.id] = task
        let output: HanlinAISDKToolExecutionOutput
        do {
            output = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
        } catch {
            if !observation.enteredExecutor { return Self.noDispatch(invocation, error: error) }
            let uncertain = entry.writeGuarantee != .readOnly
            return .init(result: .init(invocationID: invocation.request.id, logicalToolID: invocation.request.logicalToolID,
                outcome: .failed(.init(code: .nativeFailure, userMessage: uncertain
                    ? "The operation outcome is uncertain. Do not retry automatically." : "The host operation failed.")),
                completedAt: .now), effectState: uncertain ? .uncertain : .confirmedNoEffect,
                context: invocation.session.context, reconciliationReference: uncertain ? invocation.request.id.rawValue : nil)
        }
        if let denial = observation.denial { return Self.noDispatch(invocation, error: denial) }
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
                                      source adapter: (any HanlinOriginalToolSource)?) throws {
        guard let adapter, source().map(ObjectIdentifier.init) == ObjectIdentifier(adapter),
              let current = try adapter.allToolDefinitions().first(where: { $0.name == entry.route.alias }),
              current.inputSchemaData == definition.inputSchemaData else { throw HanlinHostError.staleContext }
        if let descriptor = adapter.descriptor(for: entry.route.alias) {
            guard descriptor.logicalID == entry.route.logicalToolID,
                  descriptor.descriptorRevision == entry.route.descriptorRevision else { throw HanlinHostError.staleContext }
        } else {
            guard entry.route.logicalToolID.providerInstanceID.rawValue == "hanlin.meta",
                  entry.writeGuarantee == .readOnly else { throw HanlinHostError.staleContext }
        }
    }

    static func preDispatchError(_ error: Error) -> HanlinPlatformError {
        if let error = error as? HanlinPlatformError { return error }
        let code: HanlinErrorCode
        let message: String
        switch error {
        case is CancellationError:
            code = .cancelled
            message = "The operation was cancelled before dispatch."
        case HanlinHostError.denied:
            code = .permissionDenied
            message = "The operation was not approved, or its approval expired. Do not retry it automatically."
        case HanlinHostSchemaValidation.Failure.invalidArguments, HanlinHostError.invalidArguments:
            code = .invalidArguments
            message = "The arguments do not match the tool's input schema. Read the current tool schema and correct the arguments before retrying."
        case HanlinHostSchemaValidation.Failure.lossyProjection:
            code = .schemaProjectionWidensInput
            message = "The tool input cannot be preserved exactly by the current adapter. Repeating the same call will not resolve this."
        case HanlinHostSchemaValidation.Failure.inputTooLarge:
            code = .sizeLimitExceeded
            message = "The tool input exceeds the supported size. Use a smaller input or the tool's supported file reference."
        case HanlinHostSchemaValidation.Failure.unsupportedSchema:
            code = .unsupportedSchemaKeyword
            message = "The original tool schema is unavailable or unsupported. Refresh the available tools before continuing."
        case HanlinHostError.staleContext:
            code = .operationUnavailable
            message = "The conversation, tool catalog, or request deadline changed before dispatch. Continue only with a fresh request in the current conversation."
        default:
            code = .operationUnavailable
            message = "The original operation input or context could not be verified."
        }
        return .init(code: code, userMessage: message + " No operation was dispatched.")
    }

    static func noDispatch(_ invocation: HanlinHostInvocation, error: Error) -> HanlinHostExecutionResult {
        .init(result: .init(invocationID: invocation.request.id, logicalToolID: invocation.request.logicalToolID,
            outcome: .failed(Self.preDispatchError(error)), completedAt: .now), effectState: .notDispatched,
            context: invocation.session.context)
    }

    func cancel(_ invocation: HanlinToolInvocationID) { executions[invocation]?.cancel() }

    func revoke() { for execution in executions.values { execution.cancel() } }

}
