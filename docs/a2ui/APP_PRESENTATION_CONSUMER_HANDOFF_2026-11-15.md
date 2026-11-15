# Actual app presentation consumer

This source implements the actual `HanlinAppAgentPresentationConsumer` extracted by the SDK
owner at `d1eedf9ed73b4f6c7c64f488caf92494602db865`. The app owner/APIManager source is the
SDK8b hook plus the committed3ba46192603e9d31ff2029cbc684d2f05649c675 read-only restore hook;
these are required joint integration dependencies, not duplicated in this branch.

`ChatView` retains one `HanlinAppAgentSessionOwner` across requests and strongly retains its
observable `HanlinA2UIAppPresentation`. The owner's protocol property remains weak. Before
the existing APIManager request, the original assistant placeholder is inserted in its original
ModelContext and its existing UUID, conversation, scene, legacy UI run and temporary flag are
passed in the actual owner Request. No new row/database/transcript/provider engine is created.

The consumer validates the installed Session, actual canonical run and original row/UI-run pair
before forwarding canonical parts. A canonical run cannot retarget a different row. UI lookup
uses the immutable binding to obtain canonical run/message IDs; neither current run nor prose
is an identity fallback. Observable dictionary/source reads occur in the existing bubble body;
updates occur in protocol callbacks, outside that body. The old canonical-ID environment shortcut
is removed. Inline and expanded views share the same original official SDK Surface owner.

The APIManager's existing typed-text fallback is consumed once into the original bound row,
even if legacy tool presentation previously created another split placeholder. Surface-only
responses count as real rich content, while canonical text is preserved exactly at finalization
and bubble construction. Ordinary unbound Markdown retains its existing trimming/fallback path.

Actual resolved Button actions queue their original key/request/binding. The UI checks that key
again before queueing and after the MCP-scope await, uses the same conversation owner, and starts
the existing request/assistant-row path with `interaction: originalRequest`. Request model name
and capabilities are captured before that await; changed model selection revokes the owner.
Composer draft attachments/prompts are not silently sent with a form submission. No view-side
action directly runs a tool or creates a business effect. Only successfully drained owners may
queue app continuations; cancellation/invalidation revoke immediately.

Read-only history uses a separate bounded adapter without any native Session, preserving the
historical binding/context and leaving the live run budget available. It cannot admit actions.
Replay validates all bindings before publishing, disposes a failed reader, and retains at most
the last64 rich history owners; older history keeps its canonical storage/Markdown fallback.

Opening the original chat also calls `owner.restoreHistory` in a cancellable task, after
installing the strong consumer, without creating an engine or sending a model request. It
captures the original conversation/scene/temporary identity and does not decode a parallel
presentationReference. New request/context cancellation is silent; actual load failure retains
Markdown and reports a generic, nonpersisted unavailable label with finite diagnostics.

## Native proof scope

The new manual `a2ui_app_consumer` selector compiles the real consumer and the exact verbatim
Foundation/SDK-only app protocol file from d1. It archives the actual SDK/Platform sibling tree
from that same SHA and records the contract's source SHA/hash. No owner/store/APIManager stub
or alternate DTO is used. It executes five new app-consumer cases, six affected live/replay SDK
consumer cases on the newer SDK snapshot, and four affected canonical projection controls.
The four projections are affected by the factored registered-identity lookup. All15 passed in
native macOS run43740867685/job132893514622 at ba868c6aa1587c86983c4bf0a40bb1239809049b.
Exact original source blobs (including the d1 contract), SDK trees, unchanged lock, toolchain
and all15 unique Passed xcresult nodes were authenticated. The durable record is
`evidence/app-consumer-43740867685.json`; artifact14172755169 SHA256
`34df084c24b958ed4869fd13e068a44b0f688596c397d195cee92332201fe63c`.
The later ChatView history task changes no tested component input and is not claimed as tested.
The prior29-case3637 callback proof remains separate;
unaffected ownership/pure-validator/media controls are not repeated or relabeled as fresh.

This proof excludes the SwiftData owner implementation and actual ChatView compilation. Those
require the combined enabled application graph and original app XCUITest, including temporary
conversation/modal/scene lifetime, actual placeholder persistence, split/tool row behavior,
submit/new-turn behavior, replay, RTL/AX and physical device. Live provider/business effects and
the forthcoming typed cross-app original-return navigation port also remain OPEN.

## Combined app graph requirements

AI_Hanlin needs the real SDK app owner/store/Host/APIManager+optional ChatRecords field from8b/d1/3ba
in addition to the three SDK package products already linked by integration. Its synchronized
source folder includes these files automatically; do not add duplicate PBX source references.
Link official root package `https://github.com/a2ui-project/a2ui` at exact revision
`3ed9601862ecc78027e20ac80ad8b1b98a5d9079` and its `A2UISwiftCore`, `A2UISwiftUI`, `BasicCatalog`,
`BasicCatalogSwiftUI` products into AI_Hanlin and its direct unit consumer, not MiniApps.
Enable `HANLIN_A2UI_POC` for the actual app/unit validation configuration while preserving DEBUG
and inherited conditions. A flag-disabled or canImport-disabled app build is not this path's
compilation evidence. No automatic workflow trigger or distribution permission is broadened.
