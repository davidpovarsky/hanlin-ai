# Original OpenClaw policy in Hanlin

Task: [SKILL-OPENCLAW-03](https://app.asana.com/0/0/1220546571007976).
Implementation checkpoint: 2026-11-18. Expanded native acceptance is pending;
the task remains incomplete until its original product/device gates pass.

## Exact source and boundary

The maintained build uses original OpenClaw [v2026.11.3](https://github.com/openclaw/openclaw/tree/847611dcaa3bf0e2783335f961dd1fd0580e4d9f),
commit `847611dcaa3bf0e2783335f961dd1fd0580e4d9f`. Its original MIT license is retained.
The whole application requires a newer Node version and a broad dependency graph;
it is not embedded or claimed as an isolated npm package. Hanlin keeps its original
Node 24.5.0 JITless engine and its existing Yams YAML parser.

`policy-pin.json`, `dependency-audit.json` and `upstream-pin.json` authenticate every
fetched source/test file by SHA256 and Git blob. `fetch-upstream.mjs --policy`
verifies the exact tag/revision and 89 unique pinned files. `--offline` verifies
the same cached bytes without network access.

`extract-policy.cjs` follows TypeScript symbols to retain 90 unchanged original
declarations in 21 modules. It records source spans and dependency closure. It
rejects unresolved runtime globals/imports and executable omitted module
initialization; no blanket side-effect suppression or hand-written replacement
policy is used. Original JSON5 2.2.3 and semver 7.8.5 are bundled with MIT/ISC
notices. There is no second YAML parser, desktop workspace loader, new execution
engine or new authorization service.

The generated ESM artifact has 17 original exports, 136257 bytes and SHA256
`d6cc833943108245a2a68fc85ff4d67bf50719ade36e52fc63c784afedf9d565`.
Only `node:fs`, `node:path` and `node:module` remain imported. The retained original
binary discovery fallback is never called: every evaluation supplies an explicit
fact callback. Inspection does not run an installer or imported Skill.

## Product integration

`SkillOpenClawProjection` encodes the original Yams document for the upstream
string/JSON5 frontmatter API. It preserves UTF-8 key identity and rejects duplicate
or complex keys, unsupported tags and nonrepresentable numbers. Original functions
own selection, disabled/bundled policy, requirements, secret-owner gating,
invocation flags, install hints and install preferences.

The thin `policy-probe.mjs` distinguishes absent, supported and unsupported
metadata. It evaluates the original predicate at both unknown boolean bounds, so
original short-circuit behavior determines whether an unobserved fact matters.
Unknown config facts never borrow OpenClaw's browser defaults; native observations
never borrow iSH/remote PATH facts. The existing SKILL_ID environment boundary
does not expose shared provider/Keychain secrets. Diagnostics contain names and
decisions, never secret values.

Runtime05 remains the only readiness/engine/ExecutionPlan authority. Source and
environment signatures invalidate policy after source, engine, package, environment
or enablement changes. Eligibility and install hints never claim execution success;
only actual execution receipts establish that result.

The original catalog, load_skill, read_skill_resource, execute_skill_resource and
SDK prepareStep apply current policy. Model-hidden Skills are absent from the index
and discovery suggestions. Disabled/excluded loaded Skills leave subsequent
instruction context. Independently discovered tools retain their original Tool
catalog and Host approval. Manual Skill Center actions honor user-invocable
separately from disable-model-invocation. The native view shows requirements,
unknown facts and validated installation suggestions without installing anything.
English, Hebrew and Chinese labels follow SkillL10n.

## Reproduction and evidence

Build tools only; no upstream lifecycle scripts:

```sh
npm ci --ignore-scripts --no-audit --no-fund --workspaces=false
npm run fetch:policy
npm run build:policy
node --jitless --test Tests/policy.test.mjs Tests/policy-probe.test.mjs
```

Build stages exact app resources and checks Swift compile-time artifact identities.
Provenance records source, declaration, test, tool/dependency and resource hashes.

Portable evidence: official Windows Node 24.5.0 JITless passed all 11 adapter/policy
cases, including 28 invocations/64 assertions from unchanged upstream test bodies.
Coverage includes original metadata/install validation, runtime predicate,
selection, disabled/secret-owner/bundled policy, invocation and install preferences;
controls cover unknown facts, native/iSH separation, invalid metadata, dynamic
install/removal and no execution claim. The same in-process harness also passed
portably without Node's child-process test runner.

The native probe runs that exact artifact/test closure in the original embedded
engine and records challenge, identities, actual cases, duration and Node memory.
Five native app tests also cover Yams, source/enablement changes, actual SDK
continuation and shared instruction ownership. A focused XCUITest imports a real
archive, checks original-engine compatibility, shows valid install hints and
rejects manual invocation without executing imported code. These new Apple tests
are NOT_RUN at this source checkpoint. Portable timings/RSS are not physical
iPad startup or memory acceptance.

The earlier import-free requirements probe and six-case/native evidence remain
separate; their prior pass does not establish expanded policy parity. Original
Markdown/YAML-loader and filesystem/workspace tests excluded from this extraction
are listed with reasons in `generated/policy-original-test-selection.json`. Yams
remains the native parser; the whole OpenClaw loader/application is outside scope.

## Update and rollback

Upstream changes update pins deliberately, reauthenticate bytes, rerun initializer
and dependency audits plus original parity, rebuild resources, then rerun affected
native/product acceptance. Unexpected declarations, imports, initialization,
exports, test-framework calls or resource hashes fail closed. Do not suppress
contract checks to admit a release.

Rollback reverts pipeline, Swift adapter/call sites, generated resources/provenance
and focused tests together to the previous reviewed commit. Imported source and
user data are not migrated or rewritten. No automatic CI trigger, main merge or
distribution publication is introduced.
