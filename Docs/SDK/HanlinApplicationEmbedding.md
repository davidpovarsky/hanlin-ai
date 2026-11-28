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
| `HanlinApplicationPanelView(context:panel:)` | All 16 original management panels: `.models`, `.providers`, `.skills`, `.mcp`, `.runtimes`, `.miniApps`, `.prompts`, `.memory`, `.translations`, `.knowledge`, `.diagnostics`, `.toolPermissions`, `.guide`, `.costs`, `.support`, `.shareInbox` |

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

Use `HanlinSettingsView`, the providers/models panels, or the programmatic
provider/model API below to configure a ready model. `context.createConversation(title:)` uses the same creation implementation
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

## Configure the original engine from host settings

Hosts can configure the original engine without mounting Hanlin settings. The
public context methods write the original `APIKeys` and `AllModels` records; the
original protected credential writer uses this context's scoped Keychain service.
Provider listings contain metadata and storage representation, never secrets.

```swift
let provider = try context.createProvider(.init(
    identifier: "MY_PROVIDER",
    displayName: "My provider",
    endpoint: URL(string: "https://provider.example/v1/chat/completions")!,
    api: .openAI
), credential: hostCredential)
let model = try context.createModel(
    modelID: "provider-model-id", displayName: "My model", provider: provider.id,
    capabilities: .init(tools: true, reasoning: true)
)
let conversationID = try context.createConversation(title: "Host assistant")
let controller = try context.conversationController(conversationID)
let updates = try controller.send(.init(text: "Hello", modelRecordID: model.id))
```

The endpoint is the original full request URL, not an inferred server base URL.
The provider identifier is the original stable routing identity. Use
`providers()` and `models()` for existing definitions; retain the model's record
`id` for requests. `modelID` is its original stored routing name, while
`baseModelID` uses the same suffix-removal helper as the provider engine.
`capabilities`, `identity`, `position` and `isBuiltIn` expose existing model
metadata; setting a capability does not fabricate catalog verification.

`updateProvider`, `updateModel`, `deleteProvider` and `deleteModel` mutate those
same records. Provider metadata updates preserve the exact existing credential
reference. Deletion targets the actual selected model UUID rather than every
row with an equal name. Built-in definitions remain available and can be hidden;
custom provider deletion retains model definitions and historical credential
recovery generations. `setProviderCredential`, `clearProviderCredential` and
explicit `providerCredential` access use the original versioned credential
writer/resolver. Clearing selects an empty current credential; it does not claim
to erase previously retained recovery generations or historical backups.

The original startup and conversation-creation catalog refresh reconciles providers
by their exact `identifier` (`APIKeys.company`), never their editable display names.
Custom routes configured before bootstrap remain the same rows, including a
custom route using a built-in identifier. Renaming a built-in retains its row,
credential reference and name. Explicitly changing its request endpoint or API
dialect transfers that same row to custom ownership, so later catalog refresh
preserves the override. Existing ambiguous legacy routing duplicates are retained;
programmatic access reports `duplicateProvider` instead of choosing or deleting a
credential-bearing row. Custom model metadata is likewise excluded from built-in
catalog metadata refresh. See the [identity correction receipt](HanlinProviderPreloadIdentity20261123.md)
for the focused regression selectors and validation boundary.

The focused native test
`HanlinApplicationEmbeddingTests/programmaticProviderAndModelUseOriginalRowsAndProtectedWriter`
checks provider metadata, protected credential rotation/clear, stable model
UUIDs, original provider-suffixed model naming, capability preservation and
exact-row deletion in the real SwiftData/Keychain implementations.

## Manage original conversations

Use the same original-row mutation writer as the Hanlin list and chat toolbar:

```swift
try context.renameConversation(conversationID, title: "Research notes")
try context.setConversationPinned(conversationID, isPinned: true)
let clearedMessage = try context.clearConversationHistory(conversationID)
try context.deleteConversation(conversationID)
```

Renaming preserves the original title-change information row by default. Set
`announceChange: false` for the original metadata-only behavior. Pinning leaves
the original last-edited ordering metadata intact. The original list appearance
editor uses the same writer for its existing title, icon and color fields.

Clear-history retains the conversation UUID, title, unsent draft, canvas and
independent saved excerpts. Its existing original-store transaction clears
visible and canonical history together and advances the empty revision barrier;
it does not erase an account or physical backups. Deletion removes the exact
original conversation and its existing cascading messages.

Both destructive operations synchronously revoke pending original preparation,
stream ownership, consent and inline tool authority before changing data.
Late old projections cannot insert messages or finalize a newer run. A cached
headless controller is permanently invalidated when its conversation is deleted;
its subsequent send/refresh throws. The public context returns a fresh controller
only for an actual existing original row.

Mutations checkpoint prior pending edits and return genuine save failures.
Their own failed changes are rolled back. The original mounted UI and retained
headless controllers receive a change only after a successful original-store
save. Details and focused native test selectors are in the
[conversation mutation receipt](HanlinConversationMutations20261123.md).

## Construct activity input from host-owned state

`HanlinConversationMessageSnapshot` has a public initializer so a host using
`HanlinAgentCore` or its own persistence can compose the original activity view
without instantiating the full runtime or a hidden conversation view:

```swift
let message = HanlinConversationMessageSnapshot(
    id: actualMessageID, text: observedAnswer, reasoning: observedReasoning,
    toolContent: observedToolResult, toolName: observedToolName
)
HanlinToolActivityView(message: message, isActive: isActualRunActive)
```

Keep the actual message UUID stable across updates. Every original rich DTO and
opaque serialized presentation field is accepted with empty defaults. This
initializer is presentation input only: it does not create a tool receipt, admit
a run, or authorize an action. For original full-runtime consent, pass the live
conversation controller; its matching pending approval remains authoritative.
The native test
`HanlinApplicationEmbeddingTests/hostConstructedActivitySnapshotPreservesIdentityAndOriginalPayloads`
checks identity, encoded image bytes and opaque payload preservation, and compiles
the original activity facade with a host-constructed snapshot.


## Configure original system integrations for the host

HanlinApplicationConfiguration.systemIntegrations selects the host's original
Share Inbox container, notification category and camera intent route. A plain
host configuration leaves these hooks unset; .hanlin preserves the original
App Group, category and Vision URL.

~~~swift
let configuration = HanlinApplicationConfiguration(
    appIdentifier: "com.example.reader",
    systemIntegrations: .init(
        shareAppGroupIdentifier: "group.com.example.reader",
        notificationCategoryIdentifier: "READER_REMINDER",
        visionURL: URL(string: "reader://assistant/camera")
    )
)
~~~

The host must declare its actual App Group entitlement and register its URL
scheme in its own app target. Sharing SDK code does not grant another app's
container access. The original extension-side HanlinShareInboxStore and
HanlinShareInvocation products accept that same host-owned group container;
they retain the existing batch format, content digests and invocation receipts.

HanlinShareInboxView(context:useInChat:) embeds the original list, previews,
MiniApp actions and receipts. It is also available through the .shareInbox
panel. The optional callback receives the actual batch UUID. A host Composer can
call context.prepareSharedDraft(batchID:availableFileSlots:) to obtain the
same verified text/file copies used by Hanlin's Composer. The returned
HanlinSharedDraft exposes text and files. If the user does not accept the
prepared draft, call discardPreparedSharedDraft; do not discard copies after
a sent message has retained their URLs. Preparation never sends a message or
consumes the original source batch. The original full Composer already owns
this lifecycle, so hosts using it do not need a second insertion path.

Bootstrap reads the registered notification categories before adding the SDK
category. Existing categories, actions and intent identifiers survive, including
an existing category using the configured identifier. This uses Apple's original
notification-center API; it does not replace the host's notification delegate or
request permission during bootstrap.

The original OpenVisionIntent opens the configured visionURL and reports a
configuration/open failure instead of reporting success without opening a view.
The full HanlinApplicationScene matches that route. Hosts embedding
HanlinWorkspaceView can use configuration.systemIntegrations.isVisionURL(url)
to select its original vision destination, or present HanlinVisionView within
their own navigation. Intent registration is described in the installation guide.

System integration settings are immutable for the installed original process
owner. A second incompatible profile is rejected before it can redirect a live
Share Inbox or intent. Physical App Group entitlements, OS share-sheet delivery,
notification delivery and camera permission still require their actual signed
host/device acceptance; the focused tests do not manufacture that evidence.

## Manage original MCP services without settings UI

HanlinApplicationContext.mcp exposes the original installed server catalog,
compatibility and runtime status, package preview/install/update/repair,
lifecycle, protected environment writer and per-conversation selection. It
returns request-specific results and uses the same original provider as Hanlin's
settings and chat. See [public MCP administration and selection](HanlinMCPAdministration20261123.md)
for the actual APIs, cancellation and source/native verification boundary.
