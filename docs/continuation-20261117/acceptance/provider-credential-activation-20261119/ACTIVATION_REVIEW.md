# Protected provider credential activation — phase2 review

Status: executable, unapplied proposal against published phase1 commit 37a246f404cc2ed253200ddf6fd647f999637f68. All three source inputs match that Git commit and the frozen phase1 packet byte for byte. The phase1 native run remains independently owned by root; this packet does not infer its result.

## Exact deliverable

Apply only protected-provider-activation-phase2.diff after review. It changes the original host credential owner, the existing settings UI, and the existing native owner test file. It does not change a model schema, CloudKit container, signing identity, access group, original row identity, SDK authority rules, CI workflow, or real user data.

Patch: 32,328 bytes.
SHA256: 85e1adb2d9c2c5c543dfef1d1f46167979c97cc1adab377e3d3435f1d7d15458.

The old secure-write-activation-DO-NOT-APPLY.diff is an obsolete preliminary overlay and is not this proposal. The frozen phase1 v2 diff remains ec7f6f97928561a4ada702099200eaad035f6bbfaad497114dd13c176469a596; its source and review archives remain unchanged.

## Actual behavior

| Original action | Result |
| --- | --- |
| Create a custom provider | Stage and verify an immutable Keychain generation before inserting the original SwiftData row. Its key field receives only the opaque reference. |
| Change a model, search, map or weather key | Compare actual UTF-8 bytes against the successfully loaded draft. A real replacement uses the phase1 verified secure writer and keeps the predecessor checkpoint. |
| Change only a URL, timestamp, visibility or another nonsecret field | Use saveMetadata. It requires the original current and durable credential value before checkpointing prior edits, preserves that exact representation, and creates no Keychain generation. |
| Type a value and undo to the original bytes | Treat this as unchanged; do not migrate automatically. Canonically equivalent but byte-different strings remain a real replacement. |
| Preserve nil or an empty legacy optional field | Keep its original nil/empty representation instead of converting nil to an empty string during Save. |
| Select Move this key to Keychain | Migrate only the currently loaded unchanged nonempty legacy key through the same staged writer. Current original identity/value validation applies. |
| Open a LOCAL, APPLE, APPLEMAP or automatic keyless entry | Exclude its built-in marker from the migration action. No launch or list reconciliation migration is introduced. |
| Open a missing/unavailable secured reference | Keep the reference. An untouched failed read is not Save-ready; an explicit entered replacement, including intentional empty text, may be saved through the protected writer. |
| Original store save succeeds, compact config publication fails | Keep the truthful saved state and expose publication retry. Retry has no credential mutation argument and creates no generation. |

The migration action is directly in the existing secret section. There is no new permission dialog. The concise text at the action explains that other devices need updated Hanlin and iCloud Keychain, and synchronization can take time. It states actual compatibility requirements rather than claiming current remote availability.

The original draft cancellation and unsaved discovery/probe behavior from phase1 remain in place. The explicit action is not triggered by opening settings, reading a value, selecting a provider, discovery, probing, or an ordinary unchanged Save.

## Storage and authority

Production keeps the exact original host policy already introduced in phase1: service com.itorah.chavrusachat.provider-credentials; group group.com.itorah.chavrusachat; synchronizable true; afterFirstUnlock; Data Protection Keychain. The opaque UUID identifies an immutable credential generation, not an invented account.

The key is staged with SecItemAdd and exact-byte readback before the original row changes. The phase2 writer reuses the original current/durable checks and original-row verification. A failed or uncertain commit never deletes either generation. A stale UI draft cannot checkpoint its unsaved metadata over a later durable credential.

saveMetadata has a separate invariant: its metadata callback may not change storedCredential. A violating callback is rolled back before commit. Metadata failure preserves the current key representation; no plaintext fallback or generation is created.

A missing reference never becomes a provider credential string. The original typed request namespace, model/key checks, owner epoch and post-await authority validation from phase1 remain unchanged. The existing foreign-model/deleted-origin control is retained in the proposed native lane.

## Compatibility boundary, established from original source

activation-old-client-source-audit.json authenticates the actual pre-phase1 source at ce2fb04e8a266759f6c9eed70fd2dda02029720d. Its original APIManager credential method returns stored .key unchanged, and the original map/weather consumers also read .key directly. That full host cannot consume an opaque reference. This is source evidence, not a native old-binary execution.

The supported reader boundary is phase1 or newer. Untouched legacy records preserve their existing access. Explicit replacement/migration changes that record's representation. No local process can prove that every offline client has upgraded; this patch does not pretend otherwise or leave a second plaintext copy for hidden fallback.

CloudKit row propagation and Keychain propagation are separate asynchronous services. When a supported device receives a row before its item, it remains unavailable until its actual Keychain value is available or the user explicitly replaces it. Synchronizable true preserves the possibility of supported cross-device use; it does not establish receipt on another device, override a disabled service, or create an account identity.

The source presently has no complete logout/account/store-rebinding lifecycle. This patch neither fabricates one nor claims account isolation. That remains the original SDK05 acceptance work.

## Recovery

Each staged payload retains the exact prior representation. The existing explicit restorePrevious operation validates the current original row, resolves that checkpoint and restores it. Native tests cover restoration and subsequent real read-only migration failure on each original model kind. A predecessor may be legacy plaintext; restoring it deliberately restores that compatibility rather than proving historical erasure.

Failed insertions/migrations keep staged recovery generations. This is intentional conservative recovery, not a cleanup leak claim. Reference-aware cleanup, CloudKit history, SQLite/WAL/backup erasure and account-wide deletion remain separate work. No synchronizable item is deleted by this proposal.

## Meaningful native regression scope

All new methods run in HanlinAppAgentSessionOwnerTests through the original APIKeys, SearchKeys and ToolKeys SwiftData schemas, actual disk ModelContainer, actual Security APIs in a unique synthetic non-synchronizable test service, and the actual draft/owner methods. They do not require a real provider credential or external network.

| New method | Cases | Observable boundary |
| --- | ---: | --- |
| protectedCredentialMetadataSavesPreserveOriginalRowsAndGenerations(kind:) | 3 | Original model/search/tool rows, metadata changes, typing then undo, actual protected replacement, unchanged secured generation, byte-different Unicode rotation, fresh container reopen and resolution. |
| protectedCredentialMetadataSaveRetainsNilAndEmptyRepresentations(initial:) | 2 | Exact nil/empty persistence and original identity on reopen; rejecting a callback that tries to rewrite the key. |
| protectedCredentialExplicitMigrationIsTargetedAndRecoverable(kind:) | 3 | Only the selected original row migrates; unrelated row remains raw; original identity and checkpoint survive reopen; explicit restoration; real read-only migration failure preserves the durable row and staged recovery. |
| protectedCredentialMigrationRejectsBuiltInMarkersAndEmptyKeys() | 1 | Original LOCAL / APPLEMAP / automatic keyless rows cannot enter migration. |
| protectedCredentialNewProviderCommitsOnlyReferenceAndFailedInsertRetainsExistingRows() | 1 | New original provider contains a verified reference; later real read-only insert failure leaves exactly the existing original row and a retained staged generation. |
| protectedCredentialExplicitReplacementRecoversMissingReferenceWithoutPlaintextFallback(value:) | 2 | Failed original read cannot become an implicit clear; explicit nonempty/empty replacement is protected, retains predecessor and resolves after fresh reopen. |
| protectedCredentialMetadataFailureAndStaleDraftPreserveOriginalDiskRow() | 1 | An unchanged stale draft cannot checkpoint a dirty URL over a newer secure key; actual read-only metadata save fails without replacing key/timestamp/URL or creating a generation. |

New methods: 7. Expanded new cases: 13.

The existing originalCredentialEditorRemainsTransientAndLegacyCompatible() retains its original transient/cancellation/stale protections. Its explicit-save assertion now requires a verified opaque reference and actual resolution, as required by activation. The other phase1 controls remain unchanged.

activation-native-selectors.txt retains all 11 phase1 methods (14 expanded cases), the existing original foreign-authority control, and all seven new methods. Complete planned lane: 19 selectors / 28 expanded cases. Native is NOT_RUN for this proposal.

## Completed local checks and remaining proof

Completed:
- All three base inputs equal both frozen phase1 and published37 Git objects.
- git apply --check succeeds against canonical37.
- Windows Swift6.3.3 -frontend -parse passes for all three changed Swift files.
- Phase1 diff hash is unchanged.
- Exact source and packet SHA256 manifests were written and read back.

The Windows result is syntax only. It does not establish Apple SDK type checking, SwiftData save behavior, Security entitlements, signing, iOS execution, old-binary behavior, iCloud synchronization, or account isolation.

Concrete next evidence:
1. Root reviews/applies the three-file proposal and runs the exact retained 19-selector lane.
2. The signed original host and Translation extension resolve a synthetic secured reference under the actual original shared identity/group.
3. Two supported clients with the same authorized iCloud account demonstrate actual synthetic item/row propagation and the unavailable-before-arrival case.
4. Preserve the unsupported pre-phase1 full-host boundary in release notes. Do not present it as transparent old-client compatibility.
5. Continue original SDK05 account/store lifecycle and erasure acceptance separately.

See ACTIVATION_DESIGN.md for the source-derived rollout matrix and official Apple documentation links; official-api contains the saved primary API receipts. No real user secret was read or migrated, and this child did not mutate canonical source or CI state.
