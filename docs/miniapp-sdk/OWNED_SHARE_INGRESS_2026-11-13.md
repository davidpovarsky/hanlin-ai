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

Six focused production tests cover large Unicode files after provider deletion,
whole-batch publication,24 simultaneous writers, historical data preservation,
abort, corrupt/symlink isolation, path/byte tampering, and actual NSItemProvider
file/text/URL/error loading. Syntax parse passed on Windows; actual macOS package
execution, iOS extension/application compilation and physical device evidence
are still required. Apple SDK lookup43403995138 succeeded; it is declaration
evidence, not compilation or executed ingress tests.

First native run43404507991 at7e43ba76 compiled the actual sources on
Xcode27.2/27B52 Swift6.4.2 and executed5 methods:3 PASS,2 FAIL in0.056s.
The real NSItemProvider file/text/URL/error case passed0.056s, as did abort/
corrupt isolation and path/byte tampering. Reopen and24-writer cases exposed
FileManager.createDirectory's existing-directory error. Initialization now
tolerates only that exact error, then requires the existing path to be a real
non-symlink directory. A sixth regression rejects existing files/symlinks.
All6 affected methods require another execution. Downloaded artifact14026413368
(3712B), GitHub SHA256
bbea3a87b1dd60f3a811dd7cf596eb88bdf42910ee3e3dfb29f8a58c950637f6.
One additional iOS app method exercises the actual App Group provider batch
through ChavrusaShareInbox.shared after source deletion; it is not a physical
Share sheet, signed entitlement or action dispatch acceptance test.

Corrected run43405370019 at5b04ee5f executed6/6 PASS in0.073s on
Xcode27.2/27B52 Swift6.4.2 arm64macOS27.0; job2m34s. Actual provider
case0.073s,24-writer case0.035s, reopen/Unicode file case0.032s. Downloaded
artifact14027341379 (3242B), GitHub SHA256
0127bf3000d10c949605de61dfb51e88702518a9cf5452ab911334adff018042.
This is actual macOS Foundation/provider execution. The iOS App Group method,
Share extension linking/Host UI, delivery and physical gates remain separate.

Delivery foundation follow-up: HanlinShareInvocation now builds a deterministic
ResumeQueue command using the immutable batch UUID, installed identity/generation,
entrypoint and action. The envelope contains only a batch reference, so full
text/large attachments do not consume the256KiB queue budget. After target
validation, payload resolution reads the original text/order/errors and verifies
each owned file before handing its URI/size/SHA to the action. The existing
receipt/executor retains actual return values, TTL and cancellation. Three new
production tests exercise large input/actual result/reopen/dedup/target changes,
tampering and expired/cancelled refusal. These tests and the affected queue/store
tests still require native execution. Host chooser/dispatch linkage remains to
be implemented; this factory alone is not an end-to-end Share action route.

First delivery attempt43409282098/d29d1455 failed compilation before any
selected case ran: dynamic object construction used a Swift Dictionary where
the canonical HanlinValue requires HanlinObject. The builder now uses the
existing exact-UTF8-key HanlinObject type directly, preserving its canonical
contract. Artifact14028427998/4904B, GitHub SHA256
f50e8045878193fa8205fff277966b31f9a11df455830fba25a55daa75dacb0f.
All23 selected affected queue/store/delivery cases still require execution;
zero passes are credited to the compile failure.

Corrected43409794095/ed3b05ea executed23/23 PASS in two focused invocations:
6 owned ingress/provider cases0.171s and17 queue/delivery cases1.201s (14 queue,
3 new Share receipt methods), Xcode27.2/27B52 Swift6.4.2; job4m25s. Full large
input, file hash, actual return value, reopen/dedup, target change rejection,
TTL/cancel, unstarted admission and fenced lease cases passed. Downloaded
artifact14029067721 (4236B), GitHub SHA256
8fb1972773c164ad7a2b1030c0aa565a52f0c4427ab853f03f4e35bdda01b411.

App run43407005634/302e4f38 also executed the actual NSItemProvider→App Group→
ChavrusaShareInbox.shared readback case PASS0.150s on arm64 iPad mini(A20Pro)
iOS27.2/24B8117. It compiled the Share extension and Host review UI. Overall run
FAILED an unrelated NS metadata/facade case (5/6 units PASS); no Share sheet UI,
installed-action routing, signed entitlement or physical acceptance is inferred.
Authenticated artifact14029126824/29313160B SHA256
23d66bb2a34846d8e030cf4a181fec10559d0aad4a413ddf0cacd334cc3af056.

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

## Host selection and delivery implementation (not yet executed)

The Host Shared Items screen now offers a native Menu of enabled installed
NativeScript actions whose declared inter-app.share handler equals an actual
app entrypoint. Selection binds installed ID, generation, app ID, entrypoint and
action to the original batch UUID. No Expo or undeclared action is offered.
The existing durable queue carries only the batch reference; dispatch restores
installed state before validating target/generation, then resolves and verifies
the immutable owned content. The screen reads actual queued/running/terminal
receipts and returned values, supports cancellation, and never clears a batch.

Share actions wait for the foreground NS VM to close. Other-package NS commands
also stay unstarted instead of spending an attempt or publishing a false terminal
failure. Headless admission is reserved before async file/container lookups;
foreground launch cannot create a second VM while headless work owns admission.
Generation is checked again after container resolution before starting user code.
The installed Host broker route remains authoritative: session registration no
longer replaces it with a stale session closure. One VM/active-session guards stay.
This does not yet solve every foreground-action teardown/cancellation boundary.

A new serialized actual-NS integration case imports/installs a unique package,
loads actual provider text into the App Group, selects the production target,
asserts queued/zero-attempt while foreground owns the VM, closes it, and requires
actual registered JS action receipts for all five engines across two sessions.
It checks full Unicode input, durable reopen, duplicate/no second execution, and
stale selection rejection after disabling the target. This is NOT_RUN until the
native workflow executes it; no system share-sheet/Menu activation, signed-device,
Expo parity or physical matrix pass is inferred from source or syntax checks.
