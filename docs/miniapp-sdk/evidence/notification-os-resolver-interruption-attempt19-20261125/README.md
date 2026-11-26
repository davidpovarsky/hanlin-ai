# Notification OS probe: package resolver interruption and exact prebuilt test metadata

This packet preserves the actual `notification-os-v5` interruption before any original XCTest case began. It also retains the unchanged built MiniApps xctestrun and the diagnostic evidence for using that artifact directly in a separately controlled continuation.

## Actual execution boundary

The controller started at 19:41:38.894788 UTC on 2026-11-25. Setup completed, and the original project/scheme `test-without-building` command was launched. The parent observer successfully loaded the original helper and repeatedly resolved the current runner container.

Xcode's log grew with repeated new `Resolve Package Graph` entries. No fresh test handshake, worker or notification push occurred, and no xcresult Info.plist finalized. The original stale 18:43 active file remains explicitly stale history. The selected-command record exists, but it is not evidence that a selected XCTest case executed.

A bounded three-second sample was taken from the verified owned Xcode PID. SIGINT was sent only to the verified owned controller at 19:50:24.542197 UTC, allowing its existing cleanup/accounting path to run. The actual terminal at 19:50:29.667663 UTC records a 530.7739816670073-second charge. This packet contains no product-test PASS or FAIL result.

## Cleanup warning and later observation

The raw terminal status is `CLEANUP_INCOMPLETE`, with `test group cleanup: [Errno 1] Operation not permitted`. The owned simulator reached Shutdown and the source error list was empty. The terminal's missing test-group remainder entry is preserved; no synthetic empty entry is inserted.

A separate read-only observation at 19:52 found controller 7320, test child 7517 and Xcode 7530 absent, and verified that PGID 7517 was absent. It binds the exact terminal/ledger/primary and is retained with SHA-256 `479c32388bda3ad690e19444f4986c71ab68e2aef98e06c04ad69a373c1fd9e9`. This later observation does not rewrite the original cleanup warning.

All three original OS charges remain in the immutable ledger. Their sum is 897.3027506670041 seconds of the original 900-second allowance, with 2.6972493329959 seconds unused. Any later separately authorized observation keeps this history intact.

## Resolver diagnostic and inference

The actual sample includes Swift package directory synchronization and `SPMPackageDirectoryStructureFileSystemWatcher.fileSystemEventHandler` / `packageStructureDidChange` frames. The observer was creating new bounded lookup evidence files under the project tree. Those writes are a possible trigger for repeated package graph invalidation; this is an inference, because the sample does not identify a specific changed file. No network-failure cause is established.

The proposed direct-artifact command uses the existing xctestrun without opening the project/scheme package-resolution path. It retains the original selector, UI bundle, target app and original test/worker assertions. That later execution has its own decision, ledger and result; none is inferred here.

## Exact prebuilt artifact

The unchanged 16,737-byte `HanlinMiniApps_iphonesimulator27.0-arm64.xctestrun` has SHA-256 `2d6b493aa93663d03e17a15722eab010326b260ccbbb454ed12077cae45cda96`. Its original UI target is `HanlinMiniAppsUITests`, with the existing runner bundle ID, test bundle and MiniApps target-app paths. Original dependent product paths, environment and timeout metadata are preserved without rewriting the plist.

## Contents

- [terminal/receipt.json](terminal/receipt.json) authenticates all 590 terminal members, including every retained bounded container lookup, original command/log, state, ledger, controls, history and later absence observation.
- [diagnostic/receipt.json](diagnostic/receipt.json) authenticates four exact members: the verified owned interruption, prebuilt-artifact inspection, original xctestrun and compressed three-second sample.

All stored and decompressed hashes were verified before copying. This assembly ran no native command, test, build, import, push, cleanup or product mutation.
