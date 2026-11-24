# Existing Host job beyond 300 seconds

The one selected existing Host JavaScript test passed on 2026-11-24. The Worker elapsed measurement was 305078.587501 milliseconds. The raw TAP records exactly one test, one pass, zero failures and zero skips; process exit code was 0.

## Evidence scope

This is component evidence for the exact shipped Host JavaScript at `c31c9c5f3bb7172598bc579c33de95ee06ca79b9`, executed by the already installed Node `v24.22.0` on `linux/arm64`. It is not execution evidence for embedded Node 24.5.0, iOS, the Swift/HTTP submission path, UIKit, or operating-system background continuation.

The existing test was unchanged. It starts a real Worker through production `ExecutionJobs` and `execution-worker.mjs`, omits `timeoutMilliseconds`, awaits a real 305000 ms timer, and requires completed state, result 305, the completion output marker and elapsed time above 300000 ms. No simulated clock or shortened timer was used.

## Invocation

The test ran once, from the source checkout, with only its exact name selected:

```sh
HANLIN_RUN_LONG_JOBS=1 TMPDIR=/dev/shm/hanlin-host-long-job-20261124-node24_22/tmp /usr/local/bin/node --test --test-reporter=tap --test-name-pattern='^actual Node job crosses 300 seconds with no hidden deadline$' /mnt/development/projects/worktrees/hanlin-miniapps-sdk-completion-20261123/AI_HLY/Downstream/RuntimeCore/Node/Host/Tests/execution-jobs.test.mjs
```

`receipt.json` retains the full argv, working directory, environment overrides and relevant inherited Node/environment settings, actual process.versions/platform/arch, the metadata capture command, start/end timestamps, exit status and the emitted proof with its execution ID. It records hashes for all 35 top-level Host source/package files and the selected test before and after execution. Every file matched the authorized commit and remained unchanged during execution.

The surrounding collection process allowed 540 seconds before a test-harness watchdog; that watchdog did not fire. The production job itself had no requested deadline. No Node/npm install, other test case, native selector, application build or CI dispatch occurred.

## Authentic artifacts

- `long-job.tap.log`: complete original stdout/stderr, 452 bytes, SHA-256 `d8b512e5beb49b2b54aaec775cbd68e63fccc59f7988a15e2323334960f5cf2d`.
- `receipt.json`: source/runtime identity and derived result. It explicitly records correction of a receipt-only double-escaped regex: the initial collector misclassified its derived status despite exit 0 and successful raw TAP. Literal TAP lines corrected the metadata; the test and raw output were not changed or rerun.

The earlier Mac Host result of 165 passed and one skipped remains a separate result. This component proof closes only the previously skipped long-job obligation on Linux/Node 24.22.0.
