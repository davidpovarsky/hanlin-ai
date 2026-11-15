import Foundation

/// Pure assessment: no services, filesystem, imports, installation or execution.
/// An upstream adapter selects one explicit engine before assessment. Failed
/// execution never causes this planner to try an alternative engine.
enum SkillRuntimePlanner {
    typealias C = SkillRuntimeContract

    static func evaluate(
        action: C.Action,
        engineFacts: C.EngineFacts?,
        lastTest: C.ExecutionTest? = nil,
        freshness: C.Freshness
    ) -> C.ExecutionPlan {
        var issues: [C.Issue] = []
        var missing: [C.SkillRequirement] = []
        var remediation: [C.RemediationHandle] = []
        var availableCount = 0
        var hasUnknown = false
        var hasUnsupported = false
        var binding: C.EngineBinding?
        var matchingTest: C.ExecutionTest?

        func issue(_ code: C.Issue.Code, _ requirement: C.SkillRequirement? = nil) {
            issues.append(.init(code: code, requirementID: requirement?.id))
        }
        func finish(_ readiness: C.Readiness) -> C.ExecutionPlan {
            .init(schemaVersion: 1, action: action, selectedEngine: action.engineID,
                  binding: binding, readiness: readiness, issues: issues,
                  missingRequirements: missing, remediation: remediation,
                  lastTest: matchingTest, evaluatedAt: freshness.now)
        }

        guard !action.id.isEmpty, !action.skillID.isEmpty, !action.environmentID.isEmpty,
              isSHA256(action.sourceFingerprint), isSHA256(action.actionFingerprint),
              action.invocationFingerprint.map(isSHA256) ?? true,
              freshness.notBefore <= freshness.now else {
            issue(.invalidIdentity)
            return finish(.unknown)
        }
        guard action.requirementsComplete else {
            issue(.incompleteRequirements)
            return finish(.unknown)
        }
        // Instruction-only content needs no engine, but contradictory runtime
        // requirements cannot be silently discarded by this action label.
        if action.kind == .instructions {
            guard action.engineID == nil && action.requirements.isEmpty else {
                issue(.unknownRequirement)
                return finish(.unknown)
            }
            return finish(.verified)
        }
        guard let engineID = action.engineID else {
            issue(.missingEngineSelection)
            return finish(.unknown)
        }
        guard let engineFacts, engineFacts.engineID == engineID else {
            issue(.unregisteredEngine)
            return finish(.unsupported)
        }
        guard let observedBinding = engineFacts.binding,
              observedBinding.engineID == engineID,
              observedBinding.environmentID == action.environmentID,
              !observedBinding.engineVersion.isEmpty,
              isSHA256(observedBinding.engineFingerprint),
              isSHA256(observedBinding.environmentFingerprint) else {
            issue(.unknownEngineIdentity)
            return finish(.unknown)
        }
        binding = observedBinding
        // A selected engine is itself a requirement. Empty script requirements
        // do not prove the interpreter/worker route exists in the signed app.
        guard action.requirements.contains(where: {
            $0.key.kind == .engine && $0.key.name == engineID.rawValue
        }) else {
            issue(.unknownRequirement)
            return finish(.unknown)
        }
        guard Set(action.requirements.map(\.id)).count == action.requirements.count else {
            issue(.invalidIdentity)
            return finish(.unknown)
        }

        for requirement in action.requirements {
            guard !requirement.id.isEmpty, !requirement.key.name.isEmpty,
                  requirement.key.kind != .unknown,
                  !requirement.evidence.producer.isEmpty,
                  [action.sourceFingerprint, action.actionFingerprint].contains(requirement.evidence.sourceFingerprint) else {
                hasUnknown = true
                issue(.unknownRequirement, requirement)
                continue
            }
            let candidates = engineFacts.facts.filter {
                $0.requirement == requirement.key && $0.binding == observedBinding
            }
            guard candidates.count == 1, let fact = candidates.first else {
                hasUnknown = true
                issue(candidates.isEmpty ? .missingFact : .ambiguousFact, requirement)
                continue
            }
            guard freshness.contains(fact.evidence.observedAt) else {
                hasUnknown = true
                issue(.staleFact, requirement)
                continue
            }
            guard [.observed, .tested].contains(fact.evidence.kind),
                  !fact.evidence.producer.isEmpty,
                  fact.evidence.sourceID == engineID.rawValue,
                  fact.evidence.sourceFingerprint == observedBinding.engineFingerprint else {
                hasUnknown = true
                issue(.unprovenFact, requirement)
                continue
            }
            switch fact.status {
            case .available:
                availableCount += 1
            case .missing:
                missing.append(requirement)
                issue(.missingDependency, requirement)
                if let manager = manager(for: requirement.key.kind, engine: engineID) {
                    remediation.append(.init(manager: manager, engineID: engineID,
                                             requirementID: requirement.id, target: requirement.key.name))
                }
            case .unsupported:
                hasUnsupported = true
                issue(.unsupportedDependency, requirement)
            case .unknown:
                hasUnknown = true
                issue(.unprovenFact, requirement)
            }
        }
        if hasUnsupported { return finish(.unsupported) }
        if !missing.isEmpty { return finish(.needsInstall) }
        if hasUnknown { return finish(availableCount > 0 ? .partial : .unknown) }

        if let lastTest, lastTest.actionID == action.id,
           lastTest.sourceFingerprint == action.sourceFingerprint,
           lastTest.actionFingerprint == action.actionFingerprint,
           lastTest.invocationFingerprint == action.invocationFingerprint,
           lastTest.binding == observedBinding,
           lastTest.evidence.kind == .tested,
           lastTest.evidence.sourceFingerprint == action.actionFingerprint,
           !lastTest.evidence.producer.isEmpty,
           lastTest.evidence.artifactReference?.isEmpty == false,
           freshness.contains(lastTest.evidence.observedAt) {
            matchingTest = lastTest
            if lastTest.outcome == .failed {
                issue(.previousTestFailed)
                return finish(.unknown)
            }
            return finish(.verified)
        }
        return finish(.likely)
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    private static func manager(for kind: C.RequirementKind, engine: C.EngineID) -> C.RemediationHandle.Manager? {
        if kind == .engine { return .runtimeManager }
        guard kind == .module else { return nil }
        if engine == .node || engine == .typeScript { return .nodePackages }
        if engine == .python { return .pythonPackages }
        return nil
    }
}
