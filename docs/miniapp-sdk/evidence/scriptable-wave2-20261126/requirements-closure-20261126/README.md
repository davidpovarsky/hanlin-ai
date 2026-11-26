# SCRIPTABLE01–10: bounded source closure review

**Reviewed integrated source:** `628dbe083a5ceffc28b026e5701cd8c71c8734ff`; product merge `2491a58b79f534b986b2ea1c0050d35b8dd818f3`.

The ten actual Asana task notes were read and compared with the original active engines and the integrated source. This review found **no additional unowned, source-proven implementation defect required by those notes** after the reviewed foreground, cloud-root and project-symbol corrections. This conclusion is bounded to source review. The tasks must remain open for their required native, system and physical-device results; conditional File Provider probes can still expose a concrete implementation gap.

The Hanlin CI candidate is `fba37e3636da21f897d6a86298b52f2149b462dd`. The only product-source differences between that candidate and this reviewed revision are `HanlinMiniAppsApp/MiniAppsDeveloperStudio.swift` and `HanlinMiniAppsApp/MiniAppsDeveloperWorkspace.swift`, with exact bytes from `5a22ff65007e899af34ae36e2c8f4f30efb06e01`. Root owns the separate target/input qualification; this receipt does not grant a blanket native reuse claim.

## Confirmed code gaps addressed

- **Foreground outcome and lifetime:** the final source through `a6eaf6ee77fbc0a48e9997b434dc28d2c15b916d` keeps an admitted child until its executor settles. Success without a surface and real execution failure no longer race pre-terminal cancellation. A closed surface remains a hidden, ID-qualified draining owner until explicit terminal cleanup, including Expo unregister/shutdown. Container disappearance uses the owner callback. The existing record/lease and original engine remain authoritative.
- **Studio root and drafts:** `74bd12a8c4694a3464386ba7e6fe74326cf4b4fa` moves ubiquity resolution and workspace creation off the main actor, qualifies asynchronous results, handles cancellation and preserves an already-open workspace. The earlier rename, stale validation/build, corrupt-draft and optional sourceRoot fixes remain integrated.
- **Studio project symbols:** `5a22ff65007e899af34ae36e2c8f4f30efb06e01` makes saved folder-style metadata determine the project row and style-sheet symbol. Without metadata, projects retain their project glyph and folders retain theirs. No new schema or screen was added. All eight unchanged portable workspace/root tests passed; Swift parsing and diff checks passed. The existing **14 native Studio invocations remain the required inventory**, with no new case or native execution credit.

## What remains by original task

| Task | Source review result | Required remaining evidence |
| --- | --- | --- |
| 01 — Long Running/background | Supported standalone intent, real invocation/lease, progress, cancel and original engine paths are present. | Actual Shortcuts result chaining, network/processing/files, supported locked/background behavior, deadlines, cancellation and termination/recovery on a physical device. |
| 02 — Toggle | Actual original Expo renderer, native Toggle/SetValueIntent, Boolean callback and qualified atomic state are present. | Original Apple tests plus Home Screen taps, two instances, repeated/concurrent values, cold launch, VoiceOver, rollback and disabled installation. |
| 03 — Widget families | Both configurations and shared manifests contain all eight public family identifiers, including Extra Large Portrait. | Supported-device picker/edit, resizing, rotation, RTL and measured layout. A declared family does not establish device availability. |
| 04 — Transparency/material | Existing authored backgrounds and public system container-removal/rendering paths are preserved. | Real wallpapers, light/dark/tinted modes, contrast and fallback screenshots. Additional widget Glass support is conditional on actual public widget-target availability. |
| 05 — Typed Shortcuts | Typed codec/file route, OS-selected foreground/background mode, owned UI and localization metadata are present. | Real Dictionary/List/file delivery as the SDK permits, output chaining, invalid/empty/nested/Hebrew values, Open When Run and supported system result/deep-link/Home Screen surfaces. |
| 06 — Concurrency | Supported NativeScript windowFactory sessions, persisted-generation admission, scoped provider/storage and final foreground drain ownership are present. | Actual original concurrency regressions and three or more invocations across supported engine pairs, reverse completion, timeout, restored windows and iPad/iPhone UI/state. |
| 07 — Live Activities | Original APIs and seven region contracts remain; the existing per-activity queue orders update/end without serializing unrelated activities. | Actual ActivityKit and system lock-screen/Dynamic Island evidence on supported hardware. Remote APNs is a separate conditional provisioning gate. |
| 08 — Widget components | Original native controls and Refresh, the generated interactive fixture and the existing supported-component matrix are present. | Native renderer/fixture tests, real install/picker/actions/configurations, edge values, accessible layout and supported-family screenshots. |
| 09 — Reliability | Original Expo and prepared widget stores retain identity-qualified last successful content with atomic/hash/generation checks. | Native LKG/atomic regressions and actual system failure/recovery, two installations with the same public name, preserved configurations, corrupt/missing data and disabled/uninstall cases. |
| 10 — Studio/gallery/drawing | Existing editor, folder, theme/font, gallery and original drawing paths plus the reviewed data-preservation/symbol fixes are present. | Native Studio/image gates; real editor and gallery install/run flows; applicable layouts; signed cloud/File Provider and Files-tag probes described below. |

The source details and exact remaining criteria are in [requirements.json](requirements.json). The task notes, modification timestamps and SHA-256 values are retained in [asana-task-notes.json](asana-task-notes.json). [source-manifest.json](source-manifest.json) binds 148 source/mapping files, including the actual original Expo renderers and invocation queue/executor. A fingerprint is a source locator, not execution proof or a full transitive native closure.

## Conditional implementation versus missing acceptance

**iCloud:** existing source declares the container and CloudDocuments/CloudKit, but signed container access has not been established by this review. The off-main root fix does not claim remote placeholder/download support. First run the original signed-app/provider flow. If listing or download fails for an actually supported container, the supported remedy is public ubiquity metadata/download APIs inside the current workspace coordination and draft lifecycle. Selected document identity, unsaved contents and conflict versions must survive any transition.

**Files tags:** the inspected installed iOS SDK marks `NSURLTagNamesKey` unavailable on iOS. This is a public-platform boundary, not permission to add an unsupported API. Verify tag editing and preservation through public Files/document UI on an actually accessible authored-project URL. Source-level file-sharing declarations alone do not prove every runtime workspace is visible. If a project cannot be reached, an explicit user-selected project copy through the existing import/export architecture is the bounded remedy; do not expose the runtime directory or introduce a new File Provider extension solely for this comparison.

**Device adaptation:** use applicable real destinations and qualify compact/expanded/windowed evidence honestly. The actual named device needs its own qualification; a relabeled generic simulator cannot provide it. Fix concrete clipping/navigation failures in the existing UI if observed.

**Glass, Dictionary parameters and remote push:** these are constrained by the public widget/App Intents APIs or actual provisioning. The existing typed JSON text/IntentFile route reflects the inspected SDK. The integrated intent declares `.background` and `.foreground(.immediate)`; the actual Open When Run UI and OS-selected delivery remain original OS probes. Remote push is required only when configured/provisioned. No unsupported capability is credited.

## Scope boundaries

A standalone What's New screen is not an explicit Task10 implementation requirement. The vendor Settings-row icon note does not imply alternate application icons. Inline JavaScript in Task05 was conditional on the package architecture and policy; it does not authorize a second runtime or unvalidated raw-code bypass. NativeScript supports its cooperating windowFactory model, not arbitrary VM isolation. The frozen Scripting-JSC/ScriptUI development boundary remains intact. The 17 unbound generic SystemServices broker methods are not represented as available functionality.

No native job, duplicate test run, workflow edit or product expansion was performed for this review. The original Asana tasks are not marked complete by this receipt. Root, the existing CI run and the Mac owner retain the actual native/system acceptance gates and their outcomes.
