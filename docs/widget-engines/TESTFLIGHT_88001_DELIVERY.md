# TestFlight delivery — 0.7.3 (88001)

[נועם | DEV] [MAIN_SESSION] Delivered at the owner's explicit 2026-11-03 request following Pass 4 verification. Owner physical iPad acceptance remains pending.

| Field | Observed result |
|---|---|
| App | ChavrusaChat, com.itorah.chavrusachat |
| Version / build | 0.7.3 / 88001 |
| Source | bac84e3a3968daba9768c6525ffd21be52f45d28 |
| Branch | integration/hanlin-dual-widget-engines-20261029 |
| Workflow | [41568291224 — SUCCESS](https://github.com/davidpovarsky/hanlin-ai/actions/runs/41568291224), total 43m57s (signed job 39m01s) |
| Toolchain | Stable Xcode 27.1 (27A9275), iOS 27.1 SDK, per-job DEVELOPER_DIR |
| Archive / export | EXECUTED_PASS, signed Release App Store Connect IPA |
| Signature / provisioning verification | EXECUTED_PASS for app and all four extensions, matching existing team and App Groups; existing distribution identity/profiles reused |
| App Store Connect validation | EXECUTED_PASS, no validation errors at 2026-11-03T03:18:08.5798510Z |
| Upload | EXECUTED_PASS, UPLOAD SUCCEEDED with no errors at 2026-11-03T03:21:06.0949610Z |
| Apple processing | VALID, observed 2026-11-03T03:31:19.6882290Z |
| Temporary signing cleanup | EXECUTED_PASS |
| IPA SHA256 | 0c02d6fb98918e6310546a99459eeee3928e6f029d586aec4cbf3da87e80769b |
| Retained artifact | ChavrusaChat-signed-ipa-88001, ID 13202017641, 260154676 bytes |
| Artifact ZIP SHA256 | d54eb553f5d9a1118af64bd1b2b5b2ad34b00ce7408a377952148739603d4e46 |

Distributed extension identifiers: `com.itorah.chavrusachat.share`, `com.itorah.chavrusachat.widgets`, `com.itorah.chavrusachat.translation-provider`, `com.itorah.chavrusachat.notification-service`. The archive verification checked their signatures, provisioning/App Groups and build number `88001`. Fifteen required main-app privacy purpose strings were present. Signing secrets were neither replaced nor committed.

This build contains all Pass 4 fixes (`P4-01` through `P4-06` at code SHA `35fa7b06dcf6ae68e2ad13d0a27176e45de9767e` and evidence commit `bac84e3a3968daba9768c6525ffd21be52f45d28`):
- **P4-01 (`/private/var` App Group canonicalization):** Fixes the `/private/var/mobile/...` vs `/var/mobile/...` `standardizedFileURL` mismatch in `HanlinScriptExtensionStore.rejectSymlinks` that caused `invalidArtifactReference` on physical iPadOS (`0.7.3 (87401)`).
- **P4-02 (Two-store non-destructive publication consistency):** Decouples `HanlinAtomicScriptStore` installation from `HanlinScriptExtensionStore` snapshot publication and exposes idempotent `republishWidgets(for:)` recovery.
- **P4-03 (Actionable Package Information UI):** Auto-selects `Default` in `Copy from`, auto-attempts one idempotent `republishWidgets(for:)` recovery if `widgetInstances` is empty, and shows a structured diagnostic card with `Retry Widget Publication` and `Copy Diagnostic` on any storage failure.
- **P4-04 (Widget-only row routing):** Tapping a widget-only package (`Hanlin-ScriptWidget-Actions`, `Hanlin-ScriptWidget-Dashboard`, `Hanlin-Expo-Widget-Visuals`) in **Add Apps** opens **Package Information** instead of launching it as a foreground app.

This upload is distinct from public App Store release or a `main` merge; neither was performed. Asana remains read-only. Zero widget-authored changes were made to the four frozen Chat UI files (`AI_HLY/ChatView.swift`, `AI_HLY/Views/Components/ChatViewBottom.swift`, `AI_HLY/Views/Components/ChatViewComponents.swift`, `AI_HLY/Views/Components/ChatandFile.swift`).

Actual SpringBoard widget placement, button/toggle execution, and physical iPad acceptance remain `OWNER_DEVICE_QA_PENDING` on build `0.7.3 (88001)`: see [device checklist](DEVICE_ACCEPTANCE_CHECKLIST.md) and [CI evidence](CI_AND_DEVICE_RESULTS.md). `VALID` processing is delivery evidence, not physical-device interaction acceptance.

### 2026-11-03 Physical Device Retrospective & Pass 5 Scope
On 2026-11-03, owner physical iPad testing of build `0.7.3 (88001)` reported `OWNER_REPORTED_FAIL`:
1. **WidgetKit System Picker Empty (`WK-03` / `WP-04`):** In the iPadOS system Edit Widget configuration sheet, tapping "Widget instance" displayed no selectable installed scripts/instances (`NO_SCRIPT_SELECTION_IN_SYSTEM_WIDGET_CONFIGURATION`).
2. **Missing Chat V3.3 / OrganizerDock (`CH-01`):** Build 88001 branch (`integration/hanlin-dual-widget-engines-20261029`) lacked the owner-approved Chat V3.3 / OrganizerDock repairs separately delivered in TestFlight `0.7.3 (87901)` on `fix/hanlin-organizerdock-v33-final-repair-20261101`.
Both issues are addressed in Pass 5 under unified branch `fix/hanlin-widget-picker-dock-unified-20261103`. Delivery facts for 88001 remain authentic and historical.

Raw workflow log is preserved outside Git at `C:/Users/DAVID/.codex/backups/hanlin-testflight-41568291224/job-125694985379.log`. The signed IPA and SHA256 remain in the linked workflow artifact (`13202017641`).
