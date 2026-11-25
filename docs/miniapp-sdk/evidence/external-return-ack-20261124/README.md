# Accurate private return acknowledgement

The previous private `miniapps.return` route returned `ok: true` even when the existing actual `openSource` callback completed with `false`. Saved completion/cancellation results were already correct and are unchanged.

The receipt now distinguishes `opened`, `failed`, `not-available`, and `in-progress`. `ok` and `opened` are true only for an actual true callback. `requested` describes whether this call invoked the callback. Existing UI callers use the same `@discardableResult` method and the same cleanup bodies.

## Exact evidence boundary

The same strengthened existing XCTest method executed red then green in a Foundation-only projection: selected production methods are extracted verbatim; the original three bridge/store source files are copied unchanged and persist/read actual temporary mailbox files. Red executed one case with four failures, including true versus false for the actual failed callback. Green executed that same one case with zero failures. There is no UIKit, app bootstrap, engine, scene teardown, device or OS-open claim. The complete changed native files also passed syntax-only parsing.

`source-preservation.json` records unchanged completion/cancellation, UI-callback and engine-release method bodies plus both public facades. Source bindings in both portable projects bind every excerpt to the complete source hash and line. The warnings in retained raw logs result from excerpt boundaries omitting preceding discardable-result annotations; full production keeps them. No warnings are suppressed.

The original log bytes, including XCTest trailing spaces and terminal formatting, are retained in gzip members with original hashes. Native execution remains pending for the existing `HanlinMiniAppsTests/CrossAppInvocationTests/testUnavailableCallbackRetainsResultForSourceRecovery` selector. Root owns the focused eleven-case run.
