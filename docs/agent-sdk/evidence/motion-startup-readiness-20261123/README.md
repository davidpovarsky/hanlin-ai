# Bounded Motion startup admission and retained diagnostics

**Portable controls PASS16/16; Apple readiness and A/B/C acceptance NOT_RUN. No native dispatch has been submitted for this source.**

The preserved four-run comparison found identical toolchain, runtime build, fresh device selection and readiness code. Original D45217195070 reached native bootstatus success after160.355s; original B45223225171 attempt2 after169.871s. Both0b attempts of45236783905 timed out just beyond the180s startup budget, then failed the bounded owned-device shutdown. This does not prove the blocked hosts would have succeeded with a longer wait.

The change gives **native simulator startup admission300s**. Original boot-command15s, shutdown20s, one owned timeout recovery, immutable owner/run/attempt checks, native-success requirement and fail-closed verdicts remain unchanged. `ensure_ready` and `native_command` bodies are byte-identical; only the bootstatus budget they read changes. No global simulator/service reset, device substitution or inventory-only readiness fallback is introduced. Native Motion gestures, preset durations, geometry requirements, all original test bodies/deadlines, and workflow limits remain unchanged.

The real diagnostic loss is also repaired: timed-out read-only observations now retain their partial stdout/stderr alongside the original15s deadline marker. The selected DEVELOPER_DIR and a bounded5s `xcrun --find simctl` receipt are recorded without dumping the environment. On readiness failure, a bounded5s process observation retains only simulator-related executable names owned by the current runner UID, with PIDs/parents/state. It neither reads process environments nor signals services. Missing diagnostic tools preserve the existing readiness verdict.

## Focused controls

The existing startup/ownership suite now passes16 controls. Existing cases retain non-timeout failure rejection (including native exit124), immutable run/attempt/selection checks, Booted-inventory rejection without real readiness, one targeted recovery, failed-shutdown stop and second-timeout stop. New controls verify actual partial stdout/stderr from a real bounded subprocess timeout, filtered current-user process observations, retained timeout status, exact tool path/environment privacy, and missing-tool diagnostics without altering a failed verdict. The real subprocess controls run locally on Linux; no simulator, SwiftUI or Apple compilation was executed.

`verification.json` binds the exact helper/test sources, unchanged native inputs and admission-function bodies. `controls.stderr` preserves the original16-test output. A reviewed, source-bound original affected B+C run is still required; original A follows its actual result. Prior C PASS remains historical because the shared proof row changed.
