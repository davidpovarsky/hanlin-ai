# Original Yams Skill metadata integration

Task: [SKILL-YAMS-02](https://app.asana.com/0/0/1220546710401425).
Package/API implementation: `485933ba`; evidence preflight correction: `78c8880e`.
The manager approved `exact: "6.2.2"` adoption in `76fffd08`, retaining the original
Yams source commit for upstream update-tool discovery. App integration is `bedecb5a`
plus the selected-source regression control in `727f67b6`.
Source follow-up `a5202ee3` rebases sliced Data before document-relative indexing.
The EOF-body editor follow-up is `e44c57cf`. Both are real source changes; earlier
native passes remain historical, and all affected package tests freshly executed
for the final source as recorded below.
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

Validation of the final package source:

- EXECUTED_PASS: [Apple run43757913093](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43757913093),
  exact source `e44c57cf348b1037baa8416277a3414d7e93b805`,22 actual xcresult identities/
  27 parameter-expanded invocations on EACH macOS, iOS26 and iOS27. All66 platform
  executions are fresh; none of the earlier20/21 identities is reused for this source.
  Xcode26.6/Swift6.3.3/SDK26.5 and Xcode27.2/Swift6.4.2/SDK27.2 use Swift language6.
  Both iOS jobs compile the real package with deployment26 and execute on their
  actual selected runtime. Exact devices/runtime builds and job timing are retained.
- Raw artifacts14179715088 and14178408435: complete SHA256 digests/ZIP CRCs verified,
  each nine source hashes authenticated against the exact Git SHA and source tar.
  All actual case identities, parameter children and outcomes verified. Both actual
  native raw locks equal the checked-in exact-version lock, SHA256
  `0ce944410a619261329435970fb8f81509687140af7dff3a134e8aa1efae6d9a`.
  Original Yams archive bytes match across both toolchains. See
  `evidence/skill-yams-native-43757913093.json`.
- EXECUTED_PASS: Windows Swift6.3.3 package22 identities/27 parameter invocations,
  including nonzero-index Data slices and adding instructions after an EOF closing
  fence without rewriting the header. The generic Data-slice indexing fault was
  reproduced in a standalone Foundation probe before correction.
- RESOLVED_ONLY_PASS: actual Mac43755833008 at76fffd08,0 tests. SwiftPM's semantic
  graph records a single original Yams requirement `exact:[6.2.2]`; real raw lock,
  tag→peeled commit, previous/new source and target graphs are retained. Original
  Upstream01 checker7aeace65 also passed unchanged from ignored scratch. Its textual
  regex is not semantic manifest proof; actual SwiftPM resolution/graph supplies that
  proof. See `evidence/skill-yams-resolution-43755833008.json` and pin-check ledger.
- Historical evidence remains separate: original40 native executions43754353738
  passed while its workflow failed for unavailable26; initial43754160901 preparation
  failed with0 tests;26-only43756155889 booted successfully but a redundant post-boot
  inventory lookup timed out before testing. The lookup was removed. All-platform
  21-case run43757074472 subsequently passed, before the EOF editor follow-up.
  These records are not substituted for the final fresh22-case proof.
- Scoped app Swift syntax parsing and diff checks passed. These are not app-framework
  typechecks or executed app tests. NOT_RUN: actual app `SkillStoreAndImportTests`,
  including four controls `nestedMetadataSurvivesStoreSaveAndOverride`,
  `anchoredStoreEditDoesNotRewriteOriginal`, `zipNestedMetadataAndResourcesRemainLossless`,
  `catalogMetadataFollowsSelectedSource`. The manager's89f2caaf direct-Markdown passive
  preview method is preserved byte-for-byte. No app/Skills UI, physical-device or
  full-project CI success is claimed.
- OPEN: manager-owned focused adoption PR, app+unit product links, actual app lock
  and affected app Skills/catalog/UI checks. UPSTREAM01 owns the separate controlled
  update/rollback/failure demonstration. Task remains incomplete until required
  integration evidence exists. Proven SDK/Host package sources remain unchanged.

Rollback uses the feature commits and original installed SKILL.md bytes. No read
migration changes those files. Changing/removing the dependency must be coordinated
with the manager's product links; it is not an in-place user-data migration.
