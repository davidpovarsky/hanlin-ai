import Foundation

/// Deterministic policy planner for exposing tool schemas to the model.
/// Evaluates serialized model-schema byte cost against a strict budget
/// rather than blindly exposing all preferred tools.
public struct AssistantToolExposurePlanner: Sendable {
    /// Maximum serialized schema byte budget for directly exposed tools upon loading a skill.
    /// Tools exceeding this budget remain deferred to `tool_search`.
    public static let defaultSchemaByteBudget: Int = 4096

    public let maxSchemaBytes: Int

    public init(maxSchemaBytes: Int = defaultSchemaByteBudget) {
        self.maxSchemaBytes = maxSchemaBytes
    }

    public struct PlanningDecision: Equatable, Sendable {
        public let exposedAliases: [String]
        public let deferredAliases: [String]
        public let totalExposedBytes: Int
        public let totalDeferredBytes: Int
    }

    /// Evaluates candidate tool aliases against the schema byte budget.
    /// Uses schemas from `authority` or size proxy.
    public func plan(
        candidateAliases: [String],
        schemaSizes: [String: Int]
    ) -> PlanningDecision {
        var exposed: [String] = []
        var deferred: [String] = []
        var currentBytes = 0

        // Calculate total candidate bytes
        let totalCandidateBytes = candidateAliases.reduce(0) { $0 + (schemaSizes[$1] ?? 600) }

        if totalCandidateBytes <= maxSchemaBytes {
            // Fits within budget: expose all candidates directly
            return PlanningDecision(
                exposedAliases: candidateAliases,
                deferredAliases: [],
                totalExposedBytes: totalCandidateBytes,
                totalDeferredBytes: 0
            )
        } else {
            // Exceeds budget: keep tools deferred to tool_search
            var remainingDeferredBytes = 0
            for alias in candidateAliases {
                let bytes = schemaSizes[alias] ?? 600
                deferred.append(alias)
                remainingDeferredBytes += bytes
            }
            return PlanningDecision(
                exposedAliases: [],
                deferredAliases: deferred,
                totalExposedBytes: 0,
                totalDeferredBytes: remainingDeferredBytes
            )
        }
    }
}
