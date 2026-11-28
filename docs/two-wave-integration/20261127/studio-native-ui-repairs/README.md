# Studio native UI helper corrections

The original editor and gallery runs on source 1ee9c45796f41893c3b59745864de3412c17ddb4 each executed five UI cases and failed all five. These two source corrections address only two directly observed interaction defects. They do not close the remaining startup, Files-provider or observer-timing failures.

## Alert text replacement

The original editor log records XCTest handling the active New source file alert and pressing Cancel while the helper searched globally for Select All. The shipping prompt contains the real initial value new.ts. Only the existing guarded alert TextField caller now opts into typeKey("a", modifierFlags: .command) before the existing typeText and exact-value assertion. The default editor/menu route remains unchanged. The installed Xcode 27 iOS XCTest header explicitly exposes this keyboard API; actual simulator behavior still requires the original UI gate.

## Returning from the project library

The actual Expo gallery AX tree contains both the background catalog button labelled Developer Studio and the active My Projects navigation bar's BackButton with that label. The broad first-match query selected the background catalog control. The corrected query names the active My Projects navigation bar and its observed BackButton. The following Studio dismissal and installed-app launch assertions are unchanged.

## Preservation and validation boundary

Reversing the four explicit source replacements recovers the complete preimage byte for byte. All 28 test selector functions, Widget additions, exact-value assertions and original deadlines remain. No product, SDK, fixture producer, observer or runner source changed. The independent source review is retained with its exact hash.

No Swift compilation, simulator action or acceptance rerun was performed for this candidate. Native status is NOT_RUN. The original 5+5 failures remain retained in the authorized terminal evidence packet; they are not reclassified as success.
