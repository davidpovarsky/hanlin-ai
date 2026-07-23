# Hanlin platform implementation status

Last updated: 2026-07-23
Execution contract: Revision 2.0
Current gate: Phase 1 complete; Phase 2 not started

## Phase 0 — complete

Status: complete in normal editing mode. No runtime behavior changed.

Completed requirements:

- verified repository, branch, instructions, project, target, scheme,
  deployment target, Swift mode, workflows, packages, runtime locks,
  entitlements, and foundational subsystems;
- identified the repository as CherryHQ-derived and documented the missing
  configured upstream remote;
- recursively read the authorized source root without modifying it;
- selected root-level canonical sources through an explicit mapping and
  recorded byte-identical duplicate candidates;
- imported 999 authorized files into a portable immutable baseline;
- excluded `node_modules`, `.bin`, executables, archives, caches, temporary
  files, editor artifacts, and secret-bearing inputs;
- generated per-file and aggregate SHA-256 records;
- generated deterministic declaration, symbol, documentation, example,
  compiler, compatibility, and diagnostic indexes;
- indexed 177 fixtures while leaving all unexecuted stages truthfully
  `notRun`;
- documented the platform architecture, repository inventory, dependency
  direction, migration, distribution, isolation, wire, tooling, packaging,
  upstream, and compiler decisions in ADRs 0001–0011;
- verified source-to-repository `--check`, repository-only hashes, generated
  inventory drift, and fixture index integrity;
- confirmed a write-mode rerun is idempotent;
- added a narrowly scoped Git byte-preservation rule for the compatibility
  baseline so staging and macOS checkout cannot normalize line endings.

Baseline:

- ID: `scripting-compat-2026-07-22-8d7d33d9369e`
- Aggregate SHA-256:
  `8d7d33d9369ee555d15adf10c867abbfb85834eced7e7596a627b70ff627ff36`
- Imported files: 999
- Imported bytes: 5,918,732
- Declarations: 5
- Compiler metadata files: 3
- Documentation files: 942
- Project-example files: 49
- Documentation fixtures: 136
- Project fixtures: 41

Tests performed:

- Node syntax checks for all Phase 0 tooling;
- `verify-scripting-reference.mjs`;
- `build-scripting-inventory.mjs --check`;
- `validate-scripting-examples.mjs`;
- source-backed importer `--check`;
- write-mode idempotence rerun;
- Git ignore visibility check confirmed all 1,051 retained new Phase 0/1
  files are versionable, including both exact `tsconfig.json` inputs;
- byte comparison of canonical required files against duplicate candidates;
- strong secret-pattern scan over approved source files;
- pre-push staged-index verification confirmed all 999 original Git blobs
  match the raw Windows bytes and recorded per-file SHA-256 values;
- staged Git attributes resolve to `text: unset` and `whitespace: unset` only
  inside the compatibility baseline;
- `git diff --cached --check` passes while preserving original baseline
  whitespace;
- 1,053 intended staged files were read in full by scope/prohibited-artifact
  and strong-secret scans; `recovery-state-before.txt` remains unstaged;
- 131 versionable JSON files parse, with all 60 internal manifest-schema
  references resolving across 23 definitions.

macOS verification:

- run `30032399070`, job `89291875155`, reverified the complete baseline from
  a clean checkout: 999 files, 5,918,732 bytes, the exact baseline ID and
  aggregate SHA-256, all 177 fixture records, and all 131 versionable JSON
  files with 60 internal references across 23 definitions;
- Phase 0 does not execute the TypeScript fixtures by contract. Compiler-backed
  interpretation remains deferred to Phase 6.

Pre-push source observations:

- `Original/Types/global.d.ts` contains one intentional NUL character inside
  documentation about decoded strings. Its byte position and SHA-256 match the
  authorized source exactly; it is not an executable or encoding wrapper;
- absolute Windows paths occur only in required audit/provenance documentation
  and tooling examples. No Git-managed application or package runtime source
  embeds a local developer path;
- the authorized Transit example retains its source author name with null email
  and homepage fields. No unrelated local user files were imported.

New downstream files:

- `Reference/ScriptingCompatibility/**`;
- `Scripts/ScriptingReference/**`;
- `docs/hanlin-platform/**`.

Original/upstream files minimally edited:

- `.gitignore`: two narrow negations ensure the exact authorized compiler and
  project-example `tsconfig.json` files are included despite the existing broad
  `*config.json` secret rule. No other ignore policy changed;
- `.gitattributes`: new repository policy scoped only to
  `Reference/ScriptingCompatibility/**` with `-text -whitespace`.

Existing behavior preserved:

- RuntimeCore, MCP, NativeAppPlatform, NativeAgentExtensions, AgentActivity,
  app scenes, project configuration, signing, and entitlements were not
  changed. A manual-only Phase 1 validation mode was added to the existing
  registered iOS workflow without changing its automatic trigger or existing
  build commands.

Unresolved risks and recorded findings:

- 20 links use the Scripting documentation-root convention rather than normal
  Markdown document-relative resolution; all targets exist and the fallback is
  recorded in `Generated/diagnostics.json`;
- the Phase 0 lexer found 158 duplicate normalized declaration symbol names;
  compiler-backed interpretation is deferred to Phase 6;
- authorized source TypeScript is 7.0.2 while the existing embedded Hanlin
  compiler is 6.0.3; both lanes must report differences;
- the declaration header says `scripting v1.1.1`, which is not used as the
  baseline identity;
- app-resource size and the optional full-documentation packaging tier need
  measurement before Phase 6 packaging;
- Apple API availability, App Store interpretation, entitlements, and hard
  JavaScript interruption require explicit SDK/device verification;
- user authorization is recorded by the execution contract; publisher and
  third-party notice presentation still needs release/legal review;
- exact current divergence from CherryHQ cannot be computed without an
  upstream remote/fetch.

## Phase 1 — complete

Status: complete. The isolated contract gate and both full-application jobs
passed from clean macOS checkouts of exact implementation commit
`2c41b445427703f65444330a947ca46fba47ebf6`. The later documentation-only
closure commit records these results and does not change the tested
implementation. Phase 2 has not started.

Implemented:

- new downstream package `Packages/HanlinPlatform`;
- iOS 26 product / macOS 26 host-test / Swift 6
  `HanlinPlatformContracts` target with no app-model dependency;
- validated `RawRepresentable`, `Codable`, `Hashable`, `Sendable` identifiers
  for all required contract identities, plus typed MCP server and publisher
  identities;
- canonical API, manifest, wire, package, and host-range version models;
- deterministic tagged `HanlinValue` encoding with non-finite number rejection;
- recursive Codable `HanlinJSONSchema` with semantic definition validation;
- localized values, origins, risk, execution contexts, distribution modes,
  implementation variants, entry points, routes, actions, tools,
  capabilities, dependencies, extensions, authors, integrity, and unified app
  descriptor;
- semantic manifest validation for supported versions, safe relative entry
  points, required contexts, duplicate IDs, authors, distribution modes,
  SHA-256 form, and nested schemas;
- bundled Draft 2020-12 `HanlinAppManifest.schema.json`;
- stable platform error codes and separate user/diagnostic messages;
- versioned Codable script envelope with request correlation, version
  validation, payload bounds, deterministic encoding, and message-kind rules;
- Swift Testing suites covering deterministic round trips, malformed IDs,
  versions, values and schemas, unknown versions and message kinds, unsafe
  paths, duplicate IDs, unknown-field tolerance, request IDs, and payload
  limits.

Static checks performed:

- readable official Apple PackageDescription documentation confirmed
  package-level Swift 6 language modes and processed resources; readable
  official Swift Dictionary documentation confirmed conditional `Hashable`
  conformance used by value contracts;
- manifest JSON Schema parsed successfully;
- all 60 internal JSON Schema references resolve across 23 definitions;
- 12 Swift/package files passed delimiter-balance scanning;
- no trailing whitespace or missing final newline;
- no placeholder/TODO/fatal stub, force cast/unwrap, `[String: Any]`,
  `AnyView`, legacy observation, GCD, or detached-task pattern in the package;
- no public identifier field uses an unchecked raw `String`;
- no import or reference to AI_HLY app models.

Contract test sources:

- `IdentifierAndVersionTests.swift`;
- `ValueAndSchemaTests.swift`;
- `ManifestAndWireTests.swift`.

Gate acceptance:

- the isolated Phase 1 validation passed on the exact tested commit;
- all 14 contract tests passed;
- generic iOS Simulator and iOS device compilation passed;
- the full application passed Release device compilation and unsigned IPA
  packaging;
- the full application launched on an iPad Simulator and passed shell and MCP
  runtime acceptance without a crash report;
- the pinned `server-everything` install, compatibility scan, runtime probe,
  MCP initialize, tools/list, harmless echo call, clean worker stop, and
  persisted acceptance report all passed.

Original/upstream files minimally changed:

- the Phase 0 `.gitignore` exception and narrow `.gitattributes` policy are the
  only repository policy touchpoints;
- `.github/workflows/build-ios26-unsigned-ipa.yml` adds one default-false
  manual input, one isolated fail-fast validation job, and two condition
  guards that prevent application jobs from running in validation-only mode;
- the package is not yet wired into `AI_HLY.xcodeproj`.

Validation failure history:

- checkpoint `5a9a4f3` pushed successfully, but GitHub returned HTTP 404 before
  creating a run because a brand-new workflow that exists only on a feature
  branch is not registered for dispatch;
- root-cause category: CI workflow registration, not source, package, schema,
  baseline, or Xcode failure;
- the unregistered standalone workflow was removed. Its job was moved into the
  existing registered `build-ios26-unsigned-ipa.yml` workflow as an explicitly
  selected manual-only mode. No runner was launched for the failed dispatch;
- the first registered-workflow dispatch was then rejected with HTTP 422
  because the `runner` expression context is unavailable in job-level `env`.
  Log-directory resolution was moved to a step using `$RUNNER_TEMP`, where the
  runner context is valid. This failure also launched no runner;
- run `30031979860`, job `89290494746`, validated the clean macOS baseline,
  JSON, schema references, and package resolution, then failed at the first
  `swift build`. The package declared only iOS 26, so host compilation inherited
  an old default macOS minimum and rejected modern Foundation APIs. The package
  now declares macOS 26 for host build/tests as well as iOS 26, without
  availability fallbacks or reduced language/concurrency strictness. Evidence
  artifact `phase1-validation-72fa7747d8f210bab83a2f5ecb9fe5cc9f810c46`
  is retained through 2026-08-22;
- run `30032180092`, job `89291151693`, confirmed the macOS 26 package fix,
  and all 14 Swift Testing tests passed. The next command failed before iOS
  compilation because the generated Swift-package workspace does not expose a
  scheme named after the library target. The workflow now records
  `xcodebuild -list -json` and uses only the discovered
  `HanlinPlatform-Package` scheme or a single unambiguous generated scheme.
  Evidence artifact
  `phase1-validation-4067e363b85d66f67d62cc153d9dc481a8a0e0c0` is retained
  through 2026-08-22;
- run `30032399070`, job `89291875155`, on exact commit
  `aa78443de6f3679913184bf8585108ebdc8988b7` completed the isolated gate:
  baseline and schema validation, package resolution, Swift build, all 14
  Swift Testing tests, and generic iOS Simulator/device Xcode builds passed
  with the discovered `HanlinPlatform` scheme. Evidence artifact
  `phase1-validation-aa78443de6f3679913184bf8585108ebdc8988b7` is retained
  through 2026-08-22;
- full-application run `30032560629` used that same exact commit. Device job
  `89292426462` passed the Release iOS 26 build, located the app, packaged the
  unsigned IPA, validated its dyld closure, and uploaded both IPA and logs.
  Simulator job `89292427012` passed the Release arm64 build, app-resource
  scan, dyld closure, launch, 23-command shell acceptance, and process-liveness
  checks, but failed waiting for `mcp-acceptance.json`;
- the MCP diagnostic log proves Node 24.5.0 reached `host_ready`, installed
  dependencies, and entered `checkingCompatibility`. The app remained alive
  with no crash report, but the sequential archive scan did not finish within
  the 360-poll CI window. The same pinned package contains 4,318 tree entries
  and passes the macOS integration test with 13 tools;
- the correction retains every archive safety check while scanning
  independent directories and metadata concurrently in bounded batches. It
  also batches installed-size metadata reads and records compatibility
  sub-stages so any future timeout identifies archive, entry-point, or runtime
  probe work precisely. Local Node syntax, all 28 deterministic host tests,
  and the pinned npm integration test passed after the change;
- the correction was committed as
  `2c41b445427703f65444330a947ca46fba47ebf6` and passed both final workflows
  described below.

## Phase 1 closure evidence

Exact tested implementation commit:

- `2c41b445427703f65444330a947ca46fba47ebf6`.

Runner and toolchain:

- macOS 26.4, build `25E246`;
- Xcode 26.6, build `17F113`, selected from
  `/Applications/Xcode_26.6.app/Contents/Developer`;
- Apple Swift 6.3.3
  (`swiftlang-6.3.3.1.3 clang-2100.1.1.101`);
- iOS, iOS Simulator, and macOS SDK 26.5;
- package language mode Swift 6 and deployment targets iOS 26 / macOS 26.

Isolated contract run:

- workflow run `30036246827`;
- job `89304830925`, `Validate baseline, contracts, tests, and iOS
  compilation`;
- result: success;
- evidence artifact `8575396468`,
  `phase1-validation-2c41b445427703f65444330a947ca46fba47ebf6`,
  retained through 2026-08-22;
- clean-checkout baseline result: 999 files, 5,918,732 bytes, exact baseline
  ID and aggregate SHA-256, 177 fixture records, and 131 JSON files with all
  60 internal references across 23 definitions;
- Swift package resolution and macOS host compilation passed;
- discovered Swift-package Xcode scheme: `HanlinPlatform`;
- generic iOS Simulator Debug compilation passed with code signing disabled
  and complete strict concurrency;
- generic iOS device Debug compilation passed with code signing disabled and
  complete strict concurrency;
- the contract warning scan found zero compiler-warning lines.

All 14 contract tests passed:

1. `manifestRoundTripsDeterministically`
2. `schemasValidateAndRoundTrip`
3. `majorMinorVersionsRejectNonCanonicalAndUnknownVersions`
4. `wireEnvelopeRoundTripsAndEnforcesRequestIdentity`
5. `hostVersionRangeRejectsInversion`
6. `packageVersionsUseStableTotalOrdering`
7. `valuesRejectNonFiniteAndUnknownRepresentations`
8. `identifiersValidateAndRoundTripCanonically`
9. `valuesRoundTripWithDeterministicEncoding`
10. `manifestRejectsUnsafePathsAndUnsupportedVersions`
11. `manifestRejectsDuplicateCanonicalIdentifiers`
12. `manifestSchemaResourceIsValidJSONAndUnknownFieldsAreTolerated`
13. `wireEnvelopeRejectsUnknownVersionMalformedKindAndOversizedPayload`
14. `schemasRejectMalformedDefinitions`

Full-application run:

- workflow run `30036394400`;
- simulator job `89305320796`: success;
- device and unsigned-IPA job `89305320850`: success;
- both jobs checked out the exact tested implementation commit;
- project `AI_HLY.xcodeproj`, scheme `AI_HLY`, Release configuration, iOS 26
  deployment target;
- Release device compilation passed, the app was found, its dyld closure
  passed, and an unsigned IPA was packaged;
- IPA payload size: 80,156,373 bytes; SHA-256:
  `c31840ddbcc4924f60f85a77c1dc25b0a865aacd12a40c7ec5739442a0e41402`;
- build-log artifact `8576178216` and unsigned-IPA artifact `8576177511` are
  retained through 2026-08-06;
- Release arm64 Simulator compilation, app-resource scan, and dyld closure
  passed;
- the app installed and launched on an iPad mini (A17 Pro), iOS 26.5;
- shell acceptance passed all 23 commands, found no workspace escape, and the
  app remained alive for 24 seconds;
- MCP acceptance passed with embedded Node 24.5.0 and pinned
  `@modelcontextprotocol/server-everything` 2026.7.4: 264 reachable modules,
  635 resolutions, 13 listed tools, successful initialize, tools/list, and
  harmless echo call, clean worker stop, zero terminal errors, and no use of
  `child_process`, client stdio, or `cross-spawn`;
- no new crash diagnostic report was produced;
- simulator evidence artifact `8576030321` is retained through 2026-08-06.

Validation commands:

- local: `node --check package-compatibility.mjs`,
  `node --check package-installer.mjs`, `npm test`,
  `npm run test:integration`,
  `node Scripts/ScriptingReference/import-scripting-reference.mjs --source
  C:\Users\DAVID\Code\ScriptingProjects --check`,
  `node Scripts/ScriptingReference/verify-scripting-reference.mjs`,
  `node Scripts/ScriptingReference/build-scripting-inventory.mjs --check`,
  `node Scripts/ScriptingReference/validate-scripting-examples.mjs`,
  `node Scripts/ScriptingReference/validate-json-and-schema.mjs`,
  `git diff --check`, and `git diff --cached --check`;
- isolated macOS runner: `sw_vers`, `xcodebuild -version`,
  `xcode-select -p`, `swift --version`, `xcodebuild -showsdks`, the baseline
  verifier, inventory check and deterministic regeneration, fixture validator,
  JSON/schema validator, `swift package --package-path
  Packages/HanlinPlatform resolve`, `swift build --package-path
  Packages/HanlinPlatform`, `swift test --package-path
  Packages/HanlinPlatform --parallel`, `xcodebuild -list -json`, and clean
  generic iOS Simulator/device `xcodebuild` commands for the discovered
  `HanlinPlatform` scheme with `CODE_SIGNING_ALLOWED=NO` and
  `SWIFT_STRICT_CONCURRENCY=complete`;
- full-application runner: isolated host-resource copy plus
  `npm ci --ignore-scripts --no-audit --no-fund`, `npm test`,
  `npm run test:integration`, MCP install-dedup validation, runtime-host
  packaging and content checks, runtime-link and dyld-scanner tests, pinned
  archive size/checksum validation, Xcode project listing/settings inspection,
  package dependency resolution, clean Release device and arm64 Simulator
  `xcodebuild` commands, app and packaged-IPA dyld-closure validation, IPA
  resource/property-list checks, `simctl` boot/install/launch/process-liveness
  checks, shell acceptance validation, MCP acceptance validation, and crash
  diagnostic collection.

Remaining warnings:

- the isolated `HanlinPlatformContracts` package emitted no compiler warnings;
- each successful full-app Xcode job emitted 60 pre-existing warning lines in
  12 upstream-owned app files. They cover iOS 26 deprecations
  (`UIScreen.main`, geocoder/placemark APIs, and concatenated SwiftUI `Text`),
  Swift concurrency and `Sendable` isolation, one unnecessary `await`, and one
  unused `isZh` value;
- affected upstream files:
  `NativeAgentExtensions/UI/NativeUIRenderer.swift`,
  `Services/ChatServices/APIManager.swift`,
  `Services/ChatServices/MapServices.swift`,
  `Services/ModelServices/ModelDown.swift`,
  `Views/Components/ChatViewBottom.swift`,
  `Views/Components/ChatViewComponents.swift`,
  `Views/Components/KnowledgeWritingView.swift`,
  `Views/Components/ModelsViewComponents.swift`,
  `Views/Components/SettingsViewComponents.swift`,
  `Views/Components/VoiceInputView.swift`, `ChatView.swift`, and
  `VisionView.swift`;
- those warnings predate the Phase 1 package, did not fail the requested gate,
  and were not broadly rewritten because that would be unrelated upstream
  modernization outside Phase 1;
- GitHub's runner also reported that selected v4 JavaScript actions target
  Node 20 and were forced onto Node 24. This is infrastructure output, not an
  application compiler warning.

Files changed to resolve validation failures:

- `.github/workflows/build-ios26-unsigned-ipa.yml`: registered the isolated
  manual validation mode, moved runner-dependent log setup into a step,
  discovered the generated package scheme, and kept full-app jobs isolated
  from validation-only dispatches;
- `Packages/HanlinPlatform/Package.swift`: declared the macOS 26 host-test
  platform required by the modern Foundation contracts;
- `AI_HLY/Downstream/RuntimeCore/Node/Host/package-compatibility.mjs`:
  preserved archive-safety semantics while bounding independent metadata
  scans concurrently;
- `AI_HLY/Downstream/RuntimeCore/Node/Host/package-installer.mjs`: batched
  installed-size metadata and exposed compatibility substages;
- `AI_HLY/Downstream/RuntimeCore/Node/Host/Tests/compatibility.test.mjs`:
  proved serial and concurrent safety decisions are equivalent;
- this status document: records the failure chain and final evidence.

The contracts package remains intentionally unlinked from the application
target in Phase 1. The package gate and full-app runtime regression gate were
validated independently. Phase 2 capability, permission, policy, audit,
redaction, distribution, UI-model, and registry-adapter work has not started.

Exact next gate:

Phase 1 is closed. Do not begin Phase 2 without a subsequent task authorizing
that work.
