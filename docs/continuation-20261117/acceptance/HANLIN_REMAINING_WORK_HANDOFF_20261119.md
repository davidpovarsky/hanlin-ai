# HANLIN — מסירת פערים מאומתת, 19.11.2026

**מועד בדיקה:** 2026-11-19 14:15 UTC; **מטרת המסמך:** מה נותר פתוח, ראיות מדויקות, מסירת עבודה וקריטריוני סגירה. אין כאן אישור הפצה או טענה שכל קוד עודכן.

## תמונת אמת
- 30 משימות מקור נבדקו ישירות ב־Asana בבדיקה זו: **1 DONE (SDK-01, ביקורת קוד בלבד), 29 OPEN**.
- Phase 2: IN_PROGRESS; Phase 3: IN_PROGRESS; **Release: NO-GO**. אין לשנות completed לפני DoD.
- Branch: codex/hanlin-product-completion-20261117; HEAD בזמן צילום ההתחלה: 114c98d4fc9228882f89efd74bfa011f3a4830e0 (קומיט מסירה/תיעוד). בסיס קוד מוצר אחרון בסנאפשוט: ab581ece28f7ec8120019e4c926d67cd99dfcff6; main f7082624e2d1c81ba58f2ebdac76224e008c7292.
- PR16 מוזג ל־main **רק** workflow upstream proof, ולא את מלוא מוצר Hanlin. אין merge של ענף המוצר ל־main.
- מפת קבלה של **278 יכולות** נמדדה לאחרונה ב־2026-11-19 04:46 UTC: **20 ראיות חלקיות, 0 יכולות בעלות קבלה מלאה** באותו סנאפשוט. אין לגזור ממנה סטטוס חדש של ריצה מאוחרת. מרשם הראיות המקורי מכיל 106 רשומות נכון לאותו צילום.
- באיתור Asana קיימות גם משימות תוספת (OpenUI, Presentation SDK, Live V17) ומשימות חפ״ק ישנות. **אינן כלולות במכנה 30**; גם הן אינן סגורות.
- מספר תיקיות evidence חדשות ב־docs/product-split/evidence/durability-fix וקובץ foreground-results.json נמצאו לא מנוהלים על ידי Git בעת הבדיקה. **לא שונו, לא נוספו ולא נמחקו**; ייתכן שמדובר בעבודה מקבילה. התיעוד הזה נוצר במסמכי acceptance ייעודיים בלבד.

## מה אכן עבר
- Skills/Yams/Python Apple workflow 44453570922 — SUCCESS, אבל לא קבלה מלאה של מסכי Skill Center/התקנה פיזית.
- PR16 Upstream proof merged, portable 93 tests ועימות 139 Host files עברו; gate production לא עבר בגלל secret קריאה מצומצם חסר ומחזור proof שלם שלא בוצע.
- Paired historical run 44447129341 — 5/8 PASS, כולל העברת חבילה/Storage/reopen/rollback וארבע בדיקות Host; 3/8 UI FAIL.
- Historical iPad run 44447126258 — 14/14 unit PASS, 4/17 UI PASS, 13/17 UI FAIL; source עתיק ואינו הוכחה לקוד הנוכחי.
- Anytype Wave15 run 44476680808 — SUCCESS לפי מסירה קודמת; Maktabah 44480833870 — FAIL לפי מסירה קודמת; לא נבדקו מחדש בביקורת GitHub הנוכחית.

## נושאים חוסמים לפי סדר קריטי
1. **DATA/Composer unit:** Run 44466305765 נעצר לפני tests בשלב Prepare verified embedded RuntimeCore. הלוג מאמת שה־lock עבר ולבסוף התקבל **release not found**. יש לפתור את ארטיפקט/Release RuntimeCore המדויק, ואז להפעיל selectors מקוריים של Keychain, חשבונות, session/transport ו־Composer.
2. **A2UI Native:** Run 44466312634 הגיע לבדיקות מקוריות. **6 בדיקות בוצעו, 5 נכשלו, מתוכן 3 unexpected**. exit 65 אינו '65 בדיקות'. הראיות כוללות 0 components מול 5 צפויים, ו־InvalidTransition idle → failed(deinit). יש לתקן lifecycle/rich-surface, למדוד שוב TTL/stream/replay/ביצועים.
3. **Hanlin ↔ MiniApps paired:** Run 44466308930 — native original acceptance לא העביר את כל המקרים, job failed. חייבים לחלץ את case-level artifact, לתקן request/return/cancel/share, לשמר Storage/reopen/rollback ולבדוק מסירת תוצאות לסוכן.
4. **Composer/Chat/Safari:** תו ראשון והסמן התבלבלו במבחני UI הישנים; תיקוני הקוד פורסמו ב־6d629578 ואחריו. Runs 44458939610 ו־44459110497 נכשלו לפני UI בשל שגיאות הקומפילציה הישנות ב־SurfaceViewModel.components וב־#require ללא try; קוד 6b5dc2 תיקן את ה־API של הבדיקות, אך אין PASS מחודש ל־compact, ספק, selection, consent, UI/IME.
5. **Motion:** Run 44465711797 מסומן failure, אבל **ה־XCUITest הנייטיבי testDRapidInputDiagnosticOnly עבר (1 test, 0 failures)**. לאחר סיום ה־test קרתה שגיאת **AssertionError** בסקריפט post-test; נדרש לתקן/להסביר gate/trace. Motion B rapid reversal נכשל בעבר; 5 presets × 20 cycles ונגישות נשארים פתוחים.
6. **Skills/Host/Core:** סגירה נדרשת של Skills CRUD/disable/re-enable/import/consent/UI, NativeScript/Expo APIs, חתימת חוזי Host, פרטי חשבון והרשאות, Source/Navigation וצרכני Anytype/Otzaria בממשקים המקוריים.
7. **CloudKit/Auth/Storage:** אטומיות ומניעת כתיבה לאחר מחיקה, בידוד משתמשים, Keychain rollback, App Group וסנכרון CloudKit דורשים ראיות חיות ואת בדיקות ה־negative המקוריות; הצלחת יחידות נפרדות לא מספיקה.
8. **Upstream protection:** GitHub secret ייעודי HANLIN_UPSTREAM_PROTECTION_READ_TOKEN עם Administration:read על המאגר בלבד עדיין לא הוגדר; להריץ ניסיון נכשל/מוצלח, הגנת שרת, merge ו־rollback ללא עקיפת ההגנות.
9. **Apple release:** Xcode מחזיר NoProfile אף ש־CMS של 6 פרופילים תקין; אין IPA חתום לשתי האפליקציות והרחבותיהן. לא נצפה iPad פיזי עם USB developer transport; אין אישור TestFlight או בדיקת hardware.
10. **Semantic parity:** לכל 278 יכולות ו־26 החלטות UX צריך מקור, אימות UI/אבטחה/נגישות/מכשיר וסימוכין ב־SHA החדש. OpenUI, Live V17, Presentation SDK ו־AppIntents/Extensions לא אושרו במלואם.

## כל 30 משימות המקור — מצב Asana חי, 19.11.2026
| קוד ומשימת Asana | שלב | מצב | המשך חובה |
|---|---|---|---|
| [SDK-01](https://app.asana.com/0/0/1220542174541844) — Audit package/source/host/platform | 1 | DONE (ביקורת בלבד) | הביקורת הושלמה ונשמרה; אין להעביר DONE לכל המשימות התלויות |
| [SKILL-YAMS-02](https://app.asana.com/0/0/1220546710401425) — Yams source package and app adoption | 1 | OPEN | לקשור הצלחת 44453570922 לבדיקות Store/UI המלאות |
| [WAVE-A](https://app.asana.com/0/0/1219605220234118) — Canonical legacy baseline and product parity | 1 | OPEN | המשך קבלת מוצר ולא רק מיפוי מקור/תלויות |
| [SKILL-UPSTREAM-01](https://app.asana.com/0/0/1220546608370437) — Pinned upstream PR9/maintenance and accepted safe pipeline | 1 | OPEN | להגדיר Secret מצומצם לקריאת branch protection, לבצע negative/green/merge/rollback |
| [SDK-03](https://app.asana.com/0/0/1220373608755846) — NativeScript targeted TS SDK/Host capabilities (not Full-SDK metadata) | 2 | OPEN | בדיקות Native ו־UI במוצר המקורי, שגיאות נוכחיות ותיעוד לפי SHA |
| [SDK-04](https://app.asana.com/0/0/1220373832827086) — Expo SDK generated bridge and native-api | 2 | OPEN | בדיקות Native ו־UI במוצר המקורי, שגיאות נוכחיות ותיעוד לפי SHA |
| [INT-03](https://app.asana.com/0/0/1220374076374903) — NativeScript runtime.execute/TS/Shell and scheduler | 2 | OPEN | בדיקות Native ו־UI במוצר המקורי, שגיאות נוכחיות ותיעוד לפי SHA |
| [SKILL-RUNTIME-05](https://app.asana.com/0/0/1220546710400478) — Passive engine facts/readiness planner and real skill execution | 2 | OPEN | בדיקות Native ו־UI במוצר המקורי, שגיאות נוכחיות ותיעוד לפי SHA |
| [A2UI-02](https://app.asana.com/0/0/1220489383643571) — Rich-content envelope for agent output and tool result | 2 | OPEN | בדיקות Native ו־UI במוצר המקורי, שגיאות נוכחיות ותיעוד לפי SHA |
| [A2UI-03](https://app.asana.com/0/0/1220489258419968) — Original SwiftUI A2UI surfaces and bindings | 2 | OPEN | בדיקות Native ו־UI במוצר המקורי, שגיאות נוכחיות ותיעוד לפי SHA |
| [A2UI-04](https://app.asana.com/0/0/1220489257946325) — Events, RPC, action broker, permissions | 2 | OPEN | בדיקות Native ו־UI במוצר המקורי, שגיאות נוכחיות ותיעוד לפי SHA |
| [A2UI-05](https://app.asana.com/0/0/1220489600044406) — Streaming, lifecycle, replay | 2 | OPEN | 5 כישלונות ב־6 בדיקות (3 חריגים) ב־44466312634; 65 הוא exit code; לתקן ולבדוק מטריצת ביצועים |
| [A2UI-09](https://app.asana.com/0/0/1220491240486416) — Native images, links, MP4/HLS, YouTube and galleries | 2 | OPEN | בדיקות Native ו־UI במוצר המקורי, שגיאות נוכחיות ותיעוד לפי SHA |
| [SKILL-AST-04](https://app.asana.com/0/0/1220546608350406) — Original Tree-sitter/AST passive skill dependencies | 2 | OPEN | בדיקות Native ו־UI במוצר המקורי, שגיאות נוכחיות ותיעוד לפי SHA |
| [CHATUX-MOTION](https://app.asana.com/0/0/1220546846740594) — Native animated disclosure, transitions and shimmer | 2 | OPEN | בדיקת Motion D עברה 1/1; ה־post-test assertion נכשל; לתקן שער אימות, ולהעביר rapid reversal וכל 20 מחזורים |
| [COMPOSER](https://app.asana.com/0/0/1220539644804804) — Approved native chat bubble and MorphView parity | 2 | OPEN | לפתור build/keyboard/IME ותזוזת סמן על iPhone |
| [ACTIVE-CHIPS](https://app.asana.com/0/0/1220541898122292) — Active tool chips above bubble / expanded state | 2 | OPEN | בדיקות Native ו־UI במוצר המקורי, שגיאות נוכחיות ותיעוד לפי SHA |
| [SKILL-UX-QA-06](https://app.asana.com/0/0/1220546710417618) — Skill Center real state/remediation and UX | 2 | OPEN | בדיקות Native ו־UI במוצר המקורי, שגיאות נוכחיות ותיעוד לפי SHA |
| [SDK-PARENT](https://app.asana.com/0/0/1219613181643838) — Shared Hanlin Agent/Chat SDK and Host integration | 2 | OPEN | בדיקות Native ו־UI במוצר המקורי, שגיאות נוכחיות ותיעוד לפי SHA |
| [SDK-02](https://app.asana.com/0/0/1220542419128390) — Importable Swift Agent/Chat/Streaming/Skills/MCP package | 2 | OPEN | בדיקות Native ו־UI במוצר המקורי, שגיאות נוכחיות ותיעוד לפי SHA |
| [SDK-03-HOST](https://app.asana.com/0/0/1220542199992529) — HostIntegration actions/policy/results/navigation | 2 | OPEN | בדיקות Native ו־UI במוצר המקורי, שגיאות נוכחיות ותיעוד לפי SHA |
| [SDK-05-DATA](https://app.asana.com/0/0/1220542199999956) — ConversationStore, Keychain, App Group, persistence | 2 | OPEN | לתקן הכנת RuntimeCore, לבדוק Keychain/CloudKit/מחיקת היסטוריה |
| [SDK-04-UI](https://app.asana.com/0/0/1220542174541940) — Shared SwiftUI ChatView/Composer/Thinking/A2UI | 2 | OPEN | לתקן A2UI Surface, שיבוש טיוטה, Safari, Consent ובחירה חלקית |
| [SKILL-OPENCLAW-03](https://app.asana.com/0/0/1220546571007976) — Original OpenClaw eligibility/gating subset and embedded node | 2 | OPEN | בדיקות Native ו־UI במוצר המקורי, שגיאות נוכחיות ותיעוד לפי SHA |
| [SPLIT-PARENT](https://app.asana.com/0/0/1219605220179926) — Two independent apps with product acceptance | 3 | OPEN | לסיים return/cancel/share ואימות שתי אפליקציות חתומות |
| [WAVE-K](https://app.asana.com/0/0/1219656771637321) — Two targets, security and shared data migration | 3 | OPEN | שתי אפליקציות חתומות, בדיקות חזרה/ביטול/שיתוף, מכשיר פיזי וקבלת 278 דרישות |
| [WAVE-J](https://app.asana.com/0/0/1219656771149125) — Approved Hanlin AI shell IA/UX | 3 | OPEN | שתי אפליקציות חתומות, בדיקות חזרה/ביטול/שיתוף, מכשיר פיזי וקבלת 278 דרישות |
| [WAVE-L](https://app.asana.com/0/0/1219656771460030) — Hanlin MiniApps independent, return to agent | 3 | OPEN | לטפל בכשל paired 44466308930 |
| [WAVE-H](https://app.asana.com/0/0/1219605235147314) — Final original source parity/non-regression matrix | 3 | OPEN | 278 דרישות, כעת 20 חלקיות ו־0 שהתקבלו בסנאפשוט הקודם |
| [WAVE-I](https://app.asana.com/0/0/1219605282038820) — iOS 26/27, real iPad and release candidate | 3 | OPEN | לפתור NoProfile, לייצא IPA חתומות ולבדוק iPad פיזי |

## משימות נוספות מחוץ ל־30
- Hanlin OPENUI-01 canonical: Asana 1220596988729175 — פתוחה; שלוב React/SwiftUI ו־shared state אינו מאומת; המשימה האחרת 1220596895787240 היא historical duplicate, לא שתי תכניות נפרדות.
- HANLIN-PRESENTATION-SDK-01: Asana 1220636669052920 — פתוחה; per-app/per-chat/per-message presentation registry, consumers/permissions.
- CHATUX-LIVE-V17: Asana 1220588718902198 — פתוחה; actual UI/tool/consent/source components.
- iSH/ARM64 POC: Asana 1220546608369952 — פתוחה, POC ולא שער שמונע כל Skills core.
- חפ״ק סוכנים/תיאום: project 1220539375574127 מכיל 20 משימות פתוחות כולל QA, Release/Dependencies ו־lanes. אלו משימות ניהוליות/היסטוריות; לא להוסיף למניין 30 או לסמן DONE אוטומטית.

## סדר עבודה לסוכן הבא — בכל שלב כתוב במקור המשימה
1. לקרוא את מסמך זה, את HANLIN_NATIVE_CI_TRIAGE_20261119.md ואת 30 משימות המקור. לבדוק מחדש branch SHA לפני תיקונים; לשמר את התיקיות הלא־מנוהלות.
2. לפתור RuntimeCore release lookup, להריץ מקבץ DATA/Composer על exact source, לשמור raw logs/xcresult והוכחות.
3. לטפל ב־A2UI 5/6 failures לפי test names ולתקן lifecycle ו־0/5 components; להריץ אותם selectors ולשמור acceptance diff.
4. לחקור paired artifact, לסגור return/cancel/share, תזמון טקסט לפני Send, Content/Safari/partial selection/Consent; לשמור rollback.
5. לתקן את post-test Motion assertion בלבד מבלי למחוק evidence של XCUITest PASS; לסגור B rapid toggle וכל 100 מחזורי preset.
6. לבדוק Skill Center מקורי, Data/CloudKit/Keychain/Host ואימוץ בששת צרכנים ובהם Anytype/Otzaria.
7. לאמת upstream proof עם GitHub credential מצומצם, ואז signing/profiles, 2 signed exports, iPad פיזי, QA ו־278 parity.
8. לעדכן משימת Asana המקורית עם commit, exact SHA, run, PASS/FAIL/NOT_RUN, ורק לאחר DoD מלא completed=true; לפרסם סטטוס NO-GO עד אז.

**כללי מסירה:** אין להמציא PASS מהצלחת build, לא להמיר exit code למספר test failures, ולא להפוך תוצאות מקור ישן להוכחת current source. כל credentials נשמרים בסביבת השירות ולא מועתקים למסמכים. יש הרשאת בעלים לפעולות העבודה הדרושות; אין לעקוף הגנות שרת.
