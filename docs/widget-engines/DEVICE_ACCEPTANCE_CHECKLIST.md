# Signed physical iPadOS 27 acceptance

Status: BLOCKED_DEVICE. No signed physical test is claimed. An unsigned IPA or foreground simulator preview cannot satisfy this checklist.

Record before testing: observed_at, device model/UDID, iPadOS version, source SHA, CI run, Xcode/SDK, signing profile/type, frozen IPA SHA256 and HanlinScriptingWidgets.appex SHA256. Install that exact developer/ad-hoc signed build once.

| Step | Procedure and raw evidence | Status |
|---|---|---|
| 1 | Configure the registered Hanlin Script widget. Place legacy, Expo and ScriptWidget together; capture Home Screen screenshot and native accessibility tree. | BLOCKED_DEVICE |
| 2 | Check available small/medium/large/extraLarge families on the actual iPad. Capture each picker entity and family. | BLOCKED_DEVICE |
| 3 | After the app is built, create/import a previously absent external JSX archive through Import Preview. Record archive, generation and program digest. Freeze app/appex hashes before/after; no rebuild. | BLOCKED_DEVICE |
| 4 | Create A1 and A2 through Package Details, select them as separate widget entities, then terminate Hanlin. Same selections share state; distinct instances must not. | BLOCKED_DEVICE |
| 5 | Tap actual Expo native increment/decrement: 7 -> 8 -> 7. Tap custom status action, capture source callback trace and state revision. Verify Hanlin did not open. | BLOCKED_DEVICE |
| 6 | Tap ScriptWidget actionID and named onClick buttons. Toggle false -> true -> false; inspect Bool storage and visible state. Restart the host and verify no reset. | BLOCKED_DEVICE |
| 7 | Alternate packages with identical targets and instances; concurrent presses and refresh must preserve independent revisions. Explicit duplicate nonce must not apply again. OS retry identifiers remain an at-least-once limitation. | BLOCKED_DEVICE |
| 8 | Test lock/unlock, first unlock after reboot, offline mode, widget-extension termination, host relaunch, upgrade, disable, uninstall, stale action and retained-generation rollback. Record OS reload delays. | BLOCKED_DEVICE |
| 9 | Capture original native slots, nested Text, Chart/Gauge, ScriptWidget tags/resources, RTL, appearance and Dynamic Type. Test Link and Button hit routing. | BLOCKED_DEVICE |
| 10 | Maintain a Live Activity and Translation UI/intent records throughout actions and publication; verify unchanged records. Collect device console, screenshots/video and committed revisions. | BLOCKED_DEVICE |

Investigate Node HTTPS/fd and RNHostView layout separately if available; neither mitigation is a proven device fix. Mixed subtree is optional and deferred. Simulator Home Screen attempts and any actual automation restriction must be documented with raw logs, not inferred here. Final acceptance remains open until the signed physical rows execute.

Hardware discovery on 2026-10-31: the Windows present-device inventory exposed an iPad Bluetooth/audio pairing only, with no Apple Mobile USB/development connection and no reported iPadOS version or developer provisioning. Connected Desktop Commander inventory exposed the Linux torah-social server and this Windows workstation, with no Mac/Xcode development host. A Bluetooth pairing does not supply a signed installation/debug path. Exact missing steps: connect/trust a compatible iPadOS 27 iPad to an Xcode Mac, enable Developer Mode, choose an authorized development/ad-hoc profile, sign the frozen build, then execute the rows above and retain their logs. Signing identities and profiles were not changed.

Discovery repeated on 2026-11-01: Desktop Commander still exposes only the Windows workstation and Linux torah-social; SentinelX exposes only the Windows workstation. No connected Mac/Xcode development host or signed physical-iPad install/test session was available through either connector. The hosted CI Mac is being used for iPad Simulator validation, not as a claim of attached physical hardware.

The Nov 1 present-device scan again found only iPad Bluetooth/audio endpoints, with no Apple USB/Mobile development device. No device OS version or developer provisioning was inferred from that pairing.

## Owner delivery handoff — 2026-11-01

OWNER_DEVICE_QA_PENDING: owner requested TestFlight upload and will test on iPad. No physical-device row is changed to PASS. Additional optional simulator/device workflows were stopped; the current delivery follows the existing signed TestFlight workflow.

Delivered: TestFlight 0.7.3 (87401), Apple processing VALID at 2026-11-01T14:00:38Z. [Signed delivery evidence](TESTFLIGHT_87401_DELIVERY.md). Physical-device rows remain pending owner execution.

## Owner physical iPad test of 0.7.3 (87401) — 2026-11-01 (`OWNER_EXECUTED_FAIL` / `DEVICE_QA_FAILED`)

On 2026-11-01, the owner installed signed TestFlight build `0.7.3 (87401)` (`279f0ead777b961728ed91386c136e7e33659c36`) on a physical iPad and tested `Hanlin-ScriptWidget-Actions.scripting` (`14:15` screenshot evidence):
- **Step 3 / Step 4 (`OWNER_EXECUTED_FAIL` / `DEVICE_QA_FAILED` on build `87401`):** `Hanlin-ScriptWidget-Actions.scripting` imported and installed into `HanlinAtomicScriptStore` at generation 1 (`widgets/widget.json`, `scripting-jsc`), but in **Package Information**, `Widget instances` was empty, `Copy from` had no selection, `Create independent instance` was disabled, and raw `invalidArtifactReference` was rendered in red. Tapping widget-only packages in **Add Apps** attempted to launch them as foreground apps and showed `Script App Error: invalidArtifactReference`.
- **Steps 1, 2, 5, 6, 7, 8, 9, 10:** Remain `NOT_RUN` / `BLOCKED_DEVICE` on build `87401` because instance publication was blocked before SpringBoard widget configuration could proceed.
- **Pass 4 corrective status (2026-11-03):** Root cause (`/private/var` vs `/var` `standardizedFileURL` mismatch for non-existent child paths in `HanlinScriptExtensionStore.rejectSymlinks`, plus widget-only tap routing and two-store publication error handling) is fixed and verified on macOS/iPadOS 27 Simulator in runs [41559080533](https://github.com/davidpovarsky/hanlin-ai/actions/runs/41559080533), [41561161396](https://github.com/davidpovarsky/hanlin-ai/actions/runs/41561161396), and [41564460036](https://github.com/davidpovarsky/hanlin-ai/actions/runs/41564460036) at `35fa7b06dcf6ae68e2ad13d0a27176e45de9767e`.
- **Owner-authorized Pass 4 TestFlight build `0.7.3 (88001)` (2026-11-03):** Delivered in [Run 41568291224](https://github.com/davidpovarsky/hanlin-ai/actions/runs/41568291224) at `bac84e3a3968daba9768c6525ffd21be52f45d28`, Apple processing state `VALID` at `2026-11-03T03:31:19Z` ([signed delivery record](TESTFLIGHT_88001_DELIVERY.md)). Physical device checklist rows 1–10 remain `OPEN` / `OWNER_DEVICE_QA_PENDING` until the owner tests build `0.7.3 (88001)` on the physical iPad.

## Owner physical iPad test of 0.7.3 (88001) — 2026-11-03 (`OWNER_REPORTED_FAIL` / `DEVICE_QA_FAILED`)

On 2026-11-03, the owner installed signed TestFlight build `0.7.3 (88001)` on their physical iPad and reported:
- **`NO_SCRIPT_SELECTION_IN_SYSTEM_WIDGET_CONFIGURATION` (`OWNER_REPORTED_FAIL` / `DEVICE_QA_FAILED` on build `88001`):** In the native iPadOS Home Screen widget configuration editor ("Edit Widget"), tapping the "Widget instance" parameter displayed no selectable installed scripts or instances.
- **Root Cause Analysis (Pass 5):**
  1. `HanlinScriptPackageEntityQuery` only conformed to `EntityQuery` and omitted `EnumerableEntityQuery` (`allEntities()`) and `EntityStringQuery` (`entities(matching:)`), preventing WidgetKit from enumerating entity options in the configuration picker sheet.
  2. `availableEntities` enumerated `snapshot.widgets` instead of authoritative `snapshot.widgetInstances`.
  3. `publishWidgetTemplates` could permanently omit `Default` if previous instances only had custom variants.
  4. Query errors in the extension process were ephemeral in-memory without cross-process durable logging.
  5. Missing branch integration: 88001 was built from `integration/hanlin-dual-widget-engines-20261029` and lacked the approved Chat V3.3 / OrganizerDock repairs from `fix/hanlin-organizerdock-v33-final-repair-20261101` (`0.7.3 (87901)`).

### Pass 5 Unified Physical iPad Acceptance Procedure (Post-Fix)

When an authorized new TestFlight build is released, execute the following steps on physical iPadOS 27:
1. **In-place Upgrade:** Install the new build over `88001` to preserve existing App Group packages and data.
2. **Package Information:** Open ChavrusaChat -> Apps -> Add Apps -> tap installed `ScriptWidget Actions`. Confirm widget-only row opens Package Information (no `Script App Error`). Under `Widget instances`, confirm `Default` is present.
3. **Instance Creation:** Create independent instance `A1` and `A2`.
4. **Home Screen Widget Placement & System Picker:** Long-press Home Screen -> Edit Home Screen -> Add Widget -> Hanlin Script (Medium). Long-press placed widget -> **Edit Widget**. Tap **Widget instance** parameter row.
   - Verify non-empty list of installed choices: `ScriptWidget Actions · scriptwidget · Default`, `A1`, `A2`, `Expo Counter`, `Legacy`.
   - Select an instance, return to Home Screen, confirm widget renders selected package.
5. **Native Action Execution (Host Terminated):** Force-terminate ChavrusaChat. Tap `Sync now` on ScriptWidget (0->1->2) and toggle `Backup` (off->on->off). Tap `Increment +1` on Expo Counter (7->8->7). Confirm host does NOT open.
6. **Chat V3.3 & OrganizerDock Parity:** Open ChavrusaChat, verify compact/wide split, three recent conversations, native model popover zoom, and bounded composer.
