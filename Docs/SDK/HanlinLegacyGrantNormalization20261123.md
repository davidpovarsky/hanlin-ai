# Legacy scripting grant normalization — 2026-11-23

## Result

The public `HanlinScriptPermissionAuthority.init(grants:revokedGrantIDs:now:)` and `replace(grants:revokedGrantIDs:)` no longer trap when an input array repeats a grant ID. Both use one shared indexing helper. Public signatures remain unchanged.

This component stores legacy grant metadata. Its existing `authorize` returns `.allowed`; actual iOS device-service authorization and Host permission gates are separate and unchanged. This repair does not add, remove or reinterpret a permission gate.

## Defined input behavior

Arrays are processed in their supplied order, matching the existing `upsert` assignment for grant records:

- Repeated identical records coalesce to one record.
- Differing records with the same ID retain the last complete supplied record. Fields, subjects, scopes, conditions, expiry and provenance are not combined.
- Distinct IDs remain distinct.
- Initial loading and replacement retain the complete explicitly supplied `revokedGrantIDs` set. They do not use `upsert` to ingest rows, because `upsert` deliberately clears that row's revocation.
- Replacement still replaces the entire prior metadata snapshot. An empty input clears records while retaining the supplied revocations.

The conflict rule is storage compatibility with an existing public mutation, not a new permission-resolution policy. In the reviewed implementation, neither the private grant map nor its revocation set is consulted by `authorize`. Keeping that existing behavior is covered by the original selected permission test.

## Original failure reproduced

The original input closure at Hanlin `8538287fc7f17af6a5b2a0e7333ffed356b64a9a` was compiled with all **30 original Swift source files** from `HanlinPlatformContracts`, `HanlinScriptContracts` and `HanlinScriptServices`, including their original resources. There were no replacement/stub production declarations, deleted original declarations or external dependencies.

Swift 6.4.3 on aarch64 Linux compiled the original closure. Separate child processes then reproduced both sites:

| Public call | Input | Original result | Repaired result |
| --- | --- | --- | --- |
| Initializer | The same complete grant twice | SIGTRAP, exit `-5`, duplicate-key diagnostic | PASS, exit `0` |
| `replace` | Two different complete records with the same grant ID | SIGTRAP, exit `-5`, duplicate-key diagnostic | PASS, exit `0` |

The source record and exact synthetic probes are retained in [the evidence directory](../../docs/agent-sdk/evidence/legacy-grant-normalization-20261123/). The original authority SHA-256 is `ee315d32cc319b30a4b776fe7f24dfc6cf388962e928ac29bad5cc590d9dbb4b`; the repaired SHA-256 is `009f7c5a8700feee07854ada7bd2437fc213000207094ea707b2e7416f1871b8`.

## Focused verification

Only the affected controls ran:

1. Four new Swift Testing methods in `HanlinScriptPermissionAuthorityTests`: identical coalescing; complete-record conflict resolution in both input orders with an unrelated ID; public initialization with identical/conflicting rows; public replacement with identical/conflicting rows. The two public-boundary methods each have two parameter cases.
2. The existing `HanlinScriptServiceBrokerTests.permissions` method, confirming legacy metadata still does not add a Hanlin permission gate.
3. The exact two formerly crashing public probes, now passing.
4. Six actor-isolated storage checks covering both input classes: actual initialized/replaced records and explicit revocations; unchanged `upsert` and `revoke` behavior; and an empty replacement that preserves its supplied revoked IDs.

Swift Testing reported **5 tests in 2 suites PASS**, 0 failures, 0.006 seconds after compilation. The six storage checks also passed.

The private-state checks used a probe-only read-only actor extension appended after the entire production authority declaration. The production prefix SHA-256 equals the repaired file exactly. The extension adds no mutation or replacement implementation, and it is not part of the production target or public SDK. The regular selected unit tests and the two direct public probes ran first against the unmodified production declaration, before that fixture extension was appended.

The original `revoke`, `upsert` and `authorize` suffix is byte-identical. Both explicit revoked-set assignments and the original public signatures are unchanged. No Host permission implementation, iOS permission adapter, source identity contract, expiry declaration or scope declaration was edited.

## Evidence and limits

[Machine receipt](../../docs/agent-sdk/evidence/legacy-grant-normalization-20261123/receipt.json) binds the complete source list, baseline/repaired binaries, probe extension, test selection, logs and source-preservation checks. Oracle execution artifacts remain at:

`/mnt/development/projects/worktrees/hanlin-sdk-host-api-20261123/build/permission-authority-duplicates-20261123`

These are focused actual-source Linux controls for a Foundation-only storage change. No Apple build, native device authorization, broad suite replay, consumer repin or CI dispatch was performed. Prior unrelated acceptance evidence is unchanged.
