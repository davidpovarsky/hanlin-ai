# Original C-only capture: native runner not acquired

Run [45157020895](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45157020895), attempt 1, was dispatched exactly once on `646b22918b1c56e5a6a16addcb1d3ebd982d3846` with the original `MotionUITests/testCReadableLongContentRTLTypeOrientationAndCompletion` selector. The published route selects only C and keeps the original app screenshot plus the additional full-screen landscape attachment. A, B and D were not selected.

The workflow reports failure. Its actual native job `137632459705` ended **cancelled**, with `runner_id=0`, an empty runner name and **zero executed steps**. GitHub's original annotation is retained verbatim: “The job was not acquired by Runner of type hosted even after multiple attempts.” The job interval was 10:32:27–10:47:27 UTC.

No source preparation, simulator setup, package resolution, macro admission, build or XCTest ran. The run has zero artifacts. No new screenshot, video or result bundle exists to inspect. Consequently C is **NOT_RUN** and its visual recapture is **NOT_CAPTURED**; this is not a failed animation assertion. The source hashes in the receipt identify the requested harness, not native execution or dependency validation.

The existing automated C pass from `45133334293@6772dce6` remains the latest executed result. Its clipped app-boundary landscape image still does not establish a clean visual pass. B's original failure, A's historical acceptance gap and the two unexecuted current D attempts remain unchanged. No test assertion, timing or product animation was changed, and no retry was submitted.

The sole finite watcher `job_c6999ad41ae9` ended at 10:47:58 UTC. It did not cancel or replace the independently owned root 26-selector run. The exact dispatch intent, source-confirmed dispatch receipt, native job, original check annotation, empty artifact inventory and terminal receipt are retained alongside this document.
