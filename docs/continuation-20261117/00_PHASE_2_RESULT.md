# Hanlin — דוח שלב 2

מצב: **IN_PROGRESS — אין עדיין קבלת שלב**. עודכן 18.11.2026 16:58 (Asia/Hebron).
מקור התיקונים המאוחד: `4b765b447d7d47426498d1632581af59facd3f2f`.
ענף: `codex/hanlin-product-completion-20261117`.

## מה שולב

ההמשך נשען על Hanlin Agent SDK, HostIntegration, ספקי המודלים, אחסון השיחות והמנועים המקוריים. שולבו מסלולי consent/allow/deny/cancel, תוצאות כלים ושמירת שיחה; ה־Composer, ה־Markdown, רכיבי A2UI/OpenUI וה־Motion נותרו מחוברים למקור המשותף. Runtime05 ו־Skill Center מחברים את הייבוא, התוכנית הפסיבית, המנוע האמיתי, ההרשאה, הביטול והראיות השמורות.

התיקונים כוללים את תצוגת המדיה וה־QuickLook המקוריים, שמירת טיוטה ומצב מקלדת, פתיחת שיחה עם ספק native/LOCAL שבאמת זמין, בחירת מודל ללא תלות במודל אופטימיזציה אופציונלי, חיפוש Unicode ללא קריסת String.Index, כלי טקסט בהקשר ההודעה, Canvas דרך CPython המקורי, ומסך עזרה מקורי ומדויק. לא נבנה סוכן AI או מנוע הרשאות נוסף.


## תוצאות Native סופיות שנקראו

שלוש הריצות שהיו ממתינות הסתיימו בכישלון workflow. כל הצלחה מתייחסת ל־SHA ולהיקף שלה; אין הצלחה כוללת של המקור החדש.

| ריצה / מקור | תוצאות בפועל | משמעות |
| --- | --- | --- |
| [44264360254](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44264360254) · `3542cc20` | build PASS; Runtime/Skills: 41/41 invocations ב־12 מתודות; UI: 21/45 PASS, 24 FAIL; Motion B/C: 0/2 | 33 Arguments ועוד 8 מתודות ללא פרמטרים הם 41 הרצות. אין לספור גם את סיכומי המתודות. |
| [44271250054](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44271250054) · `d7002ab1` | build PASS; Host: 23/24 PASS; UI: 9/19 PASS | עברו CPython אמיתי עם אישור ושחזור שיחה, NativeScript/Expo בתוך AI, ניווט ותרחישי Skill מקוריים. נותרו כשלים מפורשים. |
| [44273341845](https://github.com/davidpovarsky/hanlin-ai/actions/runs/44273341845) · `7f5a8465` | build PASS; compact UI: 0/2 | ה־AX מראה כפתורי Composer מתחת למקלדת. תיקון חדש ממתין ל־Native. |


## תיקונים מקומיים בעקבות הראיות

ה־AX מאמת שיבוש ממשי בטקסט המשתמש בפרומפטי Diagnostics, Code Fences, Search ו־Reasoning. בדיקת Retry מצאה תשובה נכונה בתוך UITextView, אך חיפשה StaticText. כפתורי New Chat/Saved Messages נמצאים בתפריט העודפים המקורי של sidebar ב־iPad. שדות Instructions ב־Skill Center היו מתחת לאזור הרשימה שמומש בפועל.

| commit מקומי | תיקון / שינוי | גבול האימות |
| --- | --- | --- |
| `fec75a68` | Original Host writer/interaction: Reject a second owner before engine creation, recheck after asynchronous preparation, and bind the original HostInteractionSource explicitly. Added original owner/engine/store action-continuation regression. | Native pending |
| `dddec57a` | Compact keyboard viewport: Keep the one persistent original composer in the same flexible VStack as the navigation content; observe its actual available size. | Native pending |
| `1e752571` | Native editor synchronization: Distinguish new model text from an unrelated render, preserving UIKit edits and cursor before delegate synchronization. Regression covers ASCII, Hebrew/emoji and long drafts. | Native pending |
| `684121f6` | Canvas presentation ownership: Capture the original record/model, validate the model index, and attach sheet presentation to the stable body owner. Candidate for observed Canvas event-loop failure; native causality unconfirmed. | Native pending |
| `eebbb19c` | Native UI paths: Verify exact prompt text before sending; use sidebar-specific native overflow; count Retry canonical rows containing native text; scroll original Skill detail list to persisted instructions. | Native pending |
| `0bbe4628` | Original tool fixture contracts: Use required progress schema, real Skill/discovery and exact one-use consent. Require returned Python/HTML results before fixture completion; no injected execution receipts. | Native pending |
| `f7516cce` | Approved Morph acceptance: Exercise the existing Morph panel/back/close and real input resize. Historical test selectors retained (35 before/after); retired Organizer drag-to-open/shared-ZStack assertions explicitly superseded by approved source, not relabeled as passed. | Native pending |
| `4b765b44` | Markdown host dependency: All three original pins reference local upstream6bde022. The retained native paragraph refreshes its current OpenURLAction; regression test added in the original dependency. Publication and iOS verification pending. | Native pending |


שינוי בדיקות Morph מפורש: נשמרו כל 35 שמות בדיקות השיחה. בדיקות המבנה הישן של Organizer עודכנו למסלול ה־Morph המאושר, לפי `docs/composer/MAPPING_WAVE1_2026-11-15.md` וה־reference hash `51bb10cdf71ee1c10cac8108f602eee4b34e78967de23dc437985aa89db9bbbb`. בדיקות drag של ידית המגירה שהוסרה אינן מדווחות כ־PASS; בדיקות resize אמיתי של שדה ההקלדה, עיגון, פאנל פנימי וניווט נשמרו. Native pending.

## ראיות קודמות נשמרות בהיקפן

SDK53, Core/A2UI46, transfer25, MiniApps20+7, editor6, Unicode/model20, Resolver/Canonical21 וראיות המדיה נשמרו במרשם עם SHAs והרצות מקוריות. A2UI16 היא מפת מתודות מתוך Core46, לא תוספת לספירה. בדיקת CPython אמיתי משתמשת בספק מודל נשלט; היא אינה בדיקת מודל חי.

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
