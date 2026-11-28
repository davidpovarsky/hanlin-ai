# Original Motion B fails; C passes native and visual review

Source: `9575dd15e816009e11d84ab7f4e21b45cb67c5e8`.
[Original affected B+C run45248270552](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45248270552) executed after the reviewed row grouping and startup-only readiness fix. No Motion component, preset timing, gesture, geometry assertion or native test deadline changed in this continuation.

## Actual results

| Scope | Status | Evidence |
|---|---|---|
| Owned fresh simulator readiness | PASS | Native bootstatus success after279.588s inside300s admission budget; no recovery. |
| Original selected SDK build | PASS | Original build log ends `TEST BUILD SUCCEEDED`; exact source/resolved/macro gates passed. |
| B rapid reversal | FAIL | Original line160 assertion after35.087904s. All3 callbacks arrived65.2/22.0ms apart, but each captured pre-action height was0 points. |
| B checks after that assertion | NOT_RUN | Raw-height assertion, preset switching, nested state/count, drag cancellation and scrolling, persistence, invalid-preset fallback and actual system Reduce Motion scenario. |
| C native | PASS | Original case passed in40.883938s on the changed row. |
| C visual | PASS, component proof scope | All4 original screenshots inspected; full-screen landscape confirms complete actual bounds. |
| A | NOT_RUN on corrected row | Earlier original acceptance remains unresolved. |
| D | DIAGNOSTIC_CAPTURED previously | Original12 observations are reused as diagnostics; no D replay or B acceptance claim. |

Native job137950733725 ran19:26:11–19:50:21UTC (1450s), within its unchanged25-minute budget. The original measured phases were preflight428s, resolve481s, build237s, tests241s, results10s. This was an assertion failure, not an infrastructure timeout. The helper records actual `/Applications/Xcode_27.2.app/Contents/Developer` and its simctl executable.

## Source-bound original artifacts

Native artifact14857540016 is72,372,184 bytes, SHA256 `d1e641e3e41043a8e247506a8110502847afe7c1bc1dafe20e8f2ca64ed6c3d7`. API digest/size and ZIP CRC passed. The raw xcresult is finalized, readable and archived, SHA256 `ba13acffc450ae3fe73e33b81485c50b979e18c12bc72f3e1cc48fe220e7ad51`. The full selected source closure and all52 original artifact member hashes are retained in the copied receipts. No aggregate result-validator PASS exists after the original test exit65.

[Read-only original-result inspection45258652803](https://github.com/davidpovarsky/hanlin-ai/actions/runs/45258652803) exported the two original cases without simulator launch, build or test replay. Its artifact14859038574 is11,943,872 bytes, SHA256 `d96488e2437a1cc08916e15ae5026dc131c148a2b528f19903f6fc5c5f5e588e`; all19 members, size/digest and ZIP CRC were verified. Original activity JSON, receipts, synthesized event records and C PNGs are preserved unchanged under `inspection/original`. Full original binaries remain in verified GitHub artifacts and the Oracle build directories.

## B review and unresolved cause

The baseline is authentic: two warm-up callbacks, expanded=false and geometry=collapsed. The rapid receipt captures actions=5, expanded=true, natural=100, visible=0, actionVisible=0/106/0/0/0 and no intermediate later callback. Its separately queried geometry label is expanded by the time the attachment is written; that does not alter the recorded callback-time heights.

Original video frame388 at mediaPTS29.066667 shows `v1.relaxed`, “Smooth and relaxed”, and `shimmer=true;numeric=true`. The failure did not use No Animations or effective Reduce Motion. This is not execution of the later system Reduce Motion acceptance step, which remained NOT_RUN.

All encoded frames405–424 were reviewed in sequence. Frame408 shows actions3/collapsed, frame409 actions3/transitioning, and frame410 actions5/collapsed, with no visible summary. Frame412 already shows actions5/transitioning with no visible summary. The first clipped summary visible in this reviewed sequence appears at frame416, mediaPTS30.250000; frame424 shows summary plus the nested header and displaced footer. Exact frame timestamps and derived contact sheets are retained. No exact XCTest wall-clock/media-clock alignment or guarantee about unsampled VFR frames is claimed.

The row grouping correction alone did not resolve B. These observations are consistent with delayed mounting/layout before a visible reveal, but do not prove the cause. The root agent owns the source geometry/transaction review; no product fix, weakened predicate, longer tap gap or extra native run is claimed by this evidence.

## C visual review

The original portrait long-content/RTL/type image is readable. The app-boundary landscape attachment contains the known rotated/cropped region and black strip, so it is not sufficient alone. The separately retained full-screen original shows the complete actual landscape UI and text within screen bounds after orientation is normalized only for viewing. The completed portrait returns to collapsed with shimmer=false and the original following footer visible. The full-resolution PNG bytes are unchanged.

This acceptance is for the original Motion proof using the real SDK components. It does not establish full-product Composer, chat integration, source citation placement or the remaining B scenarios.
