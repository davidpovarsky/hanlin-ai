# Original OpenClaw requirements probe — work in progress

Task: [SKILL-OPENCLAW-03](https://app.asana.com/0/0/1220546571007976).
This directory builds a diagnostic subset from exact original upstream TypeScript.
It does not define Runtime-05 readiness/ExecutionPlan or install/run any Skill.

Source audit on2026-11-15: latest non-prerelease
[v2026.11.3](https://github.com/openclaw/openclaw/releases/tag/v2026.11.3), commit
`847611dcaa3bf0e2783335f961dd1fd0580e4d9f`, published2026-11-10. The original MIT
license/copyright is retained unchanged. Full OpenClaw declares68 runtime and63
development dependencies, Node `>=24.16.0 <25 || >=26.1.0`, and a nightly TypeScript
toolchain. Its skill-related package export is `plugin-sdk/skill-commands-runtime`;
an independent published eligibility npm package has not been established.
The full application is not a compatible lightweight dependency for Hanlin's
embedded Node24.5.0.

The original `src/shared/requirements.ts` is an isolated import-free module. Its
entire original file is compiled by the upstream-selected esbuild0.28.2, targeting
Node24.5. The generated artifact is1520 bytes with zero runtime dependencies.
`upstream-pin.json` records exact tag/commit/Git-blob/SHA256 identities. Fetch rejects
retargeted tags/source drift; build rechecks every cached byte and rejects an
unexpected dependency closure. Generated provenance records source/tool/artifact
hashes. There is no manually copied Swift/JS eligibility implementation.

The original exports are `isOsRequirementSatisfied` and
`evaluateRequirementsFromMetadataWithRemote`. Inputs are original callbacks for
binary/env/config facts and explicit local/remote platforms. Outputs retain the
original `required`, `missing`, `eligible`, `configChecks` fields. `eligible` is the
original conditional predicate result, never a Hanlin readiness/execution proof.
`always` clears missing runtime requirements while OS remains a hard boundary.

The development memory adapter evaluates one explicit fact scope at a time. Native
and iSH snapshots cannot fill each other's missing binaries. Unknown observations
remain listed as unknown. Absent metadata may produce upstream `eligible:true` but
never establishes execution verification. Unsupported metadata, including an
unsupported merge reported by the Yams owner, yields no upstream result. The app's
single Yams document contract remains authoritative; this adapter parses no YAML.
It is not a new Runtime interface and is not wired into app selection or dispatch.

Selection/disabled state, OpenClaw secret-owner state, install-hint normalization,
tool visibility, and Hanlin readiness are not covered by this pure module. The full
`loading/config.ts` additionally reaches desktop filesystem binary discovery,
OpenClaw config/SecretRef state, bundled-source policy and frontmatter helpers.
Its `frontmatter.ts` install parser is private and its public metadata path goes
through OpenClaw's string/JSON5 manifest normalization, semver and Markdown parser
dependencies. The reproducible [dependency experiment and ADR](ADR-original-subset.md)
records78 parsed original modules and17 unresolved external import paths, including
YAML and desktop Node APIs. It is a partial graph, not a closed executable bundle.
No equivalent Hanlin engine or Runtime-05 API is invented to conceal the gap.

Build tools only (no upstream lifecycle scripts):

```sh
npm ci --ignore-scripts --no-audit --no-fund --workspaces=false
npm run fetch
npm run build
node --jitless --test Tests/requirements.test.mjs
```

Run from this directory. `fetch` requires authenticated `gh`; it reads public exact
source only. The original five upstream test bodies/assertions are compiled unchanged
and executed against the built artifact through a narrow test-framework shim
(5 tests/16 assertions). The shim supports only the assertion methods those fixtures
actually use and rejects unsupported async evolution. Desktop controls also cover
scope separation, unknown facts, absent/unsupported metadata and dynamic facts.
An initial harness assertion-count expectation15 failed after all original assertions
passed; corrected16 and reran only that affected wrapper. Other five controls had
actually passed and were not rerun solely for the count correction.

Exact official portable Windows Node24.5.0 has also executed all six in-process
cases with `--jitless`, including the original five tests/16 assertions. It remains
portability evidence only. `native-probe.mjs` prepares the same cases for an actual
embedded Node24.5.0 probe without Node's child-process test runner. The original
NodeMobile sample compiled successfully against the existing authenticated native
framework in run43766595877; simulator cold boot timed out before any embedded
case ran. Native execution, physical iPad startup/RAM, complete policy parity and
app integration are NOT_RUN at this checkpoint.
Measured diagnostic-process timings/RSS must not be presented as physical iPad or
full Hanlin startup/performance evidence.

The dependency audit can be reproduced separately without executing its output:

```sh
node audit-dependency-closure.mjs           # fetch only pinned audit blobs as needed
node audit-dependency-closure.mjs --offline # verify cached bytes and exact graph
```

This audit is a build-time investigation, not a runtime dependency or second YAML
parser. Source drift and a changed observed graph fail closed.
