# Passive Python and TypeScript syntax helpers

Runtime05 registers these trusted helpers with the existing embedded engines and supplies
immutable source bytes/file identity/cancellation. They accept memory input and return the
existing `SkillSyntaxReport` JSON shape. They do not own SourceEvidence, ExecutionPlan,
package installation, engine selection, dispatcher/Host routes, grants or readiness. The
shared Swift provenance now permits absent Bash-specific fields and carries the actual
engine version instead of inventing grammar ABI/revisions for Python/TS.

Python uses original standard-library `ast.parse`; source is never imported or executed.
Literal imports retain module names (`PIL`, `sklearn`), without guessing a distribution
(`Pillow`, `scikit-learn`). Relative/dynamic imports, aliases and evaluation/native-library
calls expose unsupported/unknown interpretation. Conditional imports stay conditional.
Runtime registration must preload this helper and its trusted stdlib before Skill cwd or
sys.path changes; invoking it as untrusted Skill code is not the analysis port. The helper
reports its real interpreter version. Host3.12 tests do not establish embedded3.14 grammar.
See the original [Python AST declarations/UTF-8 positions](https://docs.python.org/3.14/library/ast.html).

TypeScript accepts the original6.0.3 compiler already pinned in the Host lock. It uses public
`createSourceFile`, `createProgram`/syntactic diagnostics and node traversal with a memory-only
CompilerHost: no ts.sys/default host, libs/config discovery, filesystem or import resolution,
plugins, emit, code execution or import of analyzed modules. Import/export/require and type-only
references retain original AST semantics; dynamic specifiers/loader indirection remain unknown.
`.node` references identify syntax only, never available native add-ons. UTF-16 compiler offsets
are converted once to original UTF-8 bytes, including Hebrew/emoji/CRLF. Builtin `node:buffer`
`isUtf8` validates a private input copy; fatal TextDecoder is avoided for the no-ICU embedded
runtime. See the original [Compiler API](https://github.com/microsoft/TypeScript/wiki/Using-the-Compiler-API).

Both helpers bound input, nodes/pending work, depth, finding values/count and traversal time,
checking owned cancellation. Parsing itself is synchronous: post-parse deadline checks plus
input bounds are not a hard parse interrupt, process/RSS limit or proof of physical-device
latency. Runtime05 owns host lifecycle/cancellation and aggregate bundle evidence. No parser
tree/source is cached here. Runtime/package/compiler/Skill changes must invalidate any
caller-owned cache. No analyzed-source side effect may be replayed on a fallback engine.

Reproduce portable checks without installing another product runtime:

```powershell
py -3 docs/skills/ast/prepare_host_compiler_proof.py
npm ci --prefix build/ast-ts-proof --ignore-scripts --no-audit --no-fund
py -3 -B docs/skills/ast/test_python_helper.py
node --test docs/skills/ast/test_typescript_helper.mjs
```

The temporary proof lock contains the exact TypeScript entry/integrity from the EXISTING
Host lock, not a new product dependency. The tests include26 mixed source fixtures:12 Python
common-grammar cases plus one3.14-only template (NOT_RUN on3.12), and13 TypeScript cases.
Further checks exercise canaries, compiler IO hooks that throw on use, malformed UTF-8,
Hebrew/emoji/CRLF, cancellation, budgets and native-add-on/type-only facts. Native Swift tests
decode the actual host-generated helper JSON with its actual host versions; decoding is not
embedded execution.

Current portable execution: Python3.12.5 four methods passed (12 common fixtures;3.14 template
NOT_RUN); Node22.17.0/TypeScript6.0.3 four methods passed (13 fixtures). Embedded Python3.14,
embedded Node24.5.0 JITless, iOS Runtime registration/cancellation/performance, dependency
manifest interpretation, authoritative module/distribution/version mapping and full product
acceptance remain NOT_RUN. Shared SkillFormat root/ranges/format findings must be retained:
nil convenience fields, tagged/merged/ambiguous metadata are unknown interpretation, not
evidence of zero requirements. No parallel YAML/readiness parser is introduced here.

## Dependency manifest tranche

`hanlin_python_manifest.py` accepts immutable bytes and the trusted existing original
`packaging26.3` Requirement parser supplied by Runtime, not imported from Skill paths. Tests
use the already-vendored original wheel and record its SHA. Requirements retain original
PEP508 constraints/extras/markers/URLs without resolving, fetching or installing anything;
pip includes/directives/continuations and unsupported lines remain unknown and are not read.
The original [Requirement API](https://packaging.pypa.io/en/stable/requirements.html) parses
only declarations; it does not establish availability or module/distribution equivalence.

Original stdlib [tomllib](https://docs.python.org/3.14/library/tomllib.html) reads bounded
`pyproject.toml` bytes. It supplies values, not token spans: dependency findings deliberately
use the whole original document range at line1, UNKNOWN confidence and an explicit span reason.
No custom TOML lexer or invented exact token location is used. Project/optional/build
requirements are retained; dynamic metadata/build backends, extra tool/dependency-group
interpretation and Python version compatibility are unknown and never executed. Post-parse
node/depth/pending/time limits complement the pre-parse byte bound; they do not promise a hard
allocation/parse interrupt.

The same TypeScript compiler helper accepts strict `package.json`. Builtin JSON syntax
validation is followed by original compiler AST positions, preserving duplicate dependency
keys and reporting unknown rather than using a flattened last-key-wins object. Runtime/dev/
optional/peer constraints, engine ranges and bin paths remain declared syntax. Lifecycle,
native-build/platform/export/peer metadata stays unresolved. TypeScript `ts.sys` IO hooks
throw in both source and JSON tests; no lifecycle string or referenced binary is run.

`dependencyDeclaration` is distinct from imported `moduleReference`. `Pillow>=10` is an actual
distribution declaration; importing `PIL` does not create one. npm facts retain the literal
`name@specifier` form, including scopes/aliases/paths, with separate optional/development/
peer/engine reasons. Runtime05 owns authoritative version/platform/package-name resolution,
installed native modules/binaries and readiness. These facts grant no permission or execution.

Portable manifest tranche: Python3.12.5/packaging26.3 five methods and Node22.17.0/TypeScript6.0.3
five source+JSON methods passed. Raw source/test/lock/wheel/log hashes are in
`evidence/portable-manifests-2026-11-15.json`. Embedded engines/iOS remain NOT_RUN. A ninth native
Swift test decodes actual manifest helper JSON and checks declaration/import distinction and
source ranges; the changed enum/schema/fixture closure requires fresh native validation.
