# Standalone Developer Kit authoring — SDK19 / attempt 19

The original production CLI and authoring module successfully validated and built Expo and NativeScript packages using only an isolated copy of SDK19 and the declared Node/Python prerequisites. Six actual Oracle invocations matched their expected outcomes: four successful validate/build commands and two deliberate TypeScript rejections. This evidence covers standalone authoring and archive creation; native installation and execution of these Oracle-generated archives are `NOT_RUN`.

## Production and SDK provenance

The two CLI files are exact production copies, unchanged between consumer source `d4a0b115b106d4250ea40ad66153d5156847a07c` and SDK producer `a2c8a1b1be746461272ba77254603304567c309d`:

| Production path | Bytes | SHA-256 |
| --- | ---: | --- |
| `Scripts/MiniApps/miniapp.mjs` | 4,101 | `1c256c00392c626a54ebee2abe3ededaa792c5bfa6dd9b6c5aceb89be84e5b30` |
| `AI_HLY/Downstream/RuntimeCore/Node/Host/miniapp-authoring.mjs` | 50,327 | `fa5121902e231d5d44ad08bf47699784fd4d0bc2a98102f3a156e6e4ae79b9b9` |

The kit preserves their relative import layout beside `MiniAppSDK/`. Its SDK index is `MiniAppSDK/miniapp-sdk.json`. The exact SDK export is SHA-256 `1bf347311b9547054725f8674419a11b3c502a4994feb6dbd9283c3af7400210`; the manifest is `4505c28495d8b6ecd1073254e0e395adcc898cc02dd1d40699591f51db4dee92`. All 25,670 SDK files and the complete SDK file set remained unchanged after execution.

## Actual results

The six invocations ran on 2026-11-25 from 18:01:40 to 18:05:48 UTC, using Node 24.22.0 on Linux arm64 and Python 3.12.3. Complete command arrays, sanitized environments, stdout, stderr and syscall traces are retained in the proof archive.

| Operation | Exit | Result |
| --- | ---: | --- |
| Expo validate | 0 | Successful; diagnostics empty |
| Expo build | 0 | Original Metro/Expo archive created |
| NativeScript validate | 0 | Successful; diagnostics empty |
| NativeScript build | 0 | Original compiler archive created |
| Invalid NativeScript validate | 1 | Expected `TS2322`, `index.ts:36:14` |
| Invalid NativeScript build | 1 | Same expected diagnostic; no archive or build stage created |

The invalid source assigned a string to a number. Its real compiler diagnostic retains code, category, message, filename, line/column and end position. Expo used compiler 6.0.3, `strict=true` and `skipLibCheck=false`, including dependency declarations. NativeScript used compiler 5.9.3, `strict=true` and its original `skipLibCheck=true`; dependency declaration internals were skipped, while authored code remained checked.

The generated Expo archive is 1,949,117 bytes, 14 members, SHA-256 `b43e974a15b3c3a6b7775438da038d1607e2a464eba1774bc43d27cecd03e58b`. The NativeScript archive is 7,817 bytes, 16 members, SHA-256 `36c89d84a0f8105f0449f0b237ac2134a834a8acb9ea669b34ee11ad13c42ea2`. Both passed CRC validation and retain source, compiled output, authoring metadata and successful validation reports.

## Standalone boundary

No production code or SDK bytes were changed, no npm installation was used, and no Internet connections occurred. Complete traces show no repository/worktree access and no successful external dependency loads. Optional ancestor package probes remain in the raw traces as failed lookups. Node, Python's standard library and operating-system libraries were the declared system prerequisites.

The compact two-file CLI payload is preserved inside the proof archive at `payload/Hanlin-MiniApp-Authoring-CLI-2026-11-25.zip` (15,285 bytes; SHA-256 `a76b7cc57fc4ff8b2dae653226f095eb136afc91b97785e306378c096ea5b793`). The English command reference and optional maintainer export recipe are retained as raw proof; the recipe is AST-verified and was not executed. The user kit's Hebrew guide is maintained separately.

## Retained evidence

`SDK08-Standalone-Authoring-Proof-2026-11-25.zip` is the original 4,404,863-byte proof archive, SHA-256 `357827dad828dea02aa422523df8cc460222bfb1b7e5fc84c02ddde12bb4cb16`. It contains 63 members: 62 files listed by its receipt plus that receipt. It preserves complete raw traces without expanding them in Git or duplicating the SDK.

`delivery-receipt.json`, `verification-summary.json` and `proof-receipt.json` are unchanged copies of the original records. Their original relative paths refer to the isolated evidence root or matching paths inside the ZIP; `manifest.json` maps them explicitly. This folder's `receipt.json` records every other file's exact bytes and SHA-256.

This result does not replace or predict the separate full52, NativeScript five-runtime or OS-notification native gates.
