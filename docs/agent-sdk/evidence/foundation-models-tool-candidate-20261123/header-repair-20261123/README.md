# Native User-Agent admission repair and exact five-case plan

The four failed framework-to-engine controls from45259715158 stopped with
unsupportedSettings before native executor entry. Source tracing identifies the
original producer's automatic User-Agent header, rejected by the candidate's
nonempty-headers guard. The candidate now admits only case-insensitive User-Agent
metadata; it never forwards headers into native instructions, history or tools.
Every other header and every previously unsupported generation setting remains
rejected.

All seven original test/helper bodies remain unchanged. A separate
HanlinAppleToolHeaderAdmissionTests suite adds one negative control: mixed-case
User-Agent together with Authorization must throw exactly unsupportedSettings,
and the public native executor must receive zero requests. This fixture contains
no real credential and performs no network request.

## Exact next native obligation

Use the existing workflow and frozen candidate branch with
target_validation_group=agent_sdk_exact_source_proof and
exact_test_selector=HanlinNativeToolHeaderRecheck. All unrelated flags, including
runtime publication, stay false. Only these five invocations are selected:

1. nativeFrameworkHandoffUsesCanonicalExecutorAndHistory
2. nativeDenialReturnsThroughCanonicalHistory
3. nativeNumericSiblingCannotPartiallyExecute
4. nativeCancellationStopsAwaitingExecutor
5. rejectsUnsupportedTransportHeader

The current iOS HanlinAgentCore graph is built because production bridge source
changed. No simulator is launched. No CoreTests or BaselineCoreTests subprocess
runs; their current exit fields must be explicitly null.

The28 prior PASSs are separately reused only after checking the authenticated
c93/e7 artifact, every original argument identity and result, all404 package
inputs, the two precisely reviewed Swift repairs, byte-identical raw Core and
SDK locks, the pinned clean producer, and exact Xcode/Swift/SDK/OS outputs.
The original inputs of those28 controls do not enter the repaired nonempty
User-Agent branch: Core12 uses its own original-engine deterministic provider;
schema13 and schema/history2 never call that bridge admission; direct generate1
supplies no headers. This is explicit source-qualified reuse, not28 new
executions against changed source.

The old strict baseline12 guard is reused unchanged and stays bound to
45240721804 attempt2/e7. Neither the prospective07431 pin nor a changed raw lock
can pass these admissions. The five current case results,28 reused passes and
ten expected baseline failures/two baseline passes are separate report fields.

The report rejects missing/duplicate/failed/skipped cases, failure diagnostics
inside a passed aggregate, changed current selectors, extra test processes,
missing/wrong iOS build scope or mismatched process exits. Every original
reference byte is digest-bound, and the runner binds current source and proof
implementation to Git before execution.

## Checks completed

Four NEW Python report/admission methods passed in0.299s. Their synthetic current
results only test reporting/admission; they are not native execution. They also
exercise missing/duplicate cases, source/lock/reference mutation, fabricated
current exits, wrong selectors and build process mismatches. The old13 controls
were not replayed.

Swift frontend parse passed for syntax only. Shell syntax, Python runner syntax
and git diff --check passed. Native execution of the repaired five cases and the
new iOS build is NOT_RUN pending one coordinator-reviewed submission.

Four public shipping capability gates remain closed. Real SystemLanguageModel
execution remains NOT_RUN; prior deviceNotEligible evidence remains a separate
hardware/runtime blocker. No final SDK or Host acceptance is claimed here.
