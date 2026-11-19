# V3 exact-text supplement

This is the complete replacement patch against the original source; v3-from-v2.REVIEW.diff contains only the Unicode supplement. V1 and V2 remain unchanged.

Swift String equality treats canonically equivalent composed/decomposed strings as equal. Native UITextView text and NSRange carry a concrete representation. V3 uses UTF-8 elementsEqual for TextState equality, last-synchronized ownership checks, native publication, incoming-model detection and actual native replacement. The metadata trace uses the same exact equality.

The new real UIKit test switches decomposed A (two UTF-16 units) to canonically equal composed B (one unit), verifies exact bytes and cursor clamping, performs the native replacement back to decomposed text, verifies the actual B owner receives it, then applies a composed programmatic replacement. It also asserts A is unchanged and the same view remains first responder. No existing test is changed.

All v2 IME, focus, explicit-write and late-delegate protections remain unchanged. Source persistence ordering still requires the unchanged native A-to-B UI gate; there is no new persistence writer.

Swift grammar and git apply --check results are in receipt.json. Apple execution remains NOT_RUN. Total added cases across V1/V2/V3: 11 across seven methods.
