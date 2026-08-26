# Scripting Compatibility Import Report

Baseline: `scripting-compat-2026-08-26-a91e6672cb47`

## Result

- Aggregate SHA-256: `a91e6672cb470fcd5c3185a29ed25832a187008de55e7acd40e4008331efc125`
- Source files inspected: 1005
- Source directories inspected: 0
- Imported files: 1005
- Imported bytes: 6019985
- Declaration files: 5
- Documentation files: 948
- Project-example files: 49
- Excluded files under approved roots: 0
- Reparse points discovered: 0

The canonical source mapping selects the root-level `dts/`, `docs/`,
`scripts/`, `tsconfig.json`, `package.json`, and `package-lock.json`.
The absolute import source is provenance only and is not a runtime dependency.

## Required files

| Source | Destination | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| `dts/scripting.d.ts` | `Original/Types/scripting.d.ts` | 456732 | `92155306822de8d1b3c9c31acd604ab562f46c69f0fa70a4cdced63c4a7a5259` |
| `dts/global.d.ts` | `Original/Types/global.d.ts` | 713964 | `d5ed4b23de93d9f5c93fcf372736f8288e436e117fa008cdd9ac69a2656a949c` |
| `dts/node.d.ts` | `Original/Types/node.d.ts` | 40903 | `05be426cfb2493524d8ef5a167f9e30128257457289b6c14a87a14c23d5f0602` |
| `dts/web-fetch.d.ts` | `Original/Types/web-fetch.d.ts` | 16789 | `d93cf87b1e46c33c6e672d3fc451f9cfa35f7bae490065b9a7f26b0b08d16938` |
| `dts/safari-ext.d.ts` | `Original/Types/safari-ext.d.ts` | 12670 | `b86c4909673f425deb596e67c328cacad2f43022aa12ece1a03aee0e464815ae` |
| `tsconfig.json` | `Original/Compiler/tsconfig.json` | 645 | `7e47c2c814a304249510be267cc93b0c5baa07c0d5441ea360d1a8fd8b3f62ee` |
| `package.json` | `Original/Compiler/package.json` | 319 | `4383cf89cc583bc07d0e1f8307d00a50e1ed25d6cb17180cf0a5db085b895256` |
| `package-lock.json` | `Original/Compiler/package-lock.json` | 12533 | `7be92767d776519208fd152ee1fc91ae8576b2671f4083c2aaad789485053eab` |

## Duplicate required-file candidates

Duplicates were resolved by the explicit canonical root-level mapping.
They were not imported as additional baselines.

| Name | Candidate | Same as selected | SHA-256 |
| --- | --- | --- | --- |
| `scripting.d.ts` | `dts/scripting.d.ts` | yes | `undefined` |
| `scripting.d.ts` | `recorded-alternative-1` | yes | `undefined` |
| `global.d.ts` | `dts/global.d.ts` | yes | `undefined` |
| `global.d.ts` | `recorded-alternative-1` | yes | `undefined` |
| `node.d.ts` | `dts/node.d.ts` | yes | `undefined` |
| `node.d.ts` | `recorded-alternative-1` | yes | `undefined` |
| `web-fetch.d.ts` | `dts/web-fetch.d.ts` | yes | `undefined` |
| `web-fetch.d.ts` | `recorded-alternative-1` | yes | `undefined` |
| `safari-ext.d.ts` | `dts/safari-ext.d.ts` | yes | `undefined` |
| `safari-ext.d.ts` | `recorded-alternative-1` | yes | `undefined` |
| `tsconfig.json` | `tsconfig.json` | yes | `undefined` |
| `tsconfig.json` | `recorded-alternative-1` | yes | `undefined` |
| `tsconfig.json` | `recorded-alternative-2` | yes | `undefined` |
| `package.json` | `package.json` | yes | `undefined` |
| `package.json` | `recorded-alternative-1` | yes | `undefined` |
| `package-lock.json` | `package-lock.json` | yes | `undefined` |
| `package-lock.json` | `recorded-alternative-1` | yes | `undefined` |

## Exclusions

No files inside the approved roots required exclusion.

The source-wide inventory also found non-approved roots and backup artifacts.
They are intentionally outside the canonical mapping. `node_modules`, `.bin`,
platform executables, archives, caches, editor metadata, temporary files,
and secret-bearing files are never copied.

## Compiler provenance

- Scripting declaration header: `1.1.1`
- Authorized workspace TypeScript package: `7.0.2`
- Hanlin embedded compiler version is recorded in `Generated/compiler-profile.json`.
- Compiler drift is a declared compatibility lane; it is not hidden.

## Determinism

File order, JSON key order, hashes, aggregate identity, indexes, and this
report are derived deterministically from the selected source bytes.
`--check` performs no writes and fails when source or repository output drifts.

