# Paired native acceptance build-phase reporting

## Observed defect

The paired runner initialized aggregate `build` as `NOT_RUN`, invoked the MiniApps build, and only changed that field after MiniApps and the A2UI preparation command had returned. A real MiniApps build exit 65 therefore raised before any aggregate failure was recorded. `mini_build` was only assigned on success; `ai_build` was premarked failed before its command began.

The retained run 10 artifact demonstrates this exact mismatch: run `45354940642`, job `138310323164`, source `a12eb646aeb5c484f746c07ecffafc7d9f34f167`. Its original `acceptance.json` says build `NOT_RUN`, while the durable command journal records `mini-build.log` as completed, exit 65. No AI build or native UI tests ran.

## Correction

Immediately before writing final `acceptance.json`, the runner derives `mini_build`, `ai_build`, and aggregate `build` from the existing durable per-command journal. Later diagnostic or attachment commands cannot replace those records. The receipt retains the relevant command IDs, log names and observed completion/exit details.

| Observed build command | Phase result |
| --- | --- |
| No build record | `NOT_RUN` |
| Recorded completed exit 0 | `EXECUTED_PASS` |
| Recorded completed nonzero exit | `EXECUTED_FAIL` |
| Recorded timeout | `TIMED_OUT` |
| Process launch failed | `LAUNCH_FAILED` |
| Recorded interruption | `INTERRUPTED` |
| Started or exited without recorded completion | `INCOMPLETE` |

Both product builds must have recorded successful completion for aggregate `EXECUTED_PASS`. A successful MiniApps build with an unstarted AI build is `INCOMPLETE`. Unreadable/malformed journal evidence produces aggregate `INCOMPLETE`, unknown build phases and an evidence error; it cannot promote a pass.

The `command()` implementation, all 30 existing command calls in `main()` (arguments, ordering, options and timeouts), test plans, selector/count requirements and native UI result acceptance block are unchanged. There is no build-reuse branch in this runner. No workflow, SDK generation, product code, native assertion or OS signal policy changed.

## Focused verification

A new regression executes the production `main()` and final receipt path with a real subprocess that exits 65. Only simulator discovery and cleanup are stubbed, so the case is portable on Linux and makes no native-build claim. Before the correction, it failed because actual `build` was `NOT_RUN`; after the correction it passes with build and MiniApps `EXECUTED_FAIL`, and AI/UI `NOT_RUN`.

The existing portable command-evidence harness was extended, retaining all earlier checks. The eight affected tests pass: full finalization failure; both-build aggregate plus later cleanup; launch failure; streamed success; nonzero and signal exit; real timeout/child cleanup; real SIGINT cleanup; and external SIGTERM with retained unfinished evidence. A signal exit of -1 remains a completed failure and is not confused with a timeout returning -1.

Hard external termination does not guarantee execution of Python `finally` or a new acceptance file. The durable journal remains the evidence in that case; an unfinished observation stays `INCOMPLETE` and never becomes a completed pass.

Commands and raw output are recorded in `minibuild-reporting-red.command.json` and `phase-reporting-green.command.json`. Their complete command journals and subprocess logs are in `red-command-evidence/` and `green-command-evidence/`. No native test, simulator run or CI request was made in this lane.

## Authentic artifact reconciliation

`real-run10-reconciliation.json` applies only the corrected reporting transform to the already retained authentic run 10 journal, recording source artifact hashes and before/after fields. It produces:

- Aggregate build: `EXECUTED_FAIL`.
- MiniApps build: `EXECUTED_FAIL`, completed exit 65.
- AI build and UI: `NOT_RUN`.
- Overall status: unchanged `BUILD_FAILED`.

The original run 10 artifact and full raw logs remain unmodified in `../native-gate-10-button-role-20261124/`. This read-only transformation is not a native rerun. Root owns the next native dispatch.

Independent read-only review by control_authoring found no concrete blocker in the exact source delta. The runner and its test are absent from SDK source-input and current reachability/reference source lists; this change requires no SDK or source-map regeneration. Evidence remains under the already excluded evidence subtree.

`source-contract-comparison.json` records preservation checks; `receipt.json` binds results and artifacts; `SHA256SUMS` covers all retained evidence including the receipt.
