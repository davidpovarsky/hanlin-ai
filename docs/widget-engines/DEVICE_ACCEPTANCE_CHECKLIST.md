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
