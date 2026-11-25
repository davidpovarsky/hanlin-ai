# Cross-app MiniApps — current integration, 25 November 2026

## One runtime application and two original consumers

Hanlin MiniApps owns the catalog and execution engines. Maktabah/Otzaria and
Anytype/Pinkha use the shared `HanlinMiniAppsBridge` and
`HanlinMiniAppsPicker` packages. The integrations do not embed another MiniApps
engine. An original consumer's own existing runtime dependencies remain intact.

The active engine work covers Expo, React Native, the existing SwiftUI
integration and NativeScript. Development of Scripting-JSC, ScriptUI and the
dedicated `.scripting` engine is frozen under the owner's parent-task decision.
Their existing code and information are preserved.

The catalog is projected into `group.com.itorah.shared`. A request is persisted
before the producer opens:

```text
hanlinminiapps://x-callback-url/run?request=<UUID>
```

Requests carry the source application, original document/revision, UTF-16
selection, originating scene, input items and callback URLs. Each invocation
owns its foreground platform and scene identity. The bridge persists success,
error or cancellation before attempting a callback. If the source cannot open,
the result remains available for recovery.

## Shared contract

| Capability | Meaning |
| --- | --- |
| `getContext` | Read the invocation's original typed input and source context. |
| `complete` | Persist the response operation, items, status and metadata. |
| `cancel` | Persist cancellation for this request. |
| `readAttachment` | Read the authorized attachment bytes as base64. |
| `writeAttachment` | Persist a result attachment and return its file item. |

Response operations are `insert`, `replaceSelection`, `replaceDocument`,
`display` and `custom`. Native consumers decide the supported meaning of a
response; the bridge does not grant an arbitrary native command executor.
The current consumer `custom` path presents and acknowledges the result. It
must not be described as a general native business-action registry.

The active authoring surfaces are `hostServices.miniapps` in Expo and
`createHostServices().miniapps` in NativeScript. Text Studio consumes actual
selected text and returns actual editor contents. Caret insertion begins with
an empty input rather than a previous draft.

## Native picker and windows

The shared SwiftUI chooser has Favorites and additional apps, add/remove actions,
drag reordering, visibility controls, original names/icons, persistent choices,
an Edit/Done flow, and the preferred new/existing window behavior. It follows
the system share sheet's More/Edit interaction using native components.

iPad requests can open another scene or use the current scene. iPhone uses its
current window because the platform does not expose the iPad scene workflow.
The standalone iPad EN/HE and persistence tests exercise the actual app; the
separate iPhone gate covers the existing locale/layout and preference methods.
A preference test alone is not an external return-to-current-window journey.

NativeScript cooperative packages opt into `hanlinNativeScript.windowFactory: 1`.
The current original 9.1.1/Core 9.1.4 implementation isolates staged module
identities, package-local imports/dependencies, resources, root CSS, window
storage, bound services and callbacks for same-package and different-package
windows. Arbitrary process-global JavaScript/native state is still shared.
Whole-application entries retain the original singleton guard.
See [the exact NativeScript boundary](../../Packages/HanlinNativeScriptRuntime/Documentation/MULTIWINDOW_STATUS_20261123.md).

## Otzaria / Maktabah

The integration uses the original reader, selection/action menus, native
annotation editors, editor toolbar and shared picker settings. Context includes
text, source/book identity, document data and authorized files as applicable.

Read-only book text stays unchanged; returned edits become source-linked
annotations. Editable annotations use the original storage and synchronization
paths. A local SQLite transaction binds the canonical mutation and its receipt.
Native attachment upload happens outside that transaction, so the entire native
upload-plus-document workflow is not claimed to be atomic.

The native file path uses the original editor SDK's file download/upload API.
The shared File Workshop input exercises empty, single and multiple native-file
exports, identical filenames with independent bytes, cold return, cancel and
replay. Portable checks and UI compilation are separate from executing these
journeys in the original app.

## Anytype / Pinkha

The integration is inside the original object/document editor, native selection
menu and toolbar. It uses original native block actions, preserves block identity,
hierarchy and rich-text marks, and retains source information for return.

Explicit block or text selection controls export scope. Without an explicit
selection, the native file path can export the original document's file blocks.
A stale selection is rejected. Attachment metadata maps bridge attachment IDs
to the original native block IDs after actual original-file readback.

Before native writes, the consumer persists a request journal under a namespace
derived from the account, space and object. Recorded block IDs are not reapplied.
If a crash leaves a text operation without its final receipt, exact text/mark
readback identifies an already-applied result; an unchanged captured source
permits the write. Detected newer content is preserved and the result is appended
separately.

Inserted blocks carry deterministic request/index identity and the native
`pinkhaMiniAppsRequest` marker. Recovery finds that block before creating another.
A file upload is recovered only after the original download returns matching
bytes/hash and the current block state is checked again. A completed journal is
persisted before the Bridge acknowledgement, so a later replay can retry only
the acknowledgement. Recorded insertions are not recreated after a user later
edits or deletes them.

These are source-reviewed mechanisms, pending the original-app acceptance below.
Native RPCs, journal writes and the Bridge acknowledgement are separate operations.
External writers can still race between the final read and native RPC; a
multi-block change can be partial. There is **no proved native CAS-plus-receipt
transaction**. A detected mismatching upload remains pending with an error.

The required original-app gate keeps the five preparation/editor/duplicate/
returned-document/conflict cases and adds the actual native-files roundtrip,
cold reopen, cancellation and replay journey. Planning tests and SDK API checks
do not replace those original-app cases.

## Current source and acceptance

The current standalone candidate is
`fe3f75d0638671c749225e9a8ddd487db70981cf`, on
[Hanlin PR18](https://github.com/davidpovarsky/hanlin-ai/pull/18).
The actual preceding `70eb9c2d` build/export passed and its full 25-case run
finished **23 pass / 2 fail / 0 skip**. All three originally failing cases passed,
including genuine NativeScript JavaScript nonce output and relaunch. Current
fe3 acceptance is pending; its new 27.2 execution cannot inherit a 27.0 label.

The remaining 70eb cases separately exposed an OS backboardd/Metal crash and
an existing-window test querying a background scene. fe3 contains the exact
foreground selection correction, an iPad-only four-orientation declaration,
and retained-state rotation assertions. The current SDK import presentation
fix is also included before the next full run. The original 273 run remains
20 pass / 5 fail / 0 skip, with separate incomplete image-observation evidence.

[PR19](https://github.com/davidpovarsky/hanlin-ai/pull/19) is incorporated through
`dc53a6c8`: the original SDK/ESM/callback corrections, subsequent authoring
acceptance waits for real receipts, and the shipping importer ownership fix.
Its broader AI/SDK acceptance is a separate gate; this standalone 25-case run
does not grant credit for that larger selection.

The original editor SDK at `8ae85a6490c4fb763fcd01d5f93345f7e071db92`
passed actual Debug simulator framework construction, its 292-declaration
binary-only consumer, EN/HE resources and single-original-runtime ownership.
Qualification SHA-256 is
`f2863945c4fd54bde8aeb4d9096a5a17e77c6afa4b3268242b1cb59b4ca53268`.
Collections 1.3.0 is the exact shared dependency because the actual Otzaria
dependency graph requires it. Unchanged original native66/Swift and three-target
ABI evidence is explicitly retained through a source-bound donor admission.
Device Release and Release simulator qualification remain separate requirements.

The original Anytype application at `9225c41c` is compiling after the exact
original-configuration reference repair. Otzaria at `eb3ac2e1` is executing its
original preparation/build route with the current qualified SDK. Both remain
bound to their authentic 70eb producer inputs while those executions run.
Adopting a later producer requires independent admission and an explicitly
source-bound continuation; no earlier receipt is rewritten. Original-app native
acceptance and final official distribution remain open at this checkpoint.

- [Otzaria PR4](https://github.com/davidpovarsky/Maktabah/pull/4)
- [Anytype PR2](https://github.com/davidpovarsky/anytype-swift/pull/2)
- [Central Asana task](https://app.asana.com/1/1219597879016953/project/1219603102275846/task/1220823275216739)

Every reported result distinguishes executed pass, verified retained proof,
failed, not run and externally blocked. Raw failed runs remain immutable.

## Distribution boundary

The existing owner identities use Team `NA6HPWARQ2`:

| Application | Existing bundle ID |
| --- | --- |
| MiniApps | `com.itorah.hanlinminiapps` |
| Otzaria | `com.davidpovarsky.chavrusatext` |
| Anytype | `io.anytype.app.NA6HPWARQ2` |

All original consumer/extension capabilities and groups must remain. In particular,
Anytype's native group `group.io.anytype.app.NA6HPWARQ2` and its multicast
request are not removed to make an archive compile.

Current observed distribution profiles do not yet prove the complete shared
App Group allocation for both consumers and all shipping producer extensions.
An `APP_GROUPS` capability flag is not an actual profile membership. Existing
MiniApps/Maktabah App Store Connect records are visible; no Anytype/Pinkha record
was visible to the connected API key in the complete inspected app list.
That observation does not assert absence outside that key's scope.

No new TestFlight delivery is claimed at this checkpoint. Simulator entitlements,
an unsigned device archive, upload acceptance and Apple processing are separate
checks. A physical iPad run remains distinct from simulator proof.

## System references

- [Apple iPad share sheet](https://support.apple.com/en-sg/guide/ipad/ipad29729577/ipados)
- [SwiftUI WindowGroup](https://developer.apple.com/documentation/swiftui/windowgroup)
- [Configuring App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups)
