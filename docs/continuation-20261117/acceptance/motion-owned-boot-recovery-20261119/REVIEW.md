# Motion boot timeout recovery proposal

## Authenticated failure

Run44454057890 used source031a331ad8c9819abe477f3c91517533d07234d4. Its actual job environment selected input-diagnostic, meaning MotionUITests/testDRapidInputDiagnosticOnly. The job's old two-case label was inaccurate for that dispatch.

The native command xcrun simctl bootstatus 62772238-C9DF-43BF-878E-2D234E3CFEEF -b timed out after180seconds. Preflight ended after234seconds. The original bootstatus output file was empty; a later inventory reported Booted, which is not boot-readiness proof. The original owned-simulator cleanup completed successfully. Project generation, build and native UI test execution were not reached. D is NOT_RUN and original A/B/C acceptance remains unproven by this run.

Artifact14500066916 is13,969bytes with official GitHub digest31eee1441e43169dfe03d045200a0a7fbce94733790d615f76c737ccf4dbd54d. The actual native job log is22,262bytes, SHAb967061573d191b0a91919e7a87647a8b83fb468f1ea41c1398bd4fdf94c9fd1. Exact timestamps, scope and failure excerpts are in native-failure-receipt.json. The underlying CoreSimulator stall cause is not established.

## Narrow implementation

The original inline boot preflight moves to Scripts/CI/boot_motion_simulator.py. Successful ordinary startup keeps the same15second initial boot and180second bootstatus allowances. The existing production stager uses a300second cold-boot allowance; this proposal does not increase Motion's per-attempt readiness timeout.

Only an actual subprocess timeout from the first bootstatus command on the current run's freshly created Motion simulator permits recovery. It performs one shutdown of that UUID (20seconds), one boot of that UUID (15seconds), and one fresh bootstatus wait (180seconds). The maximum extra command budget is215seconds. The existing25minute job cap and every UI-test timeout remain unchanged.

An ordinary nonzero native exit, including exit124 without an actual timeout, does not qualify. Neither a reused ready device, invalid/missing/changed ownership, a failed recovery shutdown/boot, nor a second readiness timeout can trigger another recovery. There is no process-wide reset, no all-device command, no alternative simulator selection and no test retry. The UUID parser rejects values such as all before any native command.

The helper requires a successful real bootstatus result before it returns READY_FROM_NATIVE_BOOTSTATUS. Booted inventory state alone only satisfies the original ready-device selection precondition. A successful recovery does not erase the first timeout: per-command arguments, deadlines, elapsed time, native exit, explicit timeout status and raw-output hashes are recorded after every command. Raw attempt outputs and the aggregate bootstatus log are retained, including failure cases. The readiness receipt explicitly says product tests NOT_RUN.

## Original ownership boundary

The original created-selection predicate is reused from owned_simulator_receipts.py without changing its checks. Its predicate body is byte-identical: current run/attempt, original create operation, absence before creation, exact UUID/name/runtime/hardware, source-device distinction and availability all remain mandatory.

The existing non-Motion _selection wrapper retains its existing name/path derivation. A separate verify_owned_motion_creation entry point validates the original Motion name Hanlin-Phase2-Motion-<run>, its existing selection file and the same run/attempt proof. It does not broaden Live/default ownership. The immutable selection digest and full ownership receipt are rechecked before each native command and after the final readiness wait.

No change is proposed to stage_live_provider_acceptance.py or stage_simulator_fixtures.py. Their exact committed copies are included only as test dependencies to exercise the original shared-ownership regression tests. The Live IPC installation issue remains separate.

## Original test behavior and labels

All Motion project preparation, actual source extraction, build commands, selected tests, test flags, result collection and acceptance assertions after preflight are byte-identical. The original owned cleanup is also byte-identical.

The workflow only changes its Motion job/step labels to match the selected scope:

- A: original preset-cycle acceptance.
- B/C: original interaction acceptance.
- D: input diagnostic, not A/B/C acceptance.

The runner archives requested-scope.txt before preflight so another setup failure still records its requested scope. All other workflow jobs, including the new unit .xctestrun lane, are unchanged. The original B/C test identifiers remain testBRapidReversalPresetSwitchAndPersistence and testCReadableLongContentRTLTypeOrientationAndCompletion.

## Validation and pending proof

Base e32f2035dc4ffbeca43402fce2beac9f924c1a70. All snapshot inputs still matched current6d62957852ffcb428810b065b4252e5384f1374b at validation; git apply --check passed.

29 portable tests passed, zero failures/skips:12new Motion tests and17existing ownership tests. The new tests cover one successful recovery with both attempts retained, no third attempt, rejection of non-timeout exit124/204, reused-device and Booted-state controls, foreign/changed ownership, failed shutdown/reboot, UUID rejection and preservation of Live's original namespace. One test uses actual short-lived Python subprocesses to distinguish a real timeout with retained output from an ordinary exit124. Native Simulator calls are controlled fixtures; no native readiness success is claimed.

The first local test invocation exposed missing unchanged stage dependencies in the isolated proposal folder. Those dependencies were copied from the exact base commit and the complete29test run then passed. That initial packet-setup log is preserved; no product code was changed to suppress a failure.

Python AST parsing, YAML parsing and Bash syntax pass. Original predicate, cleanup and native-test tail comparisons pass. The next owned native run must establish readiness and then actually execute its originally selected tests; this packet contains no new native result.

No canonical edits, CI dispatch/cancellation, Apple execution, user credential reads or provider staging were performed.
