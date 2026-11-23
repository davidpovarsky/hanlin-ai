# Original compact transcript padding correction

Status: source correction and portable syntax check PASS; native acceptance NOT_RUN.

## Original failure and preserved evidence

Run [45260265662](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45260265662), source `e59256e8325bcdb71c0e683f6b19e7641642aad8`, executed the original three paired methods: 0 PASS / 3 FAIL. Both original shipping products built, shared App Group identity passed, and authenticated 53 foreground plus 159 Host cases were reused without baseline replay.

The original cancellation and private-value methods fail while tapping `hanlin-tool-consent-review-toggle`. Original intermediate accessibility attachments show a real finite button at `{{81.0, -62.7}, {286.0, 26.0}}`, above the transcript viewport `{{0.0, 0.0}, {402.0, 334.0}}`. This is observed in cancellation at 21:42:47.438/21:42:57.732 UTC and return at 21:44:51.798/21:45:00.141/21:45:09.276 UTC. The later cancellation snapshot at21:43:11.394 reports an infinite origin while the pending prompt is being removed; that later state is not evidence that initial layout was nonfinite.

Original SQLite payloads were decoded locally, with no Apple export, simulator, build or test replay. [Original attachments and hashes](../paired-native-45260265662/original-attachments/copy-manifest.json) preserve six teardown attachments and fourteen intermediate consent debug attachment records. PNGs are byte-identical; plain text is the original Zstandard-decoded payload with no text edits. Per-payload, SQLite and original archive hashes are retained. The cancellation and transfer review JPEGs are documented reductions of original PNGs (600px width, ffmpeg q10); cancellation and transfer were visually reviewed. The return PNG is preserved, without claiming an independent visual review.

## Original source correction

`HanlinCompactChatWorkspace` places the anchored composer as a fixed-height sibling of its flexible NavigationStack. It explicitly sets `hanlinExternalCompactComposerHost=true` and `hanlinExternalDockHeight=0` for the original ChatView. The available transcript viewport already excludes the composer.

ChatView's external branch nevertheless clamps `externalDockHeight + 24` to at least225. Its finite bottom scroll target is then225pt high, and the original consent-change auto-follow scrolls to that target. At measured external height0, this consumes201pt beyond the intended24pt transcript clearance.

The sole production change changes that external clamp and nonfinite fallback from225 to24. Existing measured positive external heights still contribute their full height plus24; negative/nonfinite heights preserve finite24pt clearance. The public `externalComposerBottomInset` override remains the first branch, including its finite check and clamp to0. The original standalone `calculateDynamicBottomPadding` implementation is byte-identical. No composer positioning, approval deadline, scroll predicate, test body, test timing or assertion changes.

## Before/after arithmetic and limits

The following is a source-based prediction, not a new native observation. Removing201pt from the original cancellation content height641 yields440, with bottom offset106 instead of307 in the334pt viewport. The private-value content height619 becomes418, offset84 instead of285. Under the same bottom-followed layout, the original review button y=-62.7 becomes138.3; the approval-card y=-73.7 becomes127.3. Native validation must confirm layout/hit testing on the corrected source.

The existing `ClassicChatRestorationTests.dynamicBottomPaddingTracksMeasuredComposerHeight()` calls only the standalone calculator (expected96/152 and attachment fallback>300). Its source is unchanged; it is not a test of this external branch and is not rerun or claimed as new acceptance.

## Affected scope

The two original consent-dependent paired methods and the original chat UI are affected by the changed shared ChatView. The transfer method does not exercise this approval/padding path; its original failure was the missing English completion string. Its original screenshot actually shows the canonical Chinese success translation. Imported saved-state, reopening and rollback assertions after that language assertion remain NOT_RUN, not a proven import failure.

The original three paired methods and all their timeouts remain unchanged. Next native execution requires a frozen reviewed integrated source and the existing strict reuse admission. This commit dispatches no CI.
