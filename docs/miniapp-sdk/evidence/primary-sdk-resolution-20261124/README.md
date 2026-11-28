# Original SDK package resolution — primary Mac evidence

## Result and boundary

The original attempt6 MiniApps and AI product builds both completed with exit0 on source bd6da170da7936fe3c5353ddaf8b25c97477a380. Both products were signed, installed and first-launched, and their shared app group was observed. Acceptance then stopped before the52 selected cases because the original modular-search authoring build loaded conflicting declarations from the supplied SDK, the checkout, and an ancestor installation. The retained build report contains16 diagnostics. The52 application cases and physical-device acceptance remain NOT_RUN in this evidence set.

The correction makes the supplied SDK authoritative for its canonical package names in TypeScript module/type/config resolution, Expo Metro resolution, NativeScript import emission and NativeScript package-body copying. SDK-owned nested dependencies retain their original search order inside the supplied graph. Noncanonical project aliases and extra project dependencies retain their existing resolution. Canonical aliases are deliberately governed by the host's original package identity. Strict checking and declaration-body checking flags are unchanged.

## Actual focused proof

On the same primary Mac, the unchanged public CLI copied into an owned proof directory ran the original modular-search source against the original extracted shipping SDK. The first candidate module (SHA1928091c166895c98a6527ddb2c28fad2ccde56dd698497e5d80781d0d4d58a8) completed its build with exit0 in13.067seconds and zero diagnostics. It produced an actual archive and Metro source map:831 sources, including818 node_modules sources, all inside the supplied SDK. The existing positive archive is retained on the Mac at the path recorded in focused-proof-state.json.

The collector initially assumed a flat source map and stopped after the successful build with KeyError 'sources'. The original error state is retained. The collector then read the actual indexed map sections and continued the negative check without rerunning the successful build. The public validator rejected a modified source with exactly TS2322 at index.ts line1; strict checking stayed enabled and skipLibCheck stayed false.

The final module SHAaecc8c0ba732396a637a7d7eda8864f7bdc5b3acbe0894a640c5e9c2e8ac1cb9 additionally aligns NativeScript emission/package copying and bounds missing canonical config subpaths. The actual primary-Mac regression used the real supplied TypeScript compiler, controlled package fixtures, and the public authoring operation: baseline0PASS/3FAIL/0SKIP, final3PASS/0FAIL/0SKIP. The generated NativeScript ESM package executed its fixture graph in Node and returned sdk:nested:project:alias, proving canonical package bytes, SDK nested dependencies, noncanonical aliases and extra project packages stayed consistent.

receipt.json records exact unchanged Expo/runtime operation/native-presentation function hashes and the unchanged module/type resolver block between the positive and final candidates. Both actual project configs have no extends. The remaining changes are covered by the final focused regression. This reuses the positive proof by its applicable input/code closure; it does not mislabel the earlier whole-module hash as the final candidate.

## Provenance

All22 raw evidence members are individually hashed in receipt.json. Compressed logs and the positive candidate source are lossless gzip with raw hashes recorded. The actual Node version is24.5.0. The TypeScript package metadata says6.0.2 while its API reports6.0.3; both identities and the exact library SHA are recorded separately.

The final patched Host must still be regenerated through the original Host producer, copied into both applications, incrementally built/installed, and exercised through the original52-case route. A successful source CLI proof alone does not establish that the shipping apps contain the corrected Host.
