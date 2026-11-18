# Hanlin — דוח שלב 3

מצב: **IN_PROGRESS**. החלטת שחרור: **NO_GO**. עודכן 18.11.2026 16:58 (Asia/Hebron).
מקור מקומי: `4b765b447d7d47426498d1632581af59facd3f2f`.

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

ריצת paired 44259936836 עברה שתי בניות, חתימות ובדיקת מכל משותף אמיתי של ה־OS, אך MiniApps יצאה לפני בדיקות; שמונת תרחישי paired/share לא בוצעו. נדרש standalone startup מוצלח לפני ניסיון paired נוסף.

## חתימה, מכשיר והפצה

שני ארכיוני Release למכשיר נבנו ב־44243216104 במקור `00a932d6`; Export נכשל ואינו מאומת למועמד הנוכחי. תעודת Apple Distribution הקיימת בתוקף לפי הבדיקה הרשומה. Bundle ID המקורי `com.itorah.hanlinminiapps` נרשם וקריאת APP_GROUPS/HEALTHKIT אומתה ב־44255527028. עדיין חסרים שיוך שתי הקבוצות המקוריות, יכולות ופרופילים תואמים (כולל Extended Virtual Addressing ב־AI), וכן רשומת App Store נפרדת.

לא זמין מכשיר פיזי מאושר בסביבת הבדיקות. בדיקות Simulator אינן VoiceOver, Stage Manager או מדידות ביצועים על מכשיר. העברת credential למודל החי וייצוא private key נדחו אוטומטית ולא בוצעו. לא נוצרה תעודה חלופית ולא הועלה TestFlight.

## קבלה שנותרה

- אימות iOS27 לתיקוני Host/interaction, Editor, compact/keyboard, NativeA2UI, Canvas, Safari, מסלולי UI והבדיקות החדשות.
- Motion B נשאר collapsed אחרי triple-tap הראשון; Motion C נכשל בהפעלה ללא PID והגיע למגבלת עשר דקות. מקור התקלה עדיין אינו מאומת, ולא בוצע תיקון Motion ספקולטיבי. 100 מחזורי Motion A ההיסטוריים נשמרים בהיקפם המקורי.
- Contextual Text Tools ביצע את פעולות התוכן המקוריות, אך רץ הבדיקה קרס בסיום; הבדיקה נשארת FAIL.
- שתי בדיקות EmbeddedResults המקוריות אחרי תיקון schema/AX; 21 בדיקות הרכיב הקודמות אינן הוכחת UI.
- הפעלה עצמאית של MiniApps עם שתי קבוצות App Group אמיתיות, NativeScript ו־Expo; אחריה שמונת תרחישי paired/share המקוריים.
- מודל חי, פרופילי Apple תואמים, exports, מכשיר פיזי ובדיקות VoiceOver/Stage Manager וביצועים. אלה שערים נפרדים.
- מפת 278 הדרישות נשארת עם 20 שורות בעלות ראיות חלקיות ו־0 קבלות מלאות; זה מדד ראיות ולא אחוז קוד שנכתב. אין להמיר בדיקות רכיב להשלמת מוצר.

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
