# Hanlin platform implementation status

Last updated: 2026-07-23
Execution contract: Revision 2.0
Current gate: Phase 1 validation

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

Tests not performed:

- no Xcode build or analysis;
- no Swift compiler or installed Apple SDK verification;
- no GitHub Actions;
- no simulator or device run;
- no TypeScript fixture compilation;
- no package bundle or application launch;
- no runtime, UI, permission, or extension test.

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

## Phase 1 — implementation complete, verification pending

Status: partial. The implementation and acceptance test suite are present, but
this Windows environment has no Swift toolchain. The contract tests have not
been compiled or executed, so the gate is not marked complete and Phase 2 has
not started.

Implemented:

- new downstream package `Packages/HanlinPlatform`;
- iOS 26 / Swift 6 `HanlinPlatformContracts` target with no app-model
  dependency;
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

Tests written but not executable in this environment:

- `IdentifierAndVersionTests.swift`;
- `ValueAndSchemaTests.swift`;
- `ManifestAndWireTests.swift`.

Verification still required before Phase 1 can be complete:

- commit and push the corrected registered-workflow validation candidate;
- run the manual Phase 1 workflow on a clean macOS checkout;
- compile with the repository's selected stable Xcode 26 toolchain;
- execute all 14 `HanlinPlatformContractsTests`;
- compile the contracts for generic iOS Simulator and device destinations;
- run the existing application build only after isolated package validation;
- confirm Swift 6 concurrency and availability diagnostics from the installed
  iOS 26 SDK.

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
  selected manual-only mode. No runner was launched for the failed dispatch.

Exact next gate:

Complete Phase 1 verification when explicitly authorized. Only after those
acceptance tests pass may Phase 2 add capability, permission, policy, audit,
redaction, distribution enforcement, UI models, and current-registry adapters.
