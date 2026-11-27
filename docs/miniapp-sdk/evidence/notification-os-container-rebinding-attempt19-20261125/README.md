# Original notification OS probe: retained failure and container diagnosis

This packet preserves the first additional original notification OS probe, its actual failure, and the read-only evidence explaining that failure. It does not record a delivery PASS.

## Actual result

The original selected case was `HanlinMiniAppsUITests/MiniAppsProductionRuntimeUITests/testOriginalNotificationAuthorizationAndOSDeliveryToBothEngines` on source `d4a0b115b106d4250ea40ad66153d5156847a07c`. It started at 18:41:11 UTC and finalized at 18:47:04 UTC on 2026-11-25. The actual UI case failed after 251.543 seconds while waiting for the external completion file at line 1584. The controller recorded `FAILED`, committed its actual 353.58866224999656-second charge once, and completed owned-process and simulator cleanup without source or cleanup errors.

The original permission flow reached “Notifications authorized.” The external worker produced zero observation files and did not reach its first push. This attempt therefore establishes neither actual notification delivery nor a notification permission failure.

## Proven observer-binding failure

The pre-test control bound the worker to runner data container `9B37C117-33C4-420A-89D1-1A9A16F75D4B`. XCTest replaced that directory. The real runner subsequently wrote fresh `active.json` and `expo.request.json` in `FC80577A-6432-4FB4-A113-DA91458A21B0`, authenticated by the exact runner MCM bundle identifier. The worker continued waiting in the old directory.

The original Mini app data directory also changed from `C129E146-10B3-4B74-81C5-5D5FFF89DC38` to `CD73F996-FB42-42E4-B1DE-7287569F3A54`. The original App Group identifier remains `group.com.itorah.chavrusachat`. Directory UUID and MCM metadata UUID are recorded separately; they need not be equal.

The subsequent read-only current-container observation verifies all 11 original staged Documents inputs and the existing 825-byte original ScriptWidget Actions package byte-for-byte. No input, queue, permission state, receipt, fixture or product source was changed by that observation.

## Evidence and boundaries

- [terminal/receipt.json](terminal/receipt.json) authenticates all 49 retained terminal members, including the original selected-test result, command logs, control and worker sources, decision, ledger, cleanup and selected original UI attachments.
- [handshake/receipt.json](handshake/receipt.json) authenticates four retained metadata/handshake members and records the absent old runner directory, actual fresh exchange files, and empty observer output.
- [current-container-inputs.json](current-container-inputs.json) binds the actual current MCM identities and unchanged 11 inputs plus the original Actions package.

The full 52-case and NativeScript five-engine successes remain independent evidence. The original worker, UI assertions, product binaries, source and SDK were preserved for the continuation. That continuation has its own result packet; this failed attempt and its elapsed charge are retained unchanged. A later PASS must not be substituted into this attempt's records.

All files were copied from finalized capture packets. This assembly ran no test, build, import, push, simulator command or product mutation.
