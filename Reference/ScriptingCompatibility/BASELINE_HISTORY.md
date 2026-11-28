# Scripting compatibility baseline history

The repository keeps one portable current baseline. Superseded bytes remain in
Git history; their identities are recorded here so a declaration refresh never
silently erases provenance.

| Status | Baseline | Aggregate SHA-256 | Declaration export |
| --- | --- | --- | --- |
| Superseded | `scripting-compat-2026-08-25-0b7b8e715573` | `0b7b8e715573ffc1656f530d9eba6cc019e6742294392278edbee812bd45a1c9` | Scripting 1.1.1 five-file export; documentation snapshot contained 942 files |
| Superseded | `scripting-compat-2026-07-22-8d7d33d9369e` | `8d7d33d9369ee555d15adf10c867abbfb85834eced7e7596a627b70ff627ff36` | `global.d.ts` 702,176 bytes (`f3d06e3b...`); `scripting.d.ts` 454,206 bytes (`0dd02869...`) |

The 2026-08-25 app export replaced only the five declaration records. The
2026-08-26 documentation refresh then replaced the documentation tree from the
user-provided archive while retaining those declarations, compiler inputs, and
project examples unchanged.
