# Original D continuation: hosted runner admission failed

[Run 45171553469](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45171553469), attempt 1, was submitted exactly once at 12:09:01 UTC on **32b3168d73a9b92c3a774bcbb97f95941d8a4db7**. The original route selected only `ChatMotionProofUITests/MotionUITests/testDRapidInputDiagnosticOnly`: six original cases in each of the native-default and immediate-touch-down phases, including the independent-coordinate variant. A, B and C were not selected.

The workflow concluded failure, but the original native job 137682098060 was **cancelled before allocation**. Its interval was 12:09:03–12:24:03 UTC; `runner_id` was 0, the runner name was empty, and its step list was empty. GitHub's annotation is retained verbatim:

> The job was not acquired by Runner of type hosted even after multiple attempts

Consequently checkout, preparation, simulator boot, source/dependency admission, build and XCTest are **NOT_RUN**. Zero diagnostic cases executed. No per-case receipt, aggregate report, screenshot, video or result bundle was created. The run has zero artifacts. This is not a failed input, animation, reset or restoration assertion, and it establishes no new product defect.

The continuation had been admitted after the distinct C run 45166004801 actually booted a fresh simulator and passed its test. That C evidence remains valid; it did not guarantee a later GitHub-hosted allocation. The local pre-dispatch source checks also remain valid: the D method and following helpers plus fixture App.swift are byte-identical to6772, while the selected SDK source/resource paths and Motion paths are unchanged from successful C source3a9e. They are source checks, not native execution for this run.

The sole finite watcher `job_3ef994396911` ended at 12:24:22 UTC. Both its recorded process IDs were absent at readback. The dispatch intent, exact source/run readback, concurrency and source admission, original job/annotation, empty artifact inventory and watcher receipts are retained alongside this document. No second POST, replacement watcher, new capacity probe, source change or test weakening followed this failure.

D still lacks actual observations. The earlier B failure is unresolved, A remains unexecuted on current input, and the three paired MiniApps UI cases remain held for root's full-app compilation qualification. Further D continuation requires new root runner/readiness evidence and explicit coordination.
