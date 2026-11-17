# Hanlin Presentation SDK

An iOS/iPadOS 27 Swift package for presentation in an existing host. It contains
no model engine, account singleton, permission broker, application database, or
network backend. The original Hanlin app imports these canonical implementations.

## Products

- `HanlinPresentationKit`: versioned profiles/catalogs/shells, conversation
  assignments, per-message state and chronological OpenUI inline framing.
- `HanlinRichUI`: the original pinned Thesys React renderer and component library
  in a local WKWebView; native SwiftUI controls and Swift Charts use the same
  upstream `lang-core` parser, evaluator, bindings, action plans and query manager.
- `HanlinChatUI`: the original workspace container, motion presets, shimmer,
  natural-height disclosure, inline Host consent, and a native research inspector.

Ordinary Markdown remains the host's existing renderer. Hanlin keeps
`ChatMarkdownView` and the original A2UI owner; marked rich blocks are ordered
inside the same existing assistant row. OpenUI itself has no A2UI compile flag.

## Host configuration

```swift
import HanlinPresentationKit
import HanlinRichUI
import HanlinChatUI

let descriptor = try OpenUICatalogs.host(appID: "my-app", research: true,
                                      capabilities: ["original-host-actions"])
let resolved = try ProfileResolver.resolve(host: descriptor,
    conversationID: conversationID, assignment: savedAssignment)
let state = MessageOpenUIStateStore(snapshot: savedMessageSnapshot)
state.onChange = { snapshot in
    // Persist in this host's EXISTING message row, not a new chat database.
}
```

The host supplies its original transcript and composer to `HanlinChatView`, and
its source viewer to `HanlinResearchShell`. Profiles choose a shell independently
of their component catalog. The bundled standard and Torah research catalogs
are examples, not hardcoded global application settings. A second host can use
different defaults and conversation assignments without sharing message state.

`OpenUIRendererConfiguration` accepts a host-owned local resource directory and
optional native component provider. Extend the original upstream library in the
asset build, export its exact versioned schema/prompt, and provide the corresponding
native view through this hook. Neither prompts nor model output may install code.
Keep previous catalog IDs and assets when registering a new version, so saved
messages continue using their original `ResolvedPresentationProfile` snapshot.

## Stream and state

Use the existing model text stream. No Thesys API key is required:

````text
Ordinary Markdown before the controls.
```openui-lang renderTarget=react
$budget = [1200]
$nights = "3"
root = Stack([Input("nights", "Nights", "text", null, $nights)])
```
Ordinary Markdown between the blocks.
```openui-lang renderTarget=swiftui
root = Stack([TextContent("Budget: " + $budget[0] + ", nights: " + $nights)])
```
````

The model chooses each block's target. A full answer may be one fenced program;
it is not required for shared state. Each message owns one state store. Original
React `initialState/onStateUpdate` and native control bindings read/write that same
store. Renderer deltas preserve sibling form fields and avoid echo loops. The
host persists snapshots with the original message and conversation identity.

`Scripts/OpenUI/build.mjs` emits the exact catalog instructions with the upstream
`inlineMode` option. Supply them through the host's existing system/developer
prompt for any selected text model. The native catalog advertises only implemented
controls; the React target retains the complete upstream library.

## Actions and authority

`OpenUIBlock.perform` returns every tool, action and link event to the original
host with immutable application, conversation, message and part identity.
Hanlin's adapter resolves its original Session/Host, original catalog, consent,
dispatcher and ordered pending-before-effect persistence. It does not execute
JavaScript produced by the model. Read-only history recreates no tool grants.

The existing model-tool numeric provenance guard is retained for normalized
Query/Mutation arguments: unverified numeric leaves are rejected before dispatch.
Local numeric form bindings work normally. This existing restriction is not
silently bypassed or relabeled as provider-original input by the presentation SDK.

## Building the pinned assets

From `Scripts/OpenUI`: `npm ci --ignore-scripts --no-audit --no-fund`, then
`npm run build` and `npm test`. Versions and integrity are pinned in the lockfile.
Generated runtime/CSS/prompts/notices are committed as package resources; app
builds do not need npm or a remote rendering website. The community Swift port
is not copied because its source license was not verified. Native views use the
MIT upstream core rather than reimplementing the grammar or expression language.

## Verification scope

Portable Foundation tests cover scope, catalog version persistence, state merge,
disclosure state, JSON and mixed-stream framing. Node tests exercise the actual
upstream parser/store/evaluator, cross-block bindings and Query/action handoff.
These do not prove UIKit/WebKit rendering. Original-app XCUITest and exact-source
Xcode evidence are recorded separately under `docs/continuation-20261117`.

The Torah sample is a reusable catalog and reference shell. It is not an Otzaria
ActionCore adapter, has no local Torah database, and does not prove Otzaria native
integration. That work belongs to the separately authorized Otzaria phase.
