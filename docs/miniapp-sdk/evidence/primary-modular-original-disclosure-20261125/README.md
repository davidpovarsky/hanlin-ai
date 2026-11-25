# Modular live text: original disclosure behavior and exact content assertions

## Actual retained failure

Attempt10's actual Modular case completed strict import validation with zero diagnostics, installed the package, searched the live Sefaria source and opened the Genesis result. It then failed the native collection container's isHittable check after15 seconds. The finalized case failed after241.374 seconds. It did not reach the full-text request.

The root agent visually inspected the actual pre-assertion screenshot SHA256 `c257bd61c88b07f48ce42bd81e860948fa89fa5ba6307627a9c6d966007db95f`, paired with accessibility tree SHA256 `8e52aa8ddc62f7c344f656324b6019decada6dc4ad80f22663f0d648a5caa62d`. It shows the populated, visible native detail screen, source data and expanded version rows with Full text buttons. No visible covering sheet appears. This does not by itself prove child hit-testing; the corrected case still requires real hittable controls and successful interactions. The frozen terminal packet receipt is `87672e323f4c8cb463fb56916cd8ecb9547d71bf4eb417c74e082ee57c59c767`.

## Original-library semantics

The exact original ExpoUI58.0.29 DisclosureGroup native props default isExpanded to true. The previous test assumed that its first tap would expand a closed group, both for source versions and returned text versions. The new test observes each exact group's current content state, taps the original control, asserts an actual state transition and leaves that group expanded. It makes no assumption about the initial default.

Original CommonViewModifierProps exposes testID. Button and DisclosureGroup pass through ExpoUIView/UIBaseView's native accessibility identifier mapping. Original Text is registered directly as TextView, whose body applies explicit modifiers instead of that common wrapper. The body therefore uses the original accessibilityIdentifier modifier. No original library, facade, native implementation, expansion state or data flow is modified.

## Product and test changes

The Modular source adds only stable accessibility identifiers through original typed APIs. Source disclosure and load-button identifiers share the source entry ID. Returned disclosure and body identifiers use both the source entry ID and returned version ID, so an expanded sibling cannot supply the assertion's content.

The case locates the actual native CollectionView/Table containing the live source link, requires a hittable original version control, and verifies collapse/reopen through actual content visibility. It presses the selected entry's real load button and waits for a newly returned API version belonging to that same entry. The exact returned body must become visible and hittable, have at least40 characters and6 words, and contain neither the empty-version fallback nor metadata text. Original language metadata, live source reference and full-text screenshot/text attachments remain required. This avoids mistaking the search snippet for the loaded body when their text happens to be identical.

There is no existence-only replacement for interaction. Child hit testing, disclosure transitions, the live full-text request and actual returned text remain pending native execution and will fail the case if unavailable. The existing420-second case allowance and60-second API-response wait remain unchanged.

## Impact and validation

These two files affect the Modular package source and MiniApps UI test bundle. Modular is outside the sealed SDK10 source-input/member/Host/native producer closures; the original paired runner rebuilds its archive through miniapp.mjs against that exact SDK and validates it again on import. The UI test bundle must be rebuilt. No Host or native-framework regeneration is required. The asynchronous parity case is executing independently on its already published source.

Diff checking passed. Original typed API definitions and native registration paths were reviewed and bound below. No new compiler, native pass, source execution or task closure is claimed by this source checkpoint. The next actual package build and UI run supply those results.
