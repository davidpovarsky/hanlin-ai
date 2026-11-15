# Runtime05 passive contract and integration boundary

The app module is `AI_HLY`. The production sources are
`AI_HLY/Downstream/RuntimeCore/Core/Skills/SkillRuntimeContract.swift`,
`SkillRuntimePlanner.swift`, and `SkillRuntimeRegistry.swift`. They use Foundation
only. This is an initial typed contract and pure planner, not completed Runtime05
integration or acceptance of any actual Skill.

`SkillRuntimeContract` owns `SkillRequirement`, `CapabilityFact`, `Readiness`,
`SourceEvidence`, `Action`, `EngineBinding`, `ExecutionTest` and `ExecutionPlan`.
Readiness wire values are VERIFIED/LIKELY/PARTIAL/NEEDS_INSTALL/UNSUPPORTED/UNKNOWN.
`ExecutionPlan` supplies the UI with selectedEngine, binding, issues,
missingRequirements, remediation handles, lastTest and evaluatedAt. Handles name
the existing Node/Python/runtime managers and perform no operation by themselves.

An adapter supplies one explicit engine ID; the planner does not derive it from
a filename. Existing IDs are hanlin.node, hanlin.typescript, hanlin.python,
hanlin.javascriptcore and hanlin.ios-system. Unregistered engines, including
future iSH, cannot become executable. Source/action SHA256, engine version and
SHA256, environment ID/SHA256 and explicit freshness must be known. A version
string, operational-ready snapshot, or Linux-like PATH is not a package fact.

Requirement keys retain original version constraints. Facts must match the exact
key and binding, have fresh observed/tested provenance, and come from an actual
engine adapter. Unknown YAML tags/merges or partial scans set
Action.requirementsComplete=false. An empty list cannot erase those unknowns.
Yams owns YAML structure and the original OpenClaw adapter owns its semantics;
this contract adds no parser or flattened YAML representation.

Complete instruction-only content with no runtime requirements needs no engine.
For executable actions, observed complete facts yield LIKELY. VERIFIED additionally
needs a fresh passed receipt for the exact source/action, engine/environment and
actual invocation fingerprint, including argv/stdin/cwd and other runtime inputs.
Changed inputs invalidate test reuse. A matching failed receipt blocks execution;
there is no alternative-engine retry. The existing execution tool must recompute
the plan and preserve its loaded/enabled/source checks and JobStore ownership;
a decoded report is not an authorization or integrity proof.

## Actual signatures for AST and Runtime composition

```swift
protocol SkillRuntimeCapabilityProvider: Sendable {
    var engineID: SkillRuntimeContract.EngineID { get }
    func snapshot(environmentID: String) async -> SkillRuntimeContract.EngineFacts
}

SkillRuntimePlanner.evaluate(action:engineFacts:lastTest:freshness:)
    -> SkillRuntimeContract.ExecutionPlan

try SkillRuntimeRegistry(providers:analysisHelpers:)
await registry.plan(action:lastTest:freshness:)
try await registry.prepareAnalysis(helperID:input:invocationFingerprint:environmentID:freshness:)
    -> SkillRuntimeRegistry.PreparedAnalysis
```

Providers inspect cached or already-launched facts only. RuntimeCore composition
supplies immutable provider/helper registrations; a Skill cannot register its own
trusted engine/helper. A registration names a pinned helper version, engine,
relativePath, sourceSHA256, requirements and outputContract=`SkillSyntaxReport`.
The original AST-owned Codable SkillSyntaxReport remains the output model, with
its original scanner/revision/grammar provenance; no second findings type exists.

`SkillRuntimeRegistry.AnalysisInput(file:utf8:sourceSHA256:)` contains schemaVersion1,
the original file identifier, original Data bytes and their original SHA256.
Its `encoded()` produces sorted-key JSON; Codable transports Data as base64.
Python ast/TypeScript Compiler API helper authors can consume that request and
produce the existing SkillSyntaxReport. They do not create dispatchers or engines.
Preparation only obtains passive facts and a plan. Actual helper file/input hash
verification, cancellation, durable output and execution still belong in the
existing RuntimeCore route and are not implemented by this registration layer.

## Validation and remaining work

The first two production files passed portable Swift6 typechecking and32 checks
on Windows Swift6.3.3. The expanded registry and38-case suite were freshly compiled
and executed on that compiler: EXECUTED_PASS38. Local results and original source/
executable hashes are in build/acceptance/local-skill-runtime-contracts/result.json.
Apple validation run43768185348/52bb7720 is EXECUTED_PASS: actual macOS compile,
38 executed cases, and iOS26.0/27.0 Simulator target typechecks. All10 artifact
manifest file hashes verified locally with0 mismatch. Apple Swift6.4.2,
Xcode27.2/27B52. Result SHA256
4ff1259eff24574b75c87faae906e29b565d2b3482dd2e11c8ce1234ca153370.
The first two failed host attempts and their harness corrections remain recorded;
no failed/skipped native acceptance is converted into a pass.
The existing manual workflow selector `SkillRuntimeContracts`
compiles and executes those actual sources on macOS, then typechecks them for
arm64 iOS Simulator deployment26.0 and27.0 using the selected installed SDK.
These synthetic checks do not replace15+ real Skills or engine/device tests.

Still unimplemented/unverified: actual native engine/provider facts and binary/
environment fingerprints; the single Swift-to-original-Node capability adapter;
Yams/OpenClaw/AST adapters; native engine selection policy; actual helper execution;
ExecuteSkillResourceTool/AppRuntimeCore/JobStore integration; import/load/search/UI
consumption; real Skills, JITless native Node, iPad and cache invalidation evidence.
No existing execution route is redirected by these standalone source additions.
