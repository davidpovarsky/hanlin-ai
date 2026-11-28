# Native import qualification and full platform suite

The actual macOS Swift runs at `167219a491a844ae838041f195c12abe9800dac3` passed both required boundaries:

- The focused command passed all **10 methods in 3 suites**: two immutable retained-archive regressions and eight ownership compatibility/negative controls.
- The original unfiltered parallel platform command passed the exact **619-method identity multiset**, with no failed or skipped methods and no controller stop. Its **13 product-summary rows** total 619. The **316 original parameter-start identities** were matched separately; they are part of the parameterized coverage, not 316 additional methods or a claim of 935 tests.

The 619-method inventory preserves the historical 603-method set and adds six typed-list codec methods, two retained-import regressions and eight ownership controls. Both executions retained their actual source and inputs unchanged. The independent root reviews are included verbatim.

## What the focused result establishes

The retained NativeScript archive passes the original package inspection and analyzer, with `canInstall` true and no error findings. Its prepared structure and existing runtime/core checks pass before Widget preparation. The retained Expo archive passes the original Widget preparation and artifact writer: the program is **5,915 bytes**, and the existing assertions verify preservation of foreground and editable source bytes.

The Expo regression covers that compiler/writer path. It does not claim current native-version admission, foreground Expo execution, an installed-store flow or OS rendering. The original artifact-size limit remains unchanged.

The eight additional methods cover dynamic imports, shared resource/module aliases, unrecognized published helpers, configured debugger source roots, incomplete or changed inventories, escaping/ambiguous resource copies, the original oversized-artifact rejection, and legacy or unrecognized authoring behavior. Internal fixture variants remain assertions within methods, without additional test-count credit.

## Prior failures remain part of the record

| Actual source | Passed | Failed | Observed boundary |
|---|---:|---:|---|
| `34dc92c1` | 0 | 2 | Widget preparation parsed retained NativeScript foreground TypeScript; the Expo Widget program was 8,997,211 bytes and the original writer rejected it. |
| `ed4a6207` | 2 | 8 | Both immutable regressions passed after the ownership repair. All eight new controls stopped at their fixture's missing required `actions` field. |
| `5baa01fb` | 7 | 3 | The required-field correction admitted the controls. Three positive rendering controls then exposed primitive values passed to the dictionary-only storage method. |
| `167219a4` | 10 | 0 | Two fixture calls use the existing scalar-capable storage method; the original Boolean/numeric expectations and all eight control meanings remain intact. |

No earlier packet or result was replaced. `history.json` and `raw-evidence-references.json` retain exact source, reconciliation, manifest and original-log hashes for each attempt.

## Exact executed commands

Focused qualification:

```sh
swift test --package-path Packages/HanlinPlatform --filter '(retainedNativeScriptSurfaceArchivePassesOriginalImportAnalysis|retainedExpoWidgetMaterializesWithOriginalArtifactWriter|HanlinWidgetInputOwnershipTests)'
```

Original full platform suite:

```sh
/usr/bin/swift test --package-path Packages/HanlinPlatform --parallel
```

The retained toolchain is Apple Swift 6.4 with Xcode 27.0, build `27A266a`, targeting arm64 macOS. The full controller retains its original 3,600-second phase bound and unchanged tracked test limits. Actual full execution ran from `2026-11-28T00:50:48.809556+00:00` to `2026-11-28T00:51:30.330907+00:00`.

## Source binding and limits

The complete `Packages` tree, including platform source, tests and resources, is byte-identical between the executed source and documentation base `575afd3e9f5bac1272169b59555ef4c73552b5f1`. File and tree identities are in `source-bindings.json`; exact method and parameter inventories are bound by SHA-256 in `results.json`.

This proof records macOS package execution. It adds no app, iOS Simulator, physical-device, signing, OS-surface, current SDK archive or Host-build PASS. The app-only editor equality change, SHA-256 `28058e1a2b8189a16e6a517d20e64db7ff76c9aebc6ddc120cde16963baa8c4c`, is outside this package run and remains separately uncompiled/unqualified here. The historical packed SDK was explicitly not current during these runs; subsequent SDK qualification belongs to its own receipt.

This documentation was assembled from immutable native evidence without rerunning tests. Complete logs, HTTP evidence, archives and native observations remain retained separately under the cited hashes.
