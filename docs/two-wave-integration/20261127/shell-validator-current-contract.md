# Shell acceptance contract reconciliation — 2026-11-27

[SUBAGENT] `/root/mac_build_resume`; independent integration/review owner: `/root`.
Candidate scope: the original Python validator and its existing unit-test fixture. No production source, native executable, command permission, shell implementation, workflow command, timeout, or acceptance launch behavior changes.

## Actual failure and provenance

The original Release `AI_HLY` arm64 Simulator build on clean source `b723338e995b14dc31f96a90ad4c865e8a4b345a` passed, as did the original SDK/resource/localization/iOS-system/dyld scans and owned boot. The same product then executed the existing `HANLIN_RUNTIME_ACCEPTANCE=shell` entry point on iPad Pro 13-inch M5 / iOS 27.0. It emitted its genuine report at 2026-11-27T14:06:17Z.

- Runtime app executable SHA-256: `4558b8ead012d063efc8ab23d0527937c0dadaf707e7cd628d1c24860707a071`; arm64 UUID: `7474662B-A79A-3561-AF42-7427CC763FB9`.
- Actual Shell report SHA-256: `46a5eba972c7b00022cd399f837bcfd42f764f8925a628feaf992897ac3ce26e`.
- The current report contains 23 successful command results, five successful current policy rows, zero workspace escapes, and a real canonical `runtime.core` PASS with zero mismatches.
- The original validator SHA-256 `7482501923c203b41dcfc889813722b4606b23b7a4eaa24bcc1be89a5264b9db` failed at its exact policy-set assertion because it expected seven obsolete row names.
- This original attempt remains **FAILED** at Shell validation. MCP is **NOT_RUN**. The post-validation 15-second liveness and later canonical workflow statements were not reached by that failed branch; the report's contents alone do not promote the original attempt to PASS.

Complete immutable original evidence is retained in Oracle handoff `original-release-b723338e-terminal`, manifest SHA-256 `7af4669d25c7b3744a152f7a202333ab60df76dcf70329c4f56ce6a3d3d6c2af` (69 members), including the raw build xcresult, original logs, scans, native report, ownership receipts, and full 4,498-file runtime-app inventory. The accepted Host archive remains `d83702acbcc7ce22f672a2c1952a6f3623606cda227fdc27172a03dc1caf5f42`; all 392 SDK source inputs still match fingerprint `0a9d3ca8f320af72485cab3d998be4861c1d858fe758c5f79e7b15d555937c50`.

## Authoritative current producer

`AI_HLY/Downstream/RuntimeCore/Shell/ShellRuntimeSmokeSuite.swift` SHA-256 `75e7ba46898a4ef86110c4600027bfd198bb9c6db666906c7cdb80dfe79be113` emits the five current policies. The existing native method `HanlinUnifiedHostServicesAgentAcceptanceTests.shellAllApprovedCommandsAndPolicies` independently requires those same five identities and all 23 commands.

These semantics predate this two-wave repair. Commit `77a914f34d68a12276917a446511345a32a45b94` (2026-11-10) explicitly replaced the obsolete parser/network-denial smoke checks with actual linked-native dispatch. Commit `bb43d7c91e231a978302828cf64d2a8d17b04963` added real chaining, `2ea15eaba4f221ecd77c11cc74bb925b36354f62` routed command-string chaining through the existing portable shell, and `21d5fcfe06608b1dc5945012369df1bdd2932390` fixed its concrete echo/output witness. This candidate reconciles the validator to that existing product contract. It does not introduce those behavioral changes.

## Explicit mapping of all seven legacy assertions

| Legacy assertion | Original meaning | Current source-owned requirement and actual witness | Disposition |
|---|---|---|---|
| `unknown_command` | Reject execution of unlinked `sh`. | `verified_command_catalog` executes the same unlinked `sh` request and requires rejection; the actual report records the verified-catalog error. | Same semantic requirement retained under its current producer identity. |
| `pipeline` | The old tokenizer rejected a pipe. | `native_pipeline_and_redirection` executes `cat cat-input.txt \| tr a-z A-Z > pipeline-output.txt`, requires exit 0 and exact `CAT-OK\n` file output. | The legacy rejection was intentionally superseded in commit 77a914f by genuine linked-native pipeline execution. The candidate does not claim these opposite assertions are equivalent. |
| `redirection` | The old tokenizer rejected output redirection. | The same current native pipeline case reads the actual redirected file and compares its exact contents; workspace containment remains independently required. | Legacy denial intentionally superseded in commit 77a914f; real redirected-output verification is required. |
| `command_chaining` | The old tokenizer rejected `&&`. | `portable_command_chaining` invokes the existing Node portable-shell route with `echo first > chain-output.txt && echo second >> chain-output.txt`, requires exit 0 and exactly `first\nsecond\n`. The actual report includes those values. | Legacy denial intentionally superseded; current concrete chained execution is required. |
| `curl_https_permission` | An HTTPS request with `allowNetwork: false` was expected to fail at a separate Hanlin permission gate. | `curl_https_native_dispatch` passes an HTTPS URL argument to actual curl with `--version`, requires exit 0 and curl output. The producer explicitly states the second Hanlin network gate is obsolete. | The Hanlin-only denial requirement was deliberately superseded in commit 77a914f. This offline case proves dispatch, not a network transfer, TLS behavior, or OS network permission. |
| `curl_http` | An HTTP URL with `allowNetwork: true` was expected to fail at the former scheme restriction. | `curl_http_native_dispatch` exercises an HTTP URL argument in the same offline native `--version` route and requires successful curl output. | The Hanlin-only HTTP-scheme denial was deliberately superseded in commit 77a914f. It does not prove an HTTP transfer. |
| `curl_offline_version` | Repeat the success of the existing actual curl command result. | The mandatory `curl` command result still requires boolean PASS, exit 0, and output identifying curl; both current URL-dispatch cases also execute `--version`. | Offline-version semantics remain enforced by the original command validation and current producer checks; the duplicate legacy policy row is absent. |

There is no claim of real network-transfer coverage in this Shell gate. Neither the historical rejection checks nor the current explicit offline dispatch checks establish that separate behavior. No production policy or native permission is changed by this reconciliation.

## Preserved and strengthened validator requirements

The current expected policy set is exact: verified command catalog, native pipeline/redirection, portable chaining, HTTP native dispatch, and HTTPS native dispatch. Every row must be unique and every expected policy must report the literal boolean `true`. Missing, extra, duplicate, false, or nonboolean success rows are rejected.

All existing command registration, dynamic-catalog rules, 23 required commands, command exit codes, curl output, initialization count, side-loading prohibition, ready/health state, workspace containment and zero-escape checks remain unchanged. The original dynamic catalog superset behavior remains allowed; this does not relax the required approved command catalog.

The original workflow's canonical-shadow checks remain byte-identical: the actual report must contain canonical evidence, `mismatchCount` must be zero, and `runtime.core` must be `passed`. The original Shell 120-poll, MCP 360-poll, 15-second liveness and 240-minute job limits remain unchanged. No legacy-name compatibility path is added.

## Verification and remaining gate

The existing validator unit fixture now spells out the current native producer contract independently of the validator's expected-set constant. This prevents the previous circular fixture from silently adapting to a stale validator. The original five tests remain, with explicit missing/extra/legacy/duplicate/failed/nonboolean policy controls and an offline curl-output control added. The original workflow source tests remain unchanged.

Portable validation against the retained genuine report can establish that the corrected validator interprets that report correctly. It is **not** a fresh native Shell/MCP pass, and cannot rewrite the failed original attempt. A reviewed, source-qualified continuation must still complete the original real launch sequence and every remaining original check. The existing accepted Release app may be reused only after exact product/source/input qualification; no package603, iOS79 or Host188 rerun is implied by this validator-only change.
