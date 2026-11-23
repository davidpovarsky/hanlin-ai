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

## Canonical Composer and Markdown

`HanlinChatUI` now owns the original `HanlinMorphComposer`,
`NativeMultilineTextEditor`, `HanlinDetachedCapabilityChips` and
`HanlinMarkdownView`, alongside motion, tool headers and inline consent.
Hanlin's old file paths contain compatibility aliases or host adapters, not a
second implementation. Drafts, selected models, capabilities, SwiftData,
selection destinations and source navigation remain with the importing host.

```swift
import SwiftUI
import HanlinChatUI

struct HostInput: View {
    @Binding var draft: String
    @State private var height: CGFloat = 38
    let send: () -> Void

    var body: some View {
        NativeMultilineTextEditor(text: $draft, textHeight: $height,
            maxHeight: 180, usesAutomaticLineLimits: true,
            onSendMessage: send)
            .frame(height: height)
    }
}

// Uses the exact original SwiftStreamingMarkdown dependency and LaTeX renderer.
// Host menus, selection, code-fence and source-link modifiers stay injectable.
// HanlinMarkdownView(text: answer, onRendered: didRender)
```

The Markdown dependency is pinned to the same commit as the app. Existing media,
fonts, selection menus and citation rendering have one implementation. A host
explicitly supplies its image policy and scoped citations; the SDK stores no
source or conversation database. Favicon decoding is bounded and performed away
from the main actor.

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

## Original code fences and transcript scrolling

The SDK also owns the production Mermaid/diff renderer and its pinned local assets.
ChatCodeFenceView(blockID:kind:source:onTrace:) provides the original source toggle,
copy/share/expand actions, diff layouts and WebKit preview. ChatCodeFenceEngine,
ChatCodeFenceDocument and ChatCodeFenceWebView are public for hosts composing
their own containers. Asset validation, renderer cache, cancellation and the
script-disabled visible document remain the original implementation.

ChatAutoFollowController, ChatAutoFollowLayout and ChatScrollViewHandle expose
the original coalescing, user pause/resume, finite geometry checks and native
viewport lifetime management. A host binds its real UIScrollView and conversation
ID; it keeps ownership of its transcript and scroll position actions. Creating a
controller does not select a conversation or access an application singleton.

An optional HanlinPresentationTraceHandler routes diagnostics to the host's
existing sink on the main actor. The SDK does not open an application log file.
Hanlin injects its existing logger; importing apps can provide their own sink.
The app's former source paths are aliases, and the asset builder writes directly
to the shared package so upgrades cannot recreate an app-only renderer.


## Original A2UI and rich media

`import HanlinA2UI` provides the original Hanlin A2UI implementation as a separately
selectable module. The app's former A2UI and media files now contain aliases to this
module; the original schemas, renderer, owner lifecycle, interactions and visual
implementation have one owner. The module enables its Apple UI implementation
without requiring the host to define `HANLIN_A2UI_POC`.

- `HanlinA2UIResultStore`, `HanlinA2UIResultKey` and `HanlinA2UIResultEventSink`
  preserve the existing run/result identity, ordered input and generation lifetime.
- `HanlinA2UIResultProjection`, `HanlinA2UIResultProjectionSource`,
  `HanlinChatContentProjection` and `HanlinChatContentProjectionSource` provide the
  original read-only tool and model content projections.
- `HanlinA2UIProjectedResultView` and `HanlinA2UIResultView` render the same official
  surfaces that Hanlin uses. The caller chooses placement, sizing and inherited
  SwiftUI locale, layout direction, accessibility and enablement.
- `HanlinYouTubePlayerView`, `HanlinImageGallery`, `HanlinSourceCard` and their data
  types expose the original iOS media components separately. The original request
  buttons, background/disappearance cleanup, source links and preview interactions
  are preserved. `HanlinRichMediaStore.shared` retains its bounded on-demand cache.
- `HanlinA2UIIngress`, `HanlinMediaCatalog`, `HanlinRemoteMediaURL`,
  `HanlinMediaAddressPolicy`, `HanlinYouTubeVideo` and `HanlinYouTubeDocument` expose
  the shared admission, catalog and normalized-media contracts.

Register a result outside `View.body` using the host's existing run/result/call
identity, retain the event sink, and feed complete ordered messages through
`store.receive(_:sequence:for:)`. Render its projection with
`HanlinA2UIProjectedResultView(projection:)` wherever the host needs it. Successful
producer EOF calls `finishRun` and keeps original controls alive under their
existing owner. Cancellation/failure calls `sealRun`; chat teardown calls
`discardAll`. An inline or expanded view does not own teardown and cannot revive a
replaced generation. `HanlinA2UISession` is also public for standalone original
surfaces and complete-graph validation.

The upstream A2UI revision remains
`3ed9601862ecc78027e20ac80ad8b1b98a5d9079`; SwiftSoup retains the app's revision
`bba848db50462894e7fc0891d018dfecad4ef11e` (2.8.7). Media typography comes from
`HanlinPresentationKit`. There are no copied A2UI resource assets. YouTube's
`Bundle.main.bundleIdentifier` deliberately remains the installed host identity,
not a package bundle identifier.

`docs/a2ui/prepare_exact_pin_proof.py` stages the canonical SDK module and actual
app aliases as separate targets. Existing test assertions are retained; the
internal lifecycle-test hook remains `DEBUG` and requires `@testable import
HanlinA2UI`. The Oracle portable proof passed the original eight ingress and seven
media-admission tests through the public module. The 38 original Apple SDK/SwiftUI
cases require the native proof route; a Linux result does not certify those cases.
