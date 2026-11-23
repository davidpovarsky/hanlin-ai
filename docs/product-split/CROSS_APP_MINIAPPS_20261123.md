# Cross-app MiniApps implementation — 2026-11-23

## Original sources and isolated branches
- Hanlin SDK source: 476a14c5533f1816078a64b9553fab3ac40f6a63.
- Actual MiniApps release branch observed at ef8259687e9e5d75686f2c2b250f6c92141632b4.
- Otzaria source: acdf25482541199e2d7fe331cc7e557ee462cddc.
- Anytype current original source: 7dc4dc1ba214cbb9e0a6cbebda9e5709fbe7c4c1.
- Asana parent: https://app.asana.com/0/1219603102275846/1220823275216739.

## Architecture and actual behavior
Consumers embed only the dependency-free HanlinMiniAppsBridge and HanlinMiniAppsPicker products.
Canonical discovery and all execution engines remain inside Hanlin MiniApps.
The producer projects its existing installed catalog into group.com.itorah.shared.
An invocation contains original app, document/revision, UTF-16 selection, scene, input items, and callback URLs.
The shared request is durable before opening hanlinminiapps://x-callback-url/run?request=<UUID>.
Every invocation owns its own foreground platform and SwiftUI scene identity.
The new-window preference is shared with the Favorites/order/visibility editor; it defaults on.
iPhone uses its current window because its OS does not expose iPad multiple scenes.

Consumers retain a durable native write receipt with the original document mutation before transport acknowledgement.
Otzaria updates the original annotation database and sync queue. Reader corpus remains immutable; output becomes a linked annotation.
Anytype uses original native block actions, preserves block identifiers/tree and rich-text marks, and verifies applied content.
If source content changes before the response arrives, output is retained without replacing unrelated content.

Text Studio now consumes actual selected text and returns actual editor contents.
Caret insertion starts with an explicitly empty editor, without reusing an unrelated previous draft.
Display-only apps have an ordinary Return action that records display completion with no document edit.
Success/error/cancel callbacks are opened only after persisting the result; callback failure retains the result for source recovery.

## Authoring API
ScriptUI has the typed global MiniApps; NativeScript uses createHostServices().miniapps;
Expo uses hostServices.miniapps. All call the existing session-bound native adapter:
- getContext(): original typed invocation.
- complete(text | {operation, items, status, message, metadata}): persist and return.
- cancel(): persist cancellation and return.
- readAttachment(id): original bytes as base64.
- writeAttachment({base64, name, typeIdentifier}): durable file item usable in output.

Example ScriptUI:

    const context = await MiniApps.getContext();
    const text = context.inputs.find(item => item.kind === "text")?.text ?? "";
    await MiniApps.complete({
      operation: context.operation,
      items: [{kind: "text", text: text.toUpperCase(), typeIdentifier: "public.utf8-plain-text"}]
    });

An app may return insert, replaceSelection, replaceDocument, display or custom.
The request defaults express the editor's intent; an app can return an explicit operation.
No extra pairing, permissions or engine configuration UI is added.

## Window boundary requiring upstream engine work
The pinned NativeScript9.1.0 main UI VM is a process-global unique_ptr in the actual upstream binary.
Starting a second independent main application destroys the first VM.
NativeScript Core's openWindow supports scenes authored inside one cooperating JS app; it does not isolate two installed mini-app packages.
The existing main-VM admission guard is retained, and admission/cleanup cannot overwrite a different scene's provider.
See Packages/HanlinNativeScriptRuntime/Documentation/MULTIWINDOW_STATUS_20261123.md.
Independent concurrent NativeScript invocations are NOT claimed as supported.
Swift views, ScriptUI sessions and Expo session models have separate per-invocation foreground ownership.

## Verification and acceptance gates
Already executed:
- 11 new shared Foundation tests on Oracle/Swift6.4.3. Evidence under Packages/HanlinMiniAppsBridge/Verification.
- 17 focused Otzaria consumer checks, including original SQLite transaction/rollback and fresh-process receipt recovery.
- 13 focused Anytype native-edit planning checks, including UTF-16, marks, conflict and replay behavior.
- 2 new actual emitted NativeScript facade tests for bound-session routing, Unicode/file payload fidelity and native error propagation.
- NativeScript TypeScript5.9.3 strict compile + emitted facade/declarations consistency.
- ScriptUI declarations generator consistency.
- Generated root package manifest consistency; all508 original/current app sources and resources retained.
- Swift source parse and Xcode project graph parse. These are not Apple typechecking.

Native gates:
- Isolated shared products Apple compilation: apple-devtools run45268107140, source3d0c6d1d35d4c04a79036eb9caceedd8fa303364, Xcode27 generic iOS Simulator, BUILD SUCCEEDED.
- The existing production_runtimes workflow selects5 new producer tests and2 new preference UI tests plus the2 affected NativeScript/Expo regressions. The twenty unchanged storage tests are not repeated.
- The exact successful producer app build is exported with source/executable/archive hashes for true consumer→TextStudio→consumer UI journeys.
- Every native test must report EXECUTED_PASS, TEST_FAILED, BUILD_FAILED or NOT_RUN accurately.
- Signed physical-device App Group provisioning is separate from simulator entitlements.

## Signing facts needing readback
MiniApps uses com.itorah.hanlinminiapps and owner team NA6HPWARQ2.
Otzaria uses com.davidpovarsky.chavrusatext and the same owner team; original groups are preserved.
Anytype's original source still declares upstream J3NXTX3T5S and io.anytype.app(.dev).
An App Group cannot be shared across independent signing teams.
The integration must use an actually registered owner fork identity and profiles, preserving existing installed user data.
The existing release-resource audit workflow reads owner Apple bundle metadata before any identity decision.
No signed/physical-sharing success is inferred from a capability flag or an unsigned build.

## Apple UI references
- https://support.apple.com/en-sg/guide/ipad/ipad29729577/ipados
- https://developer.apple.com/documentation/swiftui/windowgroup
- https://developer.apple.com/documentation/xcode/configuring-app-groups
- UI reference image: https://images.macrumors.com/article-new/2020/03/how-to-customize-share-sheet-apps-4.jpg

The shared native chooser follows More→Edit, Favorites minus/removal and drag reorder,
Suggestions plus/add and visibility switches. It controls the in-app MiniApps chooser only.
