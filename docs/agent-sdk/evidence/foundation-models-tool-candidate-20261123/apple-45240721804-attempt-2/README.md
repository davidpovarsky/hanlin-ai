# Native tool candidate: original Apple attempt 2 and repairs

Run [45240721804, attempt 2](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45240721804/attempts/2) executed frozen source f31147911a74e8984f2a510d6e11aec0bfb12975. The hosted runner was acquired; Xcode 27.2 (27B52), Swift 6.4.2, macOS SDK 27.2 and iOS Simulator SDK 27.2 ran on macOS 27.0.1 (26A434), arm64.

## Actual outcomes

| Scope | PASS | FAIL | NOT_RUN | Meaning |
|---|---:|---:|---:|---|
| Candidate controls | 5 | 7 | 20 | 12 boundary invocations executed; all20 SDK invocations were blocked by test-target compilation. |
| Original baseline controls | 2 | 10 | 0 | All expected failures reproduced; both cloud controls passed. |
| Candidate iOS AgentCore build | 1 build | 0 | 0 | The production dependency graph compiled on this exact source. This is separate from test execution. |

The two normalized-input cases and both cloud cases passed. Among the eight
numeric rejection cases, only nested exponent1e100 with requiresApproval=false
passed; the other seven failed the unchanged providerCalls==1 assertion with
observed providerCalls=2. Each numeric case satisfied the other assertions:
failure returned, no Host effect, no approval, no admitted tool event and no
accepted provenance/call ID. Those assertions do not turn the seven failed
invocations into passes. No complete original event trace was recorded by this
fixture, so one is not inferred from its counters.

The SDK test target failed Swift Testing macro expansion because @Suite and its
@Test entries inherited an @available declaration on their container. No schema
or native-framework test executed. The production bridge itself compiled in the
successful iOS AgentCore build.

## Original evidence and report reconciliation

Artifact [14853499914](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45240721804/artifacts/14853499914)
was downloaded once: 228,497,825 bytes, SHA256
39820954debd7ed83a3b0a38e5b01673c7378f673d2ae5d75510899281ebb05e.
API run/source/digest/size and ZIP CRC were verified. The original archive and
result bundles remain under the owning Oracle worktree's
build/sdk02-native-candidate-acceptance/attempt-2 directory; they are not
duplicated into Git. This packet retains original JSON, detailed per-method
exports, relevant complete build/test logs, raw locks and receipts.

All54 command stdout/stderr hashes,404 source hashes,6 workflow hashes and both
actual raw locks were authenticated. Original numeric argument displays contain
literal nested quotation marks: they are Swift Testing displays, not JSON
strings. The repaired verifier matches each complete display against a
collision-checked inventory of exact source values and recognizes Failure
Message diagnostics. All argument identities, unique method-bound URLs, own
statuses and exact32/12 counts remain required. Reconciliation uses the original
outputs; no test was replayed to repair the report.

## Source-level cause and focused repairs

At pinned producer e7bf, ParseToolCall returns an invalid call retaining parsed
numeric input. StreamTextActor records and broadcasts the call, emits a tool
error, and bypasses the approval/executor branch. Its continuation decision
counts that error as a completed tool output, then checks stopWhen before any
prepareStep callback or next model.doStream. This independent producer can
advance before Hanlin's outer stream consumes the rejected call and invokes
result.stop. The actual seven second provider invocations expose that gap.

The repair adds a native-only stopWhen condition at the existing producer step
boundary. It inspects the last step's tool calls with the same numeric validator
and stops before another provider request. The original twelve-case boundary
test, including providerCalls==1, is byte-identical. Producer sources, cloud
behavior, normal step budgets and dynamic-tool handling are unchanged.

The seven native-framework test entry identities remain unchanged. Availability
is moved into a private implementation helper, with explicit availability guards
in discoverable test methods. An older OS records a test failure rather than
silently passing or bypassing the framework requirements.

## Next bounded native verification

Use the existing build-ios26-unsigned-ipa.yml workflow on the reviewed frozen
candidate branch, target_validation_group=agent_sdk_exact_source_proof and
exact_test_selector=HanlinNativeToolCandidateRecheck. This executes the32
candidate cases and builds iOS AgentCore, with no simulator launch. The12
boundary cases are affected by the engine change, and the20 SDK cases have not
run. AgentCore depends directly on HanlinChatCore, so its previous iOS build
cannot be transferred unconditionally to the changed dependency graph.

The original baseline12 is reused only after checking its complete238-file
HanlinPlatform baseline overlay, immutable7523 variant, exact raw lock, pinned
producer cleanliness and matching Apple toolchain/OS/architecture outputs.
Reused baseline exit65 remains attributed to the original run; current
baseline_core_exit stays null. The reused FAIL10/PASS2 outcomes stay distinct
from all32 current candidate invocations. A failed reuse admission blocks
acceptance rather than silently executing or inventing a baseline.

Local repair checks:13 Python report/selector/reuse methods passed; Swift
frontend parse passed for syntax only. Current repaired Apple compilation and
tests remain NOT_RUN pending one coordinator-authorized submission. Public
native-tool gates remain closed; actual SystemLanguageModel execution remains
NOT_RUN.
