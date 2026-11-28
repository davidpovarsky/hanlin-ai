# MAIN16 actual SDK05 shipping reconciliation

Status: **PASS for the exact README/reachability shipping delta.** SDK05 remains completed. Native phases remain distinct: **MiniApps build PASS, AI test-target build FAIL, all 52 application cases NOT_RUN**.

This receipt uses the parent-authenticated artifact from run `45430463243`, tested source `7d1efaa6ada43dd80c57133c09e6a8fb327075cf`, and evidence base `1bc0360cb204796a092c9101df980028f2963459`. The existing source-input paths have no additional changes between these two commits. This lane ran no compiler, product tests, SDK/application build, generator, network, CI, download or Asana operation.

## Actual shipping identity

The actual SDK manifest SHA-256 is `f84b79a3d9c4f7dc541d6912753cd1be95bfa3ed1876cc4d0ead365aadab12fc`. Its input identity, recomputed from the real ordered 222 input records, is `307f689d68445cae8cb4f049f015c9bf55904d0de40a96e69fb59fa622d0a863`. This matches the earlier conditional expectation, now verified from the actual archive.

Exactly three inputs/file records differ from MAIN15: `docs/miniapp-sdk/README.md`, `extension-reachability.json` and `extension-reachability.md`. Their actual member bytes, sizes and hashes match Git at the exact tested source and evidence base. The clarified README SHA `90068db0d87718cc9f995f9d45c1e2e8a7bd670aa8b8f3b324f0bf4cfc591d95` is now genuinely shipped and independently covered by the actual staged-document check. Its only change from MAIN15 is prose line 109; the descriptor and all other lines remain byte-identical. Actual reachability records match both this README and the corrected generated-project hash.

The other 219 inputs and 25,658 file records remain unchanged, including source-inventory.json, 22 documentation files, all 28 example sources plus their index, and all 5,210 declaration records. Prior unaffected proof is reused only through these matching identities. Only the nested manifest and the three changed document bodies were opened; no repeat of the 112-member inspection or complete SDK body rehash is claimed. Earlier package CLI build receipts retain their original SDK attribution.

## Actual documentation validation

Report SHA `072bc4f6838752f542fe140e95fd04267d55967826dbadbdbcb7e635f92b644f` records four successful original validator projects and zero diagnostics: 14 source blocks, 7 JSON/config blocks and 8 explicit nonauthoring exclusions. Expected differences from MAIN15 are the README whole-document hash, new SDK identities and temporary source-root paths only. Compiler versions remain 6.0.3 for Expo/ScriptWidget and 5.9.3 for NativeScript with unchanged recorded strict/dependency policies. Checker source and native root-registration checks are unchanged.

## Actual native phase boundary

Two selected original command receipts are retained losslessly by raw JSON line and source-member hash in `build-phase-command-receipts.json`. The MiniApps `build-for-testing` command completed with exit 0 in 785.086133333 seconds. The AI `build-for-testing` command ended with exit 65 after 488.930143958 seconds. Paired acceptance records the aggregate build failure and UI NOT_RUN; its orchestration duration is separately labeled and is not either build-command duration.

All 52 planned application cases remain unexecuted. The parent/control lane owns the two AI test-target compilation diagnostics and later test-only fixes. The successful MiniApps build and SDK validation do not establish native UI events, publication, OS behavior, physical-device operation or distribution acceptance. The exact MAIN16 source remains the execution authority.

## Preservation

The available disk reserve was checked before creating the owned 81,812,157-byte nested archive stage, which was removed after comparison. Parent archives/logs, shared caches and the frozen independent SDK-only kit remain unchanged. Only this evidence directory changed. [receipt.json](receipt.json) is the machine-readable summary, and [SHA256SUMS](SHA256SUMS) covers every other retained file here.
