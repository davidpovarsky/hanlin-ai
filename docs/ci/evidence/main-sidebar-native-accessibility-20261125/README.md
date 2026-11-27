# Main Sidebar native accessibility ownership candidate

## Observed failure and correction

The source86d app built successfully, but its original five Sidebar UI cases
returned one pass and four failures. The closed History Done query still found a
hittable native toolbar item, and Hebrew History still exposed the composer to
the original hittability assertion. Disabled state alone did not resolve either
acceptance condition.

This candidate gives the existing weak editor owner temporary control of its
actual UITextView accessibility flags while History is presented. It records the
prior flags only when first hiding, reasserts them on every attachment update,
and restores them on closing, replacement, matching detach and workspace
disappearance. The existing native editor callback occurs before its IME early
return. Text, selection, focus, interaction state and the editor implementation
are unchanged.

All three History toolbar registrations (Done, Saved messages and New chat) are
conditional on presentation. The existing List/library and separate Profile
inset receive a closed-only semantic gate. The NavigationStack, List, search
bindings, navigation-bar visibility and state remain mounted; the full-page
library retains its default presented behavior.

## Validation and reuse plan

source-closure.json records exact source and original evidence hashes. No native
build, test, simulator creation or Mac source/cache staging has run for this
candidate. Parent and independent chat_ui source reviews found no concrete
lifecycle blocker.

The next focused run must execute nine cases: all five original Sidebar UI
methods unchanged, the original lateEditorDetachPreservesCurrentOwner method,
and the three new ownership regressions. The tests cover prior-flag restoration,
same-editor reassertion, replacement/late-detach isolation and presentation
before an editor is attached.

The five genuine source705 gesture/search unit passes remain source-eligible for
reuse, subject to final input and environment binding. Their entire original
suite remains an identical prefix. The gesture-policy/Pan implementation and
search/model-focus methods/anchor registration are byte-identical across the
full705-to-candidate range. None of these five cases calls the changed editor
lifecycle or new setter. This does not reuse a failed UI result or claim the
nine affected cases have run.

After execution, inspect the whole closed History accessibility region,
including search, title, Profile and rows, plus reopened composer behavior.
Conditional toolbar removal may change closing glyph appearance or title
alignment; inspect the original movies. A passing Done query alone is not proof
of the full semantic or visual contract.

## Public API basis

- [Conditional SwiftUI accessibility](https://developer.apple.com/documentation/swiftui/view/accessibilityhidden(_:isenabled:).md): a disabled modifier leaves the prior semantic state unchanged.
- [Toolbar content builder](https://developer.apple.com/documentation/swiftui/toolbarcontentbuilder): conditional toolbar registration is supported.
- [Native accessibility element flag](https://developer.apple.com/documentation/objectivec/nsobject-swift.class/isaccessibilityelement.md) and [native descendant visibility flag](https://developer.apple.com/documentation/objectivec/nsobject-swift.class/accessibilityelementshidden.md): public MainActor Boolean properties.

These sources establish public API availability and intent. Candidate compiler
acceptance and actual SwiftUI/UIKit semantics remain native execution obligations.
