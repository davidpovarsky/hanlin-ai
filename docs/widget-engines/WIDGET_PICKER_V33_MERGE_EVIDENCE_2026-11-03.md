# Hanlin Pass 5 — WidgetKit Picker & OrganizerDock V3.3 Synchronization Evidence
**Date:** 2026-11-03
**Repository:** `davidpovarsky/hanlin-ai`
**Task Branch:** `fix/hanlin-widget-picker-dock-unified-20261103`
**Logical Acting Identity:** `[נועם | DEV] [MAIN_SESSION]`
**Asana Status:** READ-ONLY (No writes, comments, or modifications made)
**Release / Deployment Status:** NOT DISPATCHED (No `main` merge, no forced push, no TestFlight upload without separate explicit owner authorization)

---

## 1. Branch & Source Provenance

| Component | Source Reference | Commit SHA | Verified Status |
|---|---|---|---|
| **Widget Integration (Pass 4)** | `origin/integration/hanlin-dual-widget-engines-20261029` | `a6a836cd665b4d76107f1708ef17b30d7680e24d` | Signed 88001 code at `bac84e3a3968daba9768c6525ffd21be52f45d28` |
| **OrganizerDock V3.3 (Pass 3.3)** | `origin/fix/hanlin-organizerdock-v33-final-repair-20261101` | `35b9782bda76e2b2789d0532d22cf71a1a3f3500` | Code SHA `c7b8d0127ddd980f29735aba8ae7fc4a3d8c0207` |
| **Shared Fork Point** | `git merge-base` | `279f0ead777b961728ed91386c136e7e33659c36` | Signed 87401 fork point |
| **Synthetic Merged Tree** | `git merge-tree --write-tree` | `2b153a84626d40cad6537b2f3b8c6981c51690f8` | Exit code 0, 0 textual merge conflicts |
| **Task Branch Integration** | `fix/hanlin-widget-picker-dock-unified-20261103` | Working HEAD | Normal merge preserving both branches' commit histories |

---

## 2. Invariant & Cross-Domain Audit

### 2.1 Protected Classic Chat Files (Byte-Identical to `279f0ead`)
- `AI_HLY/Views/Components/ChatViewComponents.swift` — `0` diff lines (`bc2ff417d810301cfaef5e89d578aba66427df8f`)
- `AI_HLY/Views/Components/ChatandFile.swift` — `0` diff lines (`4b0325aaca204e851508c369abfc85028d0a8213`)
- `AI_HLY/Services/ChatServices/APIManager.swift` — `0` diff lines (`60fe0b151f4391a1e1fd7ebe84337c6d2cd272a5`)

### 2.2 Preserved 11 Approved Chat V3.3 / OrganizerDock Paths
All 11 paths match `35b9782b` / `c7b8d012` exactly:
1. `AI_HLY/ChatView.swift`
2. `AI_HLY/Downstream/ChatInput/HanlinComposerPopupView.swift`
3. `AI_HLY/Downstream/ChatInput/OrganizerDock/HanlinCompactChatWorkspace.swift`
4. `AI_HLY/Downstream/ChatInput/OrganizerDock/HanlinComposerSessionBridge.swift`
5. `AI_HLY/Downstream/ChatInput/OrganizerDock/HanlinOrganizerDock.swift`
6. `AI_HLY/Downstream/ChatInput/OrganizerDock/HanlinOrganizerDockState.swift`
7. `AI_HLY/Downstream/ChatInput/OrganizerDock/HanlinPendingFirstTurn.swift`
8. `AI_HLY/ListView.swift`
9. `AI_HLY/Views/Components/ChatViewBottom.swift`
10. `AI_HLYTests/HanlinOrganizerDockParityTests.swift`
11. `AI_HLYUITests/AgentRuntimeConversationUITests.swift`

### 2.3 Preserved Pass 4 Widget & App Group Hardening Paths
All Pass 4 canonical root, `Darwin.lstat` symlink checks, hashed artifact stores, and widget-only routing preserved:
1. `AI_HLY/Downstream/MiniApps/HanlinMiniAppHost.swift`
2. `AI_HLY/NativeAppPlatform/AppsHub/NativeAppsAddSheet.swift`
3. `AI_HLY/NativeAppPlatform/AppsHub/NativeAppsHubView.swift`
4. `AI_HLYUITests/HanlinExpoProductionE2ETests.swift`
5. `Packages/HanlinPlatform/Sources/HanlinScriptStore/HanlinAtomicScriptStore.swift`
6. `Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinScriptExtensionContracts.swift`

---

## 3. Surgical WidgetKit Picker Fixes

### Defect 1: Protocol Conformance for System Widget Picker Sheet
- **File:** `HanlinScriptingWidgets/HanlinScriptingWidgets.swift`
- **Correction:** Conformed `HanlinScriptPackageEntityQuery` to `EnumerableEntityQuery` and `EntityStringQuery` in addition to `EntityQuery`.
- **Implementation:** Implemented `allEntities() async throws -> [HanlinScriptPackageEntity]` and `entities(matching string: String) async throws -> [HanlinScriptPackageEntity]`. In iPadOS 27, tapping the parameter row on `WidgetConfigurationIntent` queries `allEntities()` to enumerate available choices in the system picker sheet.

### Defect 2: Authoritative Instance-to-Template Join (`selectableWidgetEntities`)
- **Files:** `Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinWidgetInstance.swift`, `HanlinScriptingWidgets/HanlinScriptingWidgets.swift`
- **Correction:** Replaced `availableEntities` which enumerated `snapshot.widgets` (per-family snapshots) with `snapshot.selectableWidgetEntities()`.
- **Implementation:** Joins authoritative `snapshot.widgetInstances` with active per-family templates in `snapshot.widgets` by exact identity and engine. Formats human-legible labels (`<package> · <engine> · <variant>`), disambiguates duplicate package names across installations, and guarantees deterministic ordering (Default first, then alphabetical).

### Defect 3: Idempotent Default Retention on Republish
- **File:** `Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinWidgetInstance.swift`
- **Correction:** In `publishWidgetTemplates`, if `previous.widgetInstances` has custom variants but is missing `Default`, `Default` is idempotently restored without duplicating or resetting existing `A1`/`A2` instances, settings, or migration chains.

### Defect 4: Cross-Process Durable Query Diagnostics
- **Files:** `Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinScriptExtensionStore.swift`, `AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift`
- **Correction:** Added `recordDurableQueryDiagnostic` which writes atomically to `latest-query-diagnostic.json` under the shared App Group. Exposed to host Package Information via `extensionStore?.latestDurableQueryDiagnostic`.

### Defect 5: Family Mismatch Diagnostic Clarity
- **File:** `Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinPreparedWidget.swift`
- **Correction:** When a placed widget family is not supported by the selected package, throws explicit `"This widget does not support the \(family) size."` instead of a generic stale-generation error.

---

## 4. Method-Level Unit Test Suite

Added in `Packages/HanlinPlatform/Tests/HanlinScriptExtensionsTests/HanlinDualWidgetEnginesTests.swift`:
1. `testNativeEntitySuggestionsReadPublishedDefaultAndVariants`
2. `testNativeEntityLookupResolvesOnlyExactIDs`
3. `testRegistryAndTemplateJoinHandlesFamilyAndOrphans`
4. `testNativePublisherRepairsMissingDefaultWithoutLosingA1A2`
5. `testDurableQueryDiagnosticCrossProcess`

---

## 5. Cross-Ledger References
- Test Matrix: [TEST_MATRIX.md](TEST_MATRIX.md)
- CI & Device Ledger: [CI_AND_DEVICE_RESULTS.md](CI_AND_DEVICE_RESULTS.md)
- Physical Device Checklist: [DEVICE_ACCEPTANCE_CHECKLIST.md](DEVICE_ACCEPTANCE_CHECKLIST.md)
- Release & Rollback: [RELEASE_AND_ROLLBACK.md](RELEASE_AND_ROLLBACK.md)
- TestFlight 88001 Delivery: [TESTFLIGHT_88001_DELIVERY.md](TESTFLIGHT_88001_DELIVERY.md)
- OrganizerDock V3.3 Gate: [EXECUTED_TEST_AND_DEVICE_GATE.md](../hanlin-dock-v33-source-parity/EXECUTED_TEST_AND_DEVICE_GATE.md)
- Chat Touchpoints: [ORIGINAL_CHAT_TOUCHPOINT_LEDGER.md](../hanlin-dock-v33-source-parity/ORIGINAL_CHAT_TOUCHPOINT_LEDGER.md)
- Project Board: [PROJECT_BOARD.md](../../PROJECT_BOARD.md)
