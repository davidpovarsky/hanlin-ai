# Hanlin release checklist

Decision: **NO_GO**. Source snapshot: `a9085987ede10b605124e385ecf790557dcd5dfd`. Updated 18.11.2026 19:39 (Asia/Hebron).
The source candidate is published; native phase acceptance and release gates remain open.

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

- [x] Preserve original worktrees, original untracked data and the historical baseline.
- [x] Retain the original SDK, Host, provider accounts, engines, permissions and stores.
- [x] Preserve 30 original tasks, 4+20+6 mapping and all 53 evidence records.
- [x] Read all three previously pending native runs to terminal status and retain their failures.
- [x] Record Runtime/Skills 41/41 at 3542cc20; Host 23/24 and UI 9/19 at d7002ab1; wide UI 21/45 and Motion 0/2; compact UI 0/2.
- [x] Record historical SDK53/Core46/transfer25/MiniApps20+7/editor6/Unicode20/Resolver21 at their actual SHAs, without double counting.
- [x] Build both original device Release archives at 00a932d6 (historical scope only).
- [x] Register the original MiniApps Bundle ID and read back APP_GROUPS/HEALTHKIT in 44255527028.
- [x] Record explicit owner publication approval and verify both original public branch heads, including Markdown6bde022.
- [ ] Build and test the current iOS27 candidate and its original Host interaction/writer regressions.
- [ ] Accept original compact2, affected NativeA2UI7, long/RTL drafts, approved Morph interactions, and current wide UI failures.
- [ ] Verify original Canvas and internal Safari UI; retain contextual-tools runner-teardown failure until resolved.
- [ ] Resolve Motion B/C: collapsed first triple-tap and launch without process ID are failures.
- [ ] Accept original EmbeddedResultsUI2 after schema/AX repair; native21 component pass is narrower.
- [x] Verify standalone MiniApps baseline startup/storage/catalog: actual20 storage+7 UI passed44340805844 at87cf107c, zero skips/failures, full artifact SHA256 verified.
- [ ] Accept separate standalone NativeScript/ExpoUI2 and original distribution App Groups/profiles; simulator signing does not prove distribution.
- [x] Verify exact original Markdown consumer10 native cases atcda167f4 with dependency6bde022; original Safari app UI remains open.
- [ ] Accept expanded original OpenClaw policy, Runtime05/SDK consumers and Skill UI on Apple; portable11/28original/64assertions do not close this gate.
- [ ] Accept original paired/share8 after standalone startup; earlier paired build/signature/container passes executed zero UI cases.
- [ ] Finish behavior-specific feature/UX coverage. The 278 requirements currently have 20 partially evidenced rows and 0 fully accepted; do not treat this as code completion percentage.
- [ ] Perform an approved actual live-model/tool/persistence run. No credential export has occurred.
- [x] Assign/verify both original Apple App Groups for both products and all four extensions, and save/read back missing original required capabilities.
- [ ] Regenerate compatible profiles and verify actual signed exports of both apps and four extensions.
- [ ] Produce signed exports with exact entitlements; verify current branding and original automatic signing in final archives.
- [ ] Finish the separate MiniApps App Store record through the existing owner account.
- [ ] Install on an accessible supported physical iPad/iPhone and verify VoiceOver, Stage Manager, RTL, lifecycle and measured performance.
- [ ] Verify actual Share/translation/widget/notification and account/CloudKit entrypoints wherever required; Host fixtures are narrower.
- [ ] Resolve the full visual-reference gap with explicit reference scope.
- [ ] Review final version/build, artifacts and rollback eligibility before distribution.
- [ ] Release only after required acceptance is proven. No main merge or TestFlight upload has occurred.

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


## Exact native results

| ריצה / מקור | תוצאות בפועל | משמעות |
| --- | --- | --- |
| [44264360254](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44264360254) · `3542cc20` | build PASS; Runtime/Skills: 41/41 invocations ב־12 מתודות; UI: 21/45 PASS, 24 FAIL; Motion B/C: 0/2 | 33 Arguments ועוד 8 מתודות ללא פרמטרים הם 41 הרצות. אין לספור גם את סיכומי המתודות. |
| [44271250054](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44271250054) · `d7002ab1` | build PASS; Host: 23/24 PASS; UI: 9/19 PASS | עברו CPython אמיתי עם אישור ושחזור שיחה, NativeScript/Expo בתוך AI, ניווט ותרחישי Skill מקוריים. נותרו כשלים מפורשים. |
| [44273341845](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44273341845) · `7f5a8465` | build PASS; compact UI: 0/2 | ה־AX מראה כפתורי Composer מתחת למקלדת. תיקון חדש ממתין ל־Native. |

## Current independent blockers

- **PHYSICAL_DEVICE — UNAVAILABLE**: Authorized supported physical iPad/iPhone accessible to the testing host; existing CI audit finds no physical device.
- **LIVE_MODEL_PROVIDER — CI_PROVIDER_SECRET_MISSING**: HANLIN_ACCEPTANCE_GEMINI_API_KEY is absent from CI. Prior automatic review rejected exporting the existing host credential; that history remains, and no secret was transferred. Complete on a host with an already authorized provider account or with the required CI secret supplied through an approved credential route.
- **SIGNED_PROVISIONING — PROFILES_EXPORT_PENDING**: Apple Developer authentication completed. Both original groups are assigned to MiniApps and verified on AI plus all four extensions. Required missing capabilities were saved and read back: Extended Virtual Addressing on both apps, Time Sensitive Notifications and WeatherKit on MiniApps. Original certificate retained. Automatic profile regeneration, signed exports and separate Mini App Store record remain pending.
- **APPROVED_FULL_VISUAL_REFERENCE — PARTIAL_REFERENCE**: Original 26-decision summary and authenticated Composer reference exist; full October master prompt was not found. Source/visual conclusions must state their actual references.
- **PUBLIC_SOURCE_PUBLICATION — RESOLVED**: Both reviewed original public branches are published and verified after explicit owner consent. Reuse the recorded authorization for the same scoped actions; native acceptance is separate.

## Latest verified native results and pending runs

| Run / source | Actual result | Scope |
| --- | --- | --- |
| [44340805844](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44340805844) · `87cf107c` | EXECUTED_PASS | Standalone MiniApps baseline: 20 storage + 7 UI, zero failures/skips |
| [44343462395](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44343462395) · `cda167f4` | EXECUTED_PASS | Exact original Markdown native consumer: 10 methods. Main-app/Safari UI NOT_RUN |
| [44342780366](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44342780366) · `87cf107c` | BUILD_PASS_TESTS_NOT_RUN | Device-family guard correctly rejected mixed iPad/compact iPhone selectors |
| [44342772767](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44342772767) · `87cf107c` | BUILD_PASS_CANCELLED_TESTS_NOT_RUN | Original wide UI/EmbeddedResults run cancelled before preserved case events; cancellation cause not established |
| [44345443838](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44345443838) · `0c822902` | BUILD_PASS_RUNNER_PREPARATION_FAILED | Motion B/C not executed: XCTest runner stalled/crashed before a case; original failures remain open |
| [44349634595](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44349634595) · `0c822902` | CANCELLED_TESTS_NOT_RUN | Host/Editor/NativeA2UI iPad validation cancelled by shared manual validation concurrency |
| [44356501045](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44356501045) · `fd4149ac` | PLANNER_FAILED_TESTS_NOT_RUN | New OpenClaw test path lacked routing; corrected at a9085987 without weakening test coverage |

| Run / source | Pending scope | Status |
| --- | --- | --- |
| [44349642458](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44349642458) · `0c822902` | Two original compact Composer iPhone UI methods | DISPATCHED_AWAITING_TERMINAL_EVIDENCE |
| [44351078724](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44351078724) · `0c822902` | Standalone MiniApps original NativeScript/Expo UI2 | DISPATCHED_AWAITING_TERMINAL_EVIDENCE |
| [44358114755](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44358114755) · `a9085987` | Original OpenClaw policy, affected Runtime05/catalog/SDK and Skill UI | DISPATCHED_AWAITING_TERMINAL_EVIDENCE |
| [44358121911](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44358121911) · `a9085987` | Original Motion B/C with retained raw result and startup diagnostics | DISPATCHED_AWAITING_TERMINAL_EVIDENCE |

## מסמכי ראיות מחייבים

- `acceptance/NATIVE_TERMINAL_RESULTS_AND_LOCAL_REPAIRS_20261118.json`: תוצאות לפי method/case, מקור SHA, hashes, אבחנות ותיקונים ממתינים.
- `acceptance/LOCAL_CANDIDATE_VALIDATION_20261118.json`: 15 בדיקות parse מקומיות והגבול שלהן.
- `acceptance/ACCEPTANCE_REGISTER.json`: 53 רשומות ראיה, כל 30 משימות המקור, שערים ופרסום.
- `acceptance/INTEGRATION_CHANGE_MANIFEST.json`: commits ונתיבים מהבסיס המקורי, תוך שימור נתיבים לא־מנוהלים.
- `PHASE_2_INTEGRATION_LEDGER.json`, `PHASE_3_INTEGRATION_LEDGER.json` ומטריצות הקבלה: חלוקה מלאה 4+20+6, ללא כפילות או מחיקה של משימות.
