# Hanlin release checklist

Decision: **NO_GO**. Source snapshot: `4b765b447d7d47426498d1632581af59facd3f2f`. Updated 18.11.2026 16:58 (Asia/Hebron).
This is a reviewable local candidate, not phase acceptance or distribution approval.

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
- [x] Preserve 30 original tasks, 4+20+6 mapping and all 46 evidence records.
- [x] Read all three previously pending native runs to terminal status and retain their failures.
- [x] Record Runtime/Skills 41/41 at 3542cc20; Host 23/24 and UI 9/19 at d7002ab1; wide UI 21/45 and Motion 0/2; compact UI 0/2.
- [x] Record historical SDK53/Core46/transfer25/MiniApps20+7/editor6/Unicode20/Resolver21 at their actual SHAs, without double counting.
- [x] Build both original device Release archives at 00a932d6 (historical scope only).
- [x] Register the original MiniApps Bundle ID and read back APP_GROUPS/HEALTHKIT in 44255527028.
- [ ] Obtain exact public source publication approval; publish original Markdown 6bde022 before the dependent main candidate.
- [ ] Build and test the current iOS27 candidate and its original Host interaction/writer regressions.
- [ ] Accept original compact2, affected NativeA2UI7, long/RTL drafts, approved Morph interactions, and current wide UI failures.
- [ ] Verify original Canvas and internal Safari UI; retain contextual-tools runner-teardown failure until resolved.
- [ ] Resolve Motion B/C: collapsed first triple-tap and launch without process ID are failures.
- [ ] Accept original EmbeddedResultsUI2 after schema/AX repair; native21 component pass is narrower.
- [ ] Verify standalone MiniApps startup with both original real OS App Groups, then original NativeScript/ExpoUI2. Keep the 2400s cold-build budget separate from product deadlines.
- [ ] Accept original paired/share8 after standalone startup; earlier paired build/signature/container passes executed zero UI cases.
- [ ] Finish behavior-specific feature/UX coverage. The 278 requirements currently have 20 partially evidenced rows and 0 fully accepted; do not treat this as code completion percentage.
- [ ] Perform an approved actual live-model/tool/persistence run. No credential export has occurred.
- [ ] Assign original Apple App Groups, required capabilities and compatible profiles for both apps and all four extensions.
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
- **LIVE_MODEL_PROVIDER — BLOCKED_CREDENTIAL_EXPORT_APPROVAL**: Existing host Gemini credential is available, but automatic review rejected creating a new secret in the public GitHub repository. Exact transfer requires explicit owner approval, or approved local Mac/device execution with its own existing account. No credential was transferred.
- **SIGNED_PROVISIONING — EXACT_APPLE_PORTAL_CONFIGURATION_REQUIRED**: Existing identity is valid. Original MiniApps Bundle ID plus App Groups/HealthKit capability toggles registered and read back. Need both actual group assignments, all original required capability approvals and compatible profiles (AI lacks Extended Virtual Addressing), plus the separate App Store record. Official API exposes no App Group assignment or create-app endpoint; the Browser plugin exposes no callable control JS in this session. No browser account session was probed.
- **APPROVED_FULL_VISUAL_REFERENCE — PARTIAL_REFERENCE**: Original 26-decision summary and authenticated Composer reference exist; full October master prompt was not found. Source/visual conclusions must state their actual references.
- **PUBLIC_SOURCE_PUBLICATION — BLOCKED_AUTOMATIC_APPROVAL_REVIEW**: Explicit approval for reviewed source/build/test/documentation on public davidpovarsky/hanlin-ai branch codex/hanlin-product-completion-20261117 and original dependency davidpovarsky/hanlin-streaming-markdown branch codex/hanlin-markdown-link-continuation-20261118. Publish upstream6bde022 first because all main candidate pins reference it. No credential, ignored evidence or original untracked data publication.

## פרסום ואימות נוספים

הקוד המקומי הוא `4b765b447d7d47426498d1632581af59facd3f2f`; הענף הציבורי המאומת עדיין `46a99c050f18b91778eba571f2202b1ad08632c9`. נשמרו 16 commits מקומיים אחרי הפרסום האחרון, לפני commit הדוחות הזה. קובץ הסקירה הסופי יכלול גם את commit הדוחות.

מנגנון אישור אוטומטי דחה שוב push לאחר אישור כללי להמשיך, ונדרש אישור מפורש לתוכן וליעדי הפרסום הציבוריים. לא בוצע ניסיון חלופי אחרי הדחייה. היעדים הקונקרטיים הם:

1. `https://github.com/davidpovarsky/hanlin-streaming-markdown.git`, ענף `codex/hanlin-markdown-link-continuation-20261118`, commit `6bde022876ef4af738c154b3d5c871984ef76195` מעל `4072507bf5c5a1c9786d4c9a607873e65be59cc8`.
2. `https://github.com/davidpovarsky/hanlin-ai.git`, ענף `codex/hanlin-product-completion-20261117`, חבילת הקוד/בדיקות/מסמכים שמעל `46a99c050f18b91778eba571f2202b1ad08632c9`.

יש לפרסם את תלות Markdown תחילה: שלוש ההפניות המקוריות ב־Hanlin כבר תואמות ל־SHA המקומי החדש. זו תלות מקומית שטרם ניתנת לפתרון מהשרת הציבורי. החבילה אינה כוללת מפתחות, credentials, יומנים גולמיים, הקלטות, נתוני משתמש או את שלושת הנתיבים המקוריים הלא־מנוהלים.

לאחר הפרסום המאושר יש לאמת את ראשי הענפים ולהריץ את שערי iOS27 הרלוונטיים. 15 קובצי Swift ששונו עברו frontend parse ב־Windows; בדיקת diff, JSON והתאמת pins עברו. אין בכך build, typecheck או PASS של iOS.


## מסמכי ראיות מחייבים

- `acceptance/NATIVE_TERMINAL_RESULTS_AND_LOCAL_REPAIRS_20261118.json`: תוצאות לפי method/case, מקור SHA, hashes, אבחנות ותיקונים ממתינים.
- `acceptance/LOCAL_CANDIDATE_VALIDATION_20261118.json`: 15 בדיקות parse מקומיות והגבול שלהן.
- `acceptance/ACCEPTANCE_REGISTER.json`: 46 רשומות ראיה, כל 30 משימות המקור, שערים ופרסום.
- `acceptance/INTEGRATION_CHANGE_MANIFEST.json`: commits ונתיבים מהבסיס המקורי, תוך שימור נתיבים לא־מנוהלים.
- `PHASE_2_INTEGRATION_LEDGER.json`, `PHASE_3_INTEGRATION_LEDGER.json` ומטריצות הקבלה: חלוקה מלאה 4+20+6, ללא כפילות או מחיקה של משימות.
