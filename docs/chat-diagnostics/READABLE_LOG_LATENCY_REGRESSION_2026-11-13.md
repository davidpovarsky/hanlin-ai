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

## Authenticated native results and next UI failure

At cbb0d8e3, isolated iOS run43325302797 executed all19 actual cases
in23.895s (4 suites), Xcode27.2/27B52 Swift6.4.2 on arm64 iPhone18Pro
iOS27.0/24A434. Artifact13993570421 (244032B) was downloaded; GitHub
SHA256 f83150186c496a9b8efdea31c80e678eb4d4f1aef71f8905c7c114c614860d88.

Full-app run43325255401 executed41/41 selected unit cases in37.429s,
including actual Recorder/device-Keychain/capture/review, compiled intent
delivery, Expo file boundaries and37 Core obligations. Its separate diagnostics
UI failed at line51, so the overall workflow FAILED. Artifact13995225808
(65,565,832B) was downloaded and actual ZIP SHA256 verified as
2e8d3716451a393aa0414e288d5db5fd0ab0f8732b0dbb80678a33def9271dd6.

The actual retained native UI hierarchy shows authenticated26 records/21 stages
and a valid review. The request's system history/tool schemas consumed the
entire65,536-character visible prefix before response comparison or SDK content.
The visible request contains the fresh unique user marker, but neither the
expected CAPTURED response nor SDK content appears in that prefix. This is
a review ordering defect; it does not establish a transport/capture failure.

The report now puts all response comparisons before full requests; no request
is truncated from the full report. A new actual journal/replay regression uses
a request larger than the UI budget and requires both actual parser/SDK
responses in the preview plus the entire history in the complete report.
Only the affected seven-case RawReview suite and failed UI need execution;
unchanged schema/export/journal cases retain their original individual evidence.
The workflow now accepts the existing exact selector for that seven-case suite
and verifies each actual leaf; unknown filters fail instead of running zero cases.

Native response-ordering verification at88518328: run43388284038
executed7/7 selected RawReview cases/1 suite in69.758s, including the new
large-request preview case17.214s. Workflow10m42s, Xcode27.2/27B52.

Run43394275453 atf9d264af passed the UI's actual fresh-marker response, device-key
decryption, authenticated record and offline SDK replay assertions. The UI case
then failed at line61: the share action after the65,536-character List row was
not instantiated in the visible hierarchy. This is a failed UI case, not a UI
pass. Move the existing ShareLink into the native navigation toolbar so sharing
the complete redacted report remains available while reading any preview
position. The same strict UI case must execute again; no sharing is activated
by the test and the encrypted source/key remain excluded.

Corrected run43402191132 at86ef18ed actually PASSED the exact diagnostics UI
case in109.431s. The fresh uniquely identified ordinary turn, confirmation,
actual device-key lookup/decryption/authenticated records, parser/SDK replay,
credential masking, visible share action and dismissal all passed. The test
did not activate external sharing. The overall run FAILED a separate NS VM
entry-loading method (9/10 unit methods passed); do not report overall CI green.
Physical new/upgraded defaults, Files visibility, crash/cancel recovery, complete
cross-layer/provider comparison and stream performance remain separate gates.
Downloaded artifact14019563661 (223671B), GitHub SHA256
050427772514b733c0573df390963e9a5d7eea6be101b7f189e33cc3555d7855.
The failed real UI is separately pending in43389506393 with only the new
NativeScript wire suite, without repeating unchanged41 unit cases.
