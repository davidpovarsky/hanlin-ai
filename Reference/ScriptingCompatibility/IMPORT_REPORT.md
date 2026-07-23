# Scripting Compatibility Import Report

Baseline: `scripting-compat-2026-07-22-8d7d33d9369e`

## Result

- Aggregate SHA-256: `8d7d33d9369ee555d15adf10c867abbfb85834eced7e7596a627b70ff627ff36`
- Source files inspected: 2076
- Source directories inspected: 507
- Imported files: 999
- Imported bytes: 5918732
- Declaration files: 5
- Documentation files: 942
- Project-example files: 49
- Excluded files under approved roots: 1
- Reparse points discovered: 0

The canonical source mapping selects the root-level `dts/`, `docs/`,
`scripts/`, `tsconfig.json`, `package.json`, and `package-lock.json`.
The absolute import source is provenance only and is not a runtime dependency.

## Required files

| Source | Destination | Bytes | SHA-256 |
| --- | --- | ---: | --- |
| `dts/scripting.d.ts` | `Original/Types/scripting.d.ts` | 454206 | `0dd028697d487ae23ac5625e718fd8af0af0a3f7a295fb753f7a1a1d3277ede2` |
| `dts/global.d.ts` | `Original/Types/global.d.ts` | 702176 | `f3d06e3b200a0cc2f4e731b63c367f303f3ee879016d9bd25a892b1188d74b33` |
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
| `global.d.ts` | `dts/global.d.ts` | yes | `f3d06e3b200a0cc2f4e731b63c367f303f3ee879016d9bd25a892b1188d74b33` |
| `global.d.ts` | `‏‏תיקיה חדשה/dts/global.d.ts` | yes | `f3d06e3b200a0cc2f4e731b63c367f303f3ee879016d9bd25a892b1188d74b33` |
| `node.d.ts` | `dts/node.d.ts` | yes | `05be426cfb2493524d8ef5a167f9e30128257457289b6c14a87a14c23d5f0602` |
| `node.d.ts` | `‏‏תיקיה חדשה/dts/node.d.ts` | yes | `05be426cfb2493524d8ef5a167f9e30128257457289b6c14a87a14c23d5f0602` |
| `package-lock.json` | `package-lock.json` | yes | `7be92767d776519208fd152ee1fc91ae8576b2671f4083c2aaad789485053eab` |
| `package-lock.json` | `‏‏תיקיה חדשה/package-lock.json` | yes | `7be92767d776519208fd152ee1fc91ae8576b2671f4083c2aaad789485053eab` |
| `package.json` | `package.json` | yes | `4383cf89cc583bc07d0e1f8307d00a50e1ed25d6cb17180cf0a5db085b895256` |
| `package.json` | `‏‏תיקיה חדשה/package.json` | yes | `4383cf89cc583bc07d0e1f8307d00a50e1ed25d6cb17180cf0a5db085b895256` |
| `safari-ext.d.ts` | `dts/safari-ext.d.ts` | yes | `b86c4909673f425deb596e67c328cacad2f43022aa12ece1a03aee0e464815ae` |
| `safari-ext.d.ts` | `‏‏תיקיה חדשה/dts/safari-ext.d.ts` | yes | `b86c4909673f425deb596e67c328cacad2f43022aa12ece1a03aee0e464815ae` |
| `scripting.d.ts` | `dts/scripting.d.ts` | yes | `0dd028697d487ae23ac5625e718fd8af0af0a3f7a295fb753f7a1a1d3277ede2` |
| `scripting.d.ts` | `‏‏תיקיה חדשה/dts/scripting.d.ts` | yes | `0dd028697d487ae23ac5625e718fd8af0af0a3f7a295fb753f7a1a1d3277ede2` |
| `tsconfig.json` | `scripts/Transit Nearby/tsconfig.json` | no | `a3a7fae48e1e2adcdf20e7516313abd47dc33cc2575b6447418369aaf8bdea61` |
| `tsconfig.json` | `tsconfig.json` | yes | `7e47c2c814a304249510be267cc93b0c5baa07c0d5441ea360d1a8fd8b3f62ee` |
| `tsconfig.json` | `‏‏תיקיה חדשה/tsconfig.json` | yes | `7e47c2c814a304249510be267cc93b0c5baa07c0d5441ea360d1a8fd8b3f62ee` |
| `web-fetch.d.ts` | `dts/web-fetch.d.ts` | yes | `d93cf87b1e46c33c6e672d3fc451f9cfa35f7bae490065b9a7f26b0b08d16938` |
| `web-fetch.d.ts` | `‏‏תיקיה חדשה/dts/web-fetch.d.ts` | yes | `d93cf87b1e46c33c6e672d3fc451f9cfa35f7bae490065b9a7f26b0b08d16938` |

## Exclusions

| Reason | Count |
| --- | ---: |
| `excluded-extension:.zip` | 1 |

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

