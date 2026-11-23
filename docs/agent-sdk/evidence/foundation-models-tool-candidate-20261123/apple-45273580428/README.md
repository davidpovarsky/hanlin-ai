# SDK02: five exact native-framework controls executed

Run [45273580428](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45273580428) at 2c41a1b7ed6b191be7529550ae1ca4501632ce8d executed all five selected methods: **2 PASS / 3 FAIL / 0 NOT_RUN**. The normal Xcode test-failure exit is65. This is an actual behavioral result, not an empty selection or a report-format failure.

## Exact outcomes

| Original method | Result | Observed issue |
| --- | --- | --- |
| rejectsUnsupportedTransportHeader() | PASS | Unsupported Authorization rejected before executor entry |
| nativeNumericSiblingCannotPartiallyExecute() | PASS | Entire generated batch rejected before approval/effect |
| nativeFrameworkHandoffUsesCanonicalExecutorAndHistory() | FAIL | Both recorded requests contain no instruction entry instead of ORIGINAL_SYSTEM |
| nativeDenialReturnsThroughCanonicalHistory() | FAIL | Same missing original system instruction on both requests |
| nativeCancellationStopsAwaitingExecutor() | FAIL | Consumer failure field is nil and executor cancellation acknowledgement is not yet true at immediate observation |

The two continuation methods record no failure for their other original assertions: host effects/approvals, normalized provenance, call and output identities, original user-history shape, and final continuation text. Their complete case status remains FAIL. Cancellation's zero-effect and zero-approval assertions passed, but its complete case also remains FAIL.

## Source diagnosis and pending review

The original engine supplies the base system prompt, its producer retains that prompt through step preparation, and the original provider forwards options without modification. The native candidate declares DynamicInstructions separately and supplies a replacement model history through historyTransform. Removing this redundant transform is a proposed minimal correction: the documented onPrompt callback already validates canonical entries and removes the required empty trigger before model invocation. Exact private framework transform ordering was not captured, so this remains a source-based proposed cause until verified.

Cancellation has a distinct observation problem. Swift SE-0314 specifies cancelled stream iteration ends with nil after the termination callback, and the original producer stop method schedules its actor request asynchronously. The fixture records failure only in a catch and reads physical cancellation immediately after the outer consumer returns. A reviewed correction must preserve mandatory actual executor cancellation and all zero-effect assertions; it must not invent a provider error or claim a cancellation acknowledgement that was never observed. No assertion or production source was changed by this evidence commit.

Primary public contracts:
- [Apple dynamic sessions](https://developer.apple.com/documentation/foundationmodels/composing-dynamic-sessions-with-instructions-and-profiles)
- [Swift SE-0314](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0314-async-stream.md)

## Reuse and artifact binding

The previous28 accepted invocations and baseline12 are separately REUSED_VERIFIED. The existing iOS AgentCore compile from452680 at846 is separately REUSED_VERIFIED under all404 package hashes, both raw locks, six toolchain fingerprints and original successful command/output. No current Core, baseline or iOS build process ran; their current exits are null. These original results are never relabeled as current executions.

Artifact14867146247 was acquired once: 115,634,861 bytes, SHA256 068f4711ff9b32dc053ccba34933dd6cd57667c08d02bdfae9cceaa95dcecf48. API binding/digest/size, CRC/member inventory,404 source hashes,84 workflow/proof hashes,32 command outputs and two raw locks were verified. The emitted summary reproduced exactly from the original exports.

Selected originals are retained here. The complete small audit packet, including frozen reference subdirectories, remains at build/sdk02-native-candidate-acceptance/header-selector-recheck/original on the owner Oracle worktree. The sole original ZIP retains all2,125 file members;1,996 xcresult/archive members were hashed but not expanded.

All four shipping capability gates remain closed. SystemLanguageModel generation is NOT_RUN, distinct from these custom-public-executor framework controls.
