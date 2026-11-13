# Owned Share ingress checkpoint

[נועם | DEV] [MAIN_SESSION]. INT-04 remains open.

The Share extension previously persisted borrowed provider URLs in a mutable
share-inbox.json array. The Host defined an unused reader and a whole-inbox
clear operation. Provider temporary files can disappear as soon as their
completion handler returns, and concurrent appenders could overwrite a batch.

The existing HanlinScriptStore product now owns ShareInbox/Staging and Batches
inside the original App Group. Each extension instance gets a UUID transaction.
The shared HanlinShareItemLoader copies file bytes *inside* the provider callback,
with no-follow regular-file descriptors, streaming SHA256/size and protected
exclusive output files. Text/URL, item order, UTI, original name and per-item
typed errors are retained. No provider URL is persisted for an attachment.
All items publish together by same-volume directory rename; there is no shared
read/append/write index to lose concurrent submissions. Rejected/corrupt batches
cannot starve healthy batches. Reads verify filename identity and file digests;
unpublished staging is not visible. Original historical share-inbox.json data
is retained, never cleared wholesale or silently reinterpreted as owned files.

The extension links the existing lean ScriptStore product (Foundation/CryptoKit
and existing contract dependencies), without ScriptUI, ChatCore, Node, Hermes or
NativeScript. It reports saved-versus-not-executed, with Done and in-flight
cancellation. Cancellation removes only that unpublished transaction; process
loss can leave an unpublished orphan for future explicit maintenance. The Host
now reads these actual batches through Shared Items in its package screen,
previews verified owned files through Quick Look, and preserves historical
records. This is ingress review, not installed-action routing or execution.

Five focused production tests cover large Unicode files after provider deletion,
whole-batch publication,24 simultaneous writers, historical data preservation,
abort, corrupt/symlink isolation, path/byte tampering, and actual NSItemProvider
file/text/URL/error loading. Syntax parse passed on Windows; actual macOS package
execution, iOS extension/application compilation and physical device evidence
are still required. Apple SDK lookup43403995138 succeeded; it is declaration
evidence, not compilation or executed ingress tests.

Apple documents the temporary-file lifetime explicitly:
https://developer.apple.com/documentation/foundation/nsitemprovider/loadfilerepresentation%28fortypeidentifier%3Acompletionhandler%3A%29 .
String/URL loading uses the current loadObject bridge instead of the loadItem
API deprecated in iOS27. Published minimum versions are unchanged.

Still required: chooser/default selection bound to installed package/generation/
entrypoint/action, delivery through the existing INT-02 queue, TTL and per-item
execution acknowledgment, NS/Expo action parity, outgoing system share semantics,
physical iPad/iPhone multi-image/PDF/large-file/cancel/offline/cold-Host matrix and
actual signed App Group entitlements. No extension/runtime matrix cell is marked
verified by this checkpoint. Immutable ingress intentionally has no automatic
expiry/deletion policy until delivery references and user cancellation are bound.
