import Foundation

/// Portable checks of the real production contract/planner sources. These are
/// synthetic compatibility cases, not fifteen real Skills or native acceptance.
@main
enum SkillRuntimeContractChecks {
    typealias C = SkillRuntimeContract
    static let now = Date(timeIntervalSince1970: 2_000)
    static let source = String(repeating: "a", count: 64)
    static let script = String(repeating: "b", count: 64)
    static let engineHash = String(repeating: "c", count: 64)
    static let environmentHash = String(repeating: "d", count: 64)
    static let invocation = String(repeating: "e", count: 64)
    static let freshness = C.Freshness(notBefore: Date(timeIntervalSince1970: 1_900), now: now)

    struct Failure: Error { let name: String }

    actor Provider: SkillRuntimeCapabilityProvider {
        nonisolated let engineID: C.EngineID
        private var queries = 0

        init(_ engineID: C.EngineID) { self.engineID = engineID }
        func snapshot(environmentID: String) async -> C.EngineFacts {
            queries += 1
            return SkillRuntimeContractChecks.facts()
        }
        func count() -> Int { queries }
    }

    static func evidence(_ kind: C.EvidenceKind = .observed, fingerprint: String = engineHash,
                         date: Date? = now, artifact: String? = nil) -> C.SourceEvidence {
        .init(kind: kind, producer: "original-engine-adapter", producerVersion: "1",
              sourceID: C.EngineID.node.rawValue, sourceVersion: "22", sourceFingerprint: fingerprint,
              observedAt: date, artifactReference: artifact)
    }

    static func requirement(_ id: String, _ kind: C.RequirementKind, _ name: String,
                            constraint: String? = nil) -> C.SkillRequirement {
        .init(id: id, key: .init(kind: kind, name: name, versionConstraint: constraint),
              evidence: evidence(.declared, fingerprint: source))
    }

    static var requirements: [C.SkillRequirement] {
        [requirement("engine", .engine, C.EngineID.node.rawValue), requirement("module", .module, "example")]
    }

    static func action(kind: C.ActionKind = .script, complete: Bool = true,
                       engine: C.EngineID? = .node, requirements: [C.SkillRequirement] = Self.requirements,
                       source: String = Self.source, script: String = Self.script,
                       invocation: String? = Self.invocation) -> C.Action {
        .init(id: "skill/action", kind: kind, skillID: "skill", sourceFingerprint: source,
              actionFingerprint: script, invocationFingerprint: invocation, relativePath: "scripts/helper.js",
              environmentID: "group", engineID: engine, requirements: requirements,
              requirementsComplete: complete)
    }

    static func binding(engineHash: String = Self.engineHash, environmentHash: String = Self.environmentHash) -> C.EngineBinding {
        .init(engineID: .node, engineVersion: "22", engineFingerprint: engineHash,
              environmentID: "group", environmentFingerprint: environmentHash)
    }

    static func facts(module: C.FactStatus = .available, evidence: C.SourceEvidence = Self.evidence(),
                      binding: C.EngineBinding = Self.binding(), duplicate: Bool = false) -> C.EngineFacts {
        var values = requirements.map {
            C.CapabilityFact(requirement: $0.key, binding: Self.binding(),
                             status: $0.key.kind == .engine ? .available : module,
                             resolvedVersion: "1", resolvedPath: nil,
                             evidence: $0.key.kind == .engine ? Self.evidence() : evidence)
        }
        if duplicate { values.append(values[1]) }
        return .init(engineID: .node, binding: binding, facts: values)
    }

    static func test(_ outcome: C.ExecutionTest.Outcome = .passed,
                     date: Date? = now, artifact: String? = "jobs/test/receipt.json") -> C.ExecutionTest {
        .init(actionID: "skill/action", sourceFingerprint: source, actionFingerprint: script,
              invocationFingerprint: invocation, binding: binding(), outcome: outcome,
              evidence: evidence(.tested, fingerprint: script, date: date, artifact: artifact))
    }

    static func plan(_ action: C.Action = Self.action(), _ facts: C.EngineFacts? = Self.facts(),
                     test: C.ExecutionTest? = nil) -> C.ExecutionPlan {
        SkillRuntimePlanner.evaluate(action: action, engineFacts: facts, lastTest: test, freshness: freshness)
    }

    static func main() async throws {
        var passed: [String] = []
        func check(_ name: String, _ condition: @autoclosure () -> Bool) throws {
            guard condition() else { throw Failure(name: name) }
            passed.append(name)
        }
        try check("complete instructions require no runtime",
                  plan(action(kind: .instructions, engine: nil, requirements: [])).readiness == .verified)
        try check("instructions never execute",
                  !plan(action(kind: .instructions, engine: nil, requirements: [])).isExecutable)
        try check("instructions cannot erase runtime requirements",
                  plan(action(kind: .instructions)).readiness == .unknown)
        try check("unresolved merge or partial scan stays unknown",
                  plan(action(complete: false, requirements: [])).readiness == .unknown)
        try check("empty script requirements do not establish an engine",
                  plan(action(requirements: [])).readiness == .unknown)
        try check("observed complete capabilities predict likely, not tested",
                  plan().readiness == .likely && plan().lastTest == nil && plan().isExecutable)
        try check("exact fresh execution receipt verifies only its invocation",
                  plan(test: test()).readiness == .verified)
        try check("inspection without actual runtime inputs cannot reuse execution",
                  plan(action(invocation: nil), test: test()).readiness == .likely)
        try check("changed arguments invalidate tested status",
                  plan(action(invocation: String(repeating: "f", count: 64)), test: test()).readiness == .likely)
        try check("changed skill source invalidates requirement evidence",
                  !plan(action(source: String(repeating: "f", count: 64)), test: test()).isExecutable)
        try check("changed action source invalidates tested status",
                  plan(action(script: String(repeating: "f", count: 64)), test: test()).readiness == .likely)
        try check("changed engine invalidates cached capability facts",
                  plan(action(), facts(binding: binding(engineHash: String(repeating: "f", count: 64)))).readiness == .unknown)
        try check("changed environment invalidates cached capability facts",
                  plan(action(), facts(binding: binding(environmentHash: String(repeating: "f", count: 64)))).readiness == .unknown)
        try check("stale module facts are partial",
                  plan(action(), facts(evidence: evidence(date: Date(timeIntervalSince1970: 1_800)))).readiness == .partial)
        try check("future-dated facts are not fresh",
                  plan(action(), facts(evidence: evidence(date: Date(timeIntervalSince1970: 2_100)))).readiness == .partial)
        try check("inferred capability does not establish availability",
                  plan(action(), facts(evidence: evidence(.inferred))).readiness == .partial)
        let missing = plan(action(), facts(module: .missing))
        try check("missing module is not executable", missing.readiness == .needsInstall && !missing.isExecutable)
        try check("missing Node module refers to existing manager",
                  missing.remediation.count == 1 && missing.remediation[0].manager == .nodePackages)
        try check("unsupported dependency remains unsupported",
                  plan(action(), facts(module: .unsupported)).readiness == .unsupported)
        try check("ambiguous facts cannot establish readiness",
                  plan(action(), facts(duplicate: true)).readiness == .partial)
        let constrained = [requirements[0], requirement("module", .module, "example", constraint: ">=2")]
        try check("version constraints need an exact original resolver fact",
                  plan(action(requirements: constrained)).readiness == .partial)
        let future = C.EngineID(rawValue: "future.ish")
        let futurePlan = plan(action(engine: future), nil)
        try check("unregistered future iSH is unsupported without fallback",
                  futurePlan.readiness == .unsupported && futurePlan.selectedEngine == future && !futurePlan.isExecutable)
        try check("missing engine fingerprint stays unknown",
                  plan(action(), facts(binding: binding(engineHash: ""))).readiness == .unknown)
        try check("suffix does not select an engine", plan(action(engine: nil)).readiness == .unknown)
        let failed = plan(test: test(.failed))
        try check("failed exact invocation is not silently retried",
                  failed.readiness == .unknown && !failed.isExecutable && failed.lastTest?.outcome == .failed)
        try check("stale execution receipt is not reused",
                  plan(test: test(date: Date(timeIntervalSince1970: 1_800))).readiness == .likely)
        try check("receipt without artifact reference does not verify",
                  plan(test: test(artifact: nil)).readiness == .likely)
        let duplicates = [requirements[0], requirement("engine", .module, "example")]
        try check("duplicate requirement identities are rejected",
                  plan(action(requirements: duplicates)).readiness == .unknown)
        try check("declared capability is not an observation",
                  plan(action(), facts(evidence: evidence(.declared))).readiness == .partial)
        try check("invalid source identity cannot be verified",
                  plan(action(source: "unhashed"), test: test()).readiness == .unknown)
        let original = plan(test: test())
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(C.ExecutionPlan.self, from: encoded)
        try check("wire roundtrip retains typed evidence and selected engine", decoded == original)
        let engineJSON = try JSONEncoder().encode(C.EngineID.node)
        try check("engine wire identity is a string", String(decoding: engineJSON, as: UTF8.self) == "\"hanlin.node\"")
        let node = Provider(.node)
        let python = Provider(.python)
        let registry = try SkillRuntimeRegistry(providers: [node, python])
        let selected = await registry.plan(action: action(), freshness: freshness)
        let nodeCount = await node.count()
        let pythonCount = await python.count()
        try check("registry queries only the explicitly selected provider",
                  selected.readiness == .likely && nodeCount == 1 && pythonCount == 0)
        let afterFailure = await registry.plan(action: action(), lastTest: test(.failed), freshness: freshness)
        let fallbackCount = await python.count()
        try check("registry never queries an alternative after failed execution",
                  afterFailure.readiness == .unknown && fallbackCount == 0)
        var duplicateRejected = false
        do { _ = try SkillRuntimeRegistry(providers: [node, node]) }
        catch let error as SkillRuntimeRegistry.RegistrationError {
            duplicateRejected = error == .duplicateEngine(C.EngineID.node.rawValue)
        }
        try check("duplicate provider authority is rejected", duplicateRejected)
        let helper = SkillRuntimeRegistry.AnalysisHelperRegistration(
            id: "original-parser", version: "pinned-revision", engineID: .node,
            relativePath: "helpers/original-parser.mjs", sourceSHA256: source,
            requirements: requirements, outputContract: "SkillSyntaxReport")
        let helperRegistry = try SkillRuntimeRegistry(providers: [node], analysisHelpers: [helper])
        let bytes = Data("print('שלום')\n".utf8)
        let input = SkillRuntimeRegistry.AnalysisInput(file: "scripts/helper.py", utf8: bytes, sourceSHA256: script)
        let prepared = try await helperRegistry.prepareAnalysis(helperID: helper.id, input: input,
            invocationFingerprint: invocation, environmentID: "group", freshness: freshness)
        let inputRoundtrip = try JSONDecoder().decode(SkillRuntimeRegistry.AnalysisInput.self, from: input.encoded())
        try check("analysis transport retains exact original bytes", inputRoundtrip.utf8 == bytes)
        try check("helper preparation predicts without claiming execution",
                  prepared.plan.readiness == .likely && prepared.plan.lastTest == nil &&
                  prepared.registration.outputContract == "SkillSyntaxReport")
        var unknownRejected = false
        do {
            _ = try await helperRegistry.prepareAnalysis(helperID: "unregistered", input: input,
                invocationFingerprint: invocation, environmentID: "group", freshness: freshness)
        } catch let error as SkillRuntimeRegistry.RegistrationError {
            unknownRejected = error == .unknownHelper("unregistered")
        }
        try check("metadata cannot invent a trusted helper registration", unknownRejected)
        let result: [String: Any] = ["status": "EXECUTED_PASS", "cases": passed,
            "boundary": "Portable production contract/planner checks; synthetic inputs, no engine, real Skill, Apple framework, app or device execution."]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
