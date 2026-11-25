# MAIN15 actual SDK05 shipping reconciliation

Status: **PASS for the expected three-document shipping provenance delta.** SDK05 remains completed. Actual native/application acceptance remains **first build EXECUTED_FAIL, AI/UI NOT_RUN**.

This receipt uses the parent-authenticated artifact from run `45412939674`, exact tested source `e2227ccdfe0c3111d1c17ef2b4bb1653ac24bb9c`. Its evidence checkout is based on the later `788354f8e9e863eb5e4c9007a8b58ea71d028b19`; that later source is not silently substituted for the artifact source. No compiler, test, SDK/application build, generator, CI, network, download or Asana operation ran in this lane.

## Actual shipping identity

The real nested SDK manifest SHA-256 is `ab7900fbb6009606800a7d4beda2bef2cee6ef8492928bea90ad5d0460abff8b`; its input identity is `91128b0831f2d90374bc7889acb9cbbd695d49187520ee23a7a75e3c2bcef6fc`. The input hash was recomputed from the actual ordered 222 input records and matches the prior conditional expectation, now confirmed against the actual artifact.

Exactly three inputs and three file records differ from MAIN14: `docs/miniapp-sdk/source-inventory.json`, `extension-reachability.json` and `extension-reachability.md`. Only these three changed document members were opened alongside the manifest. Their complete bytes, sizes and hashes match Git objects at exact source `e2227ccd`. The actual inventory and reachability documents bind ExpoHostServicesAdapter.swift to `024bd8bcb47d43ace64fb410938f393effb3c6e8bd327506cf9065851de8073c`.

The other 219 inputs and 25,658 file records are unchanged. Prior unaffected proof is reused by those exact records, including 22 unchanged documentation files, all 28 example source files plus their index, all 5,210 declaration records, and unchanged engine/upstream metadata. This is not whole-manifest equality, a repeat of the 112-member inspection, or a fresh hash of every SDK body. Earlier package CLI build receipts retain their original SDK attribution.

## Actual documentation checks

The authentic MAIN15 report SHA is `595f1e77aa5b5c52417f238e185233ec0af477d78187325239502fa5b51d83bb`. It records four successful original validator projects and zero diagnostics: 14 source blocks, 7 JSON/config blocks and 8 explicit nonauthoring exclusions, accounting for all 29 fences. Compiler versions/policies, guide hashes, checker inputs and registration checks are unchanged; report differences are only the new SDK identities and temporary source-root paths. Actual compiler versions remain 6.0.3 for Expo/ScriptWidget and 5.9.3 for NativeScript.

## Later changes are not in this artifact

The actual manifest and executed snippet report both identify README SHA `4427f49e5b729658d95d98eb6cdbb84ea08f2e4d2e33d7b7c480192914346637`, matching the tested source and prior body proof. They do not identify the later clarified README SHA `90068db0d87718cc9f995f9d45c1e2e8a7bd670aa8b8f3b324f0bf4cfc591d95`. The later README plus two derived reachability changes and later checked HanlinObject test conversion are recorded with exact before/after hashes in `post-dispatch-boundary.json`. No claim is made that MAIN15 equals latest-HEAD documentation or executed the corrected later test.

## Native status and cleanup

Authentic paired acceptance records first application build exit 65, `build=EXECUTED_FAIL`, `ai_build=NOT_RUN`, `ui=NOT_RUN`. All planned 52 application cases remain unexecuted. The parent separately owns the actual missing original React/C++ header failure evidence; the later static test conversion is not presented as that failure. No native, rendering, publication, OS, physical-device or distribution pass is inferred from SDK preparation/typechecks.

Disk space was checked before creating the owned 81,812,095-byte nested ZIP stage. That stage was removed after inspection. Parent artifacts/logs, shared caches and the frozen SDK-only kit remain unchanged. [receipt.json](receipt.json) is the concise machine-readable record; [SHA256SUMS](SHA256SUMS) hashes every other retained file here.
