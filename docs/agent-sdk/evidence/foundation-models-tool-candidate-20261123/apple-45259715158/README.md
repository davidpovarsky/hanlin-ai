# Native candidate recheck45259715158: actual outcomes

[Original run](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45259715158)
executed c93b966e6c378f56b98d7805b5086a72d3061803 with producer
e7bf34111e603ca977becd007dd4e5bb109af857. The exact route was
HanlinNativeToolCandidateRecheck / agent_sdk_exact_source_proof.
All unrelated boolean workflow inputs, including runtime_publish_release, were false.
Only the SDK job executed; no simulator was launched.

## Executed outcomes

| Scope | PASS | FAIL | NOT_RUN |
|---|---:|---:|---:|
| Original engine boundary | 12 | 0 | 0 |
| SDK schema/framework controls | 16 | 4 | 0 |
| Candidate total | 28 | 4 | 0 |

Current iOS HanlinAgentCore production compilation passed. The original twelve
boundary cases were unchanged, including providerCalls==1 for every numeric
rejection case. This establishes the targeted producer-boundary repair on e7.

The baseline12 was REUSED_VERIFIED after every exact source/artifact/raw-lock/
producer/toolchain/OS/leaf guard. Its ten expected native failures and two cloud
passes remain attributed to45240721804 attempt2, not to this execution.
No baseline subprocess ran here; baseline_core_exit is null.

The four actual failures were:
- nativeFrameworkHandoffUsesCanonicalExecutorAndHistory
- nativeDenialReturnsThroughCanonicalHistory
- nativeNumericSiblingCannotPartiallyExecute
- nativeCancellationStopsAwaitingExecutor

The first two reported unsupportedSettings and zero native executor requests.
The latter two could not observe the required executor entry/cancellation.
The SDK log records four unsupportedSettings errors. No assertion was removed,
and these are genuine FAILs. Direct native doGenerate handoff, native schema
construction/number rejection, canonical-history rejection and all13 schema
invocations passed.

## Source diagnosis and next affected scope

The pinned original producer always adds User-Agent in StreamText.swift and
forwards that transport metadata to LanguageModelV3CallOptions. The candidate
bridge rejects any nonempty headers, unlike the original public text provider.
Its direct doGenerate control passes because that request supplies no headers.
This is a source-level diagnosis consistent with the observed errors; the
fixture did not retain a raw options trace.

The proposed repair admits only case-insensitive User-Agent transport metadata,
which never becomes native instructions/history. Other headers and unsupported
generation settings stay rejected. The four failed test bodies and assertions
remain unchanged. A subsequent native submission requires coordinator review
and should target those four methods plus the new header admission control;
the accepted28 are retained with their exact source provenance.

The separate prospective07431 producer analysis is included as source reasoning.
It changes no pins or results here. None of these32 fixtures covers a completed
tool step labeled stop; that migration has a separate three-case worktree and
will not weaken the exact e7 baseline reuse contract.

## Evidence authentication

Artifact14860542354 was acquired once,117,348,666 bytes, SHA256
e3301405f1b28281ca93cc1ce5086c19a0f2e25976ffee2da4eff825dbcf3e09.
API source/digest/size and ZIP CRC passed. All404 source hashes,22 workflow/proof
hashes,46 command stdout/stderr hashes and two actual locks were authenticated.
The current verifier reproduced the original summary exactly from the retained
exports, including every source-bound argument invocation.

The original ZIP and result bundles remain in the owning Oracle worktree under
build/sdk02-native-candidate-acceptance/recheck-1. This packet retains the original
small exports, full command logs, exact locks and baseline reuse proof, without
duplicating the archive into Git.

Public native-tool capability remains disabled. SystemLanguageModel execution
is NOT_RUN; deterministic public-framework execution does not establish eligible
on-device model execution, original Host runtime acceptance or task completion.
