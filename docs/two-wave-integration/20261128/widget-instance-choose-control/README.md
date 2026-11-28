# Widget instance configuration control

## Reviewed source change

Source commit 72429f12aa8ceee9c2eefea23ca7846c067864eb changes one UI helper path, based on integrated430954cd1cab706a7abbbc7b58dfb1cdbf159cfb. The independent root review is copied verbatim into independent-root-source-review.json. Compilation and successful interaction on the new source remain **NOT_RUN**.

The original Recovery run46109371966, attributed to source de7758a9647122e302e996e72f3b9c63776764cc, started one UI case and failed it after195.659 seconds. The build phases passed. Its original failure, “Choose the exact fresh instance created by the MiniApps UI,” remains a failure.

## Actual failure boundary

The case created a real fresh named variant and obtained its READY read-only observer identity. It reached real Home edit, the provider gallery, Add Widget, the placed placeholder and Edit Widget. The broad Choose-or-Widget instance firstMatch query then resolved to a StaticText named Widget instance. The original native log records that text tap at176.71 seconds.

The final own-PID SpringBoard accessibility tree and exact screenshot still show the configuration card. Its parameter Cell contains the Widget instance StaticText and a separate blue Choose Button. The expected named-entity picker UI was not entered. The screenshot was visually inspected; all twelve original selected AX/PNG members were independently SHA/size/CRC checked against their selected-member and central-directory records.

This is evidence of the wrong control selected by the test driver. It does not establish a product entity-query error, a missing variant, whether AppIntents prefetched entities in the background, or the cause of separate remote-element warnings. The final screenshot is a post-failure observation and does not prove button hittability at every earlier instant.

## Narrow correction and preservation

Only placeMatrixWidget's configuration-opening path changes. A dedicated helper retains one original wait(12) followed by one real tap. During that wait it requires exactly one on-screen Cell containing the observed Widget instance label, then exactly one enabled and hittable Choose Button contained within that row and screen. Absent or ambiguous rows or buttons remain false through the original wait. The helper does not fall back to StaticText or a broad firstMatch query.

All42 existing test bodies and451 original assertion lines remain unchanged. The reviewed Home-navigation helper, original tap/wait/bounded helpers, later instance-name selection, host termination, case deadlines and failure/recovery assertions remain exact. Removing the added helper and reversing one call substitution recovers the complete original source file. No wait, retry, poll, timeout extension, coordinate, private API, product or fixture change was added.

The affected original call paths are Recovery, State and VoiceOver. Two related broad-query sites remain unchanged: the Layout test body and observeWidgetFamily, which serves four family cases. They are separate source risks requiring their own actual case evidence; this proof does not diagnose those runs.

The change has zero path intersections with the retained396 SDK and99 Host input sets. This is static source-impact evidence, not a new SDK or Host pass.

## Source provenance and remaining acceptance

The original runner and native-preparation artifact bind source de. The actual complete twenty-path tracked upstream patch changes neither this UI helper nor the Widget configuration intent. Exact de Git configuration-tail and intent bytes match the integrated430 base. All three prepared-source members were checked against their original selected-member and central-directory SHA/size/CRC records.

The artifact does not contain a standalone compiled UI source-file inventory. Git plus the actual tracked overlay therefore provides source attribution; no retained compiled UI-file hash is claimed. The whole parent artifact digest was not independently verified by selective range extraction.

Actual Choose-button interaction, picker presentation, exact fresh-entity selection, native family/render binding, host termination, induced failure, last-good retention and recovery remain obligations of the original native case. No tests, native commands, SDK producers or new downloads ran while preparing or sealing this source proof.

## Proof contents

qualification.json binds the source commit, frozen candidate and independent review. source-validation.json retains the whole-file inverse and original-body/assertion preservation. effective-source-qualification.json and diagnosis.json bind the original outcome and provenance limits. The native and AX excerpts preserve exact retained text with source hashes. source.patch.gz losslessly preserves the reviewed patch. manifest.json enumerates every payload, all verified from the actual proof commit's Git objects.
