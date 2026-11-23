# Hanlin MiniApps client bridge

HanlinMiniAppsBridge is a dependency-free Foundation client. HanlinMiniAppsPicker
adds a native SwiftUI chooser and preferences editor. Neither product embeds a
MiniApp engine, app registry, runtime, or scripting dependencies.

The standalone MiniApps producer projects its existing canonical catalog into
MiniAppCatalogItem and publishes it. Source applications do not independently
register or discover MiniApps.

## Integration

All signed apps join the existing group.com.itorah.shared App Group. Construct
MiniAppBridgeStore() and present MiniAppPicker(store:source:inputs:operation:
callbacks:onOpen:onError:). Capture the original document, revision, selection
(UTF-16 offsets), scene and app-specific locator/metadata before presentation.

The picker saves a request and passes a hanlinminiapps://x-callback-url/run
URL to onOpen. The request UUID identifies both its persisted record and its
MiniApps scene. The source app's registered URL scheme supplies x-success,
x-error and x-cancel callbacks. A URL launch result is not an execution result.

The producer loads request(id:), executes its canonical app/action, then calls
complete(_:). Only after the result is saved should it open
request.callbackURL(for: result).

The source handles its return URL using MiniAppBridgeStore.requestID(from:).
It also drains pendingResults(sourceAppID:) on foreground/cold start. Returned
content is applied through the host's real document/block/annotation transaction.
Persist the request ID with that mutation so repeating a callback after process
death cannot repeat the edit. Call acknowledgeResult(id:sourceAppID:) only after
that native transaction commits. The transport alone cannot atomically commit a
different app's database. Failed mutation leaves the result available for retry.

MiniAppPreferencesView(store:) embeds in an existing NavigationStack and reuses
the exact same favorites/visibility/order/new-window controls as the chooser.
An optional new-window preference defaults to true. The producer honors it when
the platform supports multiple windows, and otherwise uses its current scene.
Creating a window is the producer's responsibility.

Input and result files use importAttachment(at:name:typeIdentifier:) or
writeAttachment(_:name:typeIdentifier:), followed by attachmentURL(id:).
This finishes copying before launch and does not depend on the source sandbox
remaining accessible. No request payload-size, age or queue-count limit is added.

## Persistence and correctness

Per-request records, catalog and preferences are atomically written under
MiniAppsBridge/v1 in the shared container. An interprocess file lock serializes
read-modify-write operations. UUID file identities prevent display filenames from
becoming paths. Existing IDs cannot be silently overwritten by different requests
or results. No automatic deletion expires an outstanding edit.

MiniAppTextEditing provides a small UTF-16 text operation helper. Native hosts
remain responsible for document revision/block identity, native format conversion,
undo and idempotent commit. Read-only library material should produce an annotation
using that application's existing annotation API.

## Verification scope

swift test --package-path Packages/HanlinMiniAppsBridge --jobs 2 executes only
the new portable bridge obligations. See Verification for the authenticated
source fingerprint, raw Swift Testing receipt and exact case count.

Linux compilation does not validate SwiftUI, App Group signing, iPad windows,
cross-app launch, or native editor behavior. Those require the integration owner's
focused Apple-platform checks. Apple research references:

- https://support.apple.com/en-sg/guide/ipad/ipad29729577/ipados
- https://developer.apple.com/documentation/xcode/configuring-app-groups
- https://developer.apple.com/documentation/swiftui/windowgroup
- https://developer.apple.com/documentation/uikit/uiactivityviewcontroller
- https://x-callback-url.com/specification/
