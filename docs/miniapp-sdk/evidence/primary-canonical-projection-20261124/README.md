# Installed package canonical exposure and action identity correction

This is a focused regression on the primary Mac using the actual failed attempt 7 simulator registry. It does not claim application UI acceptance or completion of the original 52 cases.

## Production corrections

The installed Expo SwiftUI Probe A entry has five package entrypoints: app, three distinct App Intents, and widget. The three intents have identical canonical handler/runtime/context sets; one serialized context array is reversed. The old projection produced three appIntentBridge descriptors, causing existing duplicate-kind validation to reject the package and catalog discovery to omit it.

The correction sorts supported context sets, then retains the first occurrence of each fully identical canonical descriptor. Different handler/runtime/context records remain distinct and still fail existing duplicate-kind validation. Original package entrypoints, IDs, exported symbols, actions, and manifest metadata are retained.

After projection was corrected, the regression exposed a second existing defect: HanlinActionID's generic lowercase-only validator silently dropped all three camelCase action IDs. The original Expo acceptance test already requires these exact names. Only HanlinActionID now accepts uppercase ASCII letters; exact spelling survives Codable and runtime dispatch. Other identifier kinds and all existing ASCII, length, separator, and boundary rules remain unchanged.

## Actual execution

The proof copied all 47 original source/resource files in HanlinPlatformContracts, HanlinMiniAppCore, HanlinScriptContracts, and HanlinScriptStore, with original dependencies and one focused store test suite. The actual Mac app checkout remained fd81d602d3b25f09162a659e1e0cf0582e91a93a.

| Version | Observed result | UTC finish | Elapsed |
| --- | --- | --- | --- |
| Original | Stored-package positive failed with duplicateEntryPoint; three conflict cases passed | 2026-11-24 23:12:17.511 | 28.575 s including compile |
| Projection correction only | Canonical descriptor succeeds; positive exposes empty actions; three conflict cases passed | 2026-11-24 23:13:08.016 | 3.005 s |
| Projection and action identity corrections | 3 tests passed, including 3 conflict parameter cases; zero issues | 2026-11-24 23:18:32.334 | 5.816 s |

The first collector searched for a Swift function name, but Swift Testing printed its display title. Its original error/state/runner and raw baseline are preserved. The actual duplicateEntryPoint diagnostic and three passing conflict cases were verified directly, and baseline tests were not repeated. Each continuation has its own retained runner and events.

Final regression verifies exact stored entries/symbols, canonical order, all three action IDs/handlers, and foreground/intent/widget exposure. It separately checks action Codable/case identity, unchanged app/package/capability rejection, malformed action IDs, and conflicts differing in handler/runtime/contexts.

## Bindings and limits

The original simulator registry is installed-catalog.raw.json, SHA-256 66fea131922d3106c90b0341c4fff02f86de0c06932be22bb21db6d1e0c5fea8. The inline test fixture semantically equals its install-script-ec17057f5a2c82aaed6ab6ca entry.

proof/final-source-binding.json lists all 47 final inputs and the only two production changes. proof/transfer-receipt.json binds 23 raw members. proof/state.json binds all three commands and their exact logs. Both earlier product failures and the collector mismatch remain retained.

Attempt 7 separately built both products successfully, but original runtimes timed out before finalizing xcresult. The raw log's 25 terminal case events (9 passes, 16 failures) are not finalized acceptance. The other six import/render failures and finalization issue require separate work. Original acceptance scope remains 25 MiniApps plus 27 AI cases.
