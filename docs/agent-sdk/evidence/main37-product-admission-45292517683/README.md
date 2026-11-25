# Main37 original product-admission failure — 45292517683

Run https://github.com/davidpovarsky/hanlin-ai/actions/runs/45292517683 attempt1 used source a051e6a2076db8f0783f8c1a62fd6470e21b3d71 and ended FAIL. This packet preserves actual build evidence and the absence of test execution separately.

## Executed boundary

- Full app/test build PASS (00:20:37–00:32:37 UTC); original log reports TEST BUILD SUCCEEDED.
- Initial current-product validation PASS/SEALED (00:32:37–00:32:39). Its source/run/toolchain/product hashes and original build-log hash are retained.
- Resource scanner PASS:37 copied-resource checks, two equal module-bundle inventories,49 entries/45 files each.
- Localization PASS:3683 source catalog values and177 packaged translated values; four equal copies,19 entries/15 files each. These are translated values, not177 files.
- Runtime-copy signature check PASS; generated unit and UI app paths both end in AI_Hanlin.app.
- Owned simulator boot and ordinary fixture staging PASS. This does not establish app launch or EventKit permission grant.
- Run-time unit-product admission FAIL: original command current_unit_xctestrun.py admit reported git rev-parse HEAD timed out after30 seconds. Original log178648–178651 is retained by excerpt and bound to its root-owned full hash.

The workflow uses set-e: the failing admission precedes prepare_calendar_acceptance.py and xcodebuild test-without-building. Their appearances in the job log are printed shell source only; no execution trace reached either command. The smoke ZIP contains only SimulatorBuildResult.xcresult, no unit/UI result bundles or exported case results, and no calendar preparation receipt. Calendar privacy grants and the actual EventKit method are NOT_RUN. The reviewed120-second privacy preparation repair was not exercised.

## Exact requested cases

All37 authored invocations are NOT_RUN:26 unit and11 UI,33 method declarations. The frozen request is byte-identical to the prior37 request. Every method/argument row and all eight test-source SHA256 values were compared against the source-bound previous reconciliation and this run's frozen admission. No parameter prefix matching was used. Original history remains18 PASS/7 FAIL/12 NOT_RUN; this run neither fixes nor repeats those outcomes. The305 other retained historical passes were not executed here. Both native configuration methods remain unselected as admitted.

The performance summary evaluates zero metrics; its hard_gate_passed field is not test or performance acceptance.

## Acquisition and provenance

Original smoke14877902206 was downloaded once,3287009 bytes,SHA256 fff55f6c75917fcc851acf468ca6f3491d593a751a422ca0659c7631d5a29296. All91 member CRCs, SHA256 values and safe unique paths were checked. Only21 small original files were extracted; the full build log, metadata binaries and build xcresult remain in the preserved ZIP. Root's existing native job log29925615 bytes/SHA2560bc51ca4a2aec91da3aa76f1ec4ca1ccd9b2c94d83552ae1d07835ce61773682 was reused, not downloaded again.

Prepared Native artifact14875618230 is INELIGIBLE because its producer failed. It remains unacquired and unpublished. No additional CI, simulator execution, package tests, artifact acquisition, production changes or Host mutations were performed for this packet.
