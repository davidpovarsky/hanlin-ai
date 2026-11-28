# Anytype canonical SDK native readback — 23 November 2026

## Actual outcome

[Original run 45135961459](https://github.com/davidpovarsky/anytype-swift/actions/runs/45135961459), attempt 1, built the actual Anytype app from `fa078feb6bd496689b812ccf00945dce60c03599` with the canonical eight-product SDK profile pinned to `d49a4fd4115b8335105d2991bf74ab4d7f6aad2d`. The run finished **FAILURE**. The app build and native preparation passed; the original UI test failed at its unchanged background-transition assertion. This is partial integration evidence, not completed native or UI acceptance.

| Original gate | Result | Evidence |
| --- | --- | --- |
| Exact macro source and fingerprint | PASS | Equatable `597c2bb34af0c51331eb3b5e705f942d8ee20daa`; normal Xcode macro validation retained |
| Existing qualified runtime | Reused | Original producer `45091223011`; no runtime rebuild |
| Native controller controls | Retained | 69 admitted existing methods; zero rerun during this lane |
| Actual app build | PASS | Original execution receipt records `native_build_succeeded=true` |
| `prepareRealHostFixture()` | 1 PASS, 0 failures | Original SQLite: 23.124465942382812 seconds |
| `testRealNativeConsentCreatePageAndAuthorityRevocation()` | 1 FAIL, 0 skipped | Original SQLite: 80.0776070356369 seconds |
| Actual UI live-runtime binding | FAIL closed | Final source/process binding did not complete; no substitute app launch |

The device was the original iPad Pro 13-inch (M5), arm64 Simulator, iOS 27.0 build 24A434. The selected SDK manifest in the captured installation is SHA256 `518f91d40d3433a88ab6255c252bc2c81fa1e2199dad0322b4136bb7f2d6f20c`. The artifact contains the actual SDK snapshot and exact host source inputs. The JSON receipt records their hashes and the checked immutable Git files.

## Failure diagnosis

The unchanged UI case pressed Home at 09:28:58.873 UTC. XCTest reported the synthesized action complete at 09:28:59.365, then waited ten seconds for the app to enter the background. The compressed original XCTest session log explicitly records at 09:29:09.381 that the current state was **Running Foreground**. The assertion in `HanlinNativeAcceptanceUITests.swift:211` therefore failed before `app.activate()` or the later authority checks could run.

XCTest did not observe the required background state within its existing wait. A subsequent exact-last-frame readback does show SpringBoard, so delayed transition versus stale XCTest state remains unresolved. The encoded frame timestamps have not been assumed to map linearly to recording request acknowledgements. No test-side activation or termination occurs between Home and the assertion; the native driver awaits real scene events, and the runtime observer records zero extra launches. There is no code-proven shared SDK crash to repair from this assertion.

A later `vmmap` at 09:29:22.999 reports the app as a corpse. This occurs after the failed assertion and the test Tear Down activity, so it does not prove that an app crash caused the Home failure. All 548 Zstandard blobs in the captured UI xcresult were decoded read-only within bounded memory. The captured JSON crash diagnostics concern 18 `intelligencetasksd` and two `AppIntentsLiveEntityService` incidents; no Anytype crash report was found in those captured blobs. Embedded binary message strings were not interpreted as crash events.

The separate original live-runtime observer did not accept the actual UI process. Installed-source mapping took 28.080 seconds and process mapping 16.650 seconds before its existing 45-second final-binding deadline was exhausted. Its partial mapping and late corpse remain diagnostic evidence only. No process-binding guard, timeout, selector or artifact rule was relaxed.

## What the run and visuals establish

The native receipt reached `READY_FOR_BACKGROUND` with twelve checks true: unconfigured provider and disabled middleware logging; denial before consent; real native context read after consent; Cancel prevents creation; Confirm creates the exact page; journal-ID readback; replay produces no duplicate; the cancelled title is absent; return mounts the original document; the closed presentation denies read/create; and the second presentation initially has live read access.

All five original screenshots were reviewed on Oracle at their original resolution. They show the actual native Cancel and Confirm prompts, exact original document return, and the next SDK presentation before Home. The first two reviewed original-resolution frames from the original 70.315-second video show the SDK session form and then the underlying document after the sheet disappears. A subsequent exact frame-index extraction (frame 673 of 674, PTS 69.940 seconds) shows SpringBoard/Home. This adds evidence beyond the initial two-frame review; it does not establish process survival or satisfy the failed background-state assertion. XCTest acknowledged recording start at 09:27:51.629 and stop at 09:29:10.333; those control acknowledgements alone do not supply an exact per-frame wall clock. All screenshot, video and frame hashes are in the companion JSON.

The later background/foreground, pending-consent departure, fresh-session, permission, workspace and logout checks did not execute. The provider was intentionally unconfigured. These images do not establish live-provider chat, typed Composer acceptance or pixel-level parity.

## Evidence and next dependency

The authenticated original artifact is `14804841664`, `Pinkha-UI27-hanlin-native-45135961459-1`, 50,398,716 bytes, SHA256 `738ac36ffbed82377ec625f8febf452cf407a7dc172da3e058c0d3a3689e34fe`. Outer and inner ZIP CRC checks passed. Its 1,438 files were extracted once (71,101,847 bytes), preserving the original archive. The decoded XCTest session SHA256 is `b27e06c5a401bfc10d0da90da8ef00f58b7e55af55586e05c3abc4b8a0be6cba`.

The compiled-products metadata explicitly says `OBSERVED_PRODUCTS_INVENTORY_NOT_BUILD_PROVENANCE`; it does not authorize a compiled app reuse or a skipped build. No new tests or CI were run for this readback.

A next candidate must retain the original process-survival, real scene-event and authority assertions, resolve the real background-action issue, and coordinate the observer prerequisite with its current owner. SDK06's separate 23-method/32-case plus ACK7 continuation remains with the active existing owner. This readback neither repeats that work nor accepts its results by inference.
