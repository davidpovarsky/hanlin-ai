# Framework ownership and duplicate metadata inputs

2026-11-15 — [נועם | Runtime/SDK] [MAIN_SESSION], lease W1-001.
SDK-03 `1220373608755846`; INT-03 `1220374076374903` remain open.
Baseline: `ba7a5ba3ed9e8983cc47df532114079f64bff0b0`.

Current acceptance: **blocked on a complete Objective-C compatibility proof**.
Historical combined output43664215125 genuinely passed its output gates, but QA
rejected its error-bearing C++ role evidence and target mismatch. Corrected
source `cc15459c` fails closed. Latest focused run43673578445 failed on differing
CallInvoker alias bytes before combined generation; its SDK-only/context controls
passed. All43 eventual Apple cases remain NOT_RUN (24 previously build-blocked,
Host7 and observation12 not dispatched). See the latest checkpoint below.
The earlier checkpoints below remain historical evidence, not current acceptance.

App run [43650510166](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43650510166)
failed before all 15 selected tests. The public-header collector imported both
Products and PackageFrameworks copies of ExpoModulesCore. Sorting resolved paths
removed compiler search priority without removing physical duplicate inputs.

The collector now visits explicit framework search paths in order, then the SDK
standard framework root. A framework filename or top-level module identity has
one selected owner. Another physical copy is omitted from explicit imports only
when its complete Headers/PrivateHeaders and module-map file manifest matches
byte for byte. Each file's SHA-256, both framework paths and search priorities
are retained in the inventory. Differing content or missing files fails before
the generator runs; its conflict inventory survives temporary-directory cleanup.
Nested submodules and external module references do not claim global ownership.
Unique frameworks and existing public entry selection remain enabled. Clang
diagnostics, tool provenance and all eight required bridge symbols remain gates.

The two inherited dirty changes are included in this candidate: declaration
writer fixes for already-hidden properties and nullable blocks, and the actual
NativeScript SDK-shape characterization test. Neither is presented as a prior
native pass. The owner's untracked Expo MiniApp directory remains untouched.

## Initial checkpoint: impact and validation plan

Affected: public metadata discovery, the production wrapper, generated SDK
declarations and native metadata consumers. Runtime engine sources/archives,
HostServices ABI, package manifests, fixtures and workflows are unchanged.

- EXECUTED_PASS: four existing wrapper methods plus six new regression methods,
  `py -3 -B -m unittest Scripts.CI.Tests.test_nativescript_metadata_wrapper -v`;
  10 methods, 0.944s, Windows/Python. Synthetic framework fixtures verify file
  discovery and failure behavior; they do not prove Apple or VM behavior.
- Next: existing focused NativeScript SDK metadata workflow, compiling the actual
  metadata tool and Swift provider, checking declaration parity/negative cases.
- After focused proof: the exact 15 missing consumer selectors from the handoff,
  plus `actualNativeSDKGlobalAndPropertyShapesAreObservedWithoutInvokingUI()`.
  Each is affected or previously NOT_RUN; none is eligible for assumed reuse.
- Unrelated historical Core 305-second case: no rerun or fresh PASS claim.
- NOT_RUN: actual app/VM/UI, strict complete SDK typing and physical-device gates
  at this candidate checkpoint. Metadata proof alone cannot satisfy them.

Machine-readable results: `evidence/METADATA_FRAMEWORK_DEDUP_2026-11-15.json`.
Native execution results and exact source/run identities will be appended here.

## Actual native metadata result

Implementation `dd700c03e9fe9d22e95a031d4684275512ee6e6f` passed
[43654504526](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43654504526),
job 2m45s, Xcode 27.2/27B52, SDK 27.2, arm64. The actual rebuilt tool's source
and binary hashes match its provenance. System Python 3.9.6 ran the production
wrapper against the genuinely compiled Swift provider. All eight required
symbols are present, with zero Clang errors. SDK metadata remains byte-identical
(`dae58823…`), and the runtime-wrapper metadata remains `8c0809b1…`.
All 31 original/candidate UIKit/Host YAML files match; an invalid native SDK type
returns exit 1 with a genuine diagnostic. The actual provider declaration now
emits `onEvent: ((p1: NSDictionary<any, any>) => void) | null`, preserving its
callback and nullability. Complete strict SDK typing remains open.

Artifact `14137184091` is 28,346,655 bytes, GitHub SHA-256
`c3f0b902a56f1d07303f55a94b972ac055d97f6810d5ea56d7753a80d5551178`.
Raw downloaded evidence: `build/metadata-dedup-43654504526-artifacts/`.
The isolated probe inspected 285 SDK frameworks / 300 wrapper frameworks and
contains no physical duplicate ExpoModulesCore copies. Consequently it cannot
establish full-app deduplication or VM behavior by itself.

App follow-up [43654868788](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43654868788)
requests exactly 16 selectors (11 unit, 5 UI), preserving the previous 15 and
adding the SDK-shape test. The full baseline-to-candidate impact plan is retained
at `build/metadata-dedup-full-impact-plan.json`; the dispatch uses explicit
selectors and comparison base `dd700c03` without claiming baseline reuse.
The pinned Node/Python producer remains `42926628418`. No engine rebuild,
distribution or signing is requested.

## Actual app result and input-role blocker

Run 43654868788 FAILED during app build (simulator job 15m33s; baseline
compilation passed 2m40s). The simulator test step was skipped: **0/16 methods
executed**. Provider-summary success does not override this failure.

Its retained inventory contains 339 framework records: 327 selected owners and
12 byte-identical duplicate copies. All 12 complete input manifests were
compared after download. ExpoModulesCore's two 81-file manifests match SHA-256
`6cb6e803d96e5a8d5913230df4e85c17900ae84dc2ea5cc18868069ba0bbada9`.
The earlier-priority PackageFrameworks copy was selected; the Products copy was
omitted from root imports. There were no differing-copy conflicts. This proves
the duplicate-discovery correction on actual app inputs, not a successful build.

Artifact `14138215380`, 6,962,705 bytes, GitHub SHA-256
`cb3205f30dabb0d7666f19dcf14c50e28b2f023715f6f96161cd696d06d40661`,
retains the complete inventory, umbrella and actual diagnostics. Raw evidence:
`build/metadata-dedup-43654868788-artifacts/`. The next failure is 20 actual
Clang errors importing synthetic ReactCommon/jsi C++ headers as Objective-C
(`namespace`/`class` are unknown).

An ObjC++ attempt (`5ae5eb94`) preserved every root/header and used the project's
existing gnu++20 standard. Cheap probe
[43656411654](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43656411654)
FAILED in 2m21s: pinned Clang17 cannot parse SDK27.2 C++ builtins such as
`__builtin_clzg`, and the metadata generator cannot produce a jsName for a
CXXRecord. The wrapper rejected all eight absent bridge symbols and retained
28 Clang errors. No app retry was dispatched with that candidate.

Only that unsuccessful language change was undone. The wrapper and its test
file are restored byte-identical to dd700c03; all five code/test input hashes
again match the successful 43654504526 proof. That proof is consequently
**REUSED_VERIFIED_PASS** for the restored inputs, not a new execution. The
12-copy app discovery proof remains authentic; app/VM/UI/device gates remain
open. No diagnostics, SDK feature definitions, metadata serializers or API
declarations were suppressed to obtain a pass.

## Historical contract proposal (superseded below)

`Scripts/Expo/prepare-ios-dependencies.mjs` stages header-only modular shims
at lines 523–637. The actual ReactCommon/jsi shim headers and module maps
(5 + 8 files) match the local pinned copies byte for byte; neither shim has a
framework binary or any `@interface`/`@protocol` declarations. This provenance
supports a language-role distinction; absence of ObjC text alone is not a full
AST/API coverage proof.

Do **not** exclude the entire ModularFrameworks root: it also contains genuine
ObjC surfaces (RCTSwiftUIWrapper, React_RCTAppDelegate and react) and Yoga C
exports. Their existing search paths, owners and supported declarations must
survive. An explicit, narrowly scoped input-role contract should distinguish
the C++-only include dependencies from direct ObjC/C metadata roots, retaining
both shims in compiler framework search paths and recording their manifests
and role in the inventory. Unknown/changed inputs must not silently acquire an
exemption.

One candidate is an explicit language requirement on the two staged module
definitions, paired with a collector that honors that requirement for its ObjC
translation unit. Clang documents language requirements in its
[module-map requires declaration](https://clang.llvm.org/docs/Modules.html#requires-declaration).
This is a proposal, not an implemented exclusion or proof that the generated
module dependencies will compile unchanged.

The requested additional leases are the existing Expo staging script and
`Scripts/NativeScript/probe-sdk-metadata.py`, to construct a focused real combined
input proof before another full app run. No workflow/manifest/runtime ABI change
is proposed. The alternative is a separately scoped C++ metadata/compiler
migration; changing SDK macros, substituting SDK headers, or disabling errors is
not an acceptable repair.

The combined proof should use the existing pinned artifact/dependency staging,
the actual compiled Swift-provider header, and the real framework maps/headers.
Keep their paths/hash receipts and actual module/search order. It must prove
zero genuine diagnostics and retain the eight production bridge symbols plus
representative existing ObjC/C exports: EXExportedModule, EXModuleRegistry,
RCTBridge, RCTView, RCTAppDelegate, RCTSwiftUIContainerViewWrapper, YGNodeNew,
YGConfigNew and YGNodeStyleSetWidth. These names come from actual declarations;
their metadata presence is a **future obligation**, not an asserted pass.
Only after that proof should the unchanged 16 NOT_RUN selectors execute. The
Core 305-second case remains outside this tranche.

## Historical combined output and corrected application composition

Leases W1-004 and W1-007 extended the original scope. The input-role contract
is implemented; the preceding proposal and blocker describe earlier checkpoints.

The producer classifies actual owned declarations with the installed Clang C
API. A C++-only role requires positive AST evidence and an Objective-C-mode
compatibility audit. C/ObjC exports, mixed/unknown declarations and failures
retain public-root treatment. The forward-record/enum policy is bound to the
original NativeScript MetaFactory source `5d4569c1`; C linkage and Darwin
mangling are handled explicitly. Every receipt binds the producer, classifier,
metadata-tool policy, dependency lock, compiler library/arguments, framework
identity and complete header/map hashes. The consumer rejects changed or
unproven inputs. No header bytes, maps or compiler-search priority are changed.
Current receipt SDK/architecture is arm64 iPhone Simulator; other contexts fail
closed until genuinely classified for their own target.

Explicit module-map public headers take precedence over convenience headers,
which preserves Yoga's C API. Identical module-qualified copies of public headers
are mapped to their selected owner using a verified Clang VFS overlay. A mapping
requires matching complete public dependency trees; differing/missing trees,
ambiguous owners and unproven private-header context fail. The original LLVM17
Tooling invocation uses its public VFS overload because its convenience path
ignored `-ivfsoverlay`. The in-memory umbrella is inserted after cwd inheritance.
The original metadata serializers, format and compiler diagnostic gates remain.
These are build-tool patches, with no runtime-engine or project-manifest change.

[43664215125](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43664215125)
at `21a7394df7a43656a62229191b3b13a366835df6` **EXECUTED_PASS**, 4m38s,
Xcode27.2/27B52, SDK27.2, arm64. It stages genuine pinned Expo inputs and compiles
the actual Swift provider before running the production wrapper. Downloaded
binary/source hashes and role-receipt bindings match that historical source.

- Wrapper exit0, zero Clang errors, all eight bridge/Swift symbols present.
- All nine required Expo/React/Yoga names listed in the historical proposal
  are present, including YGNodeNew, YGConfigNew and YGNodeStyleSetWidth.
- Only ReactCommon, jsi and reactperflogger receive audited C++ include-only roles;
  their headers and search paths remain available to dependencies.
- 212 byte-identical header aliases cover22 verified complete owner/alias trees.
- SDK metadata is unchanged (`dae58823…`); all31 original/candidate UIKit/Host
  YAML files match. Genuine invalid SDK declarations still fail with exit1.
- Artifact14141631762:29,140,817 bytes, GitHub SHA-256
  `7fe09865f5800e809b0152e56f4168f732cc00b6541165e52b3111fddb5cd792`.
  Result JSON SHA-256 `1a8195a99a96a66cca183f5a6006e8af809b44fb379b15ae34621a7ab776c17f`.

The six preceding focused attempts failed honestly; the JSON records their
source/run/duration and specific findings. In particular, all bridge names alone
did not pass the strengthened Yoga obligation. The native proof is separate
from20 local regression methods (PASS12.407s, actual local libclang), Node syntax
checking, and actual app/VM execution.

Application composition `6837d0ae` removes the runtime's direct model/context
ownership. The AI-only integration keeps the existing model-selection,
credential-policy and store-publication statements, delegating to the existing
Assistant adapter. The internal publisher is synchronous `@MainActor throws`;
its public runtime wrapper remains async for compatibility. Deferred configure
work captures a service and generation and drops stale work before the atomic
commit. Nil preserves the existing explicit unavailable Assistant error.

Independent source QA closed both prior P2 findings. All eight composition cases
use an explicit Expo stub, owned temporary real extension store and deterministic
publication queue; default production initialization remains equivalent. The two
new regressions drain queued A→nil/A→B work and assert no stale or duplicate
publication. These are unit boundary checks, not real MiniApps bootstrap,
credential publication or stream-cancellation acceptance. The CI map change only
adds the new path/suite to the existing Assistant app_unit_tests rule.

Native follow-up [43665438077](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43665438077)
selects the original16 plus all8 composition cases, with comparison baseline
`ba7a5ba3` and the unchanged pinned Node/Python producer42926628418. The full
impact plan routes all changed paths without a full-validation fallback.
Execution was pending at that checkpoint; the actual failed result follows below.
Strict complete SDK typing and physical-device gates remain open. No engine rebuild, merge, signing or release occurred.

## Source QA limit and fail-closed correction

Independent QA rejected the six-code-file metadata packet for integration. The
actual compatibility audits had3 ReactCommon errors and1 each in jsi and
reactperflogger (C++ syntax/missing functional, tuple or memory). The prior
producer and consumer accepted those errors as an absence proof. They cannot
exclude a conditional public C/ObjC declaration after an incomplete parse.
Additionally classification used SDK27.2 while the real Swift provider used
minimum iOS27.0; matching SDKROOT/architecture alone is insufficient.

`a91c5309ebe7164a2e24861c0ee009620df54f24` corrects both producer and consumer:

- Incomplete/error-bearing compatibility audits, incorrect parser modes/flags,
  public/unknown declarations and changed transitive compiler headers cannot
  grant or retain a C++ include-only role. Old schema receipts are rejected.
- Schema2 records both actual grammar argument vectors and all observed compiler
  header dependencies. Real target-conditional C API fixtures distinguish27.0
  from27.2; matching SDK/architecture cannot bypass a deployment mismatch.
- Initial Expo preparation emits conservative public inventory. The wrapper
  recomputes classification from all final post-staging header/map bytes into
  per-phase receipts. It never refreshes stale hashes without rerunning audits.
- The existing launcher captures its own fully assembled ordered flags without
  executing the generator. A narrow adapter uses the actual deployment target
  instead of SDK_VERSION for the metadata parser triple. SDKROOT remains bound.
- This checkpoint replayed a staging helper and actual Node patcher. That replay
  proved incomplete; 685781e8 below replaced it with the complete production
  staging entry point. No signing or engine build step ran.

All26 local regression methods passed21.713s; Python and Node syntax checks and
`git diff --check` passed. These include incomplete audits hiding a non-C++ public
branch, malformed/unknown/mixed receipts, actual target-conditional declarations,
transitive dependencies, stale later staging, and actual adapter argument capture.

There is **no complete alternative proof for the unconditional C++ inputs yet**.
They remain public roots when Objective-C parsing fails. This correction does
not claim that the historical successful metadata output now passes source QA.
Focused replay43668027277 subsequently failed before generation; see the later
checkpoints below. No later full-app retry started.

Frozen app43665438077 at6837d0ae FAILED in build-for-testing14m24s with
`Framework input-role identity/headers changed: react.framework`; **0/24 methods
executed**, all NOT_RUN. Baseline/runtime compilation passed4m18s. Artifact
14141628849 is776,423 bytes, SHA-256
`16a13e3c57bf9dc245e6cca6ec8ba79202c882d38b17d9600b54039ddc1e008d`.
Existing later staging mutates the artifact header tree after the early receipt;
the new probe records the exact delta. The failed artifact did not retain that
final byte diff, so the specific changed-file list is not asserted retrospectively.

Separate Host/SDK correction `6c4d30c87b16635a53f168d37737d63e18c1d2bc`
uses validated canonical descriptors and foreground launch plans for installed
package discovery, recognizes explicit scriptingJSC in the existing engine
resolver, and removes Host filename hints. Disabled, invalid, nonforeground and
unknown/malformed runtime packages are not admitted. Compiled Swift discovery,
broker authority and data roots are unchanged. Independent source QA accepted
this correction. Its7 pure snapshot/discovery/catalog/launch-plan case bodies
parse on Windows; all7 Apple cases and actual installed-JSC UI remain NOT_RUN.
The eventual exact31-case plan preserves original16, composition8 and Host7;
it has not been dispatched while the metadata gate remains unresolved.
## Latest checkpoint: actual compiler context and remaining interface contract

Frozen source `cc15459cf6e5ee77f8afc989b81c6e8d20171038`, 2026-11-15.
The historical combined output remains withdrawn for source acceptance. Neither
that output nor representative symbol names establish complete public ABI coverage.

`685781e8` calls the complete actual `stage_modular_headers` entry point with
owned temporary SourcePackages/DerivedData, force enabled and signing disabled.
The optional signing parameter defaults to true in production. `d2553d9a` fixes
system Python3.9 annotation compatibility and binds schema4 staging stamps to the
exact signing mode. Legacy/unknown/mismatched stamps are rejected, and an old
stamp is removed before restaging so a failed unsigned mutation cannot preserve
a signed cache hit. Same-path unsigned→default and signed→unsigned→default
regressions use a signing spy; they do not perform real signing.

`cc15459c` captures the metadata tool's **effective** native compiler context,
after generator-owned flags and discovered include paths have been assembled.
The launcher argv alone omitted `-D__NATIVESCRIPT_METADATA_GENERATOR=1`, grammar
flags and internal include paths. Narrow dump/expected-context options in the
pinned tool use NUL-framed full compiler identity and ordered arguments. Dumping
returns before AST/emission; actual generation independently checks the expected
buffer before AST/emission. The wrapper separately binds launcher argv, cwd and
environment. Classification binds both this actual metadata frontend and the
selected classifier. Unknown or different frontend identities remain public:
Xcode Clang21 cannot prove the absence of branches exposed by metadata Clang17.
No LLVM, SDK, serializer, engine, vendor-header or feature-macro change was made.

All30 local wrapper methods passed in18.378s (`build/metadata-native-context-final-30-tests.log`).
These include conditional C APIs under the real generator macro, unknown/different
frontend identity, mutated consumer context, stale dependencies and signing stamps.
Python compilation, exact pinned-source patch application and diff checks passed.
These local checks do not execute Apple frameworks or runtime test bodies.

| Focused run / frozen source | Actual result |
| --- | --- |
|43668027277 / a91c5309|FAILED4m51s; recorded13 final header changes, then rejected CallInvoker alias bytes before combined generator/classification.|
|43669405381 / 685781e8|FAILED3m35s; complete staging succeeded (6731 files,8.985s), then Python3.9 `Path | None` import failed; fixed in d2553d9a.|
|43670588631 / d2553d9a|FAILED3m04s; complete staging succeeded (6731 files,6.439s), then CallInvoker alias guard stopped combined generation.|
|[43673578445](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43673578445) / cc15459c|FAILED3m00s; tool compilation and SDK-only/context controls passed; combined wrapper stopped at the unchanged alias guard.|

Latest actual evidence: Xcode27.2/27B52, SDK27.2, arm64, system Python3.9.6.
The tool identifies itself as Clang17.0.6; its retained binary SHA-256 is
`16619435fb1ea32da0ad94e467d4d9bdffe27ccb108effd435ae7e05475a57ac`.
Downloaded binary and build-patch source hashes match provenance. The real SDK
metadata exits0 with zero Clang errors and unchanged `dae58823…` bytes. All31
original/candidate YAML files match; invalid-type and effective-context-drift
negative controls both exit1. The actual context includes the generator macro
and internal `lib/clang/17/include` path. Its SHA-256 is
`7d7f3aeafefb7782b99779a5bd42695ae576cfeac7e967625936627e3709e55e`.
This proves context capture/verification on the SDK-only path, not C++ API absence.

The actual Swift provider compiles for `arm64-apple-ios27.0-simulator`, header
SHA-256 `cf655de3a171181605fb062db6e5e4776a7f1df43f92e63f6a16847c82c66c88`.
Complete final staging succeeds (6731 files,6.052s), retaining13 actual changes
in react.framework: React-umbrella.h and12 jsinspector-modern headers. The wrapper
then rejects differing CallInvoker bytes **before** combined argv capture,
classification and generation. Its combined compiler contexts are empty;
`symbolChecksStatus=NOT_RUN_NO_METADATA_BINARY`. False symbol entries in that
result mean unexecuted checks, not observed missing declarations.

Latest artifact14145501945:32,829,757 bytes, GitHub SHA-256
`0beeb152cf4d59323994898dda595e1485d6b3b057ef08693b80830289787966`.
Downloaded result SHA-256
`8bdf07516f291fc6040354da8a69b5d563a41baee6293efb92dd6eaa52e6998b`.
Raw evidence is under `build/metadata-effective-43673578445-artifacts/`.
Prior artifacts and their identities are retained in the machine evidence.
No watcher or full-app retry remains active.

### Bounded producer partition proposal — not implemented

The existing producer at `Scripts/Expo/prepare-ios-dependencies.mjs:1113` strips
`react/cxxstableapi` includes only from top-level modular headers. Nested aliases
retain them. For CallInvoker the difference is precisely the removed
`#include <react/cxxstableapi/UmbrellaGuard.h>`: modular SHA-256 `67f17c2a…`,
React carrier SHA-256 `6f8f8bcc…`. The actual pinned UmbrellaGuard exists; it
expresses the RN_STRICT_API/RN_UMBRELLA_CONTEXT/RN_BUILDING inclusion contract.
It is not evidence that the C/ObjC public surface is empty. Restoring producer
consistency must preserve that contract and its dependency closure.

Read-only comparison of actual retained inputs found10 differing alias pairs
across8 canonical files. ReactCommon CallInvoker/SchedulerPriority appear in
both React.xcframework and unified react.framework. Six jsi files also differ
in **NativeScript.framework**: decorator, instrumentation, jsi-inl, jsi, jsilib,
threadsafe. Those may represent a separate NativeScript C++ dependency version.
They must not be overwritten with RN headers or waived as equal merely because
their namespace and filename match. Hashes/full paths are in machine evidence.
The historical212-alias success did not examine the excluded C++ owner pairs.

The exact initial producer scope is19 headers plus3 module maps:

- ReactCommon: CallInvoker, SchedulerPriority, RuntimeExecutor,
  RuntimeExecutorSyncUIThreadUtils.
- jsi: decorator, hermes-interfaces, instrumentation, jsi-inl, jsi, jsilib,
  threadsafe. JSIDynamic is already excluded by the existing producer.
- reactperflogger: BridgeNativeModulePerfLogger, FuseboxPerfettoDataSource,
  FuseboxTracer, HermesPerfettoDataSource, NativeModulePerfLogger, ReactPerfetto,
  ReactPerfettoCategories, ReactPerfettoLogger.

These are generated from pinned RN0.88.0 ReactNativeHeaders.xcframework;
artifact SHA-256 `7d896249102e6f10faa76218caf4bd2b8d739d1b6e3d032181ac498b34884165`.
The dependency lock remains unchanged, SHA-256
`d9ded3b3d73b1d563d149e1456ffaf8d2bfecdf222ecca6657aafb10cc4ea536`.
Available evidence is the actual source/header/map inventory, positive C++ AST
counts,31 SDK/Host YAML comparisons and representative Expo/React/Yoga names.
**Missing:** an independently reviewed complete per-file C/ObjC declaration,
type/layout, constant, availability and linkage contract for these roots and the
separate NativeScript JSI variant. The error-bearing historical ObjC parse is
not a golden inventory. Neither `requires cplusplus` nor an empty guessed
inventory supplies this contract.

The smallest defensible next delta is a producer-owned projection helper and
reviewed per-file contract, connected only at existing staging hooks. Preserve
immutable original vendor inputs. Partition identified C++ constructs/includes
with `__cplusplus` guards while preserving every contracted C/ObjC declaration
and dependent type. Preserve the C++ token/AST/layout surface and distinguish
NativeScript's dependency ownership. Validate valid actual Clang17 ObjC roots,
context/contract drift rejection and C++ equivalence before combined metadata.
Exact additive helper/contract paths require a lead lease; no such header rewrite
or new helper is included in this frozen source. Unknown/mixed inputs stay public.

### Capability observation checkpoint

W1-008 source `bfe33506` provides observation over actual SkillStore/catalog and
native UserDefaults state. MCP selection mutations return committed affected
chat/mode scopes; stable per-scope signals avoid cross-chat/mode invalidation.
Absent selections and explicit empty selections remain distinct. Strict
`readSelection(chatID:temporary:)` propagates that request's load/read failure;
the legacy getter remains compatible. Temporary tests disable legacy migration
explicitly; production defaults, JSON schema, preference keys and authority stay.

All12 observation cases have only passed Windows Swift syntax parsing; their
Apple test bodies are **NOT_RUN**. The prepared43-case plan (original16 +
composition8 + Host7 + observation12) has not been dispatched. Consumer UI must
include chatID/mode/revision in task identity and discard stale completions;
no delayed UI execution is claimed. SDK-03, INT-03, full strict SDK typing,
actual VM/UI/device and release gates remain open. The owner's untracked
MiniApp directory remains untouched.
