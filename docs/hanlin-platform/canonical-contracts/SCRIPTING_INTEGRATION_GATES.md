# Scripting Integration Gates

Status: implementation authorized on 2026-08-24; gates remain evidence-based
and close only when their pass criteria are demonstrated.

## 1. Verified repository facts

- Authorized baseline ID:
  `scripting-compat-2026-07-22-8d7d33d9369e`.
- Aggregate SHA-256:
  `8d7d33d9369ee555d15adf10c867abbfb85834eced7e7596a627b70ff627ff36`.
- 999 reference files; declarations, docs, examples, and compiler metadata are
  immutable originals.
- Reference compiler metadata pins TypeScript 7.0.2 with strict mode,
  `ESNext`, CommonJS, classic JSX, `createElement`, and `Fragment`.
- Embedded RuntimeCore lock pins TypeScript 6.0.3.
- Generated compatibility records currently say the reference APIs are planned,
  not implemented.
- Current TypeScript runtime supports one-source compilation and full project
  compilation endpoints, but that is not evidence that Scripting declarations,
  JSX runtime, module resolution, host APIs, or lifecycle are compatible.

## 2. Compiler policy

The selected product lane ships TypeScript 7.0.2 exactly for Scripting. The
current RuntimeCore 6.0.3 resource is not a Scripting compiler and cannot share
its cache. Compiler version, integrity, options, baseline, ABI, and context are
part of every descriptor, diagnostic, artifact, source map, and cache key.
Changing declarations, `skipLibCheck`, or `transpileModule` cannot establish
compatibility.

## 2.1 Traceability

| Gate | Current state | Closing evidence |
| --- | --- | --- |
| SG-0 | Closed | Owner authorization and `HANLIN_FULL_SCRIPTING_EXECUTION_PLAN_HE.md` decisions |
| SG-1 | Open | Clean baseline verification and generated-resource drift checks |
| SG-2 | Open | Shipped 7.0.2 compiler, deterministic multi-project fixtures, iOS verification |
| SG-3 | Open | Typed async wire, lossless conversion, limits, randomized round trips |
| SG-4 | Open | Safe import, canonical descriptors, atomic install/update/rollback/uninstall |
| SG-5 | Open | QuickJS lifecycle, isolation, cancellation, recovery, leak tests |
| SG-6 | Open | Capability mappings, grants, OS authorization, revocation and bypass tests |
| SG-7 | Open | ScriptUI and extension render/interaction/accessibility evidence |
| SG-8 | Open | Canonical Script tool routing, collisions, progress and cancellation |
| SG-9 | Open | Store fixtures, crash recovery, migrations and stale-grant/cache rejection |
| SG-10 | Open | Acceptance packages, compatibility matrix, performance and approved Xcode run |

## 3. Gates

### SG-0 — Owner scope approval

Decide the first supported execution contexts and API subset. Recommended first
context is a non-UI, manually invoked `assistant_tool` or explicit developer
execution with no device capability APIs, no nested `Script.run`, and strict
resource limits. Widgets, intents, notification, keyboard, control widget, live
activity, translation provider, and full SwiftUI-like rendering remain out of
scope until their targets/entitlements/lifecycle are designed.

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

## 4. Required decisions before implementation

- Compiler lane and whether embedded TypeScript upgrades to 7.0.2.
- First contexts and API subset.
- Whether nested scripts and UI rendering are in first scope.
- Permission prompt UX and local versus synced grants.
- Script package identity/signing/update policy.
- Workspace/storage quota and backup/sync behavior.
- CPU, memory, time, output, callback/handle, and stream caps.
- Which Apple extension targets/entitlements, if any, will exist.
- Compatibility claim wording and required fixture threshold.

Until these decisions and gates pass, Scripting is not a tool provider, app
runtime, platform service consumer, or executable contract source.
