# TextEditor delivered-props and native edit correction

## Observed failures

The immutable complete case extracts record two real failures on source f33a0d41 and SDK18, while the original 25-case run was still in progress:

- GeneratedModifierHitTestingAndSubmitScope reached the actual native TextView and failed line 853: its value was an empty string rather than the fixture's exact bilingual default, “Affinity example: hello مرحبا”. Case duration: 38.860 seconds.
- ManualInputLayoutAndDataAdapters passed the focus/keyboard prerequisites and typed “alpha” into the actual manual editor, then failed line 540 waiting for the exact React callback label EDITOR_VALUE:alpha. Case duration: 63.805 seconds.

These are complete original case logs, not a finalized suite result. The original captures retain their RUNNING controller observations unchanged. Actual final AX/screenshots and the corrected native rerun remain separate. No success is inferred for the ManualInput correction.

## Original source contract

The retained original Expo58 sources show the relevant lifecycle. SwiftUIViewDefinition.createView creates Props() before constructing the view. UIBaseView stores Content(props: props), and the original virtual view later calls updateRawProps to apply React fields and publish objectWillChange. Hanlin's prior init-only state seed therefore read the empty native defaults before the supplied defaultValue.

The original UIBaseView renders innerView through a normal SwiftUI content boundary. AnyChild returns the child view itself. This review did not establish a direct body bypass or prove that all State properties in Expo views are uninstalled. The original Expo TextField uses its own ObservableState and native binding; Hanlin TextEditor is Hanlin's adapter and does not replace or patch that original component.

## Sole production change

Commit 38785cff47b019f15a6304484b5a979406978a14 changes only Packages/HanlinExpoRuntime/Sources/HanlinExpoRuntime/HanlinExpoUIModule.swift (ccb46dbd… → bd8c397a…).

A private mounted SwiftUI child owns the editor's state. Native defaultValue is optional, matching the existing optional JavaScript input and distinguishing an undelivered default from an explicitly empty one. The first supplied default initializes only once; controlled value takes priority and later controlled updates are observed. Any real user edit closes default initialization, so later defaults cannot reset uncontrolled input. The TextEditor's actual Binding setter emits native edit events directly. Applying incoming React props does not synthesize user events.

Original ExpoUIView registration, native TextEditor, common modifiers, accessibility/placeholder/editability behavior and public JavaScript types remain intact. The fixture source and original two failing UI assertions are unchanged. No vendor file is edited.

## Required verification and impact boundary

Only source inspection, exact byte comparisons and diff whitespace checking were performed in this lane. The candidate requires real consumer compilation and the unchanged affected UI cases, including typed native-to-React feedback and React-to-native reset. It is not yet a native PASS.

The sole modified Swift source is absent from SDK18's actual 235 direct inputs and 94 audited source rows. stage-sdk.mjs does not include this runtime Swift subtree; runtime_host_archive.py adds the Node Host tree, fixed build scripts and runtime network fixtures, not this Swift source. The change affects the compiled consumer module. Existing SDK18 bytes may remain eligible only when the native owner binds the complete actual source/input closure; invoking prepare-runtime-host rewrites provenance before reuse and can itself create a different archive. No SDK input, producer, public typed declaration, fixture or acceptance selector is changed here.
