# Notification synchronization candidate — Oracle source evidence

## Ready for parent integration

- Base: `1f27a36e257573df0a74ec5b3b0ca3586f6854ad`.
- Candidate: `d8150350901b245d52b2637277f454a6f2da5446`.
- Git tree: `78242f94c61f2e8f2be3a64f4a59d7af23f35fc7`.
- Clean isolated checkout: `/mnt/development/projects/worktrees/hanlin-ai-cache-notification-sync-20261125`.
- Normal MiniSDK merge `c632453129feb529266662fd8c90e9c0e6aab5d3` retains head `b0cf26a668a698682f5307252f14cf0af8c6d00a`; normal wave merge `69ec622743fc1544753ef975628aa5986dc6d067` retains head `f3a0a97e63cc38acd58c0673447efe8d61b556da`.
- Final follow-up commits three original generated files and one direct fixture correction. No source edits occurred after the recorded tests/checks; the candidate snapshot binds their source bytes. No Mac operations, native builds, resolutions or native tests were performed by this agent.

The only merge conflict was `Scripts/MiniApps/stage-sdk.mjs`. The resolution retains assistant tools, declarations, examples and documentation while adding the notification contract/declaration package/documentation. No owner dirty working-tree changes were included.

## Original generation and actual source verification

Original generation changed `Package.swift`, `AI_HLY.xcodeproj/project.pbxproj`, and `docs/agent-sdk/unified-package-manifest.json`. The application source count is now 524. The original graph owns the new MiniApps notification extension and shared notification delegate. The direct `test_project_graph.py` fixture replaces a stale count of three with exact Notification/Share/Translation/Widgets membership and retains namespace/App Group checks.

| Original command or fixture | Observed result | Raw evidence |
|---|---|---|
| `generate_app_intents_resources.py --check` | PASS | `app-intents-check.log` |
| `generate_manifest.py`, then `--check` | PASS | `manifest-generation.log`, `manifest-check.log` |
| `update_project.py`, then `--check` | PASS | `project-generation.log`, `project-check.log` |
| `test_host_link_ownership.py` | 6 tests PASS | `host-link-ownership.log` |
| `test_widget_cxx_imports.py` | 1 test PASS | `widget-cxx-imports.log` |
| `test_project_graph.py` | 19 tests PASS | `project-graph-fixtures.log` |
| `node --check Scripts/MiniApps/stage-sdk.mjs` | PASS | `stage-sdk-syntax.log` |
| SDK audit `--check` | Exit 1: generated source inventory stale | `sdk-audit-check.log` |
| Reachability `--check` | Exit 1: SDK authority stale; source audit required first | `reachability-check.log` |

The 26 fixture passes are actual executions. The two stale-generated-output checks are not labeled PASS. Exact commands, timestamps, return codes and raw hashes are retained in the JSON records. `source-bindings.json` binds candidate generator/fixture/manifests/extension source, not a whole native environment.

## Preserved cache and dependency scope

`preservation-receipt.json` verifies 80 core paths, 36 local/JS paths, 11 dedicated C6/cache paths, all nine active tracked lockfiles, and all six previously resolved standalone manifests remain byte-identical to the accepted base. The shared `HanlinScriptingPlatform.swift` delta is exactly the incoming notification delta. Existing three assistant-service factory compositions remain present. Selected app acceptance remains 46 methods and 48 required invocations.

The six unchanged standalone manifest/lock pairs are Platform, AgentSDK, ParityMiniApp, TextStudioMiniApp, SefariaMiniApp and WikipediaMiniApp. Their original Apple resolution evidence remains retained. The changed AppExtensions manifest has no tracked standalone Package.resolved; its change adds a local target dependency. The canonical root generated manifest changes too, so the parent must continue its original canonical Mac preparation and verify any producer output rather than hand-editing origin hashes. No upstream package revisions were changed here.

The previous App07 build/test PASS remains bound to sealed `948bdb1fe75d31559dc8d65ae8d2e70fa69de276`. This candidate has no fresh native execution. Final immutable 80/36 reuse and incoming TypeScript proof bindings are separately assigned to the native_bridge review lane.

## Required parent-owned original refresh

Run the original `python3 Scripts/Runtime/runtime_host_archive.py sync AI_HLY/RuntimeHostResources.zip`. On the changed fingerprint, it calls the existing `prepare-runtime-host.sh`, including original SDK audit/staging and Host tests. Do not precede it with a duplicate full producer. Preserve its authentic outputs and then run original archive validation, runtime-manifest generation and native-artifact inventory/checks.

The source audit writer must precede reachability generation. Expected generated authority paths include `docs/miniapp-sdk/source-inventory.json`, `MANIFEST_REFERENCE.md`, `extension-reachability.json` and `extension-reachability.md`. The old prepared ZIP cannot claim the changed notification source fingerprint. Existing original Expo/NativeScript binary producer inputs and upstream locks were not changed by this notification delta.

## Acceptance boundaries

Incoming owner evidence has one TypeScript node:test PASS (one valid compilation and five diagnostic cases), not six tests. Its final-input reuse is separately bound by native_bridge. It provides no native, OS-callback or installed-app proof.

The incoming eight SwiftTesting methods/nine invocations, extended installed-Expo reply/failure selector, unavailable-storage case, OS notification callback behavior and new standalone MiniApps notification extension embedding are not executed by the 26 Oracle fixtures or cache app suites. Keep that broader owner acceptance separate. Parent owns the next affected application validation. Live provider requests, billing claims, deployment and release are outside these source checks and remain unperformed.
