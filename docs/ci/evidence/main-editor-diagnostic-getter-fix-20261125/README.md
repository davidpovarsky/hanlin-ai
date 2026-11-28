# Main editor diagnostic getter correction

## Observed failure

The original nine-case run on `aa2ead24c5c7378f7d416d67ee7f487f99a8bbeb` finished with four Swift cases passed and all five UI cases failed at the initial Window wait. The original terminal receipt is `14db62166dfe435dcd1556fecad840115c882613552bfd97d6486125f3677347`; collection and owned cleanup completed.

Each of five independently hash-verified, same-device crash reports contains SIGABRT through `doesNotRecognizeSelector` and `HanlinCompactKeyboardOwner.traceEditorAccessibility(_:)` at source line 628. That line reads `editor.isAccessibilityElementBlock`. The record is logged only after this read, explaining why the diagnostic stream supplied no editor records. The reports do not preserve an exact exception selector string, and this run does not establish the older editor-hittability or search-route outcomes.

## Change

Remove the three optional block-presence getter reads and the two optional accessibility-container count reads from the existing diagnostic function. Their observation is explicitly recorded as `not-read`. The two container reads had not been reached before the observed exception; they are unnecessary for comparing immediate and deferred scalar ownership state. No replacement selector probe, setter, block execution, exception wrapper or new native API is added.

All scalar flags, owner/editor/window identities, frames, lifecycle records, sequence limits and diagnostic task behavior remain. The complete source outside this diagnostic function is byte-identical. Production ownership, focus, IME, navigation, bootstrap order, fixtures and original test actions/assertions/timeouts are unchanged.

## Validation and remaining evidence

`git diff --check`, exact source replacement and the outside-function byte comparison passed. An independent source peer reviewed the exact source and patch. No compile, native test, Mac mutation or additional runtime test was performed for this donor.

The corrected app must still build and execute the original affected UI methods. The four authentic Swift passes remain attributed to their actual original source and receipt; any later reuse requires an explicit source qualification. Missing block/count observations remain unknown. The existing offline analyzer algorithm accepts these optional-field omissions, but its fixed source hash must be qualified for the final integrated source before analyzing a new run.

Exact source, patch, raw report, baseline receipt and retained archive hashes are in `qualification.json`.
