# Home Screen context admission for original widget pilots

## Outcome and scope

Source commit ff625d1ad247877e64715245bd35ebdc9bc68600 changes only AI_HLYUITests/HanlinEntrypointSystemSurfaceUITests.swift, from base 3634078f89c5fa469199da1f69d6f4bad6686d96. Independent root and Mac reviews approve the source correction. Compilation, positive Home-page navigation and the affected original native cases remain **NOT_RUN** for this candidate.

The existing Matrix placement and Home-family gallery helpers now obtain the MiniApps icon through one shared Home-context query. It admits the observed Home icon container and a visible, valid Page control; it excludes the App Library and ambiguous icon matches. This corrects the specific context-selection error supported by two original failed cases. It does not establish Recovery's cause or claim an accepted placement.

## Original failure evidence

State run 46109331496 and VoiceOver run 46109228743, both at source de7758a9647122e302e996e72f3b9c63776764cc, passed their recorded build phases and created independently named real Matrix variants with READY observer identities. Each started one UI method and failed with “Open the real Home Screen edit mode.” Both original failures remain failed.

The original gesture streams contain a Home press, left swipe, 1.2-second press on MiniApps, and Options. Their own-PID final SpringBoard AX trees and exact screenshots show App Library. Its visible MiniApps icon is inside the Other category, and the context menu offers Delete App. The retained Page control is off-screen and reads Page 3 of 2. The earlier icon search did not distinguish this App Library icon from a Home-page icon.

actual-case-evidence.json identifies the original complete log hashes, selected attachment SHA/CRC records, source/product identities, variant identities and prepared-source patch hashes. actual-home-context-readback.json retains bounded exact AX excerpts and their interpretation. Both screenshots were visually inspected. The full original evidence remains in the referenced immutable handoff; no HTTP response, archive or original failure was rewritten. The referenced selected members are qualified, while the whole parent ZIP was not downloaded or independently hashed.

These are final-context observations. The final AX dump does not recover search-field hittability at every preceding gesture. The new frame/range checks reject the observed Page control independently. Separately reported remote-element and animation-idleness warnings are retained without assigning them a cause.

## Source preservation

The shared helper retains the original maximum five search observations and uses at most four public navigation swipes between them. It adds no wait, poll, retry, private API or coordinate. It navigates away from a visible App Library, checks actual Home-page identity and bounds, visits earlier pages before advancing, and does not swipe left beyond the observed final Home page.

Both original icon-absence assertions remain. The original long press, Options handling, 12-second Edit Home Screen wait, case ceilings, gallery/configuration steps, named instance binding, host termination, native checks, state/control/speech assertions, cleanup and orientation restoration remain unchanged. No icon is moved, removed, installed or substituted.

Removing the new helper and reversing two selection substitutions recovers the whole original file. All 38 base test bodies, 401 original assertion lines and 114 unaffected helper blocks are preserved. Read-only composition with root fcedca4d091a3e11d26ef7526764b8d7eae0f3e0 preserves all 42 current test bodies, including the four later native List cases. The root worktree and index were not modified for that composition.

The affected original call paths are Recovery, State, VoiceOver, Layout and the four Home-family cases. Generic system-widget cases use a separate unchanged helper. The source change intersects zero of the retained 396 SDK and zero of the 99 Host input paths; this is a static source-impact finding, not new SDK or native acceptance.

## Remaining native obligations

No successful Home-page AX/placement sample is present in the reviewed packet. The observed English Page-value format and positive Home hierarchy must be admitted by an actual original run. Missing, changed or ambiguous hierarchy fails under the existing limits. The observed AX identifiers are queried through public XCTest; they are not represented as documented stable platform APIs.

Original compilation, navigation, provider selection, placement, state isolation, WidgetKit actions and target VoiceOver speech still require native verification. This proof claims no portable test, product, full-CI or SDK pass. Official navigation references in apple-navigation-authorities.json support only page navigation and the position of App Library beyond the last Home page.

## Retained review and patch

independent-mac-source-review.json and independent-root-source-review.json are copied byte-for-byte from the approved review receipts. source.patch.gz losslessly preserves the reviewed patch. source-validation.json, source-binding.json, input-impact.json and current-root-composition.json retain the exact preservation and scope checks. The manifest enumerates every payload in this proof; the proof commit is separate from the source commit.
