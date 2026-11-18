# Hanlin — דוח שלב 3

מצב: **IN_PROGRESS**. החלטת שחרור: **NO_GO**. עודכן 18.11.2026 19:39 (Asia/Hebron).
מקור מקומי: `a9085987ede10b605124e385ecf790557dcd5dfd`.

## שתי האפליקציות

Hanlin AI ו־Hanlin MiniApps הם targets מקוריים נפרדים. שמות התצוגה עודכנו לשמות שאושרו; Bundle IDs, App Groups, כתובות חזרה, Keychain ונתיבי האחסון המקוריים נשמרו. ה־SDK וחוזי Host משותפים. MiniApps משתמשת במנועי NativeScript ו־Expo הקיימים. הקוד נשאר בענף ההמשך המאוחד; עצי העבודה הישנים והשינויים המקוריים לא נדרסו.

מסלול הבקשה/החזרה משתמש במזהים אטומים, אימות המקור וההקשר, דור/תוקף וביטול, ו־ACK לאחר קליטה בהקשר הנכון. ה־Shared Inbox מחובר ל־Composer המקורי עם העתקת קבצים פרטית מאומתת ושליחה מפורשת. זוהי אותה מערכת הרשאות ואותם חוזי Session.


## נתונים ומיגרציה

העברת נתוני MiniApps נשענת על HanlinProductTransfer והאחסון המקורי: snapshots ויומן טרנזקציה, SQLite/WAL, KV ו־UserDefaults, התאוששות לאחר עצירה, זיהוי שינויים ומניעת rollback שיאבד כתיבה חדשה. מאגרי השיחות המקוריים נשארים באפליקציית AI; אין מיגרציה הרסנית של נתוני משתמש בשלב הבדיקה.

25 קריאות בדיקה Native ב־17 מתודות של העברה/קונפליקט/rollback עברו בריצה 44223454456. 53 בדיקות foreground של הקשר והמסירה עברו במקביל לבדיקת MiniApps המקורית. ראיות אלה אינן תחליף למעבר בין שתי אפליקציות מותקנות או למכשיר חתום.


## תוצאות ריצה רלוונטיות

| ריצה / מקור | תוצאות בפועל | משמעות |
| --- | --- | --- |
| [44264360254](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44264360254) · `3542cc20` | build PASS; Runtime/Skills: 41/41 invocations ב־12 מתודות; UI: 21/45 PASS, 24 FAIL; Motion B/C: 0/2 | 33 Arguments ועוד 8 מתודות ללא פרמטרים הם 41 הרצות. אין לספור גם את סיכומי המתודות. |
| [44271250054](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44271250054) · `d7002ab1` | build PASS; Host: 23/24 PASS; UI: 9/19 PASS | עברו CPython אמיתי עם אישור ושחזור שיחה, NativeScript/Expo בתוך AI, ניווט ותרחישי Skill מקוריים. נותרו כשלים מפורשים. |
| [44273341845](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44273341845) · `7f5a8465` | build PASS; compact UI: 0/2 | ה־AX מראה כפתורי Composer מתחת למקלדת. תיקון חדש ממתין ל־Native. |


בדיקות NativeScript ו־Expo שעברו ב־44271250054 הן באפליקציית AI. הן אינן מחליפות הפעלה או בדיקות runtime באפליקציית MiniApps העצמאית.

MiniApps המקורית כבר צברה 20 בדיקות Native ו־7 UI ב־44233498638. בריצות runtime המאוחרות נחשפו בעיות App Groups ולאחריהן startup. תיקוני entitlements, loader, branding וחתימת Automatic המקורית נשמרו. ריצה 44270714044 פקעה במהלך קומפילציה לאחר 1,200 שניות, לפני UI. תקציב הכנת build מקומי הוגדל ל־2,400 שניות; תקציבי ה־job הם 90 דקות לעצמאית ו־150 ל־paired. לא שונו deadlines או תנאי קבלה של פעולות המוצר.

ריצת paired 44259936836 עברה שתי בניות, חתימות ובדיקת מכל משותף אמיתי של ה־OS, אך MiniApps יצאה לפני בדיקות; שמונת תרחישי paired/share לא בוצעו. שער standalone startup עבר כעת ב־44340805844; בדיקות runtime ו־paired נשארות עצמאיות ופתוחות.

## חתימה, מכשיר והפצה

שני ארכיוני Release למכשיר נבנו ב־44243216104 במקור `00a932d6`; Export נכשל ואינו מאומת למועמד הנוכחי. תעודת Apple Distribution הקיימת בתוקף לפי הבדיקה הרשומה. Bundle ID המקורי `com.itorah.hanlinminiapps` נרשם וקריאת APP_GROUPS/HEALTHKIT אומתה ב־44255527028. עדיין חסרים שיוך שתי הקבוצות המקוריות, יכולות ופרופילים תואמים (כולל Extended Virtual Addressing ב־AI), וכן רשומת App Store נפרדת.

לא זמין מכשיר פיזי מאושר בסביבת הבדיקות. בדיקות Simulator אינן VoiceOver, Stage Manager או מדידות ביצועים על מכשיר. העברת credential למודל החי וייצוא private key נדחו אוטומטית ולא בוצעו. לא נוצרה תעודה חלופית ולא הועלה TestFlight.

## התקדמות מאומתת — 18.11.2026 19:39

MiniApps העצמאית עברה 20 בדיקות אחסון ו־7 בדיקות ממשק ב־44340805844, עם אפס כשלונות ואפס דילוגים. קובץ ZIP מלא והראיות הגולמיות אומתו ב־SHA256. בדיקות NativeScript/Expo העצמאיות ובדיקות המעבר בין האפליקציות הן שערים נפרדים.

עשר בדיקות Markdown המקוריות עברו ב־44343462395, כולל עדכון callback בקישור של פסקה קיימת. שלוש התלויות מצביעות למקור 6bde022 המאומת. בדיקת Safari מתוך האפליקציה נשארת פתוחה.

OpenClaw חובר באמצעות 90 הצהרות מקוריות ב־21 מודולים, Yams, Node24.5 JITless, Runtime05, הקטלוג, כלי Skills, המשך SDK ומסך Skill Center. 11 מקרי בדיקה ניידים עברו, כולל 28 הרצות מקור ו־64 assertions; Native מורחב 44358114755 עדיין ממתין. אין מנוע, parser YAML או מערכת הרשאות חלופיים.

ריצות ה־iPad הרחבות בוטלו לפני ראיות מקרי בדיקה; ריצת Motion ב־0c822902 נכשלה בהכנת XCUITest לפני המקרים. המיפוי ותזמור ה־CI תוקנו ב־a9085987, לאחר 97 בדיקות ניתוב ו־34 בדיקות תשתית שעברו. ריצת Motion 44358121911 שומרת כעת את התוצאה הגולמית גם אם קורא התוצאות נתקע. אין להפוך build או dispatch לקבלת מוצר.

הכניסה לחשבון Apple הושלמה. קבוצות האפליקציות המקוריות אומתו על שני המוצרים וארבע ההרחבות; היכולות החסרות של שני המוצרים נשמרו ונקראו מחדש. יצירת פרופילים תואמים וייצוא חתום עדיין ממתינים. לא הועברו מפתחות או credentials; שערי המכשיר הפיזי והמודל החי נשארים פתוחים.

## קבלה שנותרה

- אימות iOS27 לתיקוני Host/interaction, Editor, compact/keyboard, NativeA2UI, Canvas, Safari, מסלולי UI והבדיקות החדשות.
- Motion B נשאר collapsed אחרי triple-tap הראשון; Motion C נכשל בהפעלה ללא PID והגיע למגבלת עשר דקות. מקור התקלה עדיין אינו מאומת, ולא בוצע תיקון Motion ספקולטיבי. 100 מחזורי Motion A ההיסטוריים נשמרים בהיקפם המקורי.
- Contextual Text Tools ביצע את פעולות התוכן המקוריות, אך רץ הבדיקה קרס בסיום; הבדיקה נשארת FAIL.
- שתי בדיקות EmbeddedResults המקוריות אחרי תיקון schema/AX; 21 בדיקות הרכיב הקודמות אינן הוכחת UI.
- לאחר baseline 20+7 שעבר ב־MiniApps העצמאית: אימות NativeScript/Expo, שמונת תרחישי paired/share המקוריים ופרופילי ההפצה.
- מודל חי, פרופילי Apple תואמים, exports, מכשיר פיזי ובדיקות VoiceOver/Stage Manager וביצועים. אלה שערים נפרדים.
- מפת 278 הדרישות נשארת עם 20 שורות בעלות ראיות חלקיות ו־0 קבלות מלאות; זה מדד ראיות ולא אחוז קוד שנכתב. אין להמיר בדיקות רכיב להשלמת מוצר.

## פרסום ואימות נוספים

האישור המפורש של בעל הפרויקט התקבל ונשמר. חסימת פרסום המקור נפתרה: ענף Hanlin פורסם ואומת על `a9085987ede10b605124e385ecf790557dcd5dfd`, והתלות המקורית Markdown פורסמה ואומתה על `6bde022876ef4af738c154b3d5c871984ef76195`. שלוש ההפניות המקוריות ניתנות לפתרון מהשרת. הרשאת ההמשך לאותם יעדים ופעולות נשמרה בקובצי ההנחיות ואין לבקש אותה מחדש.

הדחיות האוטומטיות המתועדות בהיסטוריה קדמו לאישור המפורש הזה. הפרסום כולל קוד, בדיקות, CI ודוחות בלבד; לא הועברו credentials, מפתחות חתימה, נתוני משתמש, יומנים גולמיים או שלושת הנתיבים המקוריים הלא־מנוהלים. לא בוצעו main merge או TestFlight.

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

בדיקות העבר נשמרות ב־SHA ובהיקף המקוריים. 15 בדיקות frontend parse מקומיות אינן הוכחת iOS. תנאי הקבלה של שני השלבים והשחרור עדיין לא הושלמו.

## מסמכי ראיות מחייבים

- `acceptance/NATIVE_TERMINAL_RESULTS_AND_LOCAL_REPAIRS_20261118.json`: תוצאות לפי method/case, מקור SHA, hashes, אבחנות ותיקונים ממתינים.
- `acceptance/LOCAL_CANDIDATE_VALIDATION_20261118.json`: 15 בדיקות parse מקומיות והגבול שלהן.
- `acceptance/ACCEPTANCE_REGISTER.json`: 53 רשומות ראיה, כל 30 משימות המקור, שערים ופרסום.
- `acceptance/INTEGRATION_CHANGE_MANIFEST.json`: commits ונתיבים מהבסיס המקורי, תוך שימור נתיבים לא־מנוהלים.
- `PHASE_2_INTEGRATION_LEDGER.json`, `PHASE_3_INTEGRATION_LEDGER.json` ומטריצות הקבלה: חלוקה מלאה 4+20+6, ללא כפילות או מחיקה של משימות.
