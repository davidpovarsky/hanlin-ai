# Simulator acceptance and TestFlight gate

This versioned gate requires the actual `AI_Hanlin` Release application and
`AI_HLYUITests`, iPhone and iPad on actual iOS/iPadOS 27, English and Hebrew,
asserted post-interaction results, raw xcresults and screenshots. A source review,
component package, generic renderer, command exit or authored test is insufficient.

QA owns `docs/qa/simulator27/coverage.json` and its whole UI test source. The
integrator owns this runner, acceptance policy and existing workflow wiring.
Missing cases, skipped cases, gaps, unknown devices, bad provenance or changed
inputs block release. Hebrew requires RTL coverage; English validates its LTR
cohort. The current three QA cases map to six authored device/locale obligations
and leave substantial required coverage open. Planning them with
`--allow-incomplete-coverage` never makes their evidence release-eligible.

The application acceptance fixture reseeds/deletes its local model data on every
launch. `run_app.py` creates each disposable simulator, rejects any ID present in
the original inventory, boots it, and rejects an existing application data
container **before** fixture-enabled tests execute. It never erases another
simulator or uses a personal device. This fixture cannot establish relaunch
persistence. Runtime, model, API and signed physical iPad obligations remain
separate from these local UI journeys.

The fresh TestFlight path freezes candidate Git/coverage inputs before release
work, runs UI before archive, and verifies the same prepared dependency/resource
inputs and signed IPA identity before upload. The artifact binds original source,
build number, IPA hash, complete UI plan/results, toolchain/runtime/locale, raw
dependencies and original upload run. Upload readback adds the actual App Store
Connect app/build IDs. Raw UI evidence is retained even when blocked or failed.

Existing-build distribution downloads a unique original UI artifact through
authenticated GitHub APIs, checks its ZIP digest, original successful approved
release workflow/repository/source, exact source tree and assertion/fixture
blobs, versioned contract, raw results, transitive/resource inventory, build/IPA
binding and App Store Connect IDs. The audience helper must select that exact
build ID before it can assign groups. It does not pretend that today's checkout
is the uploaded build's source. No cross-build or cross-source UI reuse is
permitted. A missing historical proof blocks distribution.

`run_parity.sh` is a separate buildable-target UI observation. Its disposable
application mounts the **whole existing** Swift Parity Mini App package with
real canonical private storage, broker and URLSession. Its tests exercise real
save/reload/relaunch behavior. It never enables the destructive application
fixture. Its scope is `compiled-swift-parity-miniapp-ui-only`; that result is
explicitly rejected by the comprehensive app release gate. It does not prove the
AI app, live provider, NativeScript/Expo, transport or physical hardware.

XCUITest is the interaction runner. The installed simulator-toolkit skill at
revision `86fb9ba90a438bd2ee7ab640165bd77da396d941` informs safe per-run simulator
lifecycle and evidence capture. Maestro and private Duo helpers are not used.
Locale uses Apple's documented test-runner environment prefix:
[Apple environment variables](https://developer.apple.com/documentation/xcode/environment-variable-reference).
Artifact origin/digest checks use the
[GitHub artifact API](https://docs.github.com/en/rest/actions/artifacts).

Portable checks are `python -m unittest discover -s Scripts/CI/SimulatorAcceptance`
and the scoped `test_verify_testflight_build.py` suite. Their records are synthetic
validator/transport fixtures, never application UI execution or release approval.
