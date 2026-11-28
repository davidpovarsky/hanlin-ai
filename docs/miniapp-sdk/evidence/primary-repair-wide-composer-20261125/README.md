# Wide-layout repair handoff: actual failure and source correction

## Observed baseline

The separate AI27 diagnostic used actual source `f33a0d41f6367b01d63bdb5fcba8bbc5fa474b51` and SDK18. It ended on 2026-11-25 at 10:19:30.869009 UTC with 21 executed tests: 19 passed, 2 failed and 0 skipped. Six explicitly selected Swift Testing methods were absent and the unchanged coverage verifier rejected the run. This is not a complete AI27 or original52 pass.

The retained repair UI test `testTypeErrorRepairsThroughOriginalAgentBuildAndCompanionImport` failed at its unchanged line79 assertion: “The original composer must persist the repair request.” Earlier steps perform a genuine TS2322 import diagnostic and the repair handoff; later tool/build/install/native42 assertions were not reached.

The selected accessibility attachment shows the created and selected `MiniApp · MiniAppTypeError.hanlinNativeScript` conversation, the existing `hanlin-chat-transcript`, and the diagnostic label `hanlin-phase2-request-count` with value `0`. Its chat-ID label is `E14A6418-9222-4F96-9B63-891B0656594E`. This is the exact observed label, not a substituted successful-install receipt. The root reviewer inspected the corresponding original screenshot and accessibility tree; this evidence lane independently verified their retained bytes and read the accessibility tree.

## Source-backed cause

The baseline ChatView only registered, updated and unregistered a live composer endpoint when `isExternalCompactComposerHost` was true. Its inline/wide path restored or snapshotted drafts without registering an active endpoint.

The original `HanlinActiveComposerSessionBridge` first-turn state machine requires an active endpoint matching the pending target, ready to send and not already responding. It therefore cannot dispatch a newly created wide-layout repair conversation whose view only snapshots its draft. ListView already injects that same bridge and sets the selected conversation and expected session in its repair route; a second transport or composer is unnecessary.

Relevant original source locations:

- `AI_HLY/ChatView.swift`: endpoint construction337–390 and baseline sync/onAppear/onDisappear branches.
- `AI_HLY/Downstream/ChatInput/OrganizerDock/HanlinComposerSessionBridge.swift`: restore249–284, register286–294, update296–309, unregister311–327, imported first turn487–505, dispatch559–638.
- `AI_HLY/ListView.swift`: repair routing114–126; bridge injection257.
- `AI_HLYUITests/MiniAppAuthoringUITests.swift`: unchanged diagnostic/handoff/assertion45–80 and later native42/installed-receipt checks82–112.

## Reviewed correction, not yet executed

Author commit `b1029dfb868fa690720ea8690c8a740f031bb827` changes only `AI_HLY/ChatView.swift`, SHA256 `d21659cdaa7d3e6141d4677d10ccaee067e7238ba8c4ccc2f689b63db4c41ffe`. The three changes use the existing endpoint update/register/unregister lifecycle for both mounted inline/wide and external/compact composers.

The bridge's registration still restores cached draft state, snapshots it, and attempts the guarded pending dispatch. Update/unregister still require matching session and registration token. Imported first turns preserve the Home draft and existing conversation settings; dispatch records its token before invoking the original send callback and retains at-most-once completion tracking. ChatView loads the existing history/model state before registering. Inline rendering, compact navigation/dock logic, temporary-chat layout protection, and all UI assertions remain unchanged.

Independent read-only source review: CLEAR for that exact candidate. No compiler, generator, Mac query or test was run by this evidence lane. Corrected native execution is **NOT_RUN** in this packet. The final repair still requires the real original composer/tool/build/import/native42 and installed-identity proof.

## Retention boundary

Only the selected failure screenshot, accessibility tree and finalized summary are copied byte-for-byte from producer packet `ai27-terminal-packet-attempt18/receipt.json`, SHA256 `4de255af777d3cdaedbae706651c13bf16af748f175d63dc7db19c81f1f28baa`. The complete 120-member packet is retained separately and is not duplicated or claimed fully reviewed here.

`selected-producer-members.json` preserves each selected original path, byte hash, mode and nanosecond timestamp. Git preserves file bytes and executable mode, not those original nanosecond timestamps. `source-change.patch` is the exact full-index Git diff from f33 to b102; `source-bindings.json` binds the original and candidate source bytes. These evidence-only files live outside SDK source inputs and do not change the application or acceptance criteria.
