# Original Yams Skill metadata integration

Task: [SKILL-YAMS-02](https://app.asana.com/0/0/1220546710401425).
Package/API implementation: `485933ba`; evidence preflight correction: `78c8880e`.
The manager approved `exact: "6.2.2"` adoption in `76fffd08`, retaining the original
Yams source commit for upstream update-tool discovery. App integration is `bedecb5a`
plus the selected-source regression control in `727f67b6`.
The public contract and parser/editor limits are documented in
`Packages/HanlinSkillFormat/README.md`.

The app `SkillMarkdownParser` now delegates to the single package parser. Its legacy
`ParsedSkillMarkdown` scalar fields remain available; `.document` is the complete
typed source/metadata authority. The legacy initializer remains available for existing
fixtures, with an optional document. `serialize` is now throwing and uses the original
Yams emitter rather than concatenating unescaped YAML. All three repository callers
were mapped before replacement; the Store uses the document editor instead.

Direct Markdown and ZIP entrypoints read original `Data`; extracted/original bytes
are not serialized on import. No additional installed manifest or mandatory sidecar
is introduced. `StoredSkillRecord.markdownDocument` exposes the same immutable type.
Read migration derives it freshly from existing SKILL.md without rewriting disk.

`saveCustomSkill` reads existing documents and edits known fields/body in their source
spans. An unchanged UI title fallback does not insert a previously absent title.
An exact no-op skips the SKILL.md write. `createOrUpdateOverride` starts with an
existing override or selected catalog document, including unknown metadata. A disabled
custom source can be read explicitly when the catalog has no selected entry. A
different selected source without metadata does not inherit a shadowed custom document.
An unsupported edit throws before creating a directory or writing source/state.

`HanlinSkillCatalog.markdownDocument(for:)` follows its actual selected entry and
existing precedence/disabled filtering. `register` accepts an optional document for
source owners; it does not fetch metadata from a shadowed same-ID skill. Custom and
override entries attach their exact source document. Compiled/installed package
owners may supply the same type when they have an authoritative SKILL.md source;
an inline descriptor alone does not invent one. Existing instructions/resource
resolution, enabled state and SDK descriptor/Host contracts remain unchanged.

The manager owns the shared project graph. Required delta is one local Swift package
reference `Packages/HanlinSkillFormat` and its `HanlinSkillFormat` product linked to
the app and unit-test targets. Its only original remote dependency is Yams at
`exact: "6.2.2"`, locked to `a27b21e0c81c5bf42049b897a62aaf387e80f279`. Resolve the real app graph and
retain its actual Package.resolved; do not copy an old PBX or manufacture that lock.
Existing proven AgentSDK/Host manifests/products/pins are untouched.

Validation at this checkpoint:

- EXECUTED_PASS: Windows Swift6.3.3 package tests,20 native Swift Testing identities,
  25 parameter-expanded invocations. Raw original Yams resolution and actual logs
  retained locally. Newline/Unicode source spans, nested typed OpenClaw, no-op/read
  migration, unknown fields/tags, scalar alias edits, explicit anchored-edit refusal,
  malformed/duplicate/invalid roots, cancellation and resource budgets are covered.
- EXECUTED_PASS: scoped app Swift syntax parsing and `git diff --check`. These are
  neither Apple-framework typechecks nor executed app tests.
- FAILED preparation: Apple run43754160901, evidence extractor missed inline
  `@Test func` declarations;0 tests ran. Corrected extractor counts the actual20
  identities locally; Bash syntax and all7 embedded Python blocks parse.
- EXECUTED_PASS: Apple package run43754353738 at original revision-pin source
  `78c8880e512078bafaa21f4deab87163d410f887`,20 actual xcresult identities/25 parameter
  invocations on each macOS and iOS27. Xcode27.2, Swift6.4.2, SDK27.2, Swift language6.
  The iOS package actually compiled for `arm64-apple-ios26.0-simulator`; this is a
  deployment26 compile, distinct from an actual iOS26 SDK/runtime test. All native
  argument children passed. Raw artifact digest/ZIP CRCs,9 Git/tar source hashes and
  raw lock were authenticated. The original Mac raw lock equals the original
  checked-in revision lock. See `evidence/skill-yams-native-43754353738.json`.
- BLOCKED: actual iOS26 execution; the runner has iOS27 runtimes only. No local
  xcrun or self-hosted alternate repo runner was found. Consequently the entire
  native workflow remains failure; it is not full-CI success. This is not a failed
  product test, and the40 passed native identities are retained without rerunning.
- PENDING: actual Mac exact-version resolution/source/target graph audit43755833008.
  It executes0 tests and checks both real lock resolutions, unchanged source/tests/
  fixtures, target/product/platform graph, original upstream archives and remote
  tag→peeled commit. A retargeted tag/new source fails the expecteda27 assertion.
  The actual update/rollback/controlled failure demonstration remains UPSTREAM01.
- NOT_RUN: actual app `SkillStoreAndImportTests`, including the four new controls
  `nestedMetadataSurvivesStoreSaveAndOverride`, `anchoredStoreEditDoesNotRewriteOriginal`,
  `zipNestedMetadataAndResourcesRemainLossless`, `catalogMetadataFollowsSelectedSource`. The direct-Markdown passive preview
  control retains the manager's exact89f2caaf method delta. Full app/Runtime/UI and
  physical-device acceptance are not established by package tests.
- OPEN: manager-owned focused Yams adoption PR, coordinated app package linkage/
  actual app lock and focused app test run; separate upstream update demonstration.
  The manager owns the missing iOS26 acceptance environment decision. Task remains
  incomplete until required evidence exists. Package evidence cannot close app/UI
  obligations. Affected suites include SkillStoreAndImportTests, catalog controls
  in AgentSkillsExposureTests/ProductionSystemSkillsTests and Skills UI consumers;
  unchanged SDK/Host package tests are not rerun for this app-only source change.

Rollback uses the feature commits and original installed SKILL.md bytes. No read
migration changes those files. Changing/removing the dependency must be coordinated
with the manager's product links; it is not an in-place user-data migration.
