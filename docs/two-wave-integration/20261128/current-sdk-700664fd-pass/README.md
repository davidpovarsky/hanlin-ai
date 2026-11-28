# Current SDK archive and verified Host test reuse

The canonical SDK refresh at `700664fdbf0871321c30433172f39299e706b0f8` completed **13 fresh phases**, each with exit 0 and no stop. This includes current source audits, the original SDK staging, original packing, packed JITless validation, archive reuse validation and the final source fingerprint.

| Artifact or boundary | Qualified identity |
|---|---|
| Current SDK source inputs | 396 files; `c4463f0f702e5b070f1e0236c452f90e5e31e8a2fa6a1978e72b9ad55caaf307` |
| Current SDK manifest | 25,706 file rows; SHA-256 `4819de6f518a2b9ea1c6e3c80a3567dbf46ef0ec886e883be162bb77766be480` |
| Current RuntimeHostResources.zip | 81,905,749 bytes; SHA-256 `cfda1ac4ae05729f309ac235eec883b57df0fc6fbd158de46e986cd3ebac4158` |
| Complete historical/current archive payload | 28,810 rows compared |
| Host188 | **REUSED_VERIFIED**, with **0 new Host188 invocations** |

The independent root semantic review is included verbatim. It rehashed all 48 retained payload members, reconciled the complete byte maps and SDK manifest, matched all 396 current inputs to Git, and checked the actual phase logs and exit codes.

## Fresh phases and archive checks

`execution-phases.json` records the 13 original phase names, exact commands, timestamps, exit codes and raw-log hashes. No phase was replaced with a summary-only substitute. The packed JITless check actually passed 11 contracts: GET, Request POST Unicode, redirect, HTTP error, ReadableStream, clone, gzip, multipart File, abort, HEAD and 204. Its small original output is retained unchanged.

The Mac evidence records successful archive CRC readback and an actual comparison of every payload row and file mode. The independent root review reconciles that recorded mode qualification, including all five changed rows; it does not claim to have transferred or independently reopened the ZIPs. This documentation author also did not reopen them.

Only these five payload byte changes were admitted:

- `MiniAppSDK/docs/miniapp-sdk/MANIFEST_REFERENCE.md`
- `MiniAppSDK/docs/miniapp-sdk/extension-reachability.json`
- `MiniAppSDK/docs/miniapp-sdk/extension-reachability.md`
- `MiniAppSDK/docs/miniapp-sdk/source-inventory.json`
- `MiniAppSDK/miniapp-sdk.json`

Every other payload byte and every file mode matched the accepted historical archive. The original complete maps remain retained under exact hashes; this compact proof contains the five-row delta rather than duplicating 28,810 rows.

## Host188 is reused execution evidence

The accepted Host run actually executed at `b5475156e7b0253b24c0a4385236b60da21f6f7e`: 188 passed, with no failures, cancellations or skips. Its retained long-job observation measured **305,044.987583 milliseconds**. The current refresh does not rerun those tests and does not claim a fresh original twelve-phase Host run.

Reuse is supported by the unchanged executable/dependency/test closure, including 99 original Host test files, the exact historical receipt and complete current-versus-historical archive comparison. `original-archive-reuse-qualification.json` explicitly records zero new test invocations. The existing `host-metadata.json` schema still says `tests: passed`; this qualification identifies that field's proof as the historical accepted execution.

The long-job record is Host test evidence. It is not evidence of a saved Shortcuts action running for more than 300 seconds, OS background survival, device locking or a new app-surface result.

## Source and scope

The current archive was produced from source `700664fd…`; the generated documentation retains `167219a4…` as its actual audit base under the unchanged generator contract. The source binding is exact file hashes, not a claim that the audit base must equal a later documentation commit.

The root semantic review binds the 396 inputs to integration source `9edbed3a8b52c3dae5e52032b3fd8f6ef40dda37`. This docs-only donor uses `166d53f1360a9503e94d2a92587046315936532a`; the intervening change adds only the prior native-package proof outside the SDK inputs. No source, test, workflow or tool change is included here.

The separate full macOS package run at `167219a4…` passed 619 method identities and the original 316 parameter-start identities. Its proof remains in the adjacent native-platform record; it is not an additional SDK phase or a fresh Host188 run.

Current app compilation, iOS/OS surfaces, signing and physical-device acceptance remain separate. The earlier Gallery samples do not prove another source defect or a synchronous editor callback cycle; the approved editor equality guards still require their original native acceptance. No additional product fix is claimed here.

All records were assembled from immutable evidence. No test, generator, packing command, archive validation or native job was rerun to write this proof.
