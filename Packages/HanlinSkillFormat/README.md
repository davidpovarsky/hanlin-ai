# Hanlin Skill format

`HanlinSkillFormat` is a Foundation-only, Swift 6 document/metadata library. It uses
the original [Yams 6.2.2](https://github.com/jpsim/Yams/releases/tag/6.2.2), required as
SwiftPM `exact: "6.2.2"` and locked to `a27b21e0c81c5bf42049b897a62aaf387e80f279`.
The exact version is visible to upstream dependency update tooling. Yams and its original CYaml/libyaml
target retain their upstream MIT licenses. No upstream source is copied or forked.

```swift
import HanlinSkillFormat

let document = try SkillDocumentParser.parse(originalData)
let openClaw = document.metadata?["openclaw"]
let bins = openClaw?["requires"]?["bins"]?.sequence
let edited = try document.updating(
    name: document.name, title: document.title,
    description: "New description", instructionBody: document.instructionBody)
// Write edited.originalSource atomically only after a successful edit.
```

The one shared contract is `SkillMarkdownDocument` plus `SkillMetadataNode`:

- Original UTF-8 `Data`, frontmatter/body byte ranges and raw body are retained.
- Ordered tagged scalar, sequence and mapping nodes preserve unknown fields,
  nested values, complex keys and unknown tags. Scalar numbers retain their text;
  no Double conversion or untyped object constructor runs. Tags and scalar text
  use UTF-8 storage so Swift canonical Unicode equality does not merge values.
  This is Yams' representation tree: YAML merge keys remain tagged merge entries,
  not a flattened inherited dictionary. Consumers must validate/handle such tags
  explicitly rather than treat an unsupported mapping as empty requirements.
- `name`, optional `title`, `description`, `compatibility` and `allowedTools` are
  convenience views. `legacyStringFrontmatter` is an incomplete compatibility
  projection, never the metadata authority.
- `findings` report format compatibility only. They do not establish tool grants,
  package installation, execution plans or readiness. Runtime-05 owns readiness
  and execution planning; AST owns its analysis findings. Consumers must interpret
  the same immutable metadata rather than reparsing/flattening another manifest.

Compatible parsing preserves installed legacy names/missing descriptions while
reporting standards findings. Strict parsing rejects those findings. A directory
name is installation context and is not invented or checked by this document API.
The app's existing `hanlin.json` remains optional and is not the YAML authority.

Parsing first consumes original CYaml events for per-document byte, physical and
expanded depth/node/alias/text budgets, then calls original `Yams.compose` in
explicit UTF-8 mode for the value tree. It does not modify libyaml's global depth
setting. A second original token scan obtains exact scalar source spans for edits.
Character-index marks are mapped through the original Unicode-scalar/UTF-8 table;
the BOM/CRLF/Hebrew/emoji/combining fixtures assert the actual resulting bytes.
Cancellation and resource errors are distinct from malformed YAML.

Reading and no-op saving return the exact original bytes. Known-field edits replace
only original scalar tokens; body edits preserve the header and original newline
style. Original comments, unknown fields, nested metadata, tags and aliases outside
the edited field remain in their original source spans. Fresh fields/content use
the original Yams emitter for quoting/escaping. Removing a title retains its key and
comment with a YAML null value. The editor reparses and checks requested values
before returning new bytes.

Explicit limits: cyclic aliases cannot form this finite immutable tree. A changed
anchored known field is rejected with `unsupportedEdit`, because unknown aliases
could otherwise change meaning. Complex/aliased known keys without an unambiguous
native scalar span likewise refuse editing. Reads and exact no-op edits still
preserve supported original documents. Yams rejects duplicate mapping keys using
Swift equality, including distinct canonically equivalent Unicode keys; Hanlin
does not replace/fork that upstream rule. Markdown frontmatter closes at a
column-zero `---`; indented `---` in literal content does not close it. Source that
exceeds budgets is retained by the caller, never silently rewritten or flattened.

Portable verification:

```powershell
swift test --package-path Packages/HanlinSkillFormat
```

The focused manual Apple recipe is `Scripts/CI/IntegrationValidation/run_skill_format.sh`,
selected by `agent_sdk_session_only_proof` + `HanlinSkillFormatTests` in the existing
manual workflow. It retains the exact source archive, hashes, upstream source,
actual raw resolution, toolchain, destinations and xcresults. It selects macOS,
iOS 26 and iOS 27; unavailable installed runtimes remain explicitly blocked.
Package evidence does not establish app Store/ZIP/UI or live Runtime acceptance.

`HanlinSkillFormatResolveOnly` selects a real Mac resolution/graph/tag audit without
reexecuting tests. It compares the full Sources/Tests/fixtures and target/product/
platform graph against the original revision-pin evidence, and verifies both
upstream checkouts/archives and the remote peeled tag commit. Reuse is permitted
only for authenticated original passes with unchanged source/transitive closure,
test semantics/fixtures, compiler flags, toolchain/environment and runtime inputs;
the record must identify their original SHA/platform, never call them newly executed.
Missing/failed/uncertain obligations remain separate and require their own evidence.
