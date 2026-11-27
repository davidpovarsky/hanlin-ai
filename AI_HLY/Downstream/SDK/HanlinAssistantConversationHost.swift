import Foundation
import HanlinAgentCore
import HanlinChatCore
import HanlinHostContracts
import HanlinPlatformContracts

/// Embeds the original assistant services beside an application's own catalog.
/// Tool policy and execution remain in HanlinOriginalToolExecution; native host
/// actions remain with their original host and are never dispatched here.
@MainActor
public final class HanlinAssistantConversationHost: HanlinHostIntegration, HanlinHostCapabilitySource {
    public nonisolated let apiVersion = HanlinAPIVersion(major: 1, minor: 1)
    public let identity: HanlinHostSession
    public let consent: HanlinAppToolConsent
    private let validateOwner: @MainActor @Sendable () throws -> Void
    private var revoked = false
    private var requestID: UUID?
    private var session: AssistantCapabilitySession
    private var tools: HanlinAssistantToolSource?
    private var definitions: [String: HanlinAISDKToolDefinition] = [:]
    private var originalCatalog: HanlinHostCatalog?
    private lazy var execution = HanlinOriginalToolExecution(
        source: { [weak self] in self?.tools },
        context: { [weak self] session in
            guard let self else { throw HanlinHostError.staleContext }
            return try await self.context(for: session)
        },
        catalog: { [weak self] context in
            guard let self else { throw HanlinHostError.staleContext }
            return try await self.catalog(for: context)
        },
        definitionForAlias: { [weak self] alias in self?.definitions[alias] },
        validateCurrent: { [weak self] identity in
            guard let self, identity == self.identity, self.requestID != nil else { throw HanlinHostError.staleContext }
            try self.requireCurrent()
        },
        confirmInvocation: { [weak self] invocation, scope in
            guard let self, (try? self.requireCurrent()) != nil else { return false }
            return await self.consent.request(invocation, approvalScope: scope)
        })

    init(identity: HanlinHostSession,
         validateCurrent: @escaping @MainActor @Sendable () throws -> Void,
         consent: HanlinAppToolConsent) {
        self.identity = identity
        self.validateOwner = validateCurrent
        self.consent = consent
        self.session = AssistantCapabilitySession(chatID: identity.conversationID.uuidString)
    }

    /// Freezes this request's selections. Previous full-result references stay
    /// in the original conversation result store; exposures and instructions do not.
    public func beginRequest(hostCatalog: HanlinHostCatalog,
                             attachments: [HanlinCapabilityAttachment] = []) async throws {
        try requireCurrent()
        guard requestID == nil, hostCatalog.context == identity.context else { throw HanlinHostError.staleContext }
        try hostCatalog.validate()
        let id = UUID()
        requestID = id
        session.reset()
        session = AssistantCapabilitySession(chatID: identity.conversationID.uuidString,
            resultStore: session.resultStore, capabilityAttachments: attachments)
        do {
            let source = HanlinAssistantToolSource(identity: identity, session: session,
                hostCatalog: hostCatalog, validateCurrent: { [weak self] in
                    guard let self, self.requestID == id else { throw HanlinHostError.staleContext }
                    try self.requireCurrent()
                })
            try await source.prepare()
            try requireCurrent()
            guard requestID == id else { throw HanlinHostError.staleContext }
            let projection = try HanlinOriginalToolCatalog.make(source: source, context: identity.context)
            guard Set(hostCatalog.tools.map { $0.route.alias }).isDisjoint(with: projection.definitions.keys) else {
                throw HanlinHostError.duplicateAlias
            }
            tools = source
            definitions = projection.definitions
            originalCatalog = projection.catalog
        } catch {
            if requestID == id { finishRequest() }
            throw error
        }
    }

    public func capabilityCatalog() throws -> [HanlinComposerCapabilityDescriptor] {
        try requireCurrent()
        return HanlinComposerCapabilities.assistantCatalog()
    }

    /// Cancels only this request's workers and live consent. Shared process
    /// runtimes and the conversation's original result history remain owned.
    public func finishRequest() {
        requestID = nil
        consent.revoke()
        execution.revoke()
        session.finishRun()
        session.reset()
        tools = nil
        definitions.removeAll()
        originalCatalog = nil
    }

    /// A closed or rebound owner can never be reused by a retained sheet/run.
    public func revoke() {
        revoked = true
        finishRequest()
    }

    public func context(for session: HanlinHostSession) async throws -> HanlinHostContext {
        try requireCurrent()
        guard session == identity else { throw HanlinHostError.staleContext }
        return identity.context
    }

    public func catalog(for context: HanlinHostContext) async throws -> HanlinHostCatalog {
        try requireCurrent()
        guard context == identity.context else { throw HanlinHostError.staleContext }
        if let originalCatalog { return originalCatalog }
        return try HanlinOriginalToolCatalog.make(source: nil, context: context).catalog
    }

    public func prepareStep(_ step: Int, session: HanlinHostSession) async throws -> HanlinHostStepPreparation {
        _ = try await context(for: session)
        guard let tools, requestID != nil else { throw HanlinHostError.staleContext }
        let prepared = try await tools.prepareStep()
        _ = try await context(for: session)
        guard self.tools === tools else { throw HanlinHostError.staleContext }
        return prepared
    }

    public func execute(_ invocation: HanlinHostInvocation,
                        progress: @escaping HanlinHostProgressHandler) async throws -> HanlinHostExecutionResult {
        try await execution.execute(invocation, progress: progress)
    }

    public func cancel(_ invocation: HanlinToolInvocationID) async { execution.cancel(invocation) }

    public func open(_ destination: HanlinHostDestination) async throws -> HanlinHostNavigationResult {
        try requireCurrent()
        throw HanlinHostError.unsupportedProviderCapability
    }

    private func requireCurrent() throws {
        guard !revoked else { throw HanlinHostError.staleContext }
        try validateOwner()
    }
}

/// Supplies original implementations to the shared original dispatch boundary.
/// It contains no MCP transport, Skill runtime, grant store or result store.
@MainActor
private final class HanlinAssistantToolSource: HanlinOriginalToolSource {
    let catalogGeneration = UUID()
    let identity: HanlinHostSession
    let session: AssistantCapabilitySession
    let hostCatalog: HanlinHostCatalog
    let validateCurrent: @MainActor @Sendable () throws -> Void
    private var mcpTools: [String: MCPToolDescriptor] = [:]
    private var descriptors: [String: HanlinToolDescriptor] = [:]
    private var definitions: [HanlinAISDKToolDefinition] = []
    var sdkProgressHandlers: [String: @MainActor @Sendable (String) -> Void] = [:]
    var sdkPreDispatchHandlers: [String: @MainActor @Sendable (String) throws -> Void] = [:]
    var sdkPreDispatchFailureHandlers: [String: @MainActor @Sendable (Error) -> Void] = [:]
    var sdkOutcomeHandlers: [String: @MainActor @Sendable (NativeToolExecutionOutcome) -> Void] = [:]

    init(identity: HanlinHostSession, session: AssistantCapabilitySession,
         hostCatalog: HanlinHostCatalog, validateCurrent: @escaping @MainActor @Sendable () throws -> Void) {
        self.identity = identity; self.session = session
        self.hostCatalog = hostCatalog; self.validateCurrent = validateCurrent
    }

    func prepare() async throws {
        try validateCurrent()
        let original = await MCPRuntimeProvider.shared.requestScope(chatID: identity.conversationID, temporary: false)
        try validateCurrent()
        let scope = try HanlinComposerCapabilities.scope(original, attachments: session.capabilityAttachments)
        let available = await MCPToolBridge.resolveDescriptors(scope: scope)
        try validateCurrent()
        guard Set(available.map(\.exposedName)).count == available.count else { throw HanlinHostError.duplicateAlias }
        mcpTools = Dictionary(uniqueKeysWithValues: available.map { ($0.exposedName, $0) })
        descriptors = try Dictionary(uniqueKeysWithValues: available.map {
            ($0.exposedName, try MCPCanonicalShadowAdapter.projectTool($0, descriptorRevision: .init(1)))
        })
        definitions = try [LoadSkillTool.schema, ReadSkillResourceTool.schema,
            ToolSearchTool.schema, ReadToolResultTool.schema, SkillResourceExecutor.schema].map(makeDefinition)
        let skill = definitions.first { $0.name == SkillResourceExecutor.toolName }!
        descriptors[SkillResourceExecutor.toolName] = try HanlinToolDescriptor(
            logicalID: .init(providerInstanceID: .init(validating: "native.system"),
                localToolID: .init(validating: SkillResourceExecutor.toolName)),
            descriptorRevision: .init(1), owner: .system,
            title: .init(["en": "Execute Skill Resource"]),
            summary: .init(["en": skill.description]),
            inputSchema: HanlinJSONSchemaDocument.decodeCanonicalJSON(skill.inputSchemaData, defaultDialect: .draft2020_12),
            risk: .write, approval: .init(requiresApproval: true, scopeParameters: ["skill_id", "relative_path"]))
        for tool in available.sorted(by: { $0.exposedName < $1.exposedName }) {
            // Keep the exact original wire schema. The original dispatch core
            // refuses MCP definitions whose wire provenance was not verified.
            definitions.append(.init(name: tool.exposedName,
                description: "[\(tool.serverDisplayName)] \(tool.summary ?? tool.title ?? tool.originalName)",
                inputSchemaData: tool.inputSchemaJSON,
                execute: { [weak self] arguments, callID in
                    guard let self else { throw HanlinHostError.staleContext }
                    return try await self.executeMCP(tool, arguments: arguments, callID: callID)
                }))
        }
        guard Set(definitions.map(\.name)).count == definitions.count else { throw HanlinHostError.duplicateAlias }
        guard Set(hostCatalog.tools.map { $0.route.alias }).isDisjoint(with: definitions.map(\.name)) else {
            throw HanlinHostError.duplicateAlias
        }
        session.syncMCPTools(activeMCPAliases: Array(mcpTools.keys))
        try await prepareSelections()
    }

    func allToolDefinitions() throws -> [HanlinAISDKToolDefinition] { definitions }
    func descriptor(for alias: String) -> HanlinToolDescriptor? { descriptors[alias] }
    func isMCP(_ alias: String) -> Bool { mcpTools[alias] != nil }
    func originalMCPInputSchema(for alias: String) -> Data? {
        guard let tool = mcpTools[alias], tool.originalInputSchemaVerified == true else { return nil }
        return tool.inputSchemaJSON
    }
    func mcpServerID(for alias: String) -> UUID? { mcpTools[alias]?.serverID }

    func prepareStep() async throws -> HanlinHostStepPreparation {
        try validateCurrent()
        try await prepareSelections()
        let visible = await HanlinSkillCatalog.shared.modelVisibleSkills(store: .shared)
        await session.retainCurrentlyEligibleSkills(modelSkills: visible)
        try validateCurrent()
        let active = AssistantToolExposurePlanner.activeAliases(session: session,
            sizes: schemaSizes, mcpAliases: Array(mcpTools.keys))
        return .init(activeAliases: Array(Set(active + hostCatalog.tools.map { $0.route.alias })).sorted(),
            skillIDs: session.loadedSkillIDs.map(\.rawValue).sorted(), instructions: [HanlinSkillIndex.formattedIndex(skills: visible)] + session.stepInstructions)
    }

    private var schemaSizes: [String: Int] {
        Dictionary(uniqueKeysWithValues: definitions.map { ($0.name, $0.inputSchemaData.count) }
            + hostCatalog.tools.map { ($0.route.alias, $0.originalInputSchemaJSON?.count ?? 400) })
    }

    private func prepareSelections() async throws {
        try await session.prepareExplicitSelections(availableAliases: Set(schemaSizes.keys),
            resolveAliases: { [mcpTools] attachment in
                guard attachment.reference.kind == .mcp else { return [] }
                return mcpTools.values.filter {
                    $0.serverID.uuidString.lowercased() == attachment.reference.sourceID.lowercased()
                    && (attachment.reference.capabilityID == "*" || attachment.reference.capabilityID == $0.originalName)
                }.map(\.exposedName).sorted()
            })
        try validateCurrent()
    }

    private func makeDefinition(_ schema: [String: Any]) throws -> HanlinAISDKToolDefinition {
        guard let function = schema["function"] as? [String: Any],
              let name = function["name"] as? String,
              let parameters = function["parameters"] as? [String: Any] else { throw HanlinHostError.invalidArguments }
        let bytes = try JSONSerialization.data(withJSONObject: parameters, options: [.sortedKeys])
        return .init(name: name, description: function["description"] as? String ?? "", inputSchemaData: bytes,
            execute: { [weak self] arguments, callID in
                guard let self else { throw HanlinHostError.staleContext }
                return try await self.executeOriginal(name, arguments: arguments, callID: callID)
            })
    }

    private func executeOriginal(_ name: String, arguments: String, callID: String) async throws -> HanlinAISDKToolExecutionOutput {
        try validateCurrent()
        let value = ToolInvocationMetadataExtractor.extract(from: arguments).sanitizedArgumentsJSON
        let text: String
        switch name {
        case LoadSkillTool.toolName:
            text = await LoadSkillTool.execute(argumentsJSON: value, session: session,
                schemaSizes: schemaSizes, availableAliases: Set(schemaSizes.keys))
        case ReadSkillResourceTool.toolName:
            text = await ReadSkillResourceTool.execute(argumentsJSON: value, session: session)
        case ToolSearchTool.toolName:
            text = ToolSearchTool.execute(argumentsJSON: value, session: session) { query, limit, offset, preferred in
                CanonicalToolSearchRecord.search(searchRecords, query: query, limit: limit,
                    offset: offset, preferredAliases: preferred)
            }
        case ReadToolResultTool.toolName:
            text = ReadToolResultTool.execute(argumentsJSON: value, session: session)
        case SkillResourceExecutor.toolName:
            let result = await RuntimeJobProgress.$reporter.withValue({ [weak self] job in
                guard let self else { return }
                let message = "Job \(job.executionID.uuidString.prefix(8)) · \(job.state.rawValue) · stdout \(job.stdoutBytes) B · stderr \(job.stderrBytes) B"
                self.sdkProgressHandlers[callID]?(message)
            }) {
                await SkillResourceExecutor().execute(argumentsJSON: value, session: session,
                    beforeDispatch: { [weak self] in
                        guard let self else { throw HanlinHostError.staleContext }
                        do {
                            try self.validateCurrent()
                            try self.sdkPreDispatchHandlers[callID]?(value)
                        } catch {
                            self.sdkPreDispatchFailureHandlers[callID]?(error)
                            throw error
                        }
                    })
            }
            sdkOutcomeHandlers[callID]?(result.outcome)
            return HanlinOriginalToolResultStorage.prepare(result, session: session).output(isError: !result.outcome.isSuccess)
        default: throw HanlinHostError.unknownTool
        }
        try validateCurrent()
        return .init(modelText: text, isError: text.hasPrefix("Error:"))
    }

    private func executeMCP(_ tool: MCPToolDescriptor, arguments: String, callID: String) async throws -> HanlinAISDKToolExecutionOutput {
        let value = ToolInvocationMetadataExtractor.extract(from: arguments).sanitizedArgumentsJSON
        let result = await MCPToolBridge.execute(serverID: tool.serverID, toolName: tool.originalName,
            resultTitle: tool.title ?? tool.originalName, argumentsJSON: value, expectedDescriptor: tool,
            beforeDispatch: { [weak self] in
                guard let self else { throw HanlinHostError.staleContext }
                do { try await self.validateMCPDispatch(tool, arguments: value, callID: callID) }
                catch {
                    await self.reportPreDispatchFailure(error, callID: callID)
                    throw error
                }
            })
        sdkOutcomeHandlers[callID]?(result.outcome)
        return HanlinOriginalToolResultStorage.prepare(result, session: session).output(isError: !result.outcome.isSuccess)
    }

    private func validateMCPDispatch(_ tool: MCPToolDescriptor, arguments: String, callID: String) async throws {
        try validateCurrent()
        let original = await MCPRuntimeProvider.shared.requestScope(chatID: identity.conversationID, temporary: false)
        try validateCurrent()
        let current = try HanlinComposerCapabilities.scope(original, attachments: session.capabilityAttachments)
        guard current.mcpGloballyEnabled, current.mcpServerIDs.contains(tool.serverID),
              mcpTools[tool.exposedName] == tool else { throw HanlinHostError.staleContext }
        try sdkPreDispatchHandlers[callID]?(arguments)
    }

    private func reportPreDispatchFailure(_ error: Error, callID: String) {
        sdkPreDispatchFailureHandlers[callID]?(error)
    }

    private var searchRecords: [CanonicalToolSearchRecord] {
        var result = hostCatalog.tools.map { tool in
            CanonicalToolSearchRecord(alias: tool.route.alias, title: tool.descriptor.title.preferredValue(),
                summary: tool.descriptor.summary.preferredValue(), source: tool.route.logicalToolID.providerInstanceID.rawValue,
                schemaSizeBytes: tool.originalInputSchemaJSON?.count ?? 400)
        }
        result += definitions.compactMap { definition in
            guard let descriptor = descriptors[definition.name] else { return nil }
            return CanonicalToolSearchRecord(alias: definition.name, title: descriptor.title.preferredValue(),
                summary: descriptor.summary.preferredValue(), source: descriptor.logicalID.providerInstanceID.rawValue,
                schemaSizeBytes: definition.inputSchemaData.count)
        }
        return result
    }
}
