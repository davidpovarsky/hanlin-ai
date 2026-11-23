# Original D diagnostic — native45146657017

**Attempt1 is BLOCKED_INFRASTRUCTURE; D is NOT_RUN.** This does not add an animation failure or change B's actual failure/C's automated pass.

The existing [Motion workflow](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45146657017/attempts/1) selected only `MotionUITests/testDRapidInputDiagnosticOnly` at exact source`6772dce6304fc6761a2200314f7d2020dc782e47`, matching B/C. An isolated validation ref retained the original concurrency group and all six original delivery variants in both scroll phases. No fixture, product, assertion, dependency or timeout was changed.

On Xcode27.2 / Swift6.4.2, the owned fresh iPad simulator accepted `simctl boot`, but `bootstatus -b` produced no output and hit its original180s deadline after180.906s. The existing single recovery attempt then timed out while shutting down that same owned simulator after21.620s. [The original readiness receipt](motion-boot-readiness.json) is `NOT_READY`; process phase is `preflight`.

No compiler command, dependency-resolution checkpoint, XCTest, diagnostic comparison, video or screenshot ran. The cause beyond the simulator-service boot/shutdown stall is unproven. Global simulator resets and longer waits were not introduced.

Artifact14804394578 (`chat-motion-ui-45146657017`) is13,360bytes with API-verified SHA256`abf99c444f9c5c94512df27e852ee97de26ccb2af93d45af36f22cd7e4847116`. The small original artifact remains on Oracle and GitHub; its inventory, original logs and environment digest are retained here.

A single failed-job infrastructure retry was accepted at09:39:49UTC as **attempt2 of the same run**, same6772dce6 source and original D inputs. The first watcher had ended; the global run lock was free and no orphan watch process existed. One new finite `gh run watch --exit-status --compact --interval60` owns attempt2. [Its dispatch receipt](attempt-2-dispatch-receipt.json) records scheduling only, not a native result. A/B/C are not selected or rerun. D, even if it later captures its comparisons, is diagnostic-only and cannot accept B.

## Attempt2: hosted runner not acquired

Attempt2 ended at09:54:52UTC with its sole native job137605591076 cancelled before any step. `runner_id` is0. The original GitHub check annotation is: **“The job was not acquired by Runner of type hosted even after multiple attempts.”** The workflow itself reports failure.

Build, XCTest and all D comparison variants are **NOT_RUN**. No attempt2 artifact exists; the only artifact in the run is the original attempt1 preflight artifact, which was not downloaded again or attributed to attempt2. The [exact native job](attempt-2-native-job.json), [original annotation](attempt-2-native-check-annotations.json) and [result receipt](attempt-2-result-receipt.json) are retained.

The single finite watcher exited1 and closed. No third attempt or replacement watcher was submitted. This establishes a failure to acquire a hosted runner for this job; it does not establish a general service outage. The original diagnostic still needs actual execution before it can inform B's input/render timing diagnosis.
