# Readable diagnostic sessions hidden by numeric redaction

[נועם | DEV] [MAIN_SESSION]. This was a regression in the generic secret
redactor added during this continuation, not evidence about NVIDIA/provider
response corruption. Original Build98201 metadata-only archive limits remain.

Actual [run43315911311](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43315911311)
at1e4ba8c0 finished **FAILED overall**. Its actual three Expo legacy adapter
cases passed in39.285s, including all five native backends and Python exit23.
The original-bubble Mermaid/Diff source-actions/expand UI case passed in88.101s.
The diagnostics UI case failed before opening a session. Retained native
hierarchy shows Agent Diagnostics, Full detailed logs, the original
Documents/Diagnostics path,567KB stored and No detailed agent logs. The artifact
13989953626 (68,951,436B) was downloaded and its actual ZIP SHA256 verified as
`6ade7b8891f7a153e3e5f957160ea7580685a4c162047be6d4c4ac0c6952a83d`.
The app's actual diagnostic files were not included in that artifact; the
hierarchy alone cannot establish their contents or completeness.

The source regression is deterministic: both actual session latency properties
are optional Double, but their normalized keys end in `_token`. The generic
secret rule replaced populated values with the string `<redacted>`. The list's
typed decoder then silently rejected completed sessions. The exact production
Session/Redactor/JSON encoder-decoder pipeline reproduced the failure locally:
`DecodingError.typeMismatch(Double), efficiency.timeToFirstAnswerToken`.
The initial session without populated latency decoded; the completed metric
exposed the bug. The new numeric allowlist repairs this while retaining masking
for credential keys, metric-shaped strings and booleans. Numeric0/1 are checked
by NSNumber storage type, rather than Swift Bool bridging.

The shared stored-session reader also recognizes only the exact redaction
placeholders at those two schema2 paths, omits the unavailable measurements in
memory and adds a timing-unavailable warning. It neither rewrites original files
nor guesses numeric strings or ignores other corrupt fields. Raw encrypted
sources and authentication remain unchanged.

Actual portable Swift6.3.3 Foundation tests: **4/4 EXECUTED_PASS**,0.022s,
cover typed metric roundtrip, privacy/type boundaries, read-only legacy recovery
and rejection of unrelated corruption. This is not Apple SDK or full-app proof.
The isolated iOS diagnostics workflow now requires all19 actual cases (prior15
plus4 schema cases). Shared-redactor consumers are affected, so prior15 results
are not promoted to the changed source. A full-app recorder/device-Keychain
capture/review case is also added.

The failed UI test now uses a unique current-user request/response marker and
requires that exact content in the authenticated replay report. A persisted
old RUN_B_COMPLETE cannot satisfy its completion assertion. Only this failed
diagnostics UI case needs rerunning; the passed bubble case and three unchanged
legacy adapter cases retain their original execution evidence, subject to their
own dependency closure checks. Physical/default-without-settings, forced-kill
durability and performance acceptance remain open.

Measured simulator job cost in43315911311: NativeScript preparation184s,
compiler restore61s, SPM resolution72s, app compilation375s, staging110s,
optional refresh69s, test phase972s. The latter includes test-host compilation
before the3 actual unit cases and2 UI cases; it is not39s of tests described as
16min of native execution. Keep exact filters and compatible caches; no native
engine rebuild, full project validation or publication is needed for this fix.
