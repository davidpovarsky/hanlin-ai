# Original OpenClaw subset boundary

Status: maintained original-source extraction implemented; expanded native/product acceptance pending.
Owner: SKILL-OPENCLAW-03 / SDK-Host. Runtime-05 owns readiness, engine choice and
ExecutionPlan. This decision does not authorize a merge or distribution.

## 2026-11-18 decision update

The historical direct-bundle rejection below still applies to loading the entire
OpenClaw graph. Alternative 2 is now implemented as a maintained source extractor:
90 unchanged declarations in 21 modules, explicit symbol closure, omitted-initializer
rejection, exact JSON5/semver pins and original licenses. The policy is 136257 bytes,
SHA256 d6cc833943108245a2a68fc85ff4d67bf50719ade36e52fc63c784afedf9d565.

Selected original frontmatter/selection/config/invocation functions now connect
through Yams, the original Node job boundary, Runtime05, catalog, Skill tools,
SDK continuation and Skill Center. No function body was ported to Swift or replaced.
Always supplying observed native binary callbacks prevents desktop PATH discovery.
Material unknown config/binary facts remain unknown. Existing Skill environment
isolation excludes shared secrets. Original secret-owner/bundled-selection policy
is retained and tested; Hanlin invents no upstream config or SecretRef values.

Portable Node24.5 JITless evidence: 11 cases contain 28 unchanged upstream test
invocations and 64 assertions. The same in-process harness passed portably. New
native app/UI acceptance is pending; physical iPad startup/RAM and live product
gates remain open. See README and the continuation acceptance receipt.

The statements below preserve the 2026-11-15 experiment and then-open proposal as
decision history. They do not describe the current implementation.

## Decision supported by current evidence

Keep building the complete original `src/shared/requirements.ts` from the pinned
OpenClaw release, with its original tests and license. It has no runtime imports,
accepts callbacks over in-memory facts, and provides useful requirement diagnostics.
Its `eligible` output must remain conditional source data. It cannot establish
Hanlin execution readiness, tool visibility, enablement or install support.

Do not load the broad original skill loading/config/frontmatter entry points into
Hanlin yet. The direct bundle experiment below is not a closed, memory-only
subset. This is evidence against that direct packaging path, not proof that all
future source extraction is impossible.

## Reproducible dependency experiment

Source: OpenClaw `v2026.11.3`, commit
`847611dcaa3bf0e2783335f961dd1fd0580e4d9f`. The root package declares Node
`>=24.16.0 <25 || >=26.1.0`, beyond the existing embedded Node24.5.0. Its68 runtime
dependencies are not a lightweight compatibility claim for that embedded runtime.

`dependency-audit.json` pins every source byte read by the exploratory bundle,
including Git blob and SHA256. `audit-dependency-closure.mjs --offline` verifies
the cached source and exact observed output without executing it. Omit `--offline`
to fetch missing pinned blobs through `gh`. No upstream lifecycle scripts run.

The experiment selects original `shouldIncludeSkill`, `isSkillEntrySelected`,
`resolveSkillsInstallPreferences`, `resolveSkillManifestMetadata` and
`resolveSkillInvocationPolicy`. Esbuild0.28.2 reads78 source modules, retains53
input records and produces43,871 bytes **before unresolved external dependencies**.
The size is not an install/runtime footprint. Only normalization-core workspace
imports are resolved in this experiment; other workspace packages and third-party
packages deliberately remain external. The ledger records those17 distinct
external import paths. A complete dependency closure and executable parity of
these entry points are NOT_RUN.

Concrete reasons to keep this path out of the production subset:

- `loading/config.ts` applies disabled, secret-owner and bundled-source policies
  before its runtime predicate. Its env check reads process/config secret state;
  the default binary callback reaches filesystem PATH discovery and caches.
- `shared/config-eval.ts` contains useful pure functions alongside filesystem
  discovery. Its runtime predicate short-circuits; the separate requirements
  diagnostic collects missing facts. These are distinct original APIs.
- `discovery/agent-filter.ts` also imports agent configuration resolution, pulling
  workspace/config/home-directory helpers into the broad import graph.
- `loading/frontmatter.ts` combines the private install-spec parser with Markdown
  frontmatter parsing. The latter imports `yaml@2.9.1`; introducing a second YAML
  parser would break Hanlin's single Yams authority.
- The public manifest path accepts an embedded JSON5 string, not a Yams node. It
  brings `json5@2.2.3`; original npm install-hint validation also uses
  `semver@7.8.5`. A generic object-to-string conversion is not established parity.
- Retained source includes global singleton/config/home-directory initializers;
  external Node imports include fs, path, os, async_hooks and worker_threads.
  No claim is made that every retained function performs I/O, but the direct
  artifact does not meet the import-free, explicit-fact boundary.

## Alternatives and next contract

1. **Current original predicate plus Runtime-05-owned policy (proposed).** Retain
   original bins/anyBins/env/config/os/always diagnostics. Runtime-05 must publish
   the authoritative input projection and product policy before wiring. This does
   not satisfy full OpenClaw policy parity by itself; disabled, install hints and
   tool visibility remain explicit missing obligations.
2. **A maintained original-source extractor for additional functions.** A future
   extractor may select unchanged declarations plus their exact dependency closure
   and record the extraction/tool/source hashes. It must prove that omitted module
   initialization does not alter behavior and preserve upstream fixtures. Manually
   copying bodies or marking every dependency side-effect-free is not that proof.
3. **Whole OpenClaw application.** Rejected for this integration: different Node
   floor, broad dependencies/state and duplicate YAML ownership. No new engine or
   Node upgrade is authorized by this task.

The thin projection needs one explicit native **or** iSH fact scope, requirement
names and observed booleans only, explicit platform, and a supported/absent/
unsupported metadata distinction. Unknown observations remain unknown. An absent
manifest or unsupported Yams merge cannot become verified readiness. No secret
values, Skill execution or approval prompts belong to this probe. These are
constraints for the owning Runtime-05 contract, not a newly invented public DTO.

## Acceptance still required

The original five test bodies/16 assertions and five additional diagnostic controls
have run on portable Windows Node24.5.0 JITless. Native evidence is tracked separately
in the README and CI artifacts; a portable pass cannot satisfy that obligation.
Full original disabled/install/tool-visibility parity, upstream-change parity,
actual app integration, offline product behavior, and physical iPad startup/RAM
remain required. SKILL-OPENCLAW-03 stays incomplete while these are missing.

Update and rollback use the existing pin/build pipeline: retain the prior revision,
generated artifacts and provenance together; update the source pin deliberately;
review changed source/export/dependency/test semantics; rerun affected original
parity and native obligations. A byte/hash mismatch fails rather than silently
accepting a changed contract. No automatic workflow triggers are introduced.
