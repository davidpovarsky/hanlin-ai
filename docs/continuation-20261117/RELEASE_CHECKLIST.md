# Hanlin release checklist

Decision: NO_GO. Source snapshot: c3524b52ab399a40b35bf323ef162fe5d0a6da10. Updated: 2026-11-18T07:17:06.892726+00:00.
This is a reviewable candidate checklist, not an accepted release or publication approval.

## Immutable identities

| Product | Original bundle ID | Intended display name |
| --- | --- | --- |
| Hanlin AI | com.itorah.chavrusachat | Hanlin AI |
| Hanlin MiniApps | com.itorah.hanlinminiapps | Hanlin MiniApps |
| Share extension | com.itorah.chavrusachat.share | Share to Hanlin AI |
| Widgets | com.itorah.chavrusachat.widgets | Original widgets target |
| Translation provider | com.itorah.chavrusachat.translation-provider | Hanlin AI Translation |
| Notification service | com.itorah.chavrusachat.notification-service | Original notification service |

Original shared groups group.com.itorah.chavrusachat and group.com.itorah.shared remain unchanged. No new product, account, Keychain identity or replacement provider store is introduced.

## Required gates

- [x] Register the exact original MiniApps Bundle ID and read back APP_GROUPS/HEALTHKIT in 44255527028.
- [ ] Assign both original Apple App Groups, enable every remaining source capability and obtain compatible AI/MiniApps profiles; registration alone is not signing.

- [x] Preserve original worktrees, staged source and historical baseline; source manifest records the continuation range.
- [x] Retain original SDK, Host, providers, engines, permission boundaries and storage.
- [x] Authenticate recorded SDK53, Core46, transfer25, MiniApps27, editor6 and selected media native evidence at their actual SHAs.
- [x] Build both actual original iOS27 device Release archives at 00a932d6.
- [ ] Finish actual current app/Motion, compact, standalone runtime and paired-product gates.
- [ ] Accept the 45 original UI cases and 41 expected native invocations now dispatched in 44256319287; collect Motion B/C from the same prepared simulator.
- [ ] Map behavior-specific evidence to every required feature/UX row. Do not count 278 source anchors as 278 passes.
- [ ] Complete one approved live model/tool/persistence run; credential export is currently rejected by automatic review.
- [ ] Produce local signed exports with exact required entitlements and compatible profiles for both apps and all four extensions.
- [ ] Verify final branded/Unicode candidate archives, rather than reuse older 00a932d6 archives as if current.
- [ ] Install and test on an actually accessible supported physical iPad/iPhone; verify platform trust, permissions, VoiceOver, Stage Manager, lifecycle and measured performance.
- [ ] Finish actual system Share/translation/widget/notification entrypoints and account/CloudKit conditions where required; Host-only fixtures are narrower evidence.
- [ ] Resolve MiniApps App Store registration visibility and existing Apple signing permissions through the owner's account.
- [ ] Review final release artifacts, version/build and rollback eligibility before any distribution.
- [ ] Publish only after required acceptance is satisfied; no upload has occurred.

## Backup and rollback procedure

1. Retain the exact previous accepted app build and source revision, current candidate SHA, all six product identities, signed entitlements, existing profile metadata and the release evidence hashes. A valid existing distribution certificate is a resource, not proof of a valid exported app.
2. Before a real data transition, quiesce the original runtime sessions and close store handles through the original host. Take a coherent device/account backup and the original product-transfer snapshot. A live SQLite database must be checkpointed with its WAL; copying an arbitrary open .sqlite file is not a valid backup.
3. Use the original Hanlin AI export and MiniApps Transfer from Hanlin flow. The canonical HanlinProductTransfer transaction retains old-installed and old-data, records promotion/commit state, and leaves the original AI source intact. Verify package identities, files, SQLite, KV, defaults and source/target hashes before accepting.
4. On interruption, allow prepareProductTransferRecovery to reconcile its own journal before new execution. Do not manually delete or merge transaction directories and do not rerun side effects blindly.
5. If rollback is needed before new writes, use HanlinProductTransfer.rollback with its original transaction and identity checks. It records rollback intent and restores the saved target state. Reopen and verify both apps, original conversations, attachments and imported packages.
6. If the target changed after commit, the canonical rollbackWouldLoseChanges guard must remain active. Preserve those newer files and resolve the conflict explicitly; never restore an old snapshot over new user work.
7. A binary rollback must preserve Bundle IDs, groups and storage. It must not uninstall a production app or clear iCloud/Keychain to make a regression disappear. Forward-written schemas or cloud state require a compatible recovery release and a verified backup; a previous binary alone is not a complete data rollback.
8. Native disposable-store tests prove local transaction behavior at their recorded SHA. No real user restore, device rollback or CloudKit rollback was performed in this continuation.

## Reproducible validation entrypoints

Use the current exact branch/SHA with existing manually dispatched workflows. The recorded dispatch JSON files contain exact selectors and original runtime artifact ID 42926628418.

- build-ios26-unsigned-ipa.yml: exact_test_selector for affected original-app unit/UI; phase2_app_with_motion for the documented integrated scope. The historical filename is not an iOS26 compatibility claim.
- validate-app-split.yml: paired_product_acceptance=true and paired_test_scope=product_and_share for the eight actual two-product/ingress cases.
- validate-app-split.yml: native_test_scope=production_runtimes for the two original independent companion engine cases.
- validate-app-split.yml: audit_release_resources=true for read-only existing certificate/profile/device metadata.
- validate-app-split.yml: signed_release_archives=true for actual archives and local export with the existing identity. Current export failure must be resolved before retry; no TestFlight flag is used.

## Exact blockers

Automatic review rejected the proposed Windows Gemini credential transfer to a new secret in the public owner repository. No secret was created and no alternative transfer was attempted. The approved live test is ready in source but not accepted.

Apple's actual export returned Cloud signing permission error and no matching App Store profiles. Both original archives compiled. A read-only local profile audit is in progress; required entitlements will not be removed.

The connected development host is Windows. Current native CI inventory has no physical device. Simulator or resource metadata cannot substitute for signed physical-device acceptance.
