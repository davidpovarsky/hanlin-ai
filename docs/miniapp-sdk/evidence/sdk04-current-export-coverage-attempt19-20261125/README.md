# SDK04 — current export coverage and actual native contexts

This report reconciles the original SDK04 acceptance criterion against current source `d4a0b115b106d4250ea40ad66153d5156847a07c` and the completed original Mini25 + AI27 run. All 25 Mini cases and all 27 AI cases passed with zero failures or skips; the independent NativeScript five-runtime case also passed. It records bounded coverage for the public adapters, exact original forwarding, compiler/drift evidence and device-context limits. It does not turn context-only checks into universal API or operating-system acceptance.

The original criterion, preserved verbatim in the historical receipt, is:

> DoD: תוכן .d.ts מדויק + tooling שמגלה drift, typecheck strict ו-Metro bundle, tests לכל public exported adapter, תיעוד מגבלות מכשיר.

**Review disposition:** the evidence now supports that bounded SDK04 criterion. The per-export distinctions below are part of the result. This folder is an evidence reconciliation; it introduces no production changes, tests, compiler runs, source generation or native execution.

## Source and execution provenance

- Current consumer source/tree: `d4a0b115…` / `f7a6596a…`, with the authenticated 25 prepared inputs.
- Both current consumer products were actually built at d4a in V11. Original52 uses those authenticated products and accurately records `REUSED_AUTHENTICATED_FOCUS_PRODUCTS`; it does not claim another build.
- SDK19 remains the unchanged SDK produced from `a2c8a1b1be746461272ba77254603304567c309d`, manifest `4505c284…`, input `ba8f3f1f…`.
- The original strict/Metro producer ran at `6c006c948f0a6f371f7fc68b90e393f43734f8dd`. All **58 enumerated producer, facade, native, fixture and test files are byte-identical** at current d4a. `source-identities.json` records both hashes for each file; the actual read-only Git diff is empty. This is deliberately a scoped comparison.
- The candidate `Scripts/ExpoNativeAPI/build-probe.mjs` does not exist in the current tree. It is explicitly excluded, not replaced with an assumed path. The actual existing NativeAPI preflight source is enumerated.
- The unchanged modifier capture ran against d4a using SDK19's actual TypeScript 6.0.3 parser. Its historical hard-coded `baseSHA` and old `NOT_RUN/PENDING` fields remain untouched in the raw file. The saved invocation command binds the actual source; later native results are reconciled in separate derived files.

Original52 finished at **2026-11-25 18:30:22.583701 UTC**. The current NativeScript companion finished at **18:39:21.235602 UTC**. These are actual simulator results on the recorded iPad Pro 13-inch (M5), iOS Simulator 27.0 environment. They do not establish a physical-device run.

## Public export coverage

`per-export-coverage.json` has **133 individually named core runtime-export rows**: 13 manual components, four generated views, 83 effective generated modifier factories and 33 direct NativeAPI reexports. Additional sections map metadata, original forwarding, HostServices, shared types and cross-app wrappers. The count is an inventory of these adapter groups, not the total size of the upstream SDK.

| Group | Current evidence | Exact boundary |
|---|---|---|
| 13 manual components | All mapped to actual passing native assertion bodies | Selected values, layout and callbacks; not every OS setting or dismissal |
| Four generated views | GroupBox, EditButton and EmptyView native assertions passed | DefaultDocumentGroupLaunchActions is a typed, deliberately unmounted document-scene leaf |
| 83 effective modifier factories | All have source calls, parameter fields, native Records, registry/forwarding identities and strict-project evidence | 11 bounded observable assertions; 72 context/source/type checks without individual OS-effect assertions |
| 33 NativeAPI value reexports | Exact original `@nativescript/react-native` forwarding and drift/type contract | Four exports used by the actual UIKit/Worklets fixture; not 33 independently invoked semantics |
| Metadata | Current installed runtime/bridge/inventory comparison passed | Historical red/green drift checks remain historical, with their original source and logs |
| Expo HostServices | Real five-runtime execution, storage, installed action replies/errors and prepared widget publication passed | Publication receipt has `osRendered:null`; OS push/tap and widget placement are not inferred |
| NativeScript HostServices | Storage/relaunch/lifetime tests plus separate current five-engine typed-facade case passed | Not every cancellation, wrapper mutation or system entrypoint combination |
| External MiniApp wrappers | Native mailbox, source-recovery, scene and nested-modal ownership cases passed | Saved complete/cancel acknowledgement remains separate from opening the source app |
| Original Widgets / ActivityKit | Selected original timeline/isolation/lifecycle case passed | HostServices wrapper start/update/end is not established by its enable/list probe |

### Manual adapters

| Public adapter | Actual selected assertion |
|---|---|
| TextEditor | Native text entry and controlled reset change the native value |
| Focused | Real keyboard focus and transfer to another native field deliver the expected state/event |
| Searchable | Child action, native query and submit return the expected values |
| LazyVGrid / LazyHGrid | Native cell geometry and actual taps distinguish vertical and horizontal arrangements |
| ViewThatFits | The 160/360-point proposals select the compact/wide native candidate |
| SafeAreaInset | Native inset geometry moves between bottom and top; its slot callback executes |
| Table | Native selection, controlled clearing/reselection and changed row data are asserted |
| AsyncImage | Native empty → real PNG success → actual HTTP404 failure is observed |
| Sheet | Controlled close and real drag dismissal have distinct exact callback counts |
| FullScreenCover | Two controlled present/close cycles have the expected dismissal counts |
| PopoverPresentation | Controlled close and native outside-tap dismissal are both asserted |
| Inspector | Native slot/button and controlled close/reopen cycles are asserted |

AsyncImage's real request authority is the final child's `nativeAdapterAssets.requests`: `/health` 200, `/pixel.png` 200 with 82 bytes/hash `7713482a…`, and `/missing.png` 404 with 30 bytes/hash `9cf62cb4…`. The earlier intermediate Mini25 state had an empty top-level request field; the nested asset capture was populated. The final child preserves that capture and also has the populated top-level copy. No transport response or renderer was substituted for this proof.

A controlled dismissal assertion observes the binding transition. It is not an assertion that the transition animation finished or that every OS dismissal path behaves identically.

### Generated views and modifiers

GroupBox now has actual passing dynamic label/content, child-fallback and explicit-null assertions. EditButton drives an original native List deletion and callback. EmptyView changes an original Host layout measurement from 120×44 to 0×0 and back. The document launch action remains deliberately unmounted because this embedded Host has no DocumentGroupLaunchScene/DocumentLaunchView; no document browser was added merely to change its coverage status.

The modifier inventory is **87 declarations minus four names with explicit upstream precedence = 83 effective local factories**. The excluded names are `navigationBarTitleDisplayMode`, `preferredColorScheme`, `presentationCornerRadius` and `sectionIndexLabel`; they are not counted twice. Eighteen supporting original modifier factories are listed separately.

The eleven bounded observable assertions are `accessibility`, `position`, `tracking`, `allowsHitTesting`, `submitScope`, `tableColumnHeaders`, `selectionDisabled`, `searchCompletion`, `navigationBarBackButtonHidden`, `navigationBarHidden` and `navigationBarTitle`. The JSON maps each to its exact current passing case and precise assertion. In particular, `navigationBarHidden(false)` establishes the bar's presence in that context; it does not establish every hide/show transition.

The other 72 retain each original factory's named context and limitation. VoiceOver/speech and drag/drop, file dialogs and document scenes, window activation, preview metadata, system gestures/status/overlay, platform-version and RTL behavior need their relevant system context. A successful panel mount does not prove those individual effects.

### Original forwarding, NativeAPI and HostServices

The public Expo wildcard exports still use the original implementation. The NativeAPI facade still directly exports all 33 original upstream value names and 22 upstream type names. The current real fixture uses `init`, `runOnUI`, `defineUIKitView` and `defineUIViewController` to verify actual UILabel, UISwitch target/action, UIViewController lifetime and UIDevice access. Other original exports retain source/identity/type coverage; no Hanlin replacement implementation or per-method execution is invented.

The current AI action case verifies an installed original Hermes handler, returned values, real failure acknowledgement and subsequent recovery. Its notification-ingress assertions exercise the native queue and installed handler; they do not constitute an OS notification delivery/tap test. The current publication case reopens the actual store, loads the original Expo widget consumer, verifies title/counter changes and rejects a stale generation. Its truthful receipt remains `stateCommitted/catalogVisible/reloadRequested:true` and `osRendered:null`. The old positional publisher is storage compatibility, with `published:false`.

The independent NativeScript five-engine result belongs to its own receipt, not to an inference from Mini parity or package build success. It imports the generated typed facade and calls Node, TypeScript, local Python, JavaScriptCore and shell. The original Mini parity case, lifetime cases and selected cross-app cases retain their own narrower assertions.

The selected HostServices Live Activity probe reads enabled/list. Its connected start/update/end wrappers are **not** proved by that read-only probe or by success of the separate original `expo-widgets` lifecycle case. System placement, Lock Screen/Dynamic Island rendering and the full Entrypoints matrix remain separate scopes.

## Strict types, Metro and drift

The retained original `node Scripts/Expo/build-probe.mjs` command exited zero in **42.92469737499778 seconds**. Its complete log records TypeScript **6.0.3**, strict original UI with **zero valid diagnostics and five exact negative diagnostics**, and strict original Widgets with **zero valid diagnostics and three negatives**. It applied five exact pinned declaration-file corrections, with **no skipLibCheck or runtime implementation changes**, then produced the original A/B UI and Widgets Metro packages. The source-binding comparison connects this actual producer execution to the unchanged current SDK04 files; it is not another compiler run.

Historical real drift proofs are referenced without rewriting them: stale public Expo metadata failed once before six passing checks, and actual NativeAPI Worklets version drift similarly failed before six passing checks. The current native metadata case now separately passes. The frozen legacy tools-only multiRuntime table remains untouched and is not presented as current foreground runtime metadata.

## Evidence layout and limits

- `per-export-coverage.json`: each named export, source/fixture/native binding, current case ID and exact coverage boundary.
- `current-native-results.json`: derived current 25+27+1 case index, original result-file hashes, warnings, terminal identities and actual resource requests.
- `source-identities.json` and the empty `producer-current.diff`: exact 58-file current/producer equality plus the actual read-only command.
- `historical-references.json`: immutable original DoD and portable drift/manual evidence.
- `raw/`: exact current source-capture bytes and original strict/Metro log/copy receipt/full command stream. The old failed Repair command in that historical stream remains intact.
- `manifest.json` / `receipt.json`: scope, explicit cross-folder dependencies and exact member hashes.

Complete original52 and NS5 packets belong to the separately owned `original52-final-pass-attempt19-20261125/` and `nativescript-five-runtime-pass-attempt19-20261125/` evidence folders. This map references their immutable paths and hashes rather than duplicating their raw packets. Integration must include those folders.

Original warnings remain visible: Mini25 has 17 orientation warnings, AI27 has four audio/orientation warnings, and the producer log has four asset-destination warnings. The NS5 summary has no warnings. No warning-free combined result is claimed. This report does not close physical-device acceptance, every operating-system entrypoint, every upstream method, or the generic HostServices ActivityKit mutation paths.
