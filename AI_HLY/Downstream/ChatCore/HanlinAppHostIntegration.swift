import CryptoKit
import Foundation
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
            let readOnly = [HanlinRiskLevel.passive, .read, .sensitiveRead].contains(descriptor.risk)
            return .init(route: .init(alias: definition.name, logicalToolID: logical, descriptorRevision: revision),
                descriptor: descriptor, writeGuarantee: readOnly ? .readOnly : .hostManagedMutation)
        }
        // JSON dictionaries must be canonical before hashing or unchanged schemas spuriously
        // change the catalog generation. No process-random Hasher is used for public revision.
        let canonicalTools = try tools.map { tool in HanlinJSONValue.object([
            "alias": .string(tool.route.alias),
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
        var progress: UInt64 = 0
    }

    func execute(_ invocation: HanlinHostInvocation,
                 progress: @escaping @Sendable (HanlinToolProgressEvent) async -> Void) async throws -> HanlinHostExecutionResult {
        _ = try await context(for: invocation.session)
        guard invocation.expectedRevision == nil else { throw HanlinHostError.unsupportedConditionalWrite }
        let current = try await catalog(for: invocation.session.context)
        guard current.revision == invocation.request.routingTableRevision,
              let entry = current.tools.first(where: { $0.route.alias == invocation.request.aliasUsed }),
              entry.route.logicalToolID == invocation.request.logicalToolID,
              entry.route.descriptorRevision == invocation.request.descriptorRevision,
              let definition = definitions[invocation.request.aliasUsed],
              let deadline = invocation.request.deadline, deadline > Date() else { throw HanlinHostError.staleContext }
        try Task.checkCancellation()
        let observation = ExecutionObservation()
        let callID = invocation.providerCallID
        let adapter = toolAdapter
        adapter?.sdkOutcomeHandlers[callID] = { outcome in observation.outcome = outcome }
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
            executions[invocation.request.id] = nil
        }
        let arguments = String(decoding: try invocation.request.arguments.canonicalJSONData(), as: UTF8.self)
        let task = Task { try await definition.execute(arguments, callID) }
        executions[invocation.request.id] = task
        let output = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
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
