# Scripting Integration Gates

Status: implementation authorized on 2026-08-24; gates remain evidence-based
and close only when their pass criteria are demonstrated.

## 1. Verified repository facts

- Authorized current baseline ID:
  `scripting-compat-2026-08-25-0b7b8e715573`.
- Aggregate SHA-256:
  `0b7b8e715573ffc1656f530d9eba6cc019e6742294392278edbee812bd45a1c9`.
- 999 baseline files, including the five current declaration files exported
  together by Scripting on 2026-08-25. Vendored declaration bytes are immutable;
  the preceding 2026-07-22 baseline remains documented in `BASELINE_HISTORY.md`.
- Reference compiler metadata pins TypeScript 7.0.2 with strict mode,
  `ESNext`, CommonJS, classic JSX, `createElement`, and `Fragment`.
- Embedded RuntimeCore lock pins TypeScript 6.0.3.
- Generated compatibility records classify all 2,440 approved symbol records:
  60 partial and 2,380 not yet implemented, with no planned/unknown state.
- Current TypeScript runtime supports one-source compilation and full project
  compilation endpoints, but that is not evidence that Scripting declarations,
  JSX runtime, module resolution, host APIs, or lifecycle are compatible.

## 2. Compiler and runtime policy

TypeScript 7.0.2 is the authoritative compatibility/typecheck lane on the host
and in CI. TypeScript 6.0.3 in NodeMobile is the authorized on-device
project-emitter lane. The two never share identity or cache claims. Contracts
distinguish typecheck compiler, emitter, bundler, runtime engine, hashes and
options. TypeScript 7 is not claimed to run on iOS.

Original TS/TSX/JS runs under `scripting-jsc`; QuickJS is `hanlin-quickjs`, a
separate constrained Hanlin runtime. Node and Python are trusted worker
profiles. Shell is a brokered capability service. Entrypoints persist the
choice; no engine fallback is permitted.

## 2.1 Traceability

| Gate | Current state | Closing evidence |
| --- | --- | --- |
| SG-0 | Closed | Owner authorization and `HANLIN_FULL_SCRIPTING_EXECUTION_PLAN_HE.md` decisions |
| SG-1 | Closed locally | Baseline and generated-resource drift checks pass deterministically |
| SG-2 | Implemented; full evidence pending | dual compiler provenance is typed and NodeMobile 6.0.3 is connected to install; deterministic real-package smoke passes, while full project installation evidence under Xcode remains |
| SG-3 | Implemented; verification pending | Typed wire, lossless values, limits and deterministic tests exist; randomized Xcode round trips remain |
| SG-4 | Partial | Safe preview, on-device compile, atomic install, rollback and recovery exist; complete real-package lifecycle evidence remains |
| SG-5 | Partial | typed profiles, persistent live JSC ScriptUI sessions and QuickJS limits exist; broader lifecycle, runtime-v2, worker and Xcode leak evidence remain |
| SG-6 | Partial | Capability brokers and Apple adapters exist; real-package revoke/expiry/bypass evidence remains blocked |
| SG-7 | Partial | Live ScriptUI hooks/events/navigation/presentation and generic extensions exist; parity, extension, device and full real-fixture evidence remain |
| SG-8 | Partial | Multi-tool schemas, routing, structured results and cancellation exist; production-package and approval/progress evidence remain |
| SG-9 | Implemented; verification pending | Atomic generations, recovery and stale-integrity isolation exist; Xcode migration/device evidence remains |
| SG-10 | Blocked | Full run `32794988662` passed the current tests, compilation, IPA validation and Simulator launch; one fixture is missing, four supplied packages have source diagnostics, physical-device and complete real-package acceptance are absent, and performance is unmeasured |

## 3. Gates

### SG-0 — Owner scope approval

The owner authorized the full execution plan, including foreground Script apps,
assistant tools, ScriptUI, system-service brokers and generic extension hosts.
Unsupported symbols remain explicit and non-executable; declaration presence
does not grant runtime behavior.

**Pass:** approved context/API matrix and explicit unsupported list.

### SG-1 — Baseline integrity

Reverify all 999 files and aggregate hash; keep originals immutable; generate
overlays separately; record source/declaration/compiler hashes in the build.

**Pass:** deterministic clean-checkout verification and no target linkage of
reference-only files except approved generated resources.

### SG-2 — Compiler selection and packaging

Resolve 7.0.2 versus 6.0.3 policy; verify embedded iOS execution, package
integrity/license, memory/storage cost, program builder, diagnostics, source maps,
incremental cache isolation, JSX factory/fragment, CommonJS/module resolution,
JSON modules, and ESNext target/runtime feature support.

**Pass:** exact compiler/profile is shipped and identified; full project fixtures
compile deterministically on the actual runtime. One-shot snippet compilation is
not sufficient.

### SG-3 — Canonical values and wire

Implement the approved rich/JSON conversion contract, typed general wire
envelope, negotiation, sequencing, payload limits, request correlation,
heartbeats, cancellation, shutdown, errors, callback/object-handle lifetime, and
attachment handling.

**Pass:** cross-language golden/randomized tests, no silent lossy values, and all
message kinds have typed payloads.

### SG-4 — Package/app descriptors and installation

Map Scripting `script.json` and `ScriptMetadata` into canonical package/app/
entry descriptors without inventing missing identity, schema, capability, or
integrity. Define install/update/uninstall, source visibility/editability,
signing/integrity, storage namespace, and installed-provider identity.

**Pass:** validated fixtures, transactional install/rollback, and no absolute
path in portable descriptors.

### SG-5 — Lifecycle and isolation

Define script runtime session ownership, entry/context lifecycle, UI versus
background rules, nested `Script.run`, `Script.exit`, minimize/resume,
callbacks/handles, process/app backgrounding, memory/CPU/output/deadline limits,
workspace containment, module policy, and cleanup.

**Pass:** session state/cancellation/recovery tests and no child task or handle
leaks. A reference comment warning callers to invoke `Script.exit` is not a host
lifecycle guarantee.

### SG-6 — Permissions and system services

Map each reference `ScriptingApi` and every privileged declared API to canonical
capability definitions/scopes and enforced service gateways. `Script.requestAccess`
must use canonical request/decision/grant/revocation, distinguish no-presenting-
UI contexts, and combine Hanlin policy with Apple system authorization.

**Pass:** declaration is non-authorizing, direct service bypass tests pass,
revocation/expiry cancel active access, and unsupported APIs fail explicitly.

### SG-7 — Rendering and extension contexts

Only if UI contexts are approved: specify virtual-node/value schema, diff/patch,
event callbacks, accessibility, localization, environment values, navigation,
presentation, state restoration, unsupported modifiers, extension target and
entitlement ownership, and platform availability against the actual SDK.

**Pass:** context-specific render/interaction fixtures and explicitly requested
Xcode/SDK verification. Declaration names alone are not API availability proof.

### SG-8 — Tool provider integration

Register script assistant tools as provider-qualified canonical tools, reserve
deterministic `script__...` aliases, validate input/output schemas, use canonical
invocation/progress/cancel/result, and preserve native/MCP routing behavior.

**Pass:** collision, scope, result, cancellation, and model-loop parity tests.

### SG-9 — Persistence, migration, and recovery

Classify script source, user documents, settings, credentials, compiled output,
module cache, UI state, and diagnostics. Source/user data and secrets require
preservation; compiled output/cache rebuilds. Define update rollback and grant
re-evaluation on content/integrity change.

**Pass:** store fixtures, crash recovery, uninstall/reinstall, update rollback,
and no stale grant/cache reuse.

### SG-10 — Compatibility claim and release

Run the exact baseline declaration typecheck, approved example set, runtime API
fixtures, unsupported-symbol report, performance/resource tests, and requested
Xcode app verification on the exact commit/compiler/runtime bundle.

**Pass:** publish a versioned compatibility matrix distinguishing declaration
accepted, typechecked, runtime implemented, behavior tested, and unsupported.
Only those passing all applicable columns may be called compatible.

## 4. Resolved implementation decisions

- Scripting requires an isolated, exact TypeScript 7.0.2 compiler lane; the
  embedded TypeScript 6.0.3 RuntimeCore compiler is not a substitute.
- Foreground apps, multiple assistant tools, native ScriptUI, Widget, App Intent
  and Live Activity contexts are designed; unsupported extension contexts fail
  explicitly.
- Grants are local, capability- and integrity-scoped, time bounded where
  applicable, revocable, and combined with Apple system authorization.
- Package identity, integrity, atomic generation changes, rollback, quotas,
  runtime limits and versioned compatibility claims are encoded as contracts.
- Generic Apple extensions consume signed App Group snapshots and enqueue resume
  commands; they do not compile or execute untrusted source.

Until SG-2 and SG-10 pass, the new Scripting pipeline is not a release-ready
runtime or a claim of full API compatibility. Existing legacy runtime behavior
is not evidence that these gates passed.
