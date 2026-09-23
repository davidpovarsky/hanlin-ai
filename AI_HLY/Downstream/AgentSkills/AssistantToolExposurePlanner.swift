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
            if currentBytes + bytes <= maxSchemaBytes {
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
