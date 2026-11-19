# Current-build unit test manifest admission

## Evidence and purpose

DATA run 44451321578 at source 048e431cc55b10290c03ec4b2c0162e5f9dfcf9c built successfully with the actual build-for-testing action. The original unit command later supplied the project and scheme to test-without-building, entered Resolve Package Graph and was canceled. There are zero observed test-case starts/results and no unit result bundle. The authenticated raw artifact is 14499647092, SHA256 3210940e9e60808c2113317f2b916512c959146b3e3210e1a2b594d2308070f7. The actual cancelling actor/cause is unknown.

This patch removes that second project/package-resolution route for the existing app-hosted unit lane. It does not claim to fix every cause of runner cancellation or Simulator service failure.

## Scope and execution

Exactly three changed files:

- .github/workflows/build-ios26-unsigned-ipa.yml
- Scripts/CI/current_unit_xctestrun.py
- Scripts/CI/Tests/test_current_unit_xctestrun.py

Before the current unit build, the helper preserves prior top-level .xctestrun files under simulator-logs/prior-unit-xctestrun and records their hashes. It leaves all compiled products and cache policy intact. Missing or partial preparation cannot admit tests.

After the successful main build and optional same-run warm rebuild, the helper requires exactly one newly present manifest. It accepts the original AI_HLYTests target in supported version1/version2 shapes, requires the original com.itorah.chavrusachat app host and .tests bundle identity, resolves the original build-product paths, and checks the expected Debug/Release iPhoneSimulator location. Missing files, unknown formats, ambiguous active configurations, wrong targets and paths outside the owned product directory stop the lane. Both the embedded and top-level original test bundle locations are supported.

It binds the original manifest bytes, app/test Info.plist files and executable hashes. Debug app launch stubs are insufficient, so the adjacent original .debug.dylib is included when present. The original manifest is never rewritten; its environment and test-plan settings are retained. A separate identical copy is archived as evidence, but execution uses the original manifest location so __TESTROOT__ keeps its meaning.

Immediately before unit execution, the helper rechecks those bindings, the actual Git HEAD and tracked diff, recorded build provenance, GitHub run/attempt, selected configuration, all requested selectors, selected developer directory and Xcode version. It also calls the existing verify_owned_simulator helper and requires the same destination UUID. It does not query global Simulator state.

The workflow then runs test-without-building with -xctestrun and the original owned destination, original 12 selectors, unchanged parallelism and timeout settings, original result bundle path and original verify_selected_tests.py gate. Admission happens before set +e, so an invalid manifest cannot fall through to a blank argument or another route. Other jobs and all unmodified steps were compared structurally; the original scripting/UI portion of the test step is byte-identical.

## Provenance limits

A current successful build-for-testing can legitimately reuse cached compiler products. The receipt explicitly records that fact; it does not label every object newly compiled. The old descriptors are preserved rather than selected or destroyed. The source/tree fingerprint is checked through build and admission, and the existing trackedWorkspaceModified qualification remains visible.

The sealed executable/plist fingerprints cover the test runner, app executable and adjacent app debug code; this is not a new complete transitive resource-signing system. The existing original build, dependency lock/source preparation, codesigning and product validation remain authoritative for the rest of that closure. No fallback to a different target or zero-test success is introduced.

The canceled DATA artifact did not retain its generated .xctestrun file. Accordingly, the version1/version2 parser has portable fixture coverage, not a claim that the actual Xcode27.2 manifest was parsed already. The next original unit lane must produce and admit its actual manifest, execute the requested cases and satisfy the unchanged result verifier. Unknown native format/path details fail with retained current evidence instead of being silently guessed.

## Validation

Base snapshot: 36faa1904e819c92db193d65cafbec0b8bd62ab1.
Read-only application check at 884c41d039dfbf276af4c12299d84ac4c981e082: all original input hashes unchanged and git apply --check succeeds.

18 focused tests passed, zero failures and zero skips. They exercise actual temporary files/plists, executable mutations, an actual temporary Git repository with dirty tracked content, the original owned-Simulator receipt validator, stale/cross-run/source/toolchain rejection, missing/ambiguous/foreign descriptors, source path containment including a real symlink, and preservation of all 12 DATA selectors. Synthetic test bundles and boot receipts are explicitly fixtures; no native execution is inferred.

Both Python files parse, the workflow parses as YAML, and all three changed/new shell bodies pass Git Bash syntax validation. The existing ci_router component already covers .github/** and Scripts/CI/**; the routing map is unchanged.

No canonical file was edited, no CI run was dispatched/canceled, no native Apple command was executed and no credentials were read. The original failed/canceled run remains in its separate authenticated receipt.

## Apple documentation

[Apple TN2339](https://developer.apple.com/library/archive/technotes/tn2339/_index.html) documents the separate build-for-testing and manifest-based test-without-building route, preserving destination/test filters and requiring the referenced products to exist.

[Apple WWDC19 session413](https://developer.apple.com/videos/play/wwdc2019/413/) explains that the build creates both products and the execution manifest. It cautions that manifest format changes between Xcode versions, supporting the same-toolchain receipt check.

[Apple Xcode26 release notes](https://developer.apple.com/documentation/Xcode-Release-Notes/xcode-26-release-notes) describe retaining disabled configurations in generated manifests while excluding them from default execution. The validator therefore examines enabled configurations.

[Apple Xcode11.4 release notes](https://developer.apple.com/documentation/Xcode-Release-Notes/xcode-11_4-release-notes) explain that incompatible architecture/deployment targets may be skipped during manifest execution. The existing selected-result verifier remains required; a successful command with missing cases cannot establish acceptance.

The initially suggested QA1937 addresses privacy-purpose descriptions and is not the relevant testing document.

## Version2 source review addendum

Version1 patch31c75f0e and its archive are preserved. Version2 additionally retains all bounded regular generated manifests before structural interpretation, including an unknown-format or ambiguous-manifest rejection. An additional regression proves exact raw retention without advancing PREPARED to SEALED; the ambiguity regression checks both generated files survive in the evidence. This prevents a parser failure from requiring another native inspection run just to recover the manifest.

source-and-native-path-proof.json contains authenticated DATA build log excerpts for the app and embedded unit bundle Info.plist paths, both app executable/debug-dylib linker products, and the unit executable. The original Debug/Release bundle identifiers and TEST_HOST settings are unchanged between source048 and the reviewed current project. It also records the actual workflow ordering: original provenance creation and all header/schema preparation finish before prepare; the receipt then spans the build, optional warm rebuild and admission. The provenance resource is tracked. No later explicit provenance writer exists in the simulator job; an unexpected tracked source or provenance mutation fails admission. Exact generated .xctestrun bytes remain a future native observation.
