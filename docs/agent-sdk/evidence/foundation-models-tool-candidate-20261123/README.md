# SDK02 native tool adapter candidate — 23 November 2026

**Status: candidate only; Apple compilation and framework execution NOT_RUN. Public native tool capability remains disabled.** No SDK02 completion, Host-runtime acceptance or model execution is claimed.

This isolated branch starts from source 7523f45cf8ea180a8e30f511ff0fbd3bb5ccae6d. It preserves the original HanlinAppleLanguageModel, HanlinAISDKAgentEngine, model picker, public provider factory, session and Host dispatcher. Only an internal acceptance initializer selects the candidate in the original provider. Its public initializer and the factory/catalog/APIManager gates remain text-only.

## Implemented candidate

- Translate a closed JSON Schema subset using public DynamicGenerationSchema constructors: closed objects, required/optional properties, strings/string enums, booleans, null and bounded homogeneous arrays. Unknown constraints, numeric parameters, references, unions, patterns and string-length constraints are explicitly rejected before advertising.
- Preserve canonical user/assistant/tool roles and call IDs. Reject duplicate calls, orphan/mismatched results, incomplete tool continuations, unsupported attachments and metadata.
- Use one native session for one provider step. The documented onPrompt hook removes the framework-required empty trigger before invocation; historyTransform independently supplies the admitted canonical history. Neither native session history nor the empty trigger is persisted into Hanlin.
- Intercept pre-effect onToolCall, validate every sibling in the native batch, and throw a dedicated handoff error. Emit calls to the original shared loop. Native Tool.call has no Host closure and always throws.
- Keep permission, effects, persistence and continuation in the original engine/session. Preserve tools in nonstreaming output and own cancellation through the existing task/abort-signal contracts.

## Provenance repair

Pinned producer e7bf34111e603ca977becd007dd4e5bb109af857 retains accepted V3 JSON Strings as ToolCallRawInput. GeneratedContent JSON is reserialization, while its numeric kind contains a Double. It cannot establish original model tokens.

The adapter rejects numeric generated values before emitting any batch. The trusted appleOnDevice engine boundary independently rejects numbers during schema admission, before approval and before executor entry. Native provenance remains normalized even when the producer retains that String as rawInput. Provider metadata cannot upgrade it. Cloud original-input behavior and the producer pin remain unchanged.

This latent boundary risk is tested with an explicitly injected model; shipping native-tool gates already prevent ordinary tools from reaching it.

## Current evidence

linux-before-control/ contains original logs, plan and receipt from a consumer of the actual unchanged engine and pinned producer. Oracle Swift 6.4.3 stopped in producer TypedTool.swift lines 87/266: Linux stderr access fails Swift 6 concurrency checking. **Tests did not execute.** Producer code and concurrency settings remain unchanged.

local-preflight/ contains syntax/parser and report/selector controls only. These do not typecheck FoundationModels or execute the native framework. Controls reject missing/failed/skipped/unexpected cases, false-green baselines, absent iOS builds and incorrect selectors.

The release owner acquired public declarations from run 45230545076, artifact 14847222630, source 7523f45. Excerpt SHA256: d1d50574ae65c19a319d7f8427944cc36a0373affcd8db3fba3fd6a3d531e2e0. The actual availability-only macOS query returned deviceNotEligible; no model ran. Inspection evidence is published at commit 58bc4586667c907653950194b113be303031777a.

Public API contracts:

- https://developer.apple.com/documentation/foundationmodels/composing-dynamic-sessions-with-instructions-and-profiles
- https://developer.apple.com/documentation/foundationmodels/languagemodelsession/dynamicprofile/historytransform(_:)
- https://developer.apple.com/documentation/foundationmodels/transcripterrorhandlingpolicy/preservetranscript
- https://developer.apple.com/documentation/foundationmodels/tool
- https://developer.apple.com/documentation/foundationmodels/dynamicinstructionsforeach
- https://developer.apple.com/documentation/foundationmodels/languagemodelexecutor

## Proposed Apple execution

Use existing build-ios26-unsigned-ipa.yml on this branch with:

- target_validation_group=agent_sdk_exact_source_proof
- exact_test_selector=HanlinNativeToolCandidate
- Other upload/validation flags false/default.

Only that exact selector activates the candidate route. Legacy script content is byte-equivalent after removal of the explicit branch. No workflow file or job is added.

The route retains original-source/toolchain/producer/lock guards and selects:

1. Same new engine-boundary tests against the two exact original engine/model files from 7523f45 in the candidate package graph. Native methods must fail while the cloud control passes; a compile failure is not a successful negative control.
2. HanlinChatCoreTests/HanlinAppleToolInputBoundaryTests against the restored candidate.
3. HanlinAgentCoreTests/HanlinAppleToolSchemaTests.
4. HanlinAgentCoreTests/HanlinAppleToolSessionBridgeTests through the real FoundationModels framework with a deterministic public LanguageModelExecutor.
5. An iOS Simulator build of original HanlinAgentCore; no simulator launch.

There are 12 new methods and 32 planned parameterized cases across three suites. The three boundary methods also serve as the negative control. Counts remain planned until xcresult proves actual execution.

## Remaining gates

The native compile/control route must prove actual API compatibility, pre-effect batch handoff, exact identities, trigger removal, denied-call continuation, cancellation and schema construction. No native result is currently marked PASS.

Even if deterministic framework controls pass, actual SystemLanguageModel tool choice and continuation need eligible hardware with a ready model. Unsupported schemas/metadata remain explicit errors. Original HostIntegration/session and real-app acceptance require review before capability activation. Hosted deviceNotEligible and fixture results cannot be relabeled as native model acceptance.

## Exact invocation review correction

Review of the initial report verifier found that its twelve aggregate method
nodes could pass without the parameterized executions. The corrected verifier
requires **32 candidate invocations** and separately **12 baseline invocations**:
native normalized-input 2, numeric rejection 8, cloud preservation 2, rejected
schemas 12, supported-schema 1, and seven framework bridge controls. The baseline
must reproduce all ten native failures while both cloud invocations pass, with
the normal xcodebuild test-failure exit 65. Timeouts, signals and other
infrastructure exits cannot establish the negative control.

Every parameterized method must contain each exact authored argument tuple once,
with its own executed result and a unique argument URL bound to that method.
Numeric JSON remains a raw string in this comparison; reformatting, replacing,
duplicating or truncating it fails verification. Aggregate-only results, missing
or extra arguments, unknown formats, skips and unknown statuses cannot pass.

The existing original Xcode export at
docs/continuation-20261117/acceptance/run-44383943178/08-downstream-unit-test-results.json
already demonstrates Test Case children of type Arguments, individual results,
quoted string displays and nodeIdentifierURL with an argument hash. This is
format evidence only, not execution evidence for the new candidate. A two-value
argument display has not yet been observed for these new controls. The parser
accepts only exact JSON string/Bool values or their comma-separated tuple
(optionally parenthesized); any different or truncated shape remains BLOCKED.
The same Apple invocation retains detailed per-method xcresult exports and the
original result bundles for interpretation without replaying accepted tests.

Ten local Python methods passed after this repair, including source-bound
inventory validation and adversarial report fixtures. These are verifier and
selector controls only. Actual Apple compile, all 32 candidate invocations, the
12 baseline invocations, and eligible SystemLanguageModel execution remain
NOT_RUN. No public capability gate changed.

## Actual Apple attempt 2 and current repair

See [the original Apple outcomes and focused recheck plan](apple-45240721804-attempt-2/README.md). The frozen f311 candidate executed5 PASS,7 FAIL,20 NOT_RUN; baseline10 expected failures and2 cloud passes were authenticated, and iOS AgentCore built. The repaired source has not executed. This supersedes the earlier provisional argument-display grammar: actual Swift displays keep embedded quotation marks literal, so complete source-bound display matching is used. No shipping capability was enabled.
