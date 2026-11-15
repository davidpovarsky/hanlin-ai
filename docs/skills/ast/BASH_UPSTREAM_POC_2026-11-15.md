# AST04 original Bash parser proof

This slice produces passive syntax facts from supplied UTF-8 bytes. It does not establish
an installed dependency, executable file, permitted operation or Runtime readiness. The
production build graph is unchanged: owned source is behind `HANLIN_SKILL_ANALYSIS_POC`,
enabled only by the disposable proof. Product integration awaits the shared SkillFormat
document and Runtime05 source/engine ports. No C, grammar, wrapper or replacement Bash
parser is copied into Hanlin.

## Exact original dependencies

| Original repository | Exact tag | Authenticated revision |
| --- | --- | --- |
| [SwiftTreeSitter](https://github.com/tree-sitter/swift-tree-sitter/tree/0.25.0) | 0.25.0 | `08ef81eb8620617b55b08868126707ad72bf754f` |
| [Bash grammar](https://github.com/tree-sitter/tree-sitter-bash/tree/v0.25.1) | v0.25.1 | `a06c2e4415e9bc0346c6b86d401879ffb44058f7` |
| [Tree-sitter Core](https://github.com/tree-sitter/tree-sitter/tree/v0.25.10) | v0.25.10 | `da6fe9beb4f7f67beb75914ca8e0d48ae48d6406` |

The original Bash manifest requires the wrapper from0.25.0. The wrapper's original manifest
requires Core `upToNextMinor(from:0.25.0)`, admitting0.25.10 and excluding0.26/0.27. The Bash
generated parser declares language ABI15; Core0.25.10 supports13 through15. The proof verifies
all three resolved versions, Git revisions and official URL identities before compiling. At
runtime it queries `ts_language_abi_version`, checks the Core compatibility range and invokes
the original `Parser.setLanguage`; manifest/source inspection alone is not native evidence.

The wrapper's release marked latest on2026-11-15 is0.10.0 atf97df585296977d8fcaf644cbde567151d1367b8,
14commits after0.25.0. It does not satisfy the Bash manifest's wrapper-version requirement,
despite requesting the same Core minor range. This POC deliberately uses the satisfiable
original0.25.0 tag and records that tradeoff; it does not silently patch manifests, change URL
identity to the former ChimeHQ repository, or force latest Core0.27.2 into an older wrapper.
Review the14 intervening wrapper commits before product adoption. Prefer an upstream manifest
correction for a future upgrade; retain all three prior pins/lock and revert them together for
rollback, with ABI/fixture/native validation. Upstream licenses remain in the resolved sources;
the proof records original manifests/license hashes without vendoring them.

## Semantics and limits

The actor creates one original parser per invocation. No parser/node/tree escapes actor
isolation. UTF-8 read blocks preserve native UTF-8 byte offsets and columns; the wrapper's
String convenience uses UTF-16 and is deliberately not used. Reports carry source SHA256,
file/line/byte span, finite reasons, confidence and the three upstream revisions/actual ABI.

Literal command names, shebangs, sourcing, immediate interpreter script operands, `cd`,
redirections and Python `-m` module syntax are findings. Commands inside functions/branches
are conditional syntax, not proof of execution. Pipelines retain individual command nodes.
Quoted strings/heredoc data do not become commands. Dynamic command names, expansions,
globs, evaluation and malformed syntax remain explicitly unknown/partial. Import/module
names are never guessed to equal a distribution name. Shell aliases/functions, interpreter
option resolution and referenced-file traversal are unsupported; reports expose these limits.

Bytes, visited/pending nodes, depth, findings, parser time and report-cache count are bounded.
The original wrapper's cooperative timeout is supported by the exact0.25 Core; it is not a
hard process RSS limit. Cache keys include file identity and source SHA; budgets/pins are
immutable per actor, only complete reports are cached, and raw source is not retained there.
Caller-owned bundle traversal, aggregate budgets, manifest interpretation, environment
availability/version resolution and authorization remain separate responsibilities.

## Validation contract

`prepare_bash_proof.py` is read-only on Windows. `--output` copies exact owned source/test
bytes to a fresh directory outside the checkout on macOS. Original SwiftPM packages resolve
there with exact tags and authenticated SHAs; no product PBX/project/lock is edited. The manual
`skill_ast_bash` route performs fresh native macOS tests plus unsigned generic iOS simulator
and device compilation with minimum deployment26.0, preserving original source hashes,
manifest, resolved lock, upstream audit, toolchain, raw xcresult and phase durations.

Six XCTest methods cover20 Bash fixtures, UTF-8 Hebrew/emoji locations, an importable `.sh`
that must neither be read nor executed, finite hostile-input budgets, invalid UTF-8 and
cancellation, and SHA/file-sensitive bounded caching. Twenty Bash fixtures are not the task's
full mixed Bash/Python/TS acceptance corpus. iOS runtime execution, embedded Python3.14 AST,
existing embedded Node/TypeScript Compiler API, dependency manifests/native add-ons/binary
version availability, SkillFormat metadata adapter, product importer/store/UI and physical
device memory remain NOT_RUN or pending their actual owner contracts. No full-app run is
needed to prove this isolated parser slice.

Initial local checks: owned Swift syntax parse, Python proof-plan generation and Bash syntax
check only. Native compile/tests remain NOT_RUN until an actual retained run passes.
