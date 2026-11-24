# Main14 current shipping SDK reconciliation

Status: **PASS for the expected three-document provenance delta.** SDK05 remains completed. Native main14 acceptance remains **EXECUTED_FAIL / UI NOT_RUN**.

This evidence compares the actual local archive from run `45398772829`, tested source `cf9c18903c03264265557efb446207efa7226912`, against the retained main12 and main13 shipping proof. The archive was downloaded/authenticated once by the parent. This lane rehashed that supplied file and performed data/source comparisons only: no compiler, tests, build, generator, network, CI or Asana operation ran.

## Current identity and exact change

The actual SDK manifest SHA-256 is `17df84a3ea5121d8b6362a03d095114ff3ce7702ad605a97b91f21666480a7e6`; the input identity is `2613c6ccdeb2ea17dd5268b5a0eb90f0f7e136f3c46e39faeb94c7fb0777848a`. The latter was recomputed from the exact ordered 222 source-input records using the existing staging serialization contract.

Exactly three source inputs and three declared file records changed: `docs/miniapp-sdk/source-inventory.json`, `extension-reachability.json`, and `extension-reachability.md`. Each actual changed SDK member was freshly read, hashed, size-checked, and matched byte-for-byte to both tested source and evidence base `dc518aa35d123b611c02b10ad75e11477a7eb131`. Their prior bytes match the prior tested source. Git comparison across the exact input paths confirms the same three changes and no further change between main14 source and the evidence base.

The actual shipped inventory and reachability records contain the corrected publication source hash `ce2b136f95d1eccfd27fc876e10307133602d673fd42d860816559510b5a5960`. The recorded provenance refresh commit is `23502f5430d0f57876f10d26c239b533fb181cf1`, an ancestor of tested source. Exact document differences and binding checks are retained in the adjacent JSON files.

The remaining 219 inputs and 25,658 file records are unchanged. This permits reuse of the prior unaffected proof, including 22 unchanged documentation records, all 28 example source records plus their index, all 5,210 declaration records, and unchanged engine/upstream metadata. The prior 112 selected-member body checks were not repeated; only the new manifest and the three changed document bodies were opened inside the nested ZIP. This does not claim full manifest byte equality or a new hash of every SDK file body.

## Actual documentation validation

The authentic main14 report again records four passing original validator projects and zero diagnostics: 14 source blocks plus 7 JSON/config blocks, with 8 explicit nonauthoring exclusions, covering all 29 inventoried fences. Guide hashes, checker inputs, registration checks, compiler versions and policies are unchanged. Differences from main13 are only the updated SDK identities and four temporary source-root paths. Actual compiler versions remain 6.0.3 for Expo/ScriptWidget and 5.9.3 for NativeScript, with the same recorded strict/dependency policies.

## Options-only fix impact

`Packages/HanlinWidgetSDK/Sources/HanlinScriptingWidgets/HanlinOriginalExpoWidgetOptions.swift` is not a direct SDK source/file input and is absent from the hashed source inventory, reachability `sdkSources`, and `sourceRefs`. The broad reachability Swift text scan records named symbol membership, not every scanned file hash. This file has no matching ControlWidget, CSSearchableIndex or CoreSpotlight entry, and is outside the AI_HLY-only share-caller scan.

For the separately owned options-only type/value-construction correction, the existing inventory/reachability write/check sequence and an ad hoc SDK rebuild are therefore unnecessary. This conclusion is limited to that described file-only change with the existing symbol/caller memberships preserved; actual native compilation remains a separate acceptance requirement. Exact inspected source excerpts and inclusion results are in [options-input-impact.json](options-input-impact.json). No generator was run here.

## Native and preservation boundaries

Actual main14 acceptance records first MiniApps build exit 65, `build=EXECUTED_FAIL`, `ai_build=NOT_RUN` and `ui=NOT_RUN`. No application case, native rendering, successful publication, device operation or distribution success is claimed. Earlier package build receipts keep their original SDK attribution.

Only this evidence directory was changed. The owned approximately 81.8 MB temporary nested archive was removed after inspection. Parent archives/logs, shared caches and the frozen SDK-only kit remain untouched. [receipt.json](receipt.json) is the concise machine-readable record; [SHA256SUMS](SHA256SUMS) hashes every other retained file here.
