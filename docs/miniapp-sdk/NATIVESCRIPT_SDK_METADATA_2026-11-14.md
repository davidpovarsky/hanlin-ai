# NativeScript SDK metadata evidence,2026-11-14

Actual [43629307234](https://github.com/davidpovarsky/hanlin-ai/actions/runs/43629307234)
at8fce2996 passed the focused generation contract on Xcode27.2/27B52,
iphonesimulator27.2, arm64. Job1m39s. The [original result and provenance](evidence/NATIVESCRIPT_SDK_METADATA_2026-11-14.json)
preserve all declaration hashes and the exact inputs.

- Inspected285 public-root frameworks and included207 public entry headers.
  Swift-only modules do not acquire invented ObjC declarations. SubFrameworks
  remains a dependency search path; UIKit imports its own internal dependencies.
- Actual10745446B metadata, zero clang errors, all five required UIKit/Host names
  present; metadata SHA256
  dae5882319e5c54af2719bc9bf4c799506773437bcf6a0a40bca5928e9774d2e.
- UIKit/Host declarations:31 YAML files byte-identical to the original pinned
  generator, both actually executed against the same inputs.
- Invalid return type:actual exit1; current Xcode clang syntax control:exit0.

Artifact14127228761,nativescript-sdk-metadata,18330020B; GitHub-reported SHA256
3b4e720e592de9906f35b00154565f0d2be2cbe7e1e312e44e6e0e01dd645e6c.
Downloaded result SHA256
672d03be9c9fe1324672e44d29505bbb192e192e263add3b63e3b9cd587bfe6c.
Downloaded compiler matches recorded SHA256
4bd55ad184e381aafff3c4fd57e9874c2a63ac4999ae2d03bc62a0012d49f7ef.

## Build tool and failures

Runtime remains9.1.0. The metadata compiler builds from source
5d4569c197810cdd4c1e02e7c16d42a01a77d5c0 and hash-verified upstream LLVM17.0.8
assets. The upstream trimmed bundle uses the same Apple LLVM source as17.0.6;
its CMake changes reduce linked libraries. Source/archive/CMake hashes are pinned
in build-metadata-tool.py. Upstream licenses remain in the extracted source.
The serializers and metadata format remain the original runtime's implementation.

Clang FrontendOptions.SkipFunctionBodies skips inline implementations, while
metadata consumes declarations and types. Actual31-file parity checks those
declarations. Preserving diagnostics and returning runToolOnCodeWithArgs failure
prevent a partial binary from passing. No SDK header, builtin or feature changes.

| Run | Actual result |
| --- | --- |
|43625309608|App build failed before all12 tests; Xcode resource headers alone did not fix modular parsing.|
|43627090749|Modular parser returned0 with298 errors and incomplete5414B binary; preincluded textual mode crashed.|
|43627751109|Explicit UIKit/Host input passed generation only.|
|43627918865|Ambient umbrella directly included implementation-only SDK headers;432 errors.|
|43628182968|Public framework umbrellas left18 Accelerate inline-body builtin errors.|
|43628945920|New compiler passed parity/invalid-type rejection, but full input had25 FocusEngine duplicates, also rejected by Xcode clang.|
|43629307234|Correct public entry roots:zero errors, complete required names,31-file parity and genuine negative rejection.|

## App adoption

The app wrapper stages public SDK/build-product framework headers, actual
CoreSupport headers and generated Swift interfaces, retaining module ownership.
A narrowly adapted original launcher preserves Xcode architecture/search/defines
while passing an explicit input before Xclang and selecting the verified compiler.
The wrapper retains actual input/header inventory, tool provenance, binary and
stderr, rejecting genuine errors even when all required symbols exist. Production
also requires the embedder and actual SwiftUI provider/protocol names.

The shared manual-workflow composite caches the tool by source/lockfile,
architecture and Xcode, saving only on a cache miss. App staging verifies its
executable, source-script hash, architecture and Xcode. The compiler/header helper
are included in the SDK inventory and affected-validation component.

**This focused pass is not app/Swift-provider/VM/device acceptance.** The next
app run selects the previously blocked12 cases plus shared Core, direct UIKit
and SwiftUI/lifecycle UI:15 total. They remain NOT_RUN until real matching
xcresult nodes pass. Local wrapper/parity8 cases passed0.138s and CI/router/cache
129 cases passed4.094s. Node/CPython producer42926628418 remains unchanged;
native-only reuse verification passes
d1e91cbfbc838b9a74c1127fe52eee87c2fec7ca220f29c99eab96ad45c43fd5.
The305s runtime test is unaffected. Full SDK-03/INT-03/INT-04, signing and physical
iPad gates remain open.
