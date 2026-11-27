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
    var splitCoordinator = HanlinAppSplitOriginCoordinator.shared
    weak var splitSession: HanlinAgentSession?
    var splitRowReference: (@MainActor @Sendable () -> HanlinAppAgentRowReference?)?
    var toolAdapter: HanlinAISDKToolAdapter?
    var confirmInvocation: (@MainActor @Sendable (HanlinHostInvocation, HanlinToolApprovalScope) async -> Bool)?
    private let store: HanlinAppConversationStore
    private let isCurrent: @MainActor @Sendable () -> Bool
    private var definitions: [String: HanlinAISDKToolDefinition] = [:]
    private struct CatalogCache {
        let adapterID: ObjectIdentifier?
        let generation: UUID?
        let includesSplit: Bool
        let catalog: HanlinHostCatalog
    }
    private var catalogCache: CatalogCache?
    private lazy var originalExecution = HanlinOriginalToolExecution(
        source: { [weak self] in self?.toolAdapter },
        context: { [weak self] session in
            guard let self else { throw HanlinHostError.staleContext }
            return try await self.context(for: session)
        },
        catalog: { [weak self] context in
            guard let self else { throw HanlinHostError.staleContext }
            return try await self.catalog(for: context)
        },
        definitionForAlias: { [weak self] alias in self?.definitions[alias] },
        validateCurrent: { [weak self] session in
            guard let self, self.isCurrent(), session == self.identity else { throw HanlinHostError.staleContext }
            _ = try self.store.requireOriginalConversation()
        },
        confirmInvocation: { [weak self] invocation, scope in
            guard let confirm = self?.confirmInvocation else { return false }
            return await confirm(invocation, scope)
        })

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
        let adapterID = toolAdapter.map(ObjectIdentifier.init)
        let generation = toolAdapter?.catalogGeneration
        let includesSplit = supportsSplit
        if let cached = catalogCache, cached.adapterID == adapterID,
           cached.generation == generation, cached.includesSplit == includesSplit {
            return cached.catalog
        }
        guard !(try toolAdapter?.allToolDefinitions().contains { $0.name == Self.splitAlias } ?? false) else {
            throw HanlinHostError.duplicateAlias
        }
        let projection = try HanlinOriginalToolCatalog.make(source: toolAdapter, context: context,
            additionalTools: includesSplit ? [try Self.splitTool()] : [])
        let catalog = projection.catalog
        definitions = projection.definitions
        catalogCache = .init(adapterID: adapterID, generation: generation,
                             includesSplit: includesSplit, catalog: catalog)
        return catalog
    }

    func prepareStep(_ step: Int, session: HanlinHostSession) async throws -> HanlinHostStepPreparation {
        _ = try await context(for: session)
        guard let toolAdapter else { return .init(activeAliases: []) }
        try await toolAdapter.session.prepareExplicitSelections(using: toolAdapter.preparedTools,
            catalog: toolAdapter.catalog, store: toolAdapter.skillStore)
        let prepared = await toolAdapter.prepareStep(stepNumber: step)
        _ = try await context(for: session)
        return .init(activeAliases: prepared.activeToolAliases + (!supportsSplit || prepared.activeToolAliases.contains(Self.splitAlias) ? [] : [Self.splitAlias]), skillIDs: prepared.loadedSkillIDs,
            instructions: prepared.loadedSkillInstructions)
    }

    func execute(_ invocation: HanlinHostInvocation,
                 progress: @escaping HanlinHostProgressHandler) async throws -> HanlinHostExecutionResult {
        if invocation.request.aliasUsed == Self.splitAlias {
            do {
                _ = try await context(for: invocation.session)
                let current = try await catalog(for: invocation.session.context)
                guard invocation.expectedRevision == nil, current.revision == invocation.request.routingTableRevision,
                      let entry = current.tools.first(where: { $0.route.alias == Self.splitAlias }),
                      entry.route.logicalToolID == invocation.request.logicalToolID,
                      entry.route.descriptorRevision == invocation.request.descriptorRevision,
                      let splitSession, splitSession.identity == invocation.session,
                      let row = splitRowReference?(),
                      let deadline = invocation.request.deadline, deadline > Date() else { throw HanlinHostError.staleContext }
                // External-app effects require the same scoped manifest consent.
                guard let approvalScope = try HanlinToolApprovalScopeFactory.scope(for: invocation, tool: entry, adapter: toolAdapter),
                      let confirmInvocation, await confirmInvocation(invocation, approvalScope) else { throw HanlinHostError.denied }
                try Task.checkCancellation()
                _ = try await context(for: invocation.session)
                guard deadline > Date(), splitRowReference?() == row,
                      (try await catalog(for: invocation.session.context)).revision == current.revision,
                      try HanlinToolApprovalScopeFactory.scope(for: invocation, tool: entry, adapter: toolAdapter) == approvalScope,
                      HanlinToolApprovalStore.shared.allows(approvalScope) else { throw HanlinHostError.staleContext }
                return try await splitCoordinator.execute(invocation, host: self, session: splitSession, row: row)
            } catch { return noDispatch(invocation, error: error) }
        }
        return try await originalExecution.execute(invocation, progress: progress)
    }

    private func noDispatch(_ invocation: HanlinHostInvocation, error: Error) -> HanlinHostExecutionResult {
        HanlinOriginalToolExecution.noDispatch(invocation, error: error)
    }

    func cancel(_ invocation: HanlinToolInvocationID) async { originalExecution.cancel(invocation) }

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
