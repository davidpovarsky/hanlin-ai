# Concrete protected-provider activation and rollout design

Design only. No user credential was read, staged, moved, exported or deleted. Phase1 v2 remains the independently reviewable implementation; its activation overlay is not applied.

## Decision

Activate protected storage for new provider records and actual secret replacements after the compatibility phase has passed its native gates. Keep untouched legacy rows readable in their current representation. Offer a direct per-key migration action for an existing unchanged secret. Do not migrate a credential merely because the user saves a URL, visibility flag, capability setting, or another provider's settings.

The supplied two-line activation overlay is insufficient by itself: it routes every Save to secured storage, including metadata-only edits. Replace it with the explicit transition rules below before activation. No additional blanket permission dialog is needed.

This design protects new writes without a bulk destructive move. It cannot promise that an older binary understands a new credential format, or that local Keychain success establishes remote device availability. Those are concrete release compatibility conditions, not properties to infer from a green local test.

## Existing owners and constraints

- Original records: APIKeys, SearchKeys and ToolKeys in AppDataManager's CloudKit-enabled ModelContainer.
- Original consumers: current APIManager/feature readers and the Translation compact config. Phase1 covers their dual-format reads and the full original discovery/probe path.
- Original local writes: the Hanlin app's four key editors and custom-provider form. Translation and MiniApps do not become new provider-record writers.
- Existing recovery: the new immutable Keychain payload retains the previous stored representation, while the original row retains its identity. No second schema, record zone, account identifier or rollback file is needed for this bounded protocol.
- Existing account observation: source contains HanlinSystemServicesBroker.fetchCloudStatus, a CKContainer.default().accountStatus call. There is no original account-switch/store-rebinding/logout lifecycle. Available CloudKit account status is not an account identity and does not prove iCloud Keychain synchronization.
- Source build metadata is currently marketing version 0.7.3 for Hanlin and 0.1.0 for MiniApps, with project build number 1. It is not an installed-device inventory or a proof that every user's device runs a compatible reader.

## Activation entry points

### New record

The existing custom-provider form already requires a nonempty entered credential. On its explicit Save:

1. Capture the original provider metadata and entered value.
2. Create and verify the immutable synchronizable Keychain item using the original host service/group.
3. Insert the original record with its opaque handle, never with a transient plaintext key.
4. Verify the original persisted row and current credential.
5. Publish the selected compact configuration, reporting this as a separate operation.

If Keychain staging or the original row save fails, the form stays open. A failed stage never creates a plaintext fallback. A failed row commit leaves the staged item retained for recovery; it is not authorization for a broad cleanup.

### Actual replacement of an existing secret

The transient draft already records whether the user edited it and the original stored value. For a legacy row, compare the draft's UTF-8 bytes with the original legacy value as well as checking the edit flag. Re-typing and undoing to the same value must not turn a metadata Save into an automatic migration.

When the user explicitly changes the credential, use the staged secure writer. An already-secured record remains secured. Preserve the original current-record and durable-value checks before checkpointing other edits, and recheck after staging. A stale draft never overwrites a newer original row.

### Metadata-only Save

Preserve the exact original stored credential representation, including nil versus empty. Apply only the existing metadata changes through the original context. Do not create a new Keychain generation or re-read a missing secret just to save metadata.

For an unavailable secured credential, an untouched blank editor is not an empty replacement. The current editor keeps its Save action disabled until the original read succeeds or the user explicitly enters a replacement. Existing nonsecret settings retain their original behavior; the credential field never becomes blank merely because its Keychain read failed.

### Existing unchanged legacy credential

Provide one direct action in the existing key editor: Move this key to Keychain. It acts on the currently opened original row and exact loaded value, uses the same staging/readback/commit protocol, and retains the predecessor. It is unavailable for empty values and for the original nonsecret LOCAL / APPLEMAP / keyless entries.

Do not run it automatically during app launch, provider discovery, capability probes, model selection, catalog reconciliation, opening settings or ordinary reads. A future bulk migration would require its own bounded inventory and reviewed recovery plan; it is not part of this activation.

## What the user is told

Place concise storage information beside the actual secret-save/migration action:

“Saved keys use Keychain. To use them on another device, update Hanlin and enable iCloud Keychain there. Synchronization can take time.”

For a legacy secret whose stored representation will change, the action label identifies that operation. This is meaningful compatibility information at the action that changes storage, not a vague confirmation gate. Metadata-only Save retains its ordinary meaning.

A successful local save says saved, not synced to all devices. A later compact-file failure says the key was saved and offers Retry extension update. Closing that message does not claim to undo the committed key.

## State and failure matrix

| State / event | Read / request behavior | Explicit write / recovery behavior |
|---|---|---|
| Untouched legacy row | Original legacy value remains readable; current other-device access is preserved. | Metadata-only changes preserve the raw field exactly. Only explicit replacement/migration secures it. |
| Secured reference + available item | Resolve the current original reference at use time; retain original request/namespace/owner checks. | Actual replacement creates a new immutable generation. Metadata-only Save retains the existing handle. |
| Secured reference + missing/locked/unavailable item | Show unavailable on this device. Never send the handle, use a predecessor silently, or switch providers because of the missing item. | Keep the reference. Retry after unlock/synchronization, or let the user explicitly replace the key through the same original editor. |
| Explicit empty input after an edit | Empty is not “no override” and cannot reuse the previous saved key for discovery/probes. | Treat as an explicit credential clear under the current app's clear contract; retain recovery generations. Full orphan/remote erasure remains a separate owner operation. |
| Stale draft/current row changed | Reject against the original current and durable value before any credential mutation. | Reopen/reload the original settings. Do not force an older draft onto a new row. |
| Keychain add/readback failure | Existing original row continues to use its prior representation. | No model mutation and no plaintext/device-only fallback. Show a retryable save error. |
| Original-store commit failure | Prior canonical row remains active after rollback. | Keep the staged generation; original native read-only-store test proves the ordering. |
| Commit succeeded, verification uncertain | Do not claim failure implies rollback. Re-read the original row before another mutation. | Retain both generations; do not automatically replace or delete them. |
| Commit succeeded, compact publication failed | Main app uses its verified saved key; report the extension update separately. | Retry only the compact file publication. No new key generation or timestamp change on retry. |
| Offline / no remote synchronization evidence | Local readback can establish local readiness only. | A synchronizable item may be staged locally; do not claim another device received it. If the actual local operation fails, preserve the old row. |
| iCloud Keychain disabled on another device | A synced CloudKit handle may exist without its Keychain item. It remains unavailable, not false-ready. | The device must regain Keychain access or explicitly replace a key. Never downgrade the canonical record to plaintext automatically. |
| iCloud account status changed | Status alone does not prove which original rows belong to the new account. | No invented account ID, automatic remapping, row deletion or secret migration. Account/store rebinding must be implemented in the actual AppDataManager/session owner before full account-isolation acceptance. |

Explicitly entering a replacement on a sync-off device changes the canonical credential generation. It is not a hidden local-only override. A separate “use only on this device” feature would require a distinct reviewed owner/backup contract; this design does not silently introduce it.

## Older-host compatibility

A pre-phase1 full host reads the original String as a secret. An opaque handle is not usable by that binary. This cannot be repaired by changing an accessibility flag or by proving a local Keychain read.

The compact format has a narrower fail-closed bridge: secured configurations keep its legacy apiKey empty and use the new optional reference. Old compact readers therefore see unconfigured. That does not prove full old-host compatibility.

Recommended release sequence:

1. Ship/validate the compatibility reader first, including the app and Translation extension, while legacy writes remain active.
2. Prepare the actual activation behavior above in the work branch and verify new creation, explicit replacement, metadata-only Save and explicit migration independently.
3. Publish the protected-write release with the compatibility requirement stated at the storage action and in release notes. Support secured records on phase1-or-newer clients; do not assert old binaries can use them.
4. Leave all untouched legacy records unchanged. Existing credentials keep their previous access until the user chooses replacement/migration.
5. If support for still-installed older full hosts is an absolute release requirement, do not replace a legacy field with a handle yet. No local code can prove every offline client has upgraded. An additive schema design would then need review and deployment, rather than an undocumented storage-format change.

An additive optional credentialReference field could make old full hosts see an empty key instead of an opaque handle, but it still would not let them use a protected key. It therefore does not solve the compatibility requirement and should not be added just to disguise it.

## Recovery and rollback

The new Keychain payload is the checkpoint. It contains the new value and the exact previous representation before the row changes. After a successful commit, the current row's reference reaches that checkpoint, including after a process restart or another supported device receives both the row and item.

An explicit rollback resolves that checkpoint and restores the predecessor to the same original row, after current-value validation. If the predecessor is legacy plaintext, rollback deliberately returns to legacy storage; this must be described truthfully. Never perform that downgrade because a read is temporarily unavailable.

Retain current and predecessor Keychain generations during rollout. Failed staging/commit can leave unreferenced items. Cleanup must be reference-aware and separately reviewed; deleting a synchronizable item can remove other devices' copies. No account-wide erase or forensic SQLite/WAL cleanup is implied.

## Required concrete evidence before activating release writes

1. Phase1 v2 native methods: original disk rows, Keychain write failure, commit failure, stale edits, original request revocation, discovery/probes and compact publication failure/retry.
2. Activation-specific native tests: new custom record contains only a handle; actual secret replacement secures exactly that row; metadata-only Save creates no generation and preserves nil/empty/original reference; unchanged legacy text is not auto-migrated; explicit per-key migration retains recoverable predecessor.
3. Actual original old-reader compatibility check using preserved pre-phase1 code/binary: legacy rows remain usable; secured rows are explicitly unsupported. Do not substitute a newly written fake old reader.
4. Signed app + Translation extension on the original identity/group: both resolve a generated synthetic credential and replace/clear compact config without retaining stale loaded secrets.
5. Two supported clients with the same authorized iCloud account and Keychain enabled: synthetic new/save/migrate/reopen propagation. Record each device's observed source/receipt; local success is not remote proof.
6. Missing item/locked/offline/sync-off controls: no plaintext fallback, no provider switch, no false synced/readiness claim, and no destructive retry.
7. Account switch/logout acceptance in the original store/session owner is still a separate required SDK05 gate. The source presently lacks that lifecycle; do not claim the credential writer implements it.

Only synthetic credentials are required to validate these mechanics. This packet performs no migration or read of real user secrets.

## Apple documentation that rules out shortcuts

- [CloudKit encryptedValues](https://developer.apple.com/documentation/cloudkit/ckrecord/encryptedvalues): only new fields can adopt this encryption; existing schema fields cannot simply be changed to encrypted fields.
- [SwiftData CloudKit synchronization](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices): synchronization is asynchronous and production schemas are additive. Keep the original managed container; do not manually mutate an invented parallel schema.
- [CloudKit accountStatus](https://developer.apple.com/documentation/cloudkit/ckcontainer/accountstatus(completionhandler:)): it reports account availability; CKAccountChanged prompts another status check. The original source has no store-rebinding lifecycle, and availability is not a substitute for account ownership or Keychain sync proof.
- [Synchronizable Keychain items](https://developer.apple.com/documentation/security/ksecattrsynchronizable): use attributes/data rather than persistent references; avoid ThisDeviceOnly; updates/deletes can affect synchronized copies.

The proposed sync-capable policy preserves the ability to use protected values on other supported devices. It cannot manufacture synchronization while the user has disabled that service, nor make an old client understand a new protocol.
