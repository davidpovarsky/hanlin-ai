# Embedding the original Hanlin application

The `HanlinApplication` product contains the original application implementation.
Its implementation module remains `AI_Hanlin`, preserving the SwiftData model
identities and the existing test imports. These entry points call the existing
views and original conversation owner; they do not introduce a new chat UI,
engine, or persistence implementation.

## Choose a surface

| Public entry point | Original implementation |
| --- | --- |
| `HanlinApplicationScene(context:)` | Original application windows and scene/deep-link ownership |
| `HanlinWorkspaceView(context:)` | `MainTabView`, original chat and library workspace |
| `HanlinConversationView(context:conversationID:)` | Original `ChatView` |
| `HanlinSettingsView(context:onDone:)` | Original `SettingsView` and editors |
| `HanlinLibraryView` | Original personal library and exact source-selection routes |
| `HanlinApplicationPanelView(context:panel:)` | Original models, providers, skills, MCP, runtimes, or MiniApps panel |

The independent `HanlinChatUI`, `HanlinPresentationKit`, `HanlinRichUI`,
`HanlinAgentCore`, and platform products remain the entry points for lighter
compositions, including the composer, activity views, rich content and headless
sessions. A host importing a component product does not need to instantiate a
full application context.

## Own one application context

Construct the context once and retain it for all windows/views that share the
original application. The embedding host chooses the namespace and credentials;
the package does not assume Hanlin's application group or CloudKit entitlement.

```swift
import AI_Hanlin
import SwiftUI

@MainActor
func makeReaderContext() throws -> HanlinApplicationContext {
    try HanlinApplicationContext(configuration: .init(
        appIdentifier: "com.example.reader",
        accountIdentifier: "signed-in-account",
        workspaceIdentifier: "personal-library"
    ))
}
```

This creates an isolated Application Support store with CloudKit disabled.
The default provider Keychain service is scoped to the exact app, account and
workspace. A host can supply `HanlinApplicationCredentials` to select its own
service, access group, accessibility and synchronization policy.

The Hanlin executable itself uses `.hanlin`. That explicit configuration retains
its existing SwiftData store, CloudKit/test behavior, conversation namespace,
Keychain group and runtime services. It is not the default for third-party hosts.

The original Node/Python/MCP and scripting implementations are process
singletons, including the scripting platform's model-context binding. Consequently
the full-application product supports **one active original model container and
one native-runtime profile per process**. Reuse the context across views/windows.
A second different container/profile throws during context initialization,
before it can redirect running tools. Multi-account hosts needing simultaneous
independent engines use the independently injectable `HanlinAgentCore` products;
do not switch a running full-application context between accounts. Different
host applications already have separate processes and sandboxes.

## Place the original chat in a host layout

```swift
struct ReaderAssistant: View {
    let context: HanlinApplicationContext
    let conversationID: UUID

    var body: some View {
        NavigationStack {
            HanlinConversationView(
                context: context,
                conversationID: conversationID
            )
        }
    }
}
```

The host controls layout, size, navigation and normal SwiftUI environment/style
modifiers. The view resolves the actual original `ChatRecords` in this context.
Missing or duplicate identifiers display an unavailable state; they never select
a record from another context. The public summary API does not expose mutable
SwiftData rows.

Use `HanlinSettingsView` or the providers/models panels to configure a ready
model. `context.createConversation(title:)` uses the same creation implementation
as Hanlin's workspace: original model selection, the original welcome row and the
existing persistence writer. It throws `noChatModelReady` when the original
policy cannot choose a model. Use `context.conversations()` and
`context.conversation(id)` for public navigation summaries.

When navigating from `HanlinLibraryView`, pass its
`HanlinConversationDestination` directly to
`HanlinConversationView(context:destination:)`. The route retains the original
source digest and selection provenance so source reveal behaves like Hanlin.

All public component views install the original model container and lifecycle.
`View.hanlinApplicationContext(context)` applies the same integration when
arranging additional components. Bootstrap runs once for the context, and
foreground/background handling uses the original runtime lifecycle.

## Supply actual host tools and navigation

Set `configuration.hostServices` to a factory. It receives the **actual original**
`HanlinHostSession` and the original Hanlin host ports. It returns
`HanlinApplicationHostServices` containing the host's existing
`HanlinHostIntegration`, optional capability source and optional interaction
source. The returned integration must implement the provided session context,
including current catalog, schema validation, permissions, cancellation,
original results, and navigation acknowledgements.

Returning the supplied services retains Hanlin's full tool authority. Returning
a different integration selects that integration's catalog; it does not
automatically merge unrelated tool namespaces. The factory receives the original
ports so a host adapter can explicitly compose them without rebuilding the
engine or copying the UI.

The host can also supply `onHostResult`, `onHostProgress`,
`onRunCompletion`, and `onSessionInvalidated` observers. They receive the
original canonical session callbacks after the original app presentation
callbacks. They do not replace those callbacks. Source receipts and host UI
acknowledgements should originate here, rather than from reconstructed tool text.

The original `HanlinAppAgentSessionOwner`, selected provider engine, original
tool-adapter callbacks, SwiftData conversation store, history/revision chain,
consent presentation, rich rendering and cancellation lifetime remain intact.

## Share a host-owned model container

The canonical model list is public without making all original implementation
classes public:

```swift
import SwiftData

let schema = Schema(HanlinApplicationContext.modelTypes + [HostDocument.self])
let container = try ModelContainer(for: schema)
let context = try HanlinApplicationContext(
    configuration: .init(appIdentifier: "com.example.reader"),
    modelContainer: container
)
```

`HostDocument` is the host's own `@Model` type. Choose that container's
configuration, migration and CloudKit policy in the host. A supplied container
must include the original Hanlin schema; initialization rejects an incompatible
container before mounting the UI. The original model module remains
`AI_Hanlin`, so packaging alone does not rename stored entity types.

## Integration verification

The extraction changes module/resource/native-link boundaries. Existing
behavioral test receipts still cover unchanged algorithms, but a native build,
original store reopen, actual host embedding, chat/tool continuation and visual
acceptance must be checked on the integrated package. A Linux syntax parse is
not evidence of SwiftUI rendering, Keychain entitlement or native-runtime
linkage. The focused embedding tests exercise actual credential lookup
isolation and immutable native runtime/container ownership.

## Use the complete original engine without mounting UI

`context.conversationController(id)` returns one retained headless controller for
that conversation. It calls the original `APIManager.sendStreamRequest` and
`HanlinAppAgentSessionOwner`; its SwiftData projection is the **same source**
used by the original `ChatView`.

```swift
let controller = try context.conversationController(conversationID)
let request = HanlinConversationRequest(
    text: "Help me plan this task",
    modelRecordID: selectedModel.id,
    tools: true
)
for try await update in try controller.send(request) {
    switch update {
    case .agentEvent(let event):
        // The original correlated HanlinAgentEvent, including structured parts.
        consumeOriginalAgentEvent(event)
    case .message(let message):
        renderMessageSnapshot(message)
    case .approval(let approval):
        showOriginalConsent(approval)
    case .state(let state):
        updateRunState(state)
    }
}
```

The example callback functions are host-owned UI functions.
`context.models()` supplies stable model record UUIDs. Both the original chat UI
and this controller dispatch by that selected record, so identical model names
from different configured providers cannot silently select the wrong provider.

`HanlinConversationRequest` exposes the existing image/document inputs, URLs,
prompt cards, search, knowledge, tool use, reasoning, audio, planning,
generation limits, system message and image-generation options. Its optional
interaction value is still validated by the original session; constructing a
value never grants action authority.

The controller's observable `state`, `messages`, `pendingApproval`,
`operationalState` and `operationalDescription` can drive a host layout.
Snapshots retain the original resource/calendar/health/code/audio DTOs,
NativeUIBlocks and AgentRun JSON, image representation and rich-presentation
snapshot. The original canonical agent events remain available in the stream.
Call `answerApproval(id:allowed:)` for the actual pending request or `stop()`
to cancel. Cancellation of the consuming task also cancels its admitted run.
Consent uses the original remembered/one-use behavior and original deadlines.

Use one send owner per conversation: the original mounted ChatView or the
headless controller. The two entry points share a per-container/conversation
run lease and reject overlap before inserting request rows. Cancellation or a
late cleanup from an older run cannot revoke the next run's lease. Independent
headless-only hosts do not mount an invisible SwiftUI view.

The shared stream projection preserves the original coalescing, reasoning,
tool activity, sources, calendar and other rich results, split markers,
completion and interruption behavior. Error projection is now saved together
with the failed run status; previously ChatView saved immediately before
changing the row to its visible error text.

## Original Composer and activity in a host layout

The application product also exports the original component owners, without a
second draft store, engine, renderer or consent controller. To place the input
separately, retain one `HanlinConversationPresentation` and mount exactly one
`HanlinConversationTranscriptView(presentation:)` with
`HanlinConversationComposerView(presentation:)`. The existing generation-checked
composer session bridge connects the two to the original `ChatView` state.

```swift
let presentation = try HanlinConversationPresentation(
    context: application, conversationID: conversationID)

// In the host's view hierarchy:
VStack(spacing: 0) {
    HanlinConversationTranscriptView(presentation: presentation)
    HanlinConversationComposerView(presentation: presentation)
}
```

For an overlay, set `presentation.transcriptBottomInset` to the host's chosen
obstruction height; for a separate layout region its default is zero. The host
can pass `availableWorkspaceSize` for the original Composer's expanded panels,
apply normal SwiftUI modifiers and read `composerHeight`, `draft`, `isRunning`
and `isReady`. `send()` and `stop()` use the same original guarded callbacks.
`HanlinConversationComposerView(context:conversationID:)` mounts the original
conversation owner with its Composer alone when no transcript is needed.

For a headless conversation, render `HanlinToolActivityView(message:controller:)`
from the controller's original message snapshots. It uses the exact existing
activity subtree: thinking, rounds, calls, outputs, expansion and animation
ownership. Consent buttons are present only when the supplied controller has
the matching live approval for that message. Stale actions fail closed.

These adapters preserve the original implementation. Native compilation and
visual acceptance must be bound to the integrating source commit; syntax
parsing alone does not establish those results.
