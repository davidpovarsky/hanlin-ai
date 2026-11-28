# Shortcuts system UI context correction

The source commit corrects the shared UI-test helpers used by 16 existing Shortcuts cases. It binds creation to the observed system sidebar and action entry to the manual shortcut editor, then accepts only the original action-search labels. The original tests still have to create, configure, save, reopen and run real system Shortcuts and validate their native results.

## Actual failure and bounded change

The retained source5f run started four cases and failed all four. One NativeScript case completed the observed onboarding Continue action but could not reach the dimmed New Shortcut button while the sidebar was expanded. The other created a new shortcut, then typed into the All Shortcuts library search before entering the manual Editor. Its old missing-action diagnostic does not establish an indexing defect. The two Expo cases failed earlier at an observer identity boundary and remain separate.

The correction allows at most one observed Continue and one uniquely owned Hide Sidebar action inside each original 12-second creation allowance. The original 12-second action-search allowance may enter the exact New Shortcut/Editor and open an exact Add Action or Search Actions button. Only one enabled and hittable field matching an original action-search label or placeholder is accepted. The generic library search is excluded. Built-in result-chain opening and search retain their two original phases and limits; the second phase does not repeat navigation.

## Preserved acceptance

All 42 original test method regions, 125 other helper regions and the five changed helpers' later action/configuration/assertion suffixes are byte-exact. Reversing the five substitutions and removing the three private helpers recovers the complete original file. The original wait, tap, case clipping, selectors, command limits, job limits, fixtures and product/observer behavior remain unchanged. The literal Surface dispatch yields 16 affected methods, not every branch of the shared observer switch. The source path is outside the retained 396 SDK input paths; this is membership evidence only.

## Evidence and limits

SOURCE_PROOF.json and independent-root-review.json record source approval. The raw archive retains the original native log, eight own-case AX/screenshots, bounded diagnosis records, exact source replacement material and the stopped first proof-preparation attempt. The latter initially followed every Surface branch; the corrected proof binds each test's actual literal surface. No native or portable test was repeated to package this evidence.

The actual prior run remains four failures. No separately hashed compiled UI input was retained, so source attribution is qualified to the Git source and complete retained overlay. The old action-search labels and Apple's public identifying-property query contract support the source implementation; they do not establish successful navigation on the current simulator. Native compilation and all original affected acceptance remain NOT_RUN on this correction.
