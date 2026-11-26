# SCRIPTABLE00 — release, API, product and evidence matrix

Audit date: **2026-11-26 UTC**. Product source: **b80f897a5b890fb2ade8e272ffefbb25ec601844**, tree **ed83f3e517c8fae1e73c8999d6a1b839e272f49a**. Documentation branch starts at **4373c1897b1460718593ef2f9b5de73f7e17d883**; this document changes no product source.

**The release-mapping criterion is complete: every identified 1.8–1.8.3 release item has a source/API mapping or an explicit gap, an owner/product boundary, and an evidence limit. Feature acceptance and release acceptance remain open.** A comparison gap is not permission to remove a requirement from the approved plan. This audit adds no implementation scope and does not convert source inspection into a native pass.

The immutable source catalog, including 137 selected source/test/manifest files, is [scriptable00-source-audit.json](scriptable00-source-audit.json). Each entry records its exact Git blob, bytes and SHA-256. Group IDs S01–S12 below refer to that catalog, not an unpinned working directory. The release table also exists as [scriptable00-release-api-map.json](scriptable00-release-api-map.json).

## 1. Official comparison baseline

The current [US App Store listing](https://apps.apple.com/us/app/scriptable/id1405459188) and a fresh [Bolivia listing readback](https://apps.apple.com/bo/app/scriptable/id1405459188?platform=mac) both show **Scriptable 1.8.3**. The full history displayed for 1.8, 1.8.1, 1.8.2 and 1.8.3 was inspected on the audit date. Relative publication ages were not converted into invented exact release dates. An older cached search result showing 1.8.2 was superseded by the live page.

The official API references used to interpret behavior are [ListWidget](https://scriptable.app/docs/reference/listwidget/), [args](https://scriptable.app/docs/reference/args/), [config](https://scriptable.app/docs/reference/config/), [DrawContext](https://scriptable.app/docs/reference/drawcontext/), [FileManager](https://scriptable.app/docs/reference/filemanager/) and [Font](https://scriptable.app/docs/reference/font/). Release labels below are concise paraphrases; local implementation and acceptance analysis is based on the pinned Hanlin source.

| Version | Classified release items | Baseline observation |
| --- | ---: | --- |
| 1.8 | 19 | Authoring, organization, widgets, cloud/files and rendering |
| 1.8.1 | 2 | Extended Shortcut execution and OS status |
| 1.8.2 | 6 | Additional widget/input/launch/context behavior |
| 1.8.3 | 1 | Existing Shortcut compatibility repair, including preview and app execution; the listing names OS 18, 26 and 27 |

The implementation uses Hanlin's actual public SDK contracts and original engines. It does not claim that Scriptable globals such as ListWidget, config, args, DrawContext or FileManager are exported as drop-in aliases. A functional equivalent must preserve the relevant behavior and must pass the appropriate native/OS acceptance.

## 2. Integration references and exact source equivalence

| Reference | Exact source | Relationship to audited b80 source |
| --- | --- | --- |
| PR18 | 86a6dde354947be9329fe1e8f4d45a433fe488c4 | Verified ancestor of both documentation base 4373 and b80. Composer/cache integration is present; source ancestry alone does not certify mounted UI behavior. |
| PR19 | 1177dace25b823737ed4c4775bf2ac440f049d3e | Not an ancestor of 4373; verified ancestor of b80. b80 integrates its new system surfaces with the approved MiniApps-only publication boundary. |
| PR22 | cf0d26c7cb0df29f0f3e644e125dd6dd6d5172db | Not a full ancestor of either 4373 or b80. All 12 selected cache product/test files are byte-identical in PR22, 4373 and b80. |
| Lifecycle repairs | 19cca5723115725bc3668a26ac5496e61e6dd299 and 0f3a39cce54a3eccefd0d0a3f61124f522a171a9 | Approved cumulative changes integrated into b80 while preserving the newer root Shortcuts implementation. |
| System integration | b80f897a5b890fb2ade8e272ffefbb25ec601844 | Exact 13-target source; portable checks recorded, Apple acceptance pending. |

[The fresh PR22 receipt](scriptable00-pr22-cache-equivalence.json) records the reproducible selection rule, all 12 paths and their exact Git blobs/SHA-256. The rule selects paths changed by cf0d relative to its first parent, containing “cache” case-insensitively and rooted under AI_HLY, AI_HLYTests or Packages. It excludes documentation. It neither asserts full PR22 ancestry nor substitutes for app cache execution.

The selected files are HanlinModelPromptCachePreferences, AgentTokenUsageCacheTests, AutomaticWebSearchCacheTests, HanlinModelPromptCachePersistenceTests; HanlinGoogleCachedContent, HanlinPromptCachePolicy, HanlinPromptCachePolicyMutation, HanlinPromptCachePreset; and the four package tests HanlinGoogleCachedContentTests, HanlinPromptCachePolicyMutationTests, HanlinPromptCachePresetTests and HanlinPromptCacheTests. Exact paths live in the receipt.

## 3. Product and engine ownership

The [b80 integration proof](../../../../docs/two-wave-integration/20261126/pr19-miniapps-system-integration/integration-proof.json) is authoritative for this source snapshot. It contains **13 shipping bundles**: two applications, the original eight extensions, and three new extensions belonging to the standalone MiniApps product.

| Shipping identity | Bundle ID | Ownership |
| --- | --- | --- |
| Hanlin AI application | com.itorah.chavrusachat | Original app |
| MiniApps application | com.itorah.hanlinminiapps | Standalone authoring/execution product |
| Hanlin share extension | com.itorah.chavrusachat.share | Original |
| Hanlin widgets extension | com.itorah.chavrusachat.widgets | Original |
| Hanlin translation provider | com.itorah.chavrusachat.translation-provider | Original |
| Hanlin notification service | com.itorah.chavrusachat.notification-service | Original |
| MiniApps widgets extension | com.itorah.hanlinminiapps.widgets | Original |
| MiniApps share extension | com.itorah.hanlinminiapps.share | Original |
| MiniApps translation provider | com.itorah.hanlinminiapps.translation-provider | Original |
| MiniApps notification service | com.itorah.hanlinminiapps.notification-service | Original |
| HanlinMiniAppsKeyboard | com.itorah.hanlinminiapps.keyboard | New, MiniApps only |
| HanlinMiniAppsNotificationContent | com.itorah.hanlinminiapps.notification-content | New, MiniApps only |
| HanlinMiniAppsCameraCapture | com.itorah.hanlinminiapps.camera-capture | New, MiniApps only |

The original ten signing roles, identifiers, entitlement paths and provisioning environment names are retained. New roles are miniapps_keyboard, miniapps_notification_content and miniapps_camera_capture. Shared HanlinKeyboardUI, HanlinNotificationContentUI and HanlinCameraCaptureUI products remain in the canonical extension SDK; shared contracts do not authorize publication from the Hanlin AI product.

New Spotlight/camera publication and camera-section construction are guarded by the canonical MiniApps identity. The original Hanlin application scene, intent registration and widget entry source are byte-identical to the pre-integration base, as recorded by the integration proof. Native verification of this boundary still requires the nine discovery/capture tests and actual system-surface acceptance.

Developer Studio belongs to HanlinMiniAppsApp. Shared SDKs retain one implementation of the relevant contracts/renderers and the original NativeScript, Expo and ScriptWidget paths. The existing **Scripting-JSC/ScriptUI development boundary remains frozen**. The active original ScriptWidget interpreter is a distinct existing path; referencing it does not reopen frozen development or introduce a replacement engine.

## 4. Complete release-to-implementation map

Classification is deliberately narrower than “done”:

- **VERIFY_REGRESSION:** an implementation or equivalent exists; specified current native/OS checks remain necessary.
- **PROBE_UNKNOWN:** source alone does not establish the requested behavior or complete equivalence.
- **IMPLEMENT_GAP:** the comparison exposes a missing public route or implementation. The plan owner must reconcile scope explicitly.
- **REUSE_ACCEPTED:** used only for the exact source/input-qualified historical evidence in section 8.
- **FIX_REPRODUCED:** used only when an actual failing behavior and the subsequent original acceptance run are retained.

No row below is a fresh b80 native pass.

### Version 1.8

| Item | Local public route and source | Classification and pending acceptance |
| --- | --- | --- |
| v18-01 — Duo layout adaptation | MiniAppsLibrary and Developer Studio use native NavigationStack/List and the existing per-window app roots. Sources: S07. | **PROBE_UNKNOWN** — No source-qualified Duo device/layout acceptance was found. Responsive native controls alone do not prove the vendor-specific layout criterion. |
| v18-02 — Folders, symbols, colors, cloud sync | MiniAppsDeveloperWorkspace.FolderStyle stores symbol/color metadata in .miniapps-folder.json; Studio can select local or the existing iCloud Documents/MiniAppsStudio root. Sources: S07. | **VERIFY_REGRESSION** — Folder operations have portable Foundation coverage. Native coordination, remote updates, conflicts, offline behavior and iCloud entitlement acceptance remain open. |
| v18-03 — Editable gallery imports | Studio copies canonical SDK gallery examples into an independent workspace and uses MiniAppAuthoringService validation/build; five real example projects include drawing. Sources: S07, S08. | **VERIFY_REGRESSION** — Five original validate/build pairs passed at 4d76 and qualified through 08ed. b80 changes authoring/SDK inputs; refresh the original gallery checks and then install/run accepted projects. |
| v18-04 — Widget buttons and switches | Original @expo/ui Button/Toggle props, WidgetToggleHandler, refresh-button props and HanlinExpoWidgetsViewRenderer.toggleIntent feed actual AppIntents; ScriptWidget retains its original button/toggle elements. Sources: S03. | **VERIFY_REGRESSION** — Exercise persistent state, explicit requested Boolean, action identity, reload and disabled/removed packages on actual WidgetKit surfaces. Preview/decoder success is insufficient. |
| v18-05 — Progress bars and rings | Original Expo SwiftUI views and ScriptWidget Gauge/Chart renderers remain canonical; typed manifests describe the authored widget tree. Sources: S03. | **VERIFY_REGRESSION** — Verify actual rendered progress values and edge cases in applicable widget families. No drop-in ListWidget.addProgress global is claimed. |
| v18-06 — Wallpaper transparency | Widget containers permit system background removal; ScriptWidget supports authored background colors/materials and accessibility fallbacks. Its material implementation explicitly blurs widget content, not wallpaper. Sources: S04. | **PROBE_UNKNOWN** — An iOS/iPadOS 27.2 real Home Screen check must establish wallpaper behavior and tinted/reduced-transparency handling. Local material rendering is not equivalent proof. |
| v18-07 — Completion, signatures, reference links | UIKit caret geometry positions suggestions; the original TypeScript authoring service returns completion/signature/documentation results with request/version guards and an API-reference link. Sources: S07, S08. | **VERIFY_REGRESSION** — Four original Node editor tests passed. Native keyboard, caret, selection, stale-response and accessibility execution remains required. |
| v18-08 — Editor refresh | Native UITextView editor, explicit save/rename, draft recovery and guarded asynchronous validate/build live in the standalone Studio. Sources: S07. | **VERIFY_REGRESSION** — Execute MiniAppsStudioProjectTests plus native editor acceptance. Source review and Linux parsing do not prove UIKit isolation, file-provider coordination or edit preservation. |
| v18-09 — Library and creation navigation | The standalone library exposes Developer Studio; Studio provides project creation, folder creation, import, gallery and refresh actions. Sources: S07. | **PROBE_UNKNOWN** — Functional routes exist. No literal tile design or bottom-plus parity is asserted; reconcile any exact UI requirement against the approved product plan. |
| v18-10 — SF Symbols icons | Studio folder styling accepts a system symbol and color; native views render system images. Sources: S07. | **PROBE_UNKNOWN** — Folder symbols do not establish a complete per-script icon chooser or installed-item icon editing workflow. Verify the required scope explicitly. |
| v18-11 — Searchable live logs | Studio searches and periodically refreshes the real RuntimeFileLayout logs; the displayed tail has an explicit 512 KB limit and full-file export. Sources: S07. | **VERIFY_REGRESSION** — Verify actual engine output, filtering, tail updates, export and truncation messaging in the standalone app; this is not a simulated console. |
| v18-12 — System and installed font selection | UIFontPickerViewController supplies editor fonts, with persisted font name/size preferences. Sources: S07. | **VERIFY_REGRESSION** — Native installed-font enumeration, fallback, Dynamic Type/accessibility and document editing still need execution. |
| v18-13 — Theme controls and settings appearance | Studio has persisted system/light/dark editor theme selection and applies preferredColorScheme to that editor. Sources: S07. | **PROBE_UNKNOWN** — Editor-local themes do not prove the complete MiniApps Settings-list theme/icon presentation. Settings-row icons still require source/UI comparison; an alternate application icon workflow is not a release criterion. |
| v18-14 — What's New presentation | No standalone release-notes/What's New implementation was identified in the audited Studio/library source. Sources: S07. | **IMPLEMENT_GAP** — Record whether this comparison item is part of required product acceptance; do not mark it implemented or silently remove a required criterion. |
| v18-15 — Cloud placeholders and foreground refresh | Studio enumerates its selected workspace and refreshes on scene activation and explicit refresh; the iCloud root is explicit. Sources: S07. | **PROBE_UNKNOWN** — No source-qualified proof of not-yet-downloaded placeholders was found. Test File Provider/iCloud visibility, download, foreground remote changes, conflicts and offline recovery on Apple platforms. |
| v18-16 — Refresh resilience and retained successful content | HanlinWidgetLastSuccessfulRender validates installation, generation, engine, family, settings and program identity before fallback. Sources: S05. | **VERIFY_REGRESSION** — Eleven original native cases cover validity boundaries. Their Apple execution and real WidgetKit scheduling/recovery remain open; the OS controls refresh timing. |
| v18-17 — Large-image and preview fidelity | Original ScriptWidget image decoding/modifiers and original widget renderers are retained; preview and host family contracts remain explicit. Sources: S09, S03. | **VERIFY_REGRESSION** — Nine image invocations need the UIKit branch on iOS. AppKit execution, preview construction or source parsing is not large-image iOS acceptance. |
| v18-18 — Rotation and invalid drawing dimensions | The NativeScript gallery drawing example uses actual UIKit drawing, explicit rotation and input checks; original ScriptWidget image rotation stays in the renderer. Sources: S09, S08. | **VERIFY_REGRESSION** — Canonical TypeScript/gallery build proof exists on earlier qualified source. Native output, invalid dimensions, clipping, scale and rotated-image review remain required; no DrawContext drop-in is claimed. |
| v18-19 — Files tag-color retention | Workspace writes use coordinated compare-before-overwrite replacement intended to preserve existing file metadata. No corresponding public addTag/allTags/removeTag binding was identified. Sources: S07, S11. | **IMPLEMENT_GAP** — A general Files tag API is absent from this mapping. Metadata preservation during editor save also needs Darwin/File Provider tests; it is a separate narrower behavior. |

### Version 1.8.1

| Item | Local public route and source | Classification and pending acceptance |
| --- | --- | --- |
| v181-01 — Optional extended Shortcut execution | HanlinRunMiniAppShortcutIntent is LongRunningIntent/CancellableIntent; allowLongRunning defaults false, while accepted work is enqueued before OS background/cancellation negotiation. Sources: S01, S02. | **VERIFY_REGRESSION** — Run original opt-in >300-second acceptance and cancellation/results checks. The historical Host suite's one skip is not credit for this gate. |
| v181-02 — Background status and completion | The standalone intent uses the actual AppIntents background task API; typed reportShortcutProgress routes miniapps.shortcutProgress to real Progress updates. Sources: S01. | **VERIFY_REGRESSION** — Check the OS indicator, progress, completion, cancellation and duplicate completion on supported iOS 27+; a portable continuation test cannot prove these surfaces. |

### Version 1.8.2

| Item | Local public route and source | Classification and pending acceptance |
| --- | --- | --- |
| v182-01 — Extra-large portrait widgets | HanlinWidgetFamily and prepared widget manifests include systemExtraLargePortrait alongside all seven other families. Sources: S03. | **VERIFY_REGRESSION** — Decoder/source inclusion does not create OS support on every device. Test the applicable actual iPad/device dimensions and original family render/preview. |
| v182-02 — Dictionary and list JSON input | HanlinShortcutValueCodec validates text, JSON and JSON-file intent input; structured output is delivered as a real IntentFile when appropriate. Sources: S01. | **VERIFY_REGRESSION** — Twelve portable codec cases passed. Native Shortcuts must exercise actual dictionary/list/file handoff and results without stringifying away types. |
| v182-03 — Open-when-run and inline scripts | The standalone intent invokes an installed action with supportedModes including .foreground(.dynamic). Its current command delivery still sets continueInForeground:false and canPresentUI:false. The existing shared HanlinRunScriptActionIntent is a separate foreground installed-action contract. Sources: S01, S02. | **IMPLEMENT_GAP** — There is no inline-JavaScript input in the new intent. Actual system Open When Run/foreground-toggle presentation remains PROBE_UNKNOWN because dynamic foreground mode is already declared; a UI-permitted inline-script delivery contract is not established by that declaration. |
| v182-04 — Home Screen Shortcut entry | Existing installed-action intents can be discovered by the system; no source-qualified MiniApps icon/setup guidance was identified. Sources: S01, S07. | **PROBE_UNKNOWN** — Verify actual OS-created Home Screen shortcuts, routing and user guidance. Do not equate a legacy in-app launch flag with Shortcuts-origin execution. |
| v182-05 — Shortcut and foreground UI coexistence | The production windowFactory path loads a cooperating window/session context in the original NativeScript VM without attaching a new UI; fresh store.restore guards generation/enabled admission. Sources: S02. | **VERIFY_REGRESSION** — Run both original NativeScriptShortcutConcurrencyTests methods and window-close lifecycle regression against the current source. No separate JavaScript isolate/process isolation is claimed. |
| v182-06 — Background execution context | Hanlin uses explicit shortcuts delivery and canPresentUI=false for the standalone background action, with foreground continuation separately controlled. Sources: S01, S02. | **PROBE_UNKNOWN** — This is the local policy equivalent, not an exported Scriptable config.runsInApp global. Verify actual routing and any required compatibility contract. |

### Version 1.8.3

| Item | Local public route and source | Classification and pending acceptance |
| --- | --- | --- |
| v183-01 — Existing Shortcut compatibility repair | Shared action entities use package/entrypoint/action identity and narrowly scoped legacy short-ID migration; preview and foreground/background paths remain separate. Sources: S01, S02, S03. | **PROBE_UNKNOWN** — Existing saved Shortcuts, widget previews and run-in-app migration need actual version-upgrade OS acceptance. Source identity logic does not prove vendor-equivalent compatibility. |


## 5. Public API semantics that must survive the mapping

The official ListWidget reference gives buttons an action identity, delivers toggle intent state explicitly, and distinguishes refresh-only actions from arbitrary script actions. Hanlin's corresponding routes are the original typed Expo widget props/AppIntents and original ScriptWidget events. An optimistic UI Boolean or a generic “invoke action” token is insufficient without persistence, correct action ownership and the subsequent actual render. ListWidget's progress option describes bounded progress; Hanlin must verify its actual authored controls rather than assume a shared name implies shared units.

The same reference limits transparent wallpaper behavior to iOS/iPadOS 27.2, describes family/device applicability for extra-large portrait, and treats requested refresh dates as scheduling hints. Hanlin source explicitly distinguishes authored material from wallpaper. These three behaviors require the relevant OS surface; a SwiftUI preview is only renderer evidence.

The args reference permits structured Shortcut parameters, including files; Hanlin's codec and real IntentFile handoff must preserve that boundary. The config reference distinguishes execution context and legacy Home Screen launches. Hanlin uses explicit delivery/context policy instead of claiming that its host supplies the same global object. Its background standalone action cannot present UI; the existing foreground installed-action intent is separate. Inline-JavaScript execution and saved-Shortcut upgrade compatibility are not established by these routes.

DrawContext documents rotation about the image rectangle's center. The local drawing example uses actual UIKit transforms and validates dimensions; native output still has to be compared to the intended geometry. The FileManager reference distinguishes tag operations and existing tag colors. Editor replacement that preserves metadata is narrower than providing a tag-management API. Font's programmatic constructor is also separate from an author-facing installed-font chooser; Studio uses the real UIKit picker for the latter.

### Additional approved two-wave surfaces

These are part of the project's implementation/acceptance plan even where they are not a new item in the four-version release list.

| Surface | Public contract and source group | Required proof |
| --- | --- | --- |
| Live Activities and Dynamic Island | S06: MiniAppLiveActivities list/start/update/end, original ScriptWidget/Expo programs, HanlinScriptWidgetLiveActivityController and serialized operation queue; seven region nodes remain typed | Actual ActivityKit start/update/end and race behavior, fresh snapshots/actions, applicable physical Dynamic Island regions; decoder/helper coverage alone is insufficient |
| Eight widget families | S03: small, medium, large, extra-large, extra-large portrait, accessory circular/rectangular/inline | Native renderer and actual available OS placements, with explicit device applicability |
| Keyboard | S10: shared HanlinKeyboardUI, MiniApps-owned extension target and prepared presentation contract | Native controller/composition behavior, host text document proxy, extension identity/profile and real system keyboard acceptance |
| Notification content | S10: shared HanlinNotificationContentUI and MiniApps-owned notification-content extension | Actual delivered category/content rendering and extension lifecycle; a notification service is a different extension |
| Camera capture | S10: shared HanlinCameraCaptureUI, actual capture service/preview, durable inbox and foreground coordinator | OS capture path, durable data before session invalidation, generation/enabled admission, window ownership and deferred context-load races |
| Spotlight | S10: installed MiniApp catalog/entity index and MiniApps-identity publication guard | Actual indexing, removal/update, opening the correct installed generation/product and system search behavior |
| SDK authoring and portability | S08/S12: canonical TypeScript/manifest/build routes and generated public declarations | Fresh exact-source SDK/Host, original positive and negative authoring tests, gallery validation/build, then actual native install/run |

### Approved plan item cross-reference

| Plan item | Source/release mapping | Acceptance boundary |
| --- | --- | --- |
| 00 baseline | Sections 1–3, full release table, exact PR18/19/22 receipts | Mapping complete; no feature acceptance implied |
| 01 extended Shortcuts | S01/S02, v181-01/02 | OS long-running/cancellation/progress gates |
| 02 toggle actions | S03, v18-04 | Requested state, persistence and original widget action execution |
| 03 widget families | S03, v182-01 | All eight contracts plus applicable native placements |
| 04 backgrounds | S04, v18-06 | Actual wallpaper/system rendering and accessibility |
| 05 structured input | S01, v182-02 | Real Shortcuts dictionary/list/file handoff |
| 06 concurrent execution | S02, v182-05/06 | Original VM ownership, cancellation and current-generation admission |
| 07 Live Activities | S06, section 5 | Actual ActivityKit and applicable Dynamic Island |
| 08 widget controls | S03, v18-04/05 | Original buttons, progress, gauge/chart and native rendering |
| 09 last successful render | S05, v18-16 | Identity-validated fallback plus actual refresh recovery |
| 10 authoring/gallery/drawing | S07/S08/S09, corresponding 1.8 rows | Real compiler plus Apple editor/filesystem and native gallery execution |
| 11 shared SDK | S01–S12, sections 3/6/7 | Single canonical engine contracts, honest reachability and frozen boundary |
| 12 integration/release | Sections 2/3/8/9 | Exact-source native, signed device, install and release acceptance |

## 6. The 17 unbound generic broker methods

At b80, HanlinSystemServicesBroker.swift has SHA-256 **575951b9056255d1708c414959464c24d2947b973426a5edd5005825fa5fd316**. A scoped source search finds its declaration but no production construction/call site in AI_HLY, Packages, HanlinMiniAppsApp or the NativeScript/Expo facade paths. The generated source-inventory and reachability documents also preserve this availability gap.

**None of the following is credited as an available public NativeScript/Expo broker operation merely because a Swift method exists.** Host capability policy is not OS permission or service availability.

| Swift method | Declared service | Specific limit in this audit |
| --- | --- | --- |
| fetchContacts | Contacts | No generic public broker route or permission acceptance |
| requestCameraAccess | Camera | Permission request method is not the new dedicated camera execution route |
| requestMicrophoneAccess | Microphone | No generic public route or granted-permission evidence |
| recognizeSpeech | Speech recognition | No generic public route or actual recognition acceptance |
| translateText | Translation | Explicitly throws because an interactive TranslationSession is required |
| fetchWeather | Weather | No generic public route or entitlement/live-service acceptance |
| readKeychainItem | Keychain | No generic public route or keychain access-group acceptance |
| authenticateUser | Local authentication | No generic public route or native authentication acceptance |
| fetchCloudStatus | Cloud | No generic public route or account/entitlement acceptance |
| presentShareSheet | Share sheet | UI policy check exists; generic binding and correct native presentation acceptance do not |
| searchMap | Maps | No generic public route or actual service acceptance |
| recognizeTextInDocument | Document utilities | The implementation extracts PDF text; it does not establish image OCR |
| requestCalendarAccess | Calendar | Requesting access is not proof of authorization or a public operation |
| requestReminderAccess | Reminders | Same binding/authorization distinction |
| requestHealthAccess | Health | No generic public route or physical-device entitlement/permission proof |
| requestLocationAccess | Location | The call returns after requesting access; it is not proof that access was granted |
| requestNotificationAccess | Notifications | No generic public route or permission/delivery proof |

This gap does not mean that every similarly named capability is unavailable through every original engine. The original NativeScript native APIs, dedicated extension services and ScriptWidget service provider are separate paths. Scripts/MiniApps/scriptwidget/service-types.d.ts describes calendar/reminders, notification/alarm, location/maps/weather, health/photos/music, cloud data and presentation/action contracts. Its generated declarations must be traced to their own implementation and permission tests; they do not bind this generic broker by implication.

## 7. Dependency and toolchain pins

The complete upstream manifest, tarball integrity records and source hashes are preserved in the source audit. These are the selected versions, not a claim that a later OS/runtime acceptance has already run.

| Component | Source pin |
| --- | --- |
| Expo / Expo UI / Expo Widgets | 58.0.26 / 58.0.29 / 58.0.29 |
| Expo brownfield / modules core / asset / modules JSI | 58.0.20 / 58.1.0 / 58.0.21 / 58.0.23 |
| React / React Native / worklets | 19.3.0 / 0.88.1 / 0.13.0 |
| Hermes | 260318099.0.5 |
| NativeScript core / iOS / types | 9.1.4 / 9.1.1 / 9.1.4 |
| NativeScript SwiftUI / Vite | 4.0.2 / 8.0.24 |
| Original ScriptWidget | 4da256d58247bbafb9a5cd443a285250b97b3c4b |
| Expo TypeScript selection | npm:@typescript/typescript6@6.0.2 |
| NativeScript TypeScript | 5.9.3 |
| SwiftAISDK | abf0921c6e89e6521cc2b510ff11016b45a0ef08 |
| Historical accepted Mac Host | Node 24.5.0, ICU 77.1, Unicode 16.0, darwin arm64 |
| Motion native evidence | Xcode 27.0 / SDK 27.0; actual iOS Simulator 27.2 build 24B8117 |

The authorities are Scripts/MiniApps/upstream-resolution.json, Scripts/Expo/dependency-lock.json, Scripts/NativeScript/package.json and package-lock.json, plus the actual Swift package manifests. A version label alone does not replace a resolved graph, binary/source digest, signing identity, environment or destination record.

## 8. Evidence ledger and reuse limits

[scriptable00-host-evidence.json](scriptable00-host-evidence.json) retains a digest-qualified summary of the original Host handoff and the exact gallery reuse receipt. It points to the retained raw files and records the archive SHA-256. Failed earlier attempts remain in the original handoff; this document does not relabel them.

| Evidence | Actual result and source | Accepted scope and next gate |
| --- | --- | --- |
| Original Host/SDK final | a35694f73d07b161d6db5e8c150b7d905e883455: 185 tests, 184 pass, 0 fail, 1 skip; exact final SDK verification succeeded | Historical Host acceptance. The optional long-duration case remains open. b80 changes canonical authoring/SDK inputs and requires a fresh source-qualified run. |
| Five gallery projects | Actual validation/build at 4d76e6053662957281ffbcb0a2ad28fc4f0c2f89 | REUSE_ACCEPTED through a356/08ed only: 28,802 archive members compared, with only three audit documents and manifest bookkeeping changed. No install/run proof. |
| b80 product integration | 98 Python methods and 7 Node methods passed; original failures and their corrections retained | Generator, source ownership, signing-contract and original authoring checks. Swift Linux parsing is not Apple module typechecking. Native status explicitly NOT_RUN. |
| Shortcut codec | 12 portable cases in shortcut-codec-acceptance.json | Structured input/output helper semantics; actual AppIntents transport and original Apple package target remain required. |
| Action completion | 3 portable cases in native-callback-portable-acceptance.json | Cancellation/completion helper behavior; OS completion and long-running execution remain separate. |
| Live Activity queue | 3 portable cases in live-activity-queue-acceptance.json | Ordering/ownership helper semantics; actual ActivityKit execution remains necessary. |
| Studio editor/workspace | Four original Node editor cases and four Foundation workspace cases passed | Real compiler/editor and portable filesystem logic. UIKit, NSFileCoordinator, File Provider and native project lifecycle are not credited. |
| Shared Chat interactions | Five native tests at 730bbb6d70e8c9f136c5ee21437f78cc5b6e7bfb; acceptance-r6.json | Original menu callbacks, state, host isolation and preview metrics on its recorded iOS destination. Not all app/Composer behavior. |
| Motion disclosure | Original B, A and C passed at 95367b8c06b166873dfab2143a8323a869085af2; final visual checks passed | FIX_REPRODUCED; exact source/input reuse qualified to root 0bbd. Failed dacb/24bc/efb attempts, results, captures and videos retained. Later changes require only a genuine affected-closure check. |
| Local cache | Existing local-cache-reuse.json qualifies 18 original macOS source-harness cases to a30c8267 | REUSE_ACCEPTED for nine production files, two tests and LRUCache 1.3.0 only. No full iOS app, SwiftData, provider, billing or UI acceptance. |
| PR22 cache equivalence | All 12 selected product/test blobs equal PR22, 4373 and b80 | Current source identity only; it does not expand the preceding execution scope. |

The five gallery projects are expo-hello-world, nativescript-hello-world, nativescript-image-drawing, sdk-only-departure-budget and sdk-only-table-share. The canonical authoring module's historical gallery hash was ed6244894695eeb4b83aa41ea1f7523cda2d5db2059452b666fd21a099238a30. b80's authoring hash is cea114769522eaaaceee804b89b26549c2335b3ebca16037a64f97724f2e92fc. This concrete input change prevents a blanket carry-forward of the old Host/gallery success.

### Required native selector families

This is a deduplicated inventory of relevant original sources, not an assertion that the planner's suite count equals executed tests. The source catalog contains every listed test file.

| Original target/suite | Source-supported scope | Status at this audit |
| --- | --- | --- |
| HanlinPlatformContractsTests / HanlinShortcutValueCodecTests | 12 invocations | Portable proof retained; current iOS package execution open |
| HanlinMiniAppCoreTests / HanlinMiniAppActionCompletionTests | 3 invocations | Portable proof retained; current iOS package execution open |
| HanlinScriptExtensionsTests / HanlinWidgetLastSuccessfulRenderTests | 11 invocations | Native open |
| HanlinScriptExtensionsTests / HanlinOriginalScriptWidgetImageTests | 9 invocations | UIKit/iOS execution open; AppKit is a separate branch |
| HanlinScriptExtensionsTests / HanlinLiveActivityOperationQueueTests | 3 helper invocations | Actual ActivityKit tests are additionally required |
| HanlinMiniAppsTests / NativeScriptShortcutConcurrencyTests | 2 real-VM methods | Native open |
| HanlinMiniAppsTests / MiniAppsDeveloperWorkspaceTests | 4 methods | Portable execution does not cover Darwin coordination |
| HanlinMiniAppsTests / MiniAppsStudioProjectTests | 4 methods / 6 invocations | Rename, sourceRoot, corrupt recovery and stale operation acceptance open |
| HanlinMiniAppsTests / NativeScriptWindowOwnershipTests | Both original ownership and new close/lifecycle paths | Do not run only testUnrelatedAndLateWindowCleanupPreservesNativeScriptOwner and omit testClosingWindowReleasesLifecycleCaptureBeforeRuntimeStops |
| AI_HLYTests / HanlinMiniAppDiscoveryAndCaptureTests | 9 real XCTest methods in b80 | Native NOT_RUN; includes the standalone publication-policy method and four lifecycle regressions |
| HanlinScriptExtensionsTests / HanlinKeyboardNotificationPresentationTests | 9 methods | Native open |
| HanlinScriptCompilerTests / HanlinScriptAnalyzerTests | 4 additional methods from PR19 | Native/original target coverage open |
| Original Expo widgets, original ActivityKit and native presentation suites | Expanded widget controls and original region/OS behavior | Preserve the original assertions; selector inclusion alone gives no pass |
| Original paired two-product/AppGroup runner | Full original product-specific selected invocations and fixture ownership | Separate from the affected Hanlin suite planner and package gates; current exact-source native run required |

The 12+3+11+9 package set is **35 mandatory invocations**. It is not automatically included merely because shipping app schemes passed. The existing generated HanlinPlatform package scheme and original targets supply the native route; no replacement implementation or new source-only harness is acceptance for these tests.

The prior affected planner selected 87 Hanlin suites and was explicitly not full validation. It contained no HanlinMiniAppsTests/UITests entries. The original paired runner supplies separate standalone/product acceptance, and the additional package/Studio/concurrency/ownership cases above must be accounted for independently without double counting. The later PR19 additions require current affected routing as well.

Signed-device and OS acceptance remains necessary where applicable: real Shortcuts/background UI and completion, widget wallpaper/families/refresh/actions, installed keyboard, delivered notification content, Spotlight, camera handoff, iCloud/File Provider, actual Dynamic Island, profiles/entitlements for the three new MiniApps bundles, archive/export/install and the authorized release workflow.

## 9. Remaining decisions and completion boundary

The approved implementation lanes and the comparison matrix are different acceptance dimensions. This document completes the evidence-backed classification of the vendor release list. It leaves the following explicit:

1. The original engine/SDK paths remain the canonical implementation. Current source changes require affected native execution and exact-source Host/SDK refresh.
2. Inline JavaScript plus the combined Open When Run contract, a public Files tag-management API, and a standalone What's New implementation were not found. Their comparison gaps remain visible for plan-scope reconciliation.
3. Wallpaper behavior, Duo layout, cloud placeholders, full icon-editing/setup guidance, saved-Shortcut migration and global settings parity remain unproven. No UI observation was invented.
4. The 17 generic broker methods remain unbound. Separate original APIs must be assessed independently, and capability policy does not stand in for OS availability.
5. Previous passing tests retain their exact accepted scope. A later documentation commit alone does not invalidate product evidence; a changed production/transitive input does require a qualified decision.
6. Completing SCRIPTABLE00 mapping does not close native, device, signing, install, release or any unresolved feature-acceptance task.

## 10. Source group index

The following primary paths make the implementation locations reviewable. The JSON catalog includes all grouped paths, test sources and cryptographic identities at b80.

| Group | Source responsibility | Primary exact paths |
| --- | --- | --- |
| S01 | Standalone Shortcuts and public typed input/progress | [HanlinMiniAppsApp/MiniAppsShortcutIntent.swift](../../../../HanlinMiniAppsApp/MiniAppsShortcutIntent.swift); [Packages/HanlinExpoUI/src/host-services.ts](../../../../Packages/HanlinExpoUI/src/host-services.ts); [Packages/HanlinPlatform/Sources/HanlinPlatformContracts/HanlinShortcutProgress.swift](../../../../Packages/HanlinPlatform/Sources/HanlinPlatformContracts/HanlinShortcutProgress.swift); [Packages/HanlinPlatform/Sources/HanlinPlatformContracts/HanlinShortcutValueCodec.swift](../../../../Packages/HanlinPlatform/Sources/HanlinPlatformContracts/HanlinShortcutValueCodec.swift) |
| S02 | Original engine execution, cancellation, window ownership and generation admission | [AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift](../../../../AI_HLY/Downstream/ScriptingPlatform/HanlinScriptingPlatform.swift); [Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptRuntime/HanlinNativeScriptWindowSession.swift](../../../../Packages/HanlinNativeScriptRuntime/Sources/HanlinNativeScriptRuntime/HanlinNativeScriptWindowSession.swift); [Packages/HanlinPlatform/Sources/HanlinMiniAppCore/HanlinMiniAppActionCompletion.swift](../../../../Packages/HanlinPlatform/Sources/HanlinMiniAppCore/HanlinMiniAppActionCompletion.swift) |
| S03 | Original Expo and ScriptWidget widgets, families, controls and manifests | [Packages/HanlinExpoUI/src/system-surfaces.ts](../../../../Packages/HanlinExpoUI/src/system-surfaces.ts); [Packages/HanlinExpoUI/src/widget-types.ts](../../../../Packages/HanlinExpoUI/src/widget-types.ts); [Packages/HanlinPlatform/Sources/HanlinScriptContracts/HanlinWidgetProgram.swift](../../../../Packages/HanlinPlatform/Sources/HanlinScriptContracts/HanlinWidgetProgram.swift); [Packages/HanlinPlatform/Sources/HanlinScriptExtensions/ExpoWidgets/HanlinExpoWidgetsViewRenderer.swift](../../../../Packages/HanlinPlatform/Sources/HanlinScriptExtensions/ExpoWidgets/HanlinExpoWidgetsViewRenderer.swift) |
| S04 | System container background and accessibility-aware authored material | [Packages/HanlinPlatform/Sources/HanlinScriptExtensions/ScriptWidget/Original/Component/Attributes/General/ScriptWidgetAttributeBackgroundModifier.swift](../../../../Packages/HanlinPlatform/Sources/HanlinScriptExtensions/ScriptWidget/Original/Component/Attributes/General/ScriptWidgetAttributeBackgroundModifier.swift); [Packages/HanlinWidgetSDK/Sources/HanlinScriptingWidgets/HanlinOriginalExpoWidget.swift](../../../../Packages/HanlinWidgetSDK/Sources/HanlinScriptingWidgets/HanlinOriginalExpoWidget.swift); [Packages/HanlinWidgetSDK/Sources/HanlinScriptingWidgets/HanlinScriptingWidgets.swift](../../../../Packages/HanlinWidgetSDK/Sources/HanlinScriptingWidgets/HanlinScriptingWidgets.swift) |
| S05 | Last successful prepared widget render with identity validation | [Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinScriptExtensionContracts.swift](../../../../Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinScriptExtensionContracts.swift); [Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinWidgetInstance.swift](../../../../Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinWidgetInstance.swift); [Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinWidgetLastSuccessfulRender.swift](../../../../Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinWidgetLastSuccessfulRender.swift) |
| S06 | Live Activities and Dynamic Island through the original renderers | [Packages/HanlinExpoUI/src/system-surfaces.ts](../../../../Packages/HanlinExpoUI/src/system-surfaces.ts); [Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinLiveActivityOperationQueue.swift](../../../../Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinLiveActivityOperationQueue.swift); [Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinScriptWidgetLiveActivity.swift](../../../../Packages/HanlinPlatform/Sources/HanlinScriptExtensions/HanlinScriptWidgetLiveActivity.swift) |
| S07 | Standalone Developer Studio, library, drafts and coordinated workspace | [HanlinMiniAppsApp/HanlinMiniAppsApp.swift](../../../../HanlinMiniAppsApp/HanlinMiniAppsApp.swift); [HanlinMiniAppsApp/MiniAppsDeveloperStudio.swift](../../../../HanlinMiniAppsApp/MiniAppsDeveloperStudio.swift); [HanlinMiniAppsApp/MiniAppsDeveloperWorkspace.swift](../../../../HanlinMiniAppsApp/MiniAppsDeveloperWorkspace.swift); [HanlinMiniAppsApp/MiniAppsLibrary.swift](../../../../HanlinMiniAppsApp/MiniAppsLibrary.swift) |
| S08 | Canonical authoring service, real TypeScript editor and gallery | [AI_HLY/Downstream/RuntimeCore/Core/MiniAppAuthoringService.swift](../../../../AI_HLY/Downstream/RuntimeCore/Core/MiniAppAuthoringService.swift); [AI_HLY/Downstream/RuntimeCore/Node/Host/miniapp-authoring.mjs](../../../../AI_HLY/Downstream/RuntimeCore/Node/Host/miniapp-authoring.mjs); [Scripts/MiniApps/Examples/expo-hello-world/App.tsx](../../../../Scripts/MiniApps/Examples/expo-hello-world/App.tsx); [Scripts/MiniApps/Examples/expo-hello-world/README.md](../../../../Scripts/MiniApps/Examples/expo-hello-world/README.md) |
| S09 | Original image rendering and NativeScript UIKit drawing example | [Packages/HanlinPlatform/Sources/HanlinScriptExtensions/ScriptWidget/Original/Component/Attributes/Effect/ScriptWidgetAttributeRotationEffectModifier.swift](../../../../Packages/HanlinPlatform/Sources/HanlinScriptExtensions/ScriptWidget/Original/Component/Attributes/Effect/ScriptWidgetAttributeRotationEffectModifier.swift); [Packages/HanlinPlatform/Sources/HanlinScriptExtensions/ScriptWidget/Original/Component/Attributes/Image/ScriptWidgetAttributeImageModifier.swift](../../../../Packages/HanlinPlatform/Sources/HanlinScriptExtensions/ScriptWidget/Original/Component/Attributes/Image/ScriptWidgetAttributeImageModifier.swift); [Packages/HanlinPlatform/Sources/HanlinScriptExtensions/ScriptWidget/Original/Component/Elements/ScriptWidgetElementTagImage.swift](../../../../Packages/HanlinPlatform/Sources/HanlinScriptExtensions/ScriptWidget/Original/Component/Elements/ScriptWidgetElementTagImage.swift); [Scripts/MiniApps/Examples/nativescript-image-drawing/drawing.ts](../../../../Scripts/MiniApps/Examples/nativescript-image-drawing/drawing.ts) |
| S10 | MiniApps-only system publication with shared extension SDK | [AI_HLY/Downstream/ScriptingPlatform/HanlinInstalledMiniAppEntity.swift](../../../../AI_HLY/Downstream/ScriptingPlatform/HanlinInstalledMiniAppEntity.swift); [AI_HLY/Downstream/ScriptingPlatform/HanlinMiniAppCaptureCoordinator.swift](../../../../AI_HLY/Downstream/ScriptingPlatform/HanlinMiniAppCaptureCoordinator.swift); [AI_HLY/Downstream/ScriptingPlatform/HanlinMiniAppCaptureInbox.swift](../../../../AI_HLY/Downstream/ScriptingPlatform/HanlinMiniAppCaptureInbox.swift); [AI_HLY/Downstream/ScriptingPlatform/HanlinMiniAppSpotlightIndex.swift](../../../../AI_HLY/Downstream/ScriptingPlatform/HanlinMiniAppSpotlightIndex.swift) |
| S11 | Unbound generic system broker versus separate original public service APIs | [AI_HLY/Downstream/HostServices/System/HanlinSystemServicesBroker.swift](../../../../AI_HLY/Downstream/HostServices/System/HanlinSystemServicesBroker.swift); [Scripts/MiniApps/generate-scriptwidget-service-types.mjs](../../../../Scripts/MiniApps/generate-scriptwidget-service-types.mjs); [Scripts/MiniApps/scriptwidget/service-shapes.mjs](../../../../Scripts/MiniApps/scriptwidget/service-shapes.mjs); [Scripts/MiniApps/scriptwidget/service-types.d.ts](../../../../Scripts/MiniApps/scriptwidget/service-types.d.ts) |
| S12 | Canonical dependency, target, generation and reachability authorities | [Packages/HanlinAppExtensionsSDK/Package.swift](../../../../Packages/HanlinAppExtensionsSDK/Package.swift); [Packages/HanlinPlatform/Package.swift](../../../../Packages/HanlinPlatform/Package.swift); [Packages/HanlinWidgetSDK/Package.swift](../../../../Packages/HanlinWidgetSDK/Package.swift); [Scripts/CI/IntegrationValidation/project_graph.py](../../../../Scripts/CI/IntegrationValidation/project_graph.py) |

Additional machine-readable receipts: [source catalog](scriptable00-source-audit.json), [release/API rows](scriptable00-release-api-map.json), [PR22 equivalence](scriptable00-pr22-cache-equivalence.json), [Host/gallery evidence](scriptable00-host-evidence.json).
