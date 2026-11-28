# Native acceptance gate corrections — 2026-11-18

Status: fixes committed; native reruns are required. No stage completion or release approval is claimed.

## Observed results

- Run 44236265019, c19620d3: both shipping app builds succeeded. The paired runner stopped before installation because it read the empty ad-hoc signature entitlement dictionary. Actual Xcode logs show simulator entitlements linked into __TEXT,__entitlements. Paired UI remained NOT_RUN.
- Runs 44238647553 and 44238650876, ce2aaba4: the affected-validation planner rejected three new unmapped UI test files before any native build or UI execution.
- Run 44234308320, 0616e056: five selected native media tests passed; the gallery test failed on a global image-analysis AX label query. The captured screenshot and AX hierarchy show the actual native Quick Look image. No successful gallery acceptance is claimed.

## Corrections

The paired runner reads the bounded Mach-O entitlement section of each actual built executable and records its SHA-256, the section SHA-256, and parsed entitlements. It requires all original source App Groups. Strict codesign verification, real OS group-container equality after installation, and all three original paired UI scenarios remain mandatory. No binary is re-signed or entitlement source changed.

Three exact UI test paths now route to their original suites in the existing affected-validation map. No wildcard or fallback disables the unmapped-path guard.

The gallery test scopes its image query through the observed native Quick Look renderer and image canvas. It still requires a visible nonzero-size image, native dismissal, three fetched image sources, original source links, disabled historic actions, and zero outbound replay.

## Local validation scope

- Six reader tests cover valid embedded plists and ambiguous, missing, truncated, malformed, wrong-architecture and out-of-bounds input. These are reader regression tests, not native product acceptance.
- All 97 existing affected-validation tests passed.
- Both exact wide and compact requests plan successfully with the new mappings.
- Swift syntax parsing passed; Apple compilation and execution await CI.
