# Candidate SDK export authority for a missing C linkage annotation

Status: manager-authorized narrow contract3 candidate implementation; candidate
producer implements contract3; integrated Apple validation is pending. No runtime,
full SDK, combined SDK/Host/Expo or consumer acceptance is established.

## Observed failure and actual evidence

Full SDK run43753113119 at8131a767 rejects
`AVCaptureTimecodeCreateMetadataSampleBufferAssociatedWithPresentationTimeStamp`
before output publication. Actual C and C++ signatures, calling convention,
qualifiers and recursively measured record layouts are equal. Their actual
external symbols differ. Actual API model equality has not yet been established
for this function; it remains a required gate.

Read-only source run43753540748 and focused compiler/link run43753808737 at
860e6678 retain exact SDK27.2/Xcode27B52/arm64 iOS27.2 Simulator inputs. The real
`AVCaptureTimecodeGenerator.h` line99/offset6652 declares this function without
`AVF_EXPORT`. Header SHA256 is
`bb74610a80523338eb765c952fd9a1205f56d4a59cec02dfd9326d9dc26dbc22`.
The real AVBase macro expands to `extern "C"` only when actually used in C++.
No header, macro, root or declaration was replaced in these controls.

Both locked LLVM20.1.8 and installed Apple Clang21 compile both grammar objects.
Their AST JSON and undefined object symbols agree exactly. Both ObjC links pass;
both ObjC++ links fail with the Apple linker diagnostic that the C symbol exists
in AVFCapture and the declaration may be missing `extern "C"`. The exact SDK
AVFoundation.tbd target block reexports that C symbol from AVFCapture for
arm64-ios-simulator. No matching C++ export was found in those retained blocks;
complete target-specific reexport closure must still be checked before authority
selection. The stub SHA256 is
`c03d0a38f0f7dd1aaaaa35aa2d7ccd9492bd5367afe4c28851730c9212fb856e`.
All53 compiler/link artifact files hash-verify with0 mismatches; result SHA256:
`57ffd6b707ccb6e682ea43452d4906dee43f49175ea1dceaae4b93108f8121bf`.
No resulting executable was invoked. Successful static linking is not evidence
that the API can execute in an installed app or on an iPad.

## Proposed narrow rule

Only a duplicate external C function from the same physical, immutable public
SDK framework declaration can be considered. First prove canonical owner,
source location/bytes, complete original API model, calling convention,
qualifiers, recursive signature/layout and availability equality. Only the
actual external binding may differ. Exclude explicit asm labels, aliases,
non-SDK/project/Expo declarations and all non-function entities.

Read the original framework stub with the installed LLVM TextAPI reader. Resolve
its complete reexport closure for the actual architecture/platform; bind every
physical file/hash and exact deployment triple. Only one reachable exported C
binding and zero reachable exported C++ bindings can select the actual C-owned
model. Keep both AST findings and bindings and the explicit export-authority
selection reason; do not describe differing bindings as ABI-equivalent.
Both exports present, missing/ambiguous C, absent/wrong-target/unparseable stubs,
unresolved reexports, source drift or unproven model equality remain fatal.

Retain every original pass-A root and actual model. A complete pre-merge model
graph must map each original A node either to itself in the retained graph or
to a retained authoritative node through an explicit proof. Cyclic, missing,
kind-changing and otherwise unproven routes are fatal. Store the coverage and
route ledger in the final bound receipt before any output publication.
The original serialization format and production default remain unchanged.

## Counterexamples and pending acceptance

Native export prototype run43754381698 failed to compile because its isolated
host invocation lacked the C++ SDK search path. No counterexample executed.
A focused rerun corrects the host SDK/compiler invocation. The prototype uses LLVM20's original
TextAPI parser against actual immutable SDK stubs and then derives in-memory
counterexamples: both genuine symbols exported, two C export owners, missing C,
wrong target and an unresolved reexport. No SDK file is mutated. This prototype
is not connected to the metadata producer and cannot relax its guard.

Before candidate merge acceptance: prove those counterexamples, implement and
test all-A route coverage, prove actual API model equality, publish the precise
selection contract and bind the compiler/link/export evidence. Then rerun only
affected actual controls/model gates and the failed full SDK operation. Strict
DTS, all Host/Expo export/selector coverage and actual VM consumption remain
separate obligations. Unknown dependency impact requires a rerun.

Actual focused rerun43754812889/2cacebfa passes all6 native export cases. It
resolves the complete target closure across5 reachable libraries and3 physical
SDK stubs (AVFoundation, AVFAudio, AVRouting), selecting only the C export.
All6 artifact-manifest files hash-verify with0 mismatches; result SHA256:
`54062c771ff42ab3729d04a5313f45f300d49b727e574a8f3754ac95cca908e5`.
This test used the original LLVM20 TextAPI reader. The same implementation is
now shared with the candidate producer; the integrated affected slice must
recheck it after that extraction.

Contract3 candidate scope is explicitly pinned to the actual header SHA and its
three malformed C function declarations. Each requested authority operation
requires four real compiler/grammar AST/object/link controls per declaration,
with immutable compiler/resource/source dependencies. Exact unchanged evidence
may be REUSED_VERIFIED_STATIC_BINDING_PROOF only after full fixture/helper,
argv, normalized target and dependency verification; execution is not claimed.
Every raw C/CPP binding stays in the receipt. All model/ABI/availability checks
run before choosing export authority. Unsupported declarations stay fatal.
The public model/module remains AVFoundation. The reexport implementation name
is evidence only; no private framework dependency, module or API is introduced.

Integrated run43756153599/e5c8c671 compiles the new producer and passes all13
focused+transaction cases, all31 original model comparisons and the6 shared
export counterexamples. All220 control manifest files verify with0 mismatches.
Original-A coverage proves33,015 actual graph nodes:14 kept directly and33,001
explicitly mapped,0 missing. The31-module native peak is2,146,385,920B,9.980s.
The targeted SDK operation fails before publication because Driver reports
`ios27.2` while actual AST TargetInfo reports `ios27.2.0`. Compiler identity and
full raw argv match. Its12 object compilations pass;6 C links pass and6 C++ links
are rejected for the exact3 source declarations. Those static proof passes are
separate from the failed metadata operation.

The next affected fix compares LLVM Triple architecture/vendor/OS/environment,
object format and VersionTuple OS versions; LLVM VersionTuple equality explicitly
treats omitted zero components as zero. Raw requested target argv stays byte
exact, and sysroot must equal the bound physical SDK. New native counterexamples
reject a changed deployment version and environment and accept only explicit-zero
formatting. Binding proof may erase only the symbol name: formal linkage and
visibility remain exact, with derived counterexamples from a real AST ABI object.

Actual1191af99/run43757087726 passes13 model/transaction controls, strict31
original models,9 export/target controls and the genuine SDK authority slice.
All220 model-control and6 export-control manifest files verify with0 mismatches.
The3 actual SDK functions select C authority with raw differing bindings kept;
public model owner is AVFoundation.AVCaptureTimecodeGenerator, no private module
is added. All34,151 original A graph nodes are covered:14 retained and34,137
mapped,0 missing. The slice produces2,282,320B metadata and36 declaration files;
strict generated TypeScript remains NOT_RUN. Static compiler/link controls from
e5c8c671 were REUSED_VERIFIED_STATIC_BINDING_PROOF after unchanged inputs checks;
they did not execute again in this run. Slice result SHA256:
`5ba4a0644b2202d3dd90413865a83c09ec6b0c89423bcaf040681d9652cfcecc`.
Observed RSS at receipt construction was2,299,068,416B; producer time22.188s.
Those metrics preceded final receipt rendering and are not full process peaks.

Before full SDK widening, the candidate now enforces the4GiB measured RSS budget
also after model merge, binary/YAML/TypeScript writers, lifetime postflight and
complete final receipt rendering, before publication. Receipt RSS includes its
own bounded pure rendering; elapsed-time phase is explicit and the probe records
the whole metadata child-process duration. This budget-path change requires an
affected model/SDK slice run. The separate9-case export test implementation,
fixtures and transitive code did not change; an explicit verifier reuses its
original pass only after complete source/compiler/library/environment and SDK
fixture hashes match, reporting REUSED_VERIFIED_PASS and new execution NOT_RUN.

Budget-scope run43758215868/7115b997 passes13 fresh model/transaction cases,
strict31 existing models and the actual SDK slice. The unchanged native9-case
export pass is REUSED_VERIFIED_PASS from43757087726 after935 original compile
inputs plus exact image/compiler/libraries/environment/SDK fixture checks.
All220 fresh control and1 reuse-receipt manifest files verify with0 mismatches.
The slice binary stays byte-identical (SHA5427fad1…674e); all34,151 A models
remain covered. Measured whole metadata child process25.732s; measured peak
through complete receipt rendering2,291,236,864B, below4GiB. The native receipt
states the exact time/RSS measurement phases; no final acceptance test rerun was
performed solely for acceptance. Model-merge observed peak1,949,958,144B versus
401,932,288B after the two actual AST/model collections. Full SDK is the next
new input scope, with the same source-identical tool image and static binding
proofs reused only after complete input verification.
Slice result SHA256: `db2f31f08505f229aa37469f75725b217a26691dc5de99b4033e0f28155bfe82`.

Full SDK43759466180/a7931c6b remains FAILED, with no publication. Both actual
collections completed (55,819 CPP/55,165 ObjC top-level models), observed peak
1,546,616,832B after collection, metadata child89.783s. The next first conflict
is public Accelerate.vecLib.thread_api BLASGetThreading. Actual binding, return
ABI and original no-argument model match. The inspector omitted C calling
convention because it queried FunctionProtoType only; Clang FunctionNoProtoType
also inherits actual FunctionType::getCallConv.

The affected candidate now reads that actual common FunctionType field for both
direct functions and callbacks. The original pinned TypeFactory explicitly
encodes FunctionNoProtoType with only its return type. Raw prototype versus
no-prototype facts remain different, with an unknown C declared-parameter count.
Only CPP known-empty versus C no-prototype return-only original subencodings can
match, after complete original model and all other ABI/availability/binding
proofs. Disposition is PROVEN_ORIGINAL_NO_PROTOTYPE_ENCODING_OBJC_AUTHORITY;
sourcePrototypeTypesEquivalent=false, and no extra-argument promise is made.
Actual CPP direct/callback argument additions remain fatal. New15-case native
controls include both negative cases, and the genuine Accelerate header/root
joins the affected SDK slice before any full SDK retry. Export exceptions remain
exactly the3 pinned AVFoundation declarations; none is broadened.
