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
