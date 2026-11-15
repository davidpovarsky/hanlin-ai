# Combined producer, consumer and session review packet

## Current SDK test-fixture conformance correction

Faithful Mac run43686294717 at e233bffc, as reported with verified artifact14150797620
by the lead, passed48 real producer tests and20 core tests; iOS AgentCore built.
The SDK test bundle failed compilation before cases because ExactNumericHost and
ExecutionGateHost omitted required cancel/open methods: ZERO SDK cases executed,
10 NOT_RUN, zero actual failed SDK tests. No numeric full-chain acceptance follows.

This source-only correction adds those four methods in AgentSessionTests.swift.
The numeric read fixture's cancel cannot undo its synchronous completed read. The
gated fixture forwards cancellation recording without releasing controlled work,
so Session revocation must still suppress a late result. Both navigation methods
throw test-local unsupportedNavigation; no mounted/presented ACK is fabricated.
All10 SDK test identities and their numeric/pending/receipt/lifetime assertions
remain unchanged. Production source, producer, protocols, manifests and locks are
unchanged. Current compile/typecheck/parse/test execution is NOT_RUN under the
resource gate. See evidence/sdk-test-fixture-conformance-receipt.json for hashes,
the10 identities and the exact prior artifact attribution. Roni source review then
Tomer's SDK-only real Mac10-case proof remain required; prior68 passes are reusable
only with unchanged transitive Git inputs, all3 rawlocks and toolchain.


This packet is source-frozen for independent Roni review and Tomer integration.
**Numeric model execution remains BLOCKED for Hanlin acceptance** until the actual
Hanlin engine/session/host chain compiles and passes on Apple. Neither proof below
substitutes for that chain or for a real host/device test. All SDK tasks remain open.


## Current P1 approval-correlation correction (source only)

Independent QA requested changes to producer788a / consumer58de: distinct approval
request IDs could reference the same toolCallId, permitting two approvals or a
mixed approval/denial to reach the approved path. This was a source-derived
finding, not an executed reproduction or proof of duplicated Hanlin native effects.

Corrected producer **e7bf34111e603ca977becd007dd4e5bb109af857** requires exactly one
request per toolCallId before collecting either decision. It counts every request,
even if only one has a response. The changed lease is exactly CollectToolApprovals
and RawToolInputPropagationTests; no engine, side cache, retry or consumer source
change. Existing duplicate/unknown/cancel/schema/raw provenance checks remain.

Three new regression bodies contain 56 matrix rows through REAL generateText and
streamText message-approval resume, after response/Codable roundtrip: distinct
same-call requests with two approvals, mixed decisions in either order, or one
unanswered request execute zero times; one matching approval executes exactly
once; independent calls retain individual eligibility beside an ambiguous call.
Static/dynamic and accepted/repaired original JSON are checked in both entry
points. These are **test SOURCE, NOT_RUN / NOT_TYPECHECKED / NOT_SYNTAX_PARSED**.
No compiler/build/test execution, cache growth, download, worktree expansion or
rejected-cleanup retry occurred under the resource gate.

`evidence/approval-correlation-source-manifest.json` freezes the corrected complete
497-input producer closure, its exact two-file delta and unchanged 24-input consumer
source closure. The earlier 45-producer/39-portable passes and their logs/manifests
remain historical evidence for their exact OLD closures; they do not pass the
changed producer. Tomer must run the affected real Mac proofs before QA acceptance.
Shipping pins/locks remain unchanged, and numeric/full Hanlin Apple acceptance
remains blocked. Roni must review this corrected packet independently.

## Exact inputs and dependency window

- Producer: `C:/Users/DAVID/Code/swift-ai-sdk-hanlin-raw-tool-input-20261115`, branch
  `codex/hanlin-raw-tool-input-20261115`, frozen commit
  `e7bf34111e603ca977becd007dd4e5bb109af857` (P1 delta from producer788a), based on
  `43ebcfaae67ca2c47ea1ce940d66b581e60ca7f6`.
- Consumer: the commit containing this packet in
  `C:/Users/DAVID/Code/hanlin-agent-sdk-wave1-20261115`, branch
  `codex/hanlin-agent-sdk-wave1-20261115`, review delta from
  `58de69a1e481de7ff63abbc599906f64955cbdce`; consumer source is unchanged by this P1 correction.
- Shipping manifests and locks still name the old producer `43ebcf`. The new core
  source references its additive API and **requires the new producer**; the current
  shipping dependency graph is not advertised as buildable with that source. Tomer
  alone owns the final producer dependency/lock window after independent review.
  No temporary manifest, local dependency override, pin/lock change, copied module,
  provider shim or root-package distribution claim was used for these proofs.
- `evidence/final-source-manifest.json` records consumer source bytes.
  `evidence/approval-correlation-source-manifest.json` records the corrected producer source
  closure and NOT_RUN status. Historical `evidence/producer-chain-proof.json` records
  the OLD producer788a closure, tests, compiler/link arguments and frozen Git identity. Windows
  working-tree SHA256 values include their actual line endings; Git blob IDs and
  normalized LF hashes permit comparison to the committed source on Apple.

## Producer behavior

`ToolCallRawInput` carries bounded original JSON plus call/tool identity. Typed
static/dynamic calls and the additive/default-nil `ToolCallOptions.rawInput`
preserve it. Parser acceptance retains actual final bytes; repair retains accepted
repaired bytes and rejects a changed call ID. Empty legacy argument strings and
schemas whose transformed result differs from the parsed value retain nil.

Immediate execution and stream execution (including resolver approval) validate
correlation, dynamic identity, JSON syntax/size, normalized-value agreement and
the live schema before invoking the executor. Cancellation is checked again after
validation awaits. The field is provenance, not permission or a host grant.

The existing `ToolCallPart` Codable and response conversion preserve optional raw
input/dynamic identity for actual approval resume. Legacy messages decode nil;
reserialization never manufactures original input. Ambiguous call/request/response
correlation is rejected. Denied/unknown approvals do not execute. Existing provider
prompt DTOs and telemetry carry their original normalized shape, without the new
raw field. There is no stream side cache, new loop, provider serializer change,
global numeric-type change, retry or schema/consent bypass.

## Consumer behavior and limits

The existing canonical core executor consumes the checked producer field directly,
verifying call/tool/size/value correlation again. Its additive optional
`executeWithInputProvenance` preserves existing two-argument executor call sites.
New AgentCore receives `.acceptedOriginal` or explicit `.normalized` through that
same executor, not through a parallel parser or authority registry.

`HanlinModelToolInputGuard` precedes **all** pending-call persistence and dispatch.
Missing/unverified original input rejects every numeric leaf recursively,
including small numbers; digit strings/bools/null remain unchanged. Verified
original JSON must pass the existing canonical parser: Int64 integer category and
finite Double decimal/exponent category. Decimal/exponent tokens must round-trip
to the same decimal value through Double's shortest text; excessive precision,
underflow, overflow and integers outside Int64 fail before body entry. For example
`9007199254740993` and Int64.max can remain integers, and `1.0`/`1e0` remain numbers;
`9007199254740993.0`, full UInt64 and `0.10000000000000000001` are unsupported.
No arbitrary-precision guarantee or coercion is introduced. The direct canonical
dispatcher path is unchanged. Host schema/permissions/consent/native effects and
durable idempotency remain the host's final responsibility.

Original arguments stay transient in the Hanlin session. Its existing transcript
stores null argument metadata and scoped metadata receipts rather than a second
raw argument/business-data store.

## Session lifetime and reentrancy

The run is reserved before the first host/store await. Session context checks
check cancellation, invalidation and run identity before and **after** the host
await. Event delivery, result callback, progress and capability/catalog boundaries
use those checks. The original dispatcher receipt survives invalidation after an
effect even when callback/event delivery is suppressed. No rollback/retry occurs.

**UI lifecycle contract (SDK04 planning):** `invalidate()` is terminal for that
presentation session. Cancellation of the returned stream invokes terminal
invalidation through `onTermination`; there is no verified public
cancel-current-turn-and-reuse-the-same-session API. A later send needs a **new
host-authorized HanlinHostSession identity and new HanlinAgentSession**, using the
host's current context/permission checks. A view must not silently issue identity
or authorization. Reusing a conversation still loads its record and rejects
unresolved pending/uncertain effects until the original host reconciles them; a
new session does not undo or erase those effects. Normal completed runs may reuse
a still-valid session subject to the same record/authority checks. Existing UI
controller/view/result-port types remain proposals owned by Maya/Eitan; this
packet adds no UI/Composer/renderer or app singleton.

## Historical verification before the P1 correction

The following results belong to the prior producer788a / consumer58de exact
closures. The changed producer and new tests have NO runtime/compiler pass.

| Evidence | Actual result and scope |
| --- | --- |
| Root `AGENT=1 swift test --jobs 2 --filter ...` | BLOCKED before tests by unchanged `Sources/RevAIProvider/RevAIProvider.swift:91`, Windows `URLSession.shared`; root builds unrelated provider targets despite filter. Log `producer-chain-test.log`. No shim/provider change. |
| Genuine root manifest `swift build --target SwiftAISDK --jobs 2` | PASS, complete actual production SwiftAISDK module and its real seven-module closure, Swift 6.3.3 Windows/language 6. Log `producer-scoped-build.log`. |
| Selected actual repository Swift Testing suites linked against that complete built graph | **45 tests / 4 suites PASS**. Real parse→execute static/dynamic; 2^53±1, Int64 extrema, 1.0/1e0/nesting; accepted repair; streamed immediate/resolver execution; real `generateText` approval resume after response/Codable; malformed/oversized/mismatched/stale-schema/denied/unknown/ambiguous inputs; continuation-gated cancellation during validation; legacy nil; V3/V4 provider prompt and telemetry exclusion. `run-producer-chain.ps1`, `producer-chain-{proof.json,link.log,run.log}`. This is not a root `swift test` pass. |
| Portable Hanlin closure | **39 cases PASS**. Actual contracts, dispatcher/stores/fixtures, numeric guard and pure text delta; only pinned old JSONValue.swift is compiled in its partial AISDKProvider module. Guard-body fixture and manually supplied verified flag are isolated guard tests, **not Session/full producer→Hanlin chain proof**. `portable-{source-proof.json,run.log}`. |
| Actual Hanlin Session tests | Added real engine/session source tests for numeric scope/receipt/null metadata, unsupported numeric zero pending/effect, concurrent-start reservation, and continuation-gated post-await event/result invalidation with retained committed receipt. Syntax parsed. **NOT_RUN / no full Session typecheck** on Windows; unchanged existing Apple `String(localized:)` graph blocker was already recorded and not rerun. |

No Apple SDK/FoundationModels compilation or generation, actual app/host adapter,
native UI/scene ACK, iPad/device, release/signing/TestFlight, main merge or CI run is
claimed. Producer testing uses only synthetic inputs/models/recorders. C: reserve
was monitored; no broad rebuild or dependency expansion is authorized by this
packet.

## Review and integration ownership

Roni reviews the two exact source commits and proof scope independently. Tomer
owns the final dependency window and faithful Apple compilation/test execution,
including actual `AgentSessionTests` and existing injected-provider/core cloud
regression tests. Numeric execution stays blocked until that attributable chain
passes; source/producer/portable passes alone do not close SDK02/03 or the parent.
No real Otzaria API/action/reader/search/backend enumeration or duplicate Anytype
host audit was performed. Host UI, persistence entitlements and device acceptance
remain with their existing owners.
