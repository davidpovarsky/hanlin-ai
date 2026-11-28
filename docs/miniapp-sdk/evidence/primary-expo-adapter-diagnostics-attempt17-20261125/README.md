# Actual Expo adapter failures and scoped corrections

This record binds the finalized original MiniApps25 result (16 passed, 9 failed, zero skipped; AI27 not run) to the retained native accessibility trees, screenshots and crash stack. It records proposed corrections, not passing replacement results.

The original ExpoUIView wrapper prevents the old direct named-slot casts from finding generated and manual slots. The public original ViewWrapper accessor is reused without replacing vendor registration or props. This explains the observed GroupBox, Search, Focused editor and initial Presentation content failures.

EditButton had already entered native edit mode: its accessibility label combines Remove with Generated Alpha and exposes the original minus image. The corrected query preserves native delete confirmation and exact deletion effects. Modular search had rendered actual full text but remained in its native pushed detail; the original back control must return to the root before the unchanged close helper.

The Input crash is separate. The raw stack records the installed SwiftUI TextField receiving an unsupported setSelectionAffinity: selector. The same public modifier is now demonstrated in Apple's documented TextEditor context, with a real mounted-editor/value assertion. That context is not yet natively verified, and the original TextField combination is not claimed fixed.

See analysis.json for exact source, original API, official documentation, raw identities and remaining boundaries. Original immutable packets are unchanged.
