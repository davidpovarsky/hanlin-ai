import Foundation

/// Deterministic policy planner for exposing tool schemas to the model.
/// Evaluates serialized model-schema byte cost against an optional caller budget
/// rather than blindly exposing all preferred tools.
public struct AssistantToolExposurePlanner: Sendable {
    /// Maximum serialized schema byte budget for directly exposed tools upon loading a skill.
    /// Tools exceeding this budget remain deferred to `tool_search`.
    public static let defaultSchemaByteBudget: Int? = nil

    public let maxSchemaBytes: Int?

    public init(maxSchemaBytes: Int? = defaultSchemaByteBudget) {
        self.maxSchemaBytes = maxSchemaBytes
    }

    public struct PlanningDecision: Equatable, Sendable {
        public let exposedAliases: [String]
        public let deferredAliases: [String]
        public let totalExposedBytes: Int
        public let totalDeferredBytes: Int

        public init(
            exposedAliases: [String],
            deferredAliases: [String],
            totalExposedBytes: Int,
            totalDeferredBytes: Int
        ) {
            self.exposedAliases = exposedAliases
            self.deferredAliases = deferredAliases
            self.totalExposedBytes = totalExposedBytes
            self.totalDeferredBytes = totalDeferredBytes
        }
    }

    /// Evaluates candidate tool aliases against the schema byte budget.
    /// Uses schemas from `authority` or size proxy.
    public func plan(
        candidateAliases: [String],
        schemaSizes: [String: Int],
        currentlyExposedAliases: Set<String> = []
    ) -> PlanningDecision {
        var exposed: [String] = []
        var deferred: [String] = []
        var currentBytes = currentlyExposedAliases.reduce(0) { $0 + (schemaSizes[$1] ?? 600) }

        for alias in candidateAliases {
            if currentlyExposedAliases.contains(alias) {
                exposed.append(alias)
                continue
            }
            let bytes = schemaSizes[alias] ?? 600
            // DISC-02 / DISC-03: No starvation for single tool exceeding budget, and default allows all preferred tools.
            if (maxSchemaBytes.map({ currentBytes + bytes <= $0 }) ?? true) || (exposed.isEmpty && currentBytes == 0) {
                exposed.append(alias)
                currentBytes += bytes
            } else {
                deferred.append(alias)
            }
        }

        let totalDeferredBytes = deferred.reduce(0) { $0 + (schemaSizes[$1] ?? 600) }

        return PlanningDecision(
            exposedAliases: exposed,
            deferredAliases: deferred,
            totalExposedBytes: currentBytes,
            totalDeferredBytes: totalDeferredBytes
        )
    }
}

extension AssistantToolExposurePlanner {
    /// Original per-step ordering and optional schema budget from the native
    /// adapter, also used when original services are embedded by another host.
    @MainActor
    static func activeAliases(session: AssistantCapabilitySession,
                              sizes: [String: Int], mcpAliases: [String],
                              supportsReportProgress: Bool = false,
                              maxActiveStepSchemaBytes: Int? = nil) -> [String] {
        var aliases: [String] = [
            LoadSkillTool.toolName,
            ReadSkillResourceTool.toolName,
            ToolSearchTool.toolName,
            ReadToolResultTool.toolName
        ]
        if supportsReportProgress {
            aliases.append(ToolSchemaDecorator.reportProgressName)
        }

        var currentBytes = aliases.reduce(0) { $0 + (sizes[$1] ?? 350) }

        // Priority order for exposed tools:
        // 1. Capabilities explicitly attached to this request
        // 2. Active MCP server tools (mcp__*)
        // 3. Most recently discovered tools via tool_search (reversed)
        // 4. Active skill preferred tool hints and remaining exposed tools
        var prioritizedCandidates: [String] = []
        prioritizedCandidates.append(contentsOf: session.explicitlySelectedToolAliases.sorted())
        for alias in mcpAliases.sorted() where session.exposedToolAliases.contains(alias) {
            if !prioritizedCandidates.contains(alias) {
                prioritizedCandidates.append(alias)
            }
        }
        for alias in session.discoveredToolAliases.reversed() where session.exposedToolAliases.contains(alias) {
            if !prioritizedCandidates.contains(alias) {
                prioritizedCandidates.append(alias)
            }
        }
        for alias in session.activeSkillToolHints.sorted() where session.exposedToolAliases.contains(alias) {
            if !prioritizedCandidates.contains(alias) {
                prioritizedCandidates.append(alias)
            }
        }
        for alias in session.exposedToolAliases.sorted() {
            if !prioritizedCandidates.contains(alias) {
                prioritizedCandidates.append(alias)
            }
        }

        for alias in prioritizedCandidates {
            guard sizes[alias] != nil,
                  !aliases.contains(alias) else {
                continue
            }
            let toolBytes = sizes[alias] ?? 400
            if let budget = maxActiveStepSchemaBytes, currentBytes + toolBytes > budget && aliases.count > 6,
               !session.explicitlySelectedToolAliases.contains(alias) {
                continue
            }
            aliases.append(alias)
            currentBytes += toolBytes
        }
        return aliases
    }
}
