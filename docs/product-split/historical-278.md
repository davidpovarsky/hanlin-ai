# Hanlin AI + MiniApps — מטריצת החלטות מוצר ושימור 278 יכולות

> עדכון תכנון: **19.10.2026** · סטטוס: **FUTURE / BACKLOG** — אין אישור להתחיל מימוש.  
> מקור הפריטים: Hanlin_Feature_Decision_Matrix_2026-10-11.md, שנערך על בסיס `8f24983dc4e62cc52250858f0870826a3bc5f073`. כל 278 הסעיפים וכל סיווגי ההחלטות נשמרו במלואם בהמשך. אין כאן תעודת בדיקות על מכשיר.

## זיהוי ועדכניות

- Repo: [davidpovarsky/hanlin-ai](https://github.com/davidpovarsky/hanlin-ai)
- Working branch: `codex/agent-skills-embedded-results`
- HEAD שנבדק לצורך סנכרון התכנון ב־19.10: `7c823cf84a305e4f7efd157f3c7a43195af37b4e`. בהשוואה ל־baseline קיימים **83 קומיטים ו־188 קבצים שהשתנו**. בין הקבצים ששונו גם MainTabView, ListView ו-NativeAppsHubView. **חובה לבצע delta audit מחדש לפני פיתוח**; טבלת 278 הפריטים היא baseline היסטורי בלבד.
- [Asana: משימת UX עתידית קיימת](https://app.asana.com/1/1219597879016953/project/1219603102275846/task/1219605220179926) · [שער סגירת MASTER נוכחי](https://app.asana.com/1/1219597879016953/project/1219603102275846/task/1219603005960308)

## הכרעות UX וארכיטקטורה מעודכנות

1. **לפצל לשני מוצרי iOS:** Hanlin AI (סוכן, שיחות, ידע, Skills, MCP ופעולות), Hanlin MiniApps (גלריה, יבוא, התקנה, הרצה וניהול אפליקציות). אין להעביר בעיוורון כל Runtime/Tool למוצר השני.
2. **Hanlin AI — שני יעדים גלויים:** שיחה + ספרייה. היסטוריה בסרגל נשלף, פרופיל והגדרות דרך הכותרת. פעילות הסוכן בתוך השיחה עם expand/inspector; אין טאב Activity לפני שמבוסס task manager מתמשך בין שיחות.
3. **Composer:** הקלדה, צירוף/מצלמה/קובץ, קול, שליחה/עצירה, בחירת עוזר. לשמר drafts, `@mentions`, paste, URLs, prompts, attachments-only, image zoom/remove, temporary chat, retry, scrolling/IME, voice. Liquid Glass multiline של תוכנית Classic UI נותר כעיקרון חזותי בכפוף לבדיקות.
4. **חשיפת יכולות הדרגתית:** Canvas, תרגום/ליטוש/סיכום, מפות, יומן, Health, HTML, קוד, אודיו ויצירת תמונה — רק לפי הקשר. חיפוש, Skills, Knowledge ורמות חשיבה מופעלים אוטומטית רק כשהוגדרו הרשאות ותנאי פרטיות/עלות מתאימים; כל פעולה רגישה כפופה לאישור מתאים.
5. **Advanced ולא מחיקת כוח:** מודלים, API Keys, `temperature`/`top_p`, MCP, Skill Editor, Runtimes, כלי Shell/Python, Diagnostics והעדפות המומחה נשארים במסכים מתקדמים ולא בסרגל הצ'אט.
6. **MiniApps וגשר תוצאות:** קטלוג, התקנה, מחיקה, שדרוגים ו-grants למוצר השני; הסוכן ממשיך להציג rich embedded results, קישורים, מקורות, Skills/Tools ופתיחת MiniApp מלאה כשנדרש, כולל fallback כשהאפליקציה השנייה לא מותקנת.
7. **חוזים ומיגרציה:** owner ברור ל־SDK/shared contracts, extension targets, App Groups, Keychain, SwiftData/CloudKit, התראות, Intent/Share/Translation, deep links, הרשאות, installed packages וסודות. אין להניח שהמיני־אפליקציה תישאר פעילה ברקע.
8. **ממשקים מטעים:** לתקן ולבדוק `ifAudio`, שליחת attachments-only, כפתורי Image/Local Run חזותיים, onboarding חסום, Share Inbox ופריסה RTL; לא להציג כוחות שאינם פועלים כמאומתים.

## עדכון ביחס לתוכנית Classic UI של 18.10

תוכנית Asana הקיימת נשמרת ואינה תוכנית מקבילה: Classic Hanlin visual identity, SwiftChat-inspired inline sources, Evidence, transcript, Liquid Glass Composer, glass/scroll/RTL/action semantics הם עקרונות שנשארים. עם זאת, הוראות מוקדמות כגון **KEEP visible TabBar** ו־**KEEP Apps tab** אינן מתאימות להחלטת מוצר חדשה של שני יעדים ופיצול אפליקציות. יש ליישב את 26 החלטות הממשק הישנות אל מול 278 פריטי מטריצה זו, תוך שימור יכולות ולא שימור פריסה מיושנת. תיעוד הישן נשמר להיסטוריה; שינוי קוד מותר רק בשלב עתידי מאושר.

## שערי פעולה מחייבים

- כעת: **תכנון בלבד**. לא נוגעים בארבעת קובצי Chat UI הקפואים; אין שינוי Bundle ID, תהליכי CI, IPA, SDK, secrets או release.
- לפני פיתוח: סגירת MASTER וכל החסימות הרלוונטיות בפועל, או החרגה מפורשת בידי המשתמש; אישור נפרד לשחרור הקפאת UI ולהתחלת Split.
- שלב עתידי א׳: audit של HEAD בזמן תחילת העבודה, mapping source→target, 26 החלטות היסטוריות מול 278 feature IDs והכרעה בסתירות.
- שלב עתידי ב׳: עיצוב/אישור Chat/Library/history/assistant picker/activity/embedded results/advanced + MiniApps gallery, כולל iPad/RTL/Dynamic Type.
- שלב עתידי ג׳: ארכיטקטורת שתי אפליקציות, migration/rollback לנתונים, App Groups/Keychain/CloudKit ו-permission matrix, Contracts ו-deep link routing.
- שלב עתידי ד׳: מימוש בענף בטוח רק לאחר אישור, והוכחת Feature Parity לכל 278 IDs עם PASS/FAIL/NOT_RUN/BLOCKED אמיתיים, כולל בדיקות מכשיר חתום ותיעוד ראיות.

## פירוש הסיווגים

| סיווג | משמעות |
|---|---|
| `VISIBLE` | תמיד גלוי |
| `AUTO` | ליבה אוטומטית ברקע |
| `CONTEXT` | בהקשר המתאים |
| `ADVANCED` | אופציה מתקדמת |
| `MINI` | מעבר למוצר MiniApps |
| `SHARED` | חוזה/רכיב משותף |
| `REMOVE_UI` | להסיר ממשק, לא בהכרח שירות |
| `FIX_FIRST` | לתקן/לאמת לפני החלטה |
| `RETIRE` | מועמד להסרה לאחר בדיקת תלות |

## מטריצת החלטות — 278 פריטים

הנוסח לכל feature ID והסיווג נשמרו מתוך המטריצה המקורית; טבלת source-derived baseline אינה טוענת שהמימוש עבר QA ב־HEAD החדש. הסיווג REMOVE_UI מסיר הצגה, לא בהכרח קוד או נתונים; RETIRE מחייב תלות ואישור לפני הסרה.


### NAV — ניהול שיחות והיסטוריה

| ID | Decision | Current feature from audit | Redesign note |
|---|---|---|---|
| `NAV-01` | `REMOVE_UI` | ניווט שש לשוניות קיים: שיחות, מצלמה/ראייה, ידע, מודלים/סוכנים, Apps והגדרות. `קוד` — `MainTabView.swift`. | Replace six tabs with Chat + Library; use history and settings entrypoints, not permanent tabs. |
| `NAV-02` | `VISIBLE` | יצירת שיחה חדשה והכנסת הודעת פתיחה. `קוד` — `ListView.swift`. |  |
| `NAV-03` | `AUTO` | שמירת שיחות ב-SwiftData ומבנה יחסים עם הודעות. `קוד` — `ChatRecords.swift`, `AI_HLY.swift`. |  |
| `NAV-04` | `CONTEXT` | הפרדה בין שיחות נעוצות לשיחות אחרונות. `קוד`. |  |
| `NAV-05` | `AUTO` | סדר עדכניות לפי `lastEdited`. `קוד`. |  |
| `NAV-06` | `VISIBLE` | חיפוש בשם שיחה. `קוד`. |  |
| `NAV-07` | `VISIBLE` | חיפוש בתוך גוף כל הודעות השיחה. `קוד`. |  |
| `NAV-08` | `AUTO` | התאמה והשוואה ללא תלות באותיות גדולות/קטנות. `קוד`. |  |
| `NAV-09` | `AUTO` | חיפוש Pinyin לסינית. `קוד`. |  |
| `NAV-10` | `CONTEXT` | קטע תצוגה סביב ההתאמה (40 תווים לפני/אחרי בקירוב). `קוד`. |  |
| `NAV-11` | `CONTEXT` | הדגשת הביטוי המבוקש גם בכותרת וגם בתקציר. `קוד`. |  |
| `NAV-12` | `CONTEXT` | מעבר להודעה שבה נמצאה התוצאה, ולא רק לפתיחת השיחה. `קוד`; `אימות` לדיוק גלילה. |  |
| `NAV-13` | `AUTO` | דיבאונס לחיפוש. `קוד`. |  |
| `NAV-14` | `CONTEXT` | רענון שיחות במשיכה מלמעלה. `קוד`. |  |
| `NAV-15` | `CONTEXT` | נעיצה וביטול נעיצה באמצעות תפריט הקשר או החלקה. `קוד`. |  |
| `NAV-16` | `CONTEXT` | מחיקת שיחה, כולל פעולת החלקה. `קוד`. |  |
| `NAV-17` | `CONTEXT` | שינוי כותרת שיחה. `קוד`. |  |
| `NAV-18` | `CONTEXT` | החלפת אייקון שיחה. `קוד`. |  |
| `NAV-19` | `CONTEXT` | צבע אישי לכל שיחה. `קוד`. |  |
| `NAV-20` | `CONTEXT` | תצוגת תקציר ההודעה האחרונה או סימון טיוטה. `קוד`. |  |
| `NAV-21` | `AUTO` | שמירת טיוטת הודעה לכל שיחה, גם לאחר מעבר ממנה. `קוד`. |  |
| `NAV-22` | `AUTO` | יצירת כותרת אוטומטית לאחר שיחה, בעזרת מודל אופטימיזציה. `קוד`; `מותנה`. |  |
| `NAV-23` | `AUTO` | ב-iPad `NavigationSplitView` עם רשימה ופרט בו-זמנית. `קוד`. |  |
| `NAV-24` | `AUTO` | ב-iPhone `NavigationStack` והסתרת לשוניות בתוך שיחה. `קוד`. |  |
| `NAV-25` | `FIX_FIRST` | הודעות חיווי ליצירת שיחה שאינה אפשרית עקב הגדרת ספק או מודל חסרה; מעבר מהחיווי להגדרה. `קוד`. | Remove hard blocking on optimizer model when basic chat is possible; correct onboarding. |
| `NAV-26` | `REMOVE_UI` | פעולות מהירות בראש הרשימה: תרגום, ליטוש, סיכום. `קוד`. | Move translation, polish, summary to contextual text actions, not permanent home buttons. |
| `NAV-27` | `RETIRE` | פתיחת מסמך עזרה/מדריך ב-Safari פנימי. `קוד`; מקור חיצוני ישן, `אימות`. | Retire old upstream help destinations only when replaced with accurate Hanlin documentation. |

### INPUT — Composer וקלט

| ID | Decision | Current feature from audit | Redesign note |
|---|---|---|---|
| `INPUT-01` | `VISIBLE` | תיבת טקסט רגילה. `קוד`. |  |
| `INPUT-02` | `VISIBLE` | Return לשליחה באמצעות `UITextFieldDelegate`. `קוד`. |  |
| `INPUT-03` | `CONTEXT` | עריכת טקסט בחלון גדול/רב-שורי. `קוד`. |  |
| `INPUT-04` | `VISIBLE` | פתיחת ממשק זיהוי דיבור מתוך הסרגל. `קוד`, `מותנה` בהרשאת מיקרופון ודיבור. |  |
| `INPUT-05` | `AUTO` | זיהוי תוכן שהודבק מה-clipboard: תמונה. `קוד`. |  |
| `INPUT-06` | `AUTO` | זיהוי תוכן שהודבק: כתובת קובץ או מסמך. `קוד`. |  |
| `INPUT-07` | `AUTO` | הדבקת טקסט רגיל ושמירה על פעולת ההדבקה הסטנדרטית. `קוד`. |  |
| `INPUT-08` | `AUTO` | זיהוי סוגי קובץ PDF, CSV, TXT, JSON, LOG, HTML, PY, DOCX, XLSX, PPTX, MD. `קוד`. |  |
| `INPUT-09` | `CONTEXT` | זיהוי התחלת אזכור של מודל באמצעות `@`. `קוד`. |  |
| `INPUT-10` | `CONTEXT` | הצעות אוטומטיות למודלים לאחר `@`. `קוד`. |  |
| `INPUT-11` | `CONTEXT` | בחירת הצעה מכניסה את שם המודל לטקסט, עם רווח. `קוד`. |  |
| `INPUT-12` | `AUTO` | Backspace בתוך אזכור `@…` מוחק את האזכור כולו. `קוד`. |  |
| `INPUT-13` | `AUTO` | הגנה על מצב טקסט מורכב/מסומן במקלדות דוגמת Pinyin. `קוד`. |  |
| `INPUT-14` | `AUTO` | שמירת טיוטה לאחר דיבאונס בעריכת טקסט. `קוד`. |  |
| `INPUT-15` | `CONTEXT` | סרגלי תצוגה נפתחים אוטומטית על בסיס קבצים, URL, תמונות ו-Prompts שנבחרו. `קוד`. |  |
| `INPUT-16` | `AUTO` | רטט/פידבק בבחירות ופעולות רבות. `קוד`. |  |
| `INPUT-17` | `FIX_FIRST` | סטופ שיחה כשהסוכן מייצר פלט, כפתור שליחה אחרת, וכפתור תצפית במצב ללא טקסט. `קוד`. | Split send/stop (visible) from observation (contextual Continue action). Do not lose observation semantics. |
| `INPUT-18` | `AUTO` | פקדי שליחה ושדות מושבתים בעת תגובה פעילה בחלק מהמקרים. `קוד`. |  |

### ATT — תמונות, מסמכים וקישורים

| ID | Decision | Current feature from audit | Redesign note |
|---|---|---|---|
| `ATT-01` | `CONTEXT` | צילום חדש במצלמה מתוך השיחה. `קוד`, `מותנה` בהרשאה. |  |
| `ATT-02` | `CONTEXT` | בחירת תמונות מהספרייה. `קוד`. |  |
| `ATT-03` | `AUTO` | צירוף כמה תמונות עד הגבלת רכיב (כחמש). `קוד`. |  |
| `ATT-04` | `CONTEXT` | תצוגת תצלומים ממוזערים בשורה נגללת. `קוד`. |  |
| `ATT-05` | `CONTEXT` | צפייה בתמונה במסך תצוגה מוגדל. `קוד`. |  |
| `ATT-06` | `CONTEXT` | מחיקה של תמונה בודדת לפני שליחה. `קוד`. |  |
| `ATT-07` | `CONTEXT` | הוספת עוד תמונה אחרי בחירת אחרות. `קוד`. |  |
| `ATT-08` | `CONTEXT` | בחירת מסמכים באמצעות Document Picker. `קוד`. |  |
| `ATT-09` | `CONTEXT` | הצגת שם הקובץ וחתכו באמצע כשארוך. `קוד`. |  |
| `ATT-10` | `CONTEXT` | הסרת מסמך בודד. `קוד`. |  |
| `ATT-11` | `AUTO` | הגבלת מספר מסמכים ב-composer. `קוד`. |  |
| `ATT-12` | `AUTO` | חילוץ כתובות URL מהטקסט. `קוד`. |  |
| `ATT-13` | `CONTEXT` | הצגת כתובות מזוהות כצ'יפים לפני השליחה. `קוד`. |  |
| `ATT-14` | `CONTEXT` | מחיקת צ'יפ URL מוחקת גם את הקישור מתוך הטקסט. `קוד`. |  |
| `ATT-15` | `CONTEXT` | בחירה של כמה Prompt templates שמורים. `קוד`. |  |
| `ATT-16` | `CONTEXT` | צ'יפ לכל Prompt, הסרה בודדת. `קוד`. |  |
| `ATT-17` | `CONTEXT` | הכנסת תוכן Prompt לטקסט לצורך עריכה עצמית. `קוד`. |  |
| `ATT-18` | `AUTO` | העברת ה-Prompts כחלק מהקשר של הבקשה למודל. `קוד`. |  |
| `ATT-19` | `AUTO` | אפשרות לבחור מודל רב-מודאלי לצירופי תמונות, עם התראה כשהמודל אינו מתאים. `קוד`. |  |

### MODEL — מודלים וסוכנים

| ID | Decision | Current feature from audit | Redesign note |
|---|---|---|---|
| `MODEL-01` | `VISIBLE` | בחירת מודל בתוך השיחה. `קוד`. |  |
| `MODEL-02` | `VISIBLE` | בחירת Agent (ישות עם הנחיות ומודל בסיס) במקום מודל רגיל. `קוד`. |  |
| `MODEL-03` | `REMOVE_UI` | סגנון בחירה כגלילה אופקית או תפריט. `קוד`. | Use a single assistant picker; retire end-user preference for two competing selector layouts. |
| `MODEL-04` | `REMOVE_UI` | בחירה מתוך עד שבעה מודלים בתפריט קצר. `קוד`. | Retire hard-coded top-seven menu as main discoverability pattern; keep searchable all-model chooser. |
| `MODEL-05` | `CONTEXT` | פתיחת מסך חיפוש ובחירה מלא. `קוד`. |  |
| `MODEL-06` | `AUTO` | תמיכה בחיפוש Pinyin ברשימת מודלים. `קוד`. |  |
| `MODEL-07` | `CONTEXT` | אייקון חברה או סוכן, שם תצוגה. `קוד`. |  |
| `MODEL-08` | `CONTEXT` | תוויות יכולת כלי-סוכן, טקסט, ראייה, תמונה, קול וחשיבה. `קוד`. |  |
| `MODEL-09` | `CONTEXT` | ציון מודל מקומי ותמחור יחסי. `קוד`. |  |
| `MODEL-10` | `AUTO` | סינון מודלים מוסתרים וסדר מותאם. `קוד`. |  |
| `MODEL-11` | `ADVANCED` | בחירת `temperature` לכל שיחה ושמירה. `קוד`. | Expose temperature only behind model-specific advanced settings. |
| `MODEL-12` | `ADVANCED` | בחירת `top_p` לכל שיחה ושמירה. `קוד`. | Expose top_p only behind model-specific advanced settings. |
| `MODEL-13` | `ADVANCED` | בחירת `max_tokens` לכל שיחה ושמירה. `קוד`. | Token limit in advanced settings with safe default. |
| `MODEL-14` | `ADVANCED` | בחירת גודל היסטוריה שיישלח בבקשות נוספות, ושמירה. `קוד`. | History window in advanced settings; user should not tune for every chat. |
| `MODEL-15` | `ADVANCED` | מסך system-message: הנחיית מערכת רגילה או אישית. `קוד`. | Custom system instructions in assistant customization/advanced settings. |
| `MODEL-16` | `ADVANCED` | יצירה/עריכה/מחיקה/הסתרה של מודל ספק. `קוד`. |  |
| `MODEL-17` | `ADVANCED` | ניהול סדר מודלים, הזזה והשבתה לברירת מחדל. `קוד`. |  |
| `MODEL-18` | `ADVANCED` | הוספת ספק מותאם ממשק OpenAI עם כתובת Endpoint ו-API Key. `קוד`. |  |
| `MODEL-19` | `ADVANCED` | בדיקת API ספק, בדיקת יתרה בספקים נתמכים. `קוד`, `מותנה`. |  |
| `MODEL-20` | `ADVANCED` | רענון רשימת מודלים מספק והוספה/הסרה. `קוד`, `מותנה`. |  |
| `MODEL-21` | `ADVANCED` | זיהוי יכולת מודל אוטומטי (עשוי להשתמש ב-API בתשלום). `קוד`, `מותנה`. |  |
| `MODEL-22` | `ADVANCED` | שינוי capability flags פרטניים: טקסט, ראייה, חשיבה, חשיבה ניתנת לכיבוי, כלים, תמונות. `קוד`. |  |
| `MODEL-23` | `CONTEXT` | יצירת Agent עם שם, אייקון, תיאור, system prompt, מודל בסיס. `קוד`. |  |
| `MODEL-24` | `CONTEXT` | יצירת הנחיות Agent אוטומטית, אפשרות ביטול מילוי. `קוד`, `מותנה`. |  |
| `MODEL-25` | `ADVANCED` | עריכת Agent ושכפול/העתקה למודל בסיס חלופי. `קוד`. |  |
| `MODEL-26` | `ADVANCED` | הורדת מודלים מקומיים (ניסוי) מ-HuggingFace/ModelScope. `קוד`, `מותנה`. | Local GGUF model management remains opt-in for power users; protect resource limits. |
| `MODEL-27` | `ADVANCED` | ייבוא קובץ GGUF והצגת התקדמות. `קוד`, `מותנה`. |  |
| `MODEL-28` | `ADVANCED` | הגדרת מודל Embedding יחיד, מודלי אופטימיזציה של טקסט וראייה, מודל TTS רגיל/Siri. `קוד`. |  |
| `MODEL-29` | `AUTO` | המערכת עוטפת ספקים ומודלים שונים, כולל אפשרות stream/tool calling ו-local inference. `קוד`, `מותנה`. |  |

### RUN — ביצוע סוכן ומצבי פעולה

| ID | Decision | Current feature from audit | Redesign note |
|---|---|---|---|
| `RUN-01` | `AUTO` | תשובות ב-stream בזמן אמת. `קוד`. |  |
| `RUN-02` | `VISIBLE` | cancel/stop של פעולת הסוכן. `קוד`. |  |
| `RUN-03` | `CONTEXT` | Retry לשגיאה או תשובה, באמצעות חיתוך ההיסטוריה לרגע המקורי. `קוד`. |  |
| `RUN-04` | `CONTEXT` | מצב Observation: המשך ללא הודעת משתמש רגילה. `קוד`. | Rename the eye/Observation concept to Continue; context-menu only, explain effect. |
| `RUN-05` | `ADVANCED` | אזכור מספר מודלים בפנייה ושיוך קבוצות הודעות. `קוד`; `אימות` לתרחישים משולבים. | Retain multi-model engine only as optional expert workflow; not default chat paradigm. |
| `RUN-06` | `ADVANCED` | מצב Tool Use on/off. `קוד`, `מותנה` במודל. | Tool engine automatic for approved read-only tools; per-chat override in advanced controls. |
| `RUN-07` | `AUTO` | מצב חיפוש אינטרנט on/off. `קוד`, `מותנה` במנוע. | Search automatically when beneficial, but surface source and network/cost control. |
| `RUN-08` | `AUTO` | מצב חיפוש Knowledge on/off. `קוד`, `מותנה` ב-Embedding. | Knowledge retrieval only with explicit enabled library and clear data control. |
| `RUN-09` | `CONTEXT` | Planning עבור מודלים מתאימים. `קוד`. | Do not expose Planning toggle by name; use natural language task and optional deeper-work mode. |
| `RUN-10` | `CONTEXT` | Reasoning, ובמודלים מתאימים שליטה בארבע רמות. `קוד`. | Optional Take more time mode, only if provider supports it; hide technical level numbers. |
| `RUN-11` | `FIX_FIRST` | העברת `ifAudio` כפרמטר לבקשת generation. `קוד` **אבל כפתור הקול עצמו לא משנה את `ifAudio` (ראו סיכונים)**. | Audio toggle is not wired to ifAudio. Fix before keeping a user-facing option. |
| `RUN-12` | `CONTEXT` | תמיכה בבקשות יצירת תמונה, כיווניות ריבוע/נוף/פורטרט. `קוד`, `מותנה` בספק. | Show image size choices only after image request; not permanent chat toolbar. |
| `RUN-13` | `ADVANCED` | Negative Prompt לספקי יצירת תמונה מסוימים. `קוד`, `מותנה`. | Negative prompts are professional creative options, not everyday settings. |
| `RUN-14` | `AUTO` | פיצול סיום/תחילת קבוצות תמליל ושימור סדר התוצרים. `קוד`. |  |
| `RUN-15` | `AUTO` | מעקב משך reasoning, שגיאות ספק ותזמון פעילות. `קוד`. |  |
| `RUN-16` | `CONTEXT` | הודעת שגיאה עבור אורך פלט מקסימלי או תוכן רגיש. `קוד`. |  |
| `RUN-17` | `CONTEXT` | הודעת שגיאה עבור יצירה ריקה, כשל תגובה, כשל סנכרון. `קוד`. |  |
| `RUN-18` | `AUTO` | שמירת state של Agent Run לשיחה. `קוד`. |  |
| `RUN-19` | `ADVANCED` | הגדרת scope של שרתי MCP לפי השיחה, כולל צ'אט זמני. `קוד`. |  |
| `RUN-20` | `CONTEXT` | יצירת תקציר פעילות וקריאת `report_progress` בתמליל. `קוד`. |  |

### RESULT — תוצאות השיחה ותוכן עשיר

| ID | Decision | Current feature from audit | Redesign note |
|---|---|---|---|
| `RESULT-01` | `VISIBLE` | הודעות משתמש/עוזר/מידע/שגיאה וחיפוש בעיצוב נפרד. `קוד`. |  |
| `RESULT-02` | `CONTEXT` | תווית מודל/Agent ואייקון מספק התשובה. `קוד`. |  |
| `RESULT-03` | `VISIBLE` | תצוגת Markdown וטקסט עשיר, כולל יכולת מצב נוסחאות LaTeX. `קוד`. |  |
| `RESULT-04` | `ADVANCED` | נימוק/Reasoning מתקפל. `קוד`. | Show safe progress/summary with expand; avoid dumping raw reasoning into ordinary UX. |
| `RESULT-05` | `REMOVE_UI` | בזמן סטרימינג, תצוגת שלוש שורות פעילות אחרונות. `קוד`. | Remove 3-line rolling reasoning ticker; replace with single concise activity summary. |
| `RESULT-06` | `CONTEXT` | פירוט קריאות כלי מתקפל. `קוד`. |  |
| `RESULT-07` | `CONTEXT` | פעולות על תשובה: העתק, בחר טקסט, הקרא/עצור, תרגם, Retry, שמור לידע, מחק. `קוד`. | Keep Copy immediately available; move other actions to contextual More menu. |
| `RESULT-08` | `CONTEXT` | תרגום בתוך הודעה והצגתו בחלונית מתקפלת. `קוד`. |  |
| `RESULT-09` | `CONTEXT` | אפשרות להסיר תרגום קיים. `קוד`. |  |
| `RESULT-10` | `CONTEXT` | Text selection עם Select All, copy, save to knowledge. `קוד`. |  |
| `RESULT-11` | `CONTEXT` | תגי מקורות ברשימת ציטוטים, אייקון/כותרת ופתיחת URL. `קוד`. |  |
| `RESULT-12` | `CONTEXT` | אזהרת קישור חיצוני, אפשרות להעתיק/לפתוח. `קוד`. | Preserve user protection for suspicious/untrusted external links, reduce routine friction. |
| `RESULT-13` | `CONTEXT` | תצוגה מוגדלת של תמונות פלט או תמונות משתמש. `קוד`. |  |
| `RESULT-14` | `CONTEXT` | העתקת תמונה ללוח ושמירת תמונה לאלבום. `קוד`. |  |
| `RESULT-15` | `CONTEXT` | כרטיס קובץ עם סמל תואם סיומת. `קוד`. |  |
| `RESULT-16` | `CONTEXT` | פתיחת תצוגת טקסט הקובץ, Copy ושמירה לידע. `קוד`. |  |
| `RESULT-17` | `CONTEXT` | כרטיסי קוד Python/אחרים: קוד מקור, עיצוב ו-copy all. `קוד`. |  |
| `RESULT-18` | `CONTEXT` | תצוגת HTML/WebView מתוך תוצאת כלי, כולל העתקת קוד. `קוד`. |  |
| `RESULT-19` | `CONTEXT` | Knowledge Cards ופעולת כתיבה לידע עם סמן כבר נשמר. `קוד`. |  |
| `RESULT-20` | `CONTEXT` | Audio player בתוך הודעה: play/pause, תצוגת Waveform, זמן/משך וקצב השמעה. `קוד`. |  |
| `RESULT-21` | `CONTEXT` | ציון מודל שהפיק קובץ אודיו. `קוד`. |  |
| `RESULT-22` | `CONTEXT` | כרטיס מפה אינטראקטיבי עם נקודות ומסלולים. `קוד`. |  |
| `RESULT-23` | `CONTEXT` | הצגת מפה מורחבת, ניווט ב-Apple Maps לנקודה. `קוד`. |  |
| `RESULT-24` | `CONTEXT` | כרטיס Calendar/Reminder: כותרת, זמן, מקום, הערות, פתיחת Calendar. `קוד`. |  |
| `RESULT-25` | `CONTEXT` | כרטיס מידע תזונתי: פחמימות, שומן, חלבון, קלוריות. `קוד`. |  |
| `RESULT-26` | `CONTEXT` | לחצן כתיבה ל-HealthKit ושמירת סימן נכתב. `קוד`, `מותנה` בהרשאה. |  |
| `RESULT-27` | `AUTO` | תצוגת פעולות סוכן מסוג reasoning/toolActivity/progress/assistantText/userVisibleResult/error, מסודרת בזמן. `קוד`. |  |
| `RESULT-28` | `CONTEXT` | שורות פעילות תמציתיות עם shimmer בזמן pending/running. `קוד`. |  |
| `RESULT-29` | `CONTEXT` | הרחבת פרטי פעילות: שאילתות, קלט כלי, פלט, שגיאות והפניה למסך inspector. `קוד`. |  |
| `RESULT-30` | `CONTEXT` | דף מקורות/Evidence ברשימות מקובצות, קישורים/העתקה. `קוד`. |  |
| `RESULT-31` | `CONTEXT` | סוגי מקור: Web, Wikipedia, Sefaria, GitHub repository/file/commit, מסמך, קובץ, Reminder, Calendar, Email, Contact ופריט כללי. `קוד`. |  |
| `RESULT-32` | `SHARED` | הזיהוי אם התוצאה מוטמעת הוא על בסיס Schema/Payload/Handler. `קוד`. |  |
| `RESULT-33` | `SHARED` | כל תוצאה מוטמעת יכולה להופיע כ-card או neutral, ברוחב וגובה מוגבלים. `קוד`. |  |
| `RESULT-34` | `SHARED` | פתיחת תוצאה מוטמעת ב-sheet, מסך מלא, ואצל יעד מתאים בחלון חדש. `קוד`; `מותנה` בפלטפורמה. |  |
| `RESULT-35` | `SHARED` | פעולות הקשר צפות (פתיחה במפות/מיני-אפליקציה וכו'). `קוד`. |  |
| `RESULT-36` | `SHARED` | מתאמי תוצאות ל-Swift, ScriptUI, NativeScript ו-Expo. `קוד` — לשמר כ-Shared Renderer/Contracts. |  |
| `RESULT-37` | `CONTEXT` | פתיחת MiniApp יזומה משיחה מתוך Sheet/Full Screen/New Window. `קוד` — לאחר פיצול לעדכן למסלול בין-אפליקציות עם fallback. | Inline standard cards work without MiniApps app; full app deep-links only when needed. |
| `RESULT-38` | `AUTO` | התחשבות ב-Reduce Motion בחלק מתצוגות activity, והתאמת פריסה לרוחב iPad. `קוד`. |  |

### CANVAS — Canvas

| ID | Decision | Current feature from audit | Redesign note |
|---|---|---|---|
| `CANVAS-01` | `AUTO` | יצירת Canvas ושיוכו לשיחה. `קוד`. |  |
| `CANVAS-02` | `CONTEXT` | תצוגת קישור לציור בסרגל תחתון רק כשקיים תוכן. `קוד`. |  |
| `CANVAS-03` | `CONTEXT` | סוגי תוכן: text, python, html. `קוד`. |  |
| `CANVAS-04` | `CONTEXT` | עריכת התוכן בחלון מיוחד עם בחירה בטקסט. `קוד`. |  |
| `CANVAS-05` | `CONTEXT` | AI revision על קטע נבחר, על פי הוראה ייחודית. `קוד`, `מותנה`. |  |
| `CANVAS-06` | `CONTEXT` | AI edit לכל המסמך לפי רמת קריאה/אורך. `קוד`, `מותנה`. |  |
| `CANVAS-07` | `CONTEXT` | סימון עריכה חדשה בזמן זרימה. `קוד`. |  |
| `CANVAS-08` | `CONTEXT` | היסטוריית עריכות מוגדרת בתוך CanvasData. `קוד`. |  |
| `CANVAS-09` | `CONTEXT` | Undo/Redo. `קוד`. |  |
| `CANVAS-10` | `CONTEXT` | Copy content. `קוד`. |  |
| `CANVAS-11` | `CONTEXT` | Save to Knowledge ושמירת סטטוס Saved. `קוד`. |  |
| `CANVAS-12` | `ADVANCED` | הרצת Python מתוך Canvas באמצעות Piston. `קוד`, `מותנה` ברשת. | Run remote code only after user intent and appropriate privacy/cost disclosure. |
| `CANVAS-13` | `CONTEXT` | תצוגת פלט הרצת Python וניקוי פלט. `קוד`. |  |
| `CANVAS-14` | `CONTEXT` | Preview HTML ב-WebView. `קוד`. |  |
| `CANVAS-15` | `CONTEXT` | מחיקת תוכן Canvas עם Confirmation. `קוד`. |  |

### MEDIA — מצלמה, קול וכלים מהירים

| ID | Decision | Current feature from audit | Redesign note |
|---|---|---|---|
| `MEDIA-01` | `REMOVE_UI` | ממשק Vision עצמאי עם camera preview חי. `קוד`. | Remove standalone Vision tab, retain live capture with camera controls from attachment action. |
| `MEDIA-02` | `CONTEXT` | צילום, בחירה מהספרייה, הצגת תמונה שצולמה. `קוד`. |  |
| `MEDIA-03` | `CONTEXT` | מעבר קדמית/אחורית. `קוד`. |  |
| `MEDIA-04` | `CONTEXT` | שליטה ב-Flash. `קוד`. |  |
| `MEDIA-05` | `CONTEXT` | Zoom ומחוות Pinch. `קוד`. |  |
| `MEDIA-06` | `ADVANCED` | בחירת מודל רב-מודאלי מתוך carousel. `קוד`. | Use suitable visual model automatically if configured; manual model carousel in advanced view. |
| `MEDIA-07` | `CONTEXT` | שאלה על תמונה, Follow-up רב-סבבי, reasoning, streaming. `קוד`, `מותנה`. |  |
| `MEDIA-08` | `CONTEXT` | Retry על זיהוי תמונה אחרי תקלה. `קוד`. |  |
| `MEDIA-09` | `CONTEXT` | Copy/Select של טקסט זיהוי תמונה. `קוד`. |  |
| `MEDIA-10` | `CONTEXT` | שמירת התמונה ל-Photos, ניקוי/מחיקת תמונה ואזהרה כשאין מודל תואם. `קוד`. |  |
| `MEDIA-11` | `VISIBLE` | SpeechRecognizer עם הרשאות וזיהוי בזמן הקלטה. `קוד`, `מותנה`. | Mic stays discoverable; request microphone/speech permissions on actual use. |
| `MEDIA-12` | `CONTEXT` | תצוגת waveform בתהליך הקלטה. `קוד`. |  |
| `MEDIA-13` | `CONTEXT` | עריכת/אופטימיזציית התמלול והחזרתו לתיבת ההודעה. `קוד`, `מותנה`. |  |
| `MEDIA-14` | `CONTEXT` | תרגום מהיר: שפת מקור/יעד, זיהוי אוטומטי, בחירת מודל, זרימה. `קוד`. |  |
| `MEDIA-15` | `CONTEXT` | גישה למילון תרגום אישי, העתקה/בחירת טקסט ותמיכה ב-TTS. `קוד`. |  |
| `MEDIA-16` | `CONTEXT` | ליטוש מהיר: סגנון תוכן, פורמט, אורך, הוראות חופשיות, בחירת מודל. `קוד`. |  |
| `MEDIA-17` | `CONTEXT` | סיכום מהיר של טקסט וכתובת URL, בחירת מודל ו-streaming. `קוד`. |  |
| `MEDIA-18` | `CONTEXT` | אזהרה שכלים מהירים אינם שומרים תכנים, ולכן אין להניח קיום היסטוריה. `קוד`. |  |

### LIB — ידע, זיכרון והנחיות

| ID | Decision | Current feature from audit | Redesign note |
|---|---|---|---|
| `LIB-01` | `CONTEXT` | Knowledge Notes: יצירה, מחיקה, שינוי כותרת, אייקון וצבע, נעיצה/ביטול. `קוד`. |  |
| `LIB-02` | `CONTEXT` | חיפוש Knowledge Notes והדגשת ההתאמה. `קוד`. |  |
| `LIB-03` | `CONTEXT` | פעולות החלקה/תפריט להערות ידע. `קוד`. |  |
| `LIB-04` | `CONTEXT` | עורך תוכן ידע, פתיחת מסמכים והדבקת טקסט. `קוד`. |  |
| `LIB-05` | `CONTEXT` | קריאת תוכן מסמך, ייבוא טקסט מקישור URL. `קוד`, `מותנה`. |  |
| `LIB-06` | `CONTEXT` | OCR דרך מצלמה או אלבום בתוכן ידע. `קוד`. |  |
| `LIB-07` | `CONTEXT` | Optimize/Translate על תוכן ידע. `קוד`, `מותנה`. |  |
| `LIB-08` | `CONTEXT` | מונה תווים והערכת Tokens בתוכן ידע. `קוד`. |  |
| `LIB-09` | `AUTO` | יצירת embeddings לתוכן ידע וחיווי סטטוס אינדוקס. `קוד`, `מותנה`. | Index eligible knowledge in background with progress surfaced where relevant. |
| `LIB-10` | `AUTO` | פיצול Chunking לפי כותרות Markdown וחפיפה; בניית וקטורים דרך מודל embedding. `קוד`. | Chunking and embedding always behind scenes; never expose algorithm settings to normal users. |
| `LIB-11` | `ADVANCED` | בחירת מודל אינדוקס ופתיחת הגדרות כשחסר. `קוד`. |  |
| `LIB-12` | `CONTEXT` | זיכרון: דפדוף/חיפוש/הדגשה של זיכרונות. `קוד`. |  |
| `LIB-13` | `CONTEXT` | הוספה ידנית, עריכה, מחיקה והסרת כל הזיכרונות עם אישור. `קוד`. |  |
| `LIB-14` | `CONTEXT` | הדלקת זיכרון אוטומטי וזיכרון חוצה-שיחות באופן עצמאי. `קוד`. | Memory on/off and cross-chat controls must be easy to find in Privacy & Memory, not buried in developer area. |
| `LIB-15` | `AUTO` | API כלים לשמירת/אחזור/עדכון זיכרונות במהלך סוכן. `קוד`, `מותנה`. | Memory tool calls require transparent permissions and easy user review of stored memory. |
| `LIB-16` | `CONTEXT` | פרומפטים: הוספה, חיפוש, שינוי שם, שינוי סדר, מחיקה ועריכת תוכן. `קוד`. |  |
| `LIB-17` | `CONTEXT` | בתוך עורך פרומפטים: Optimize/Translate/OCR, אפשרות סילוק תוכן ותצוגת Token count. `קוד`. |  |
| `LIB-18` | `CONTEXT` | שימוש ב-Prompt שמור בתוך שיחה כ-card ללא הכנסת תוכנו לטקסט. `קוד`. |  |
| `LIB-19` | `CONTEXT` | העברת תוכן Prompt שמור לשדה כתיבה לשינוי לפני שליחה. `קוד`. |  |
| `LIB-20` | `CONTEXT` | מילון תרגום אישי: צמדי מילים, הוספה/עריכה/מחיקה באמצעות swipe, ונגישות מתוך כלי התרגום. `קוד`. |  |

### AGENT — Skills / MCP / Tool Authority

| ID | Decision | Current feature from audit | Redesign note |
|---|---|---|---|
| `AGENT-01` | `ADVANCED` | Skill Center: רשימת Skills שמגיעים מהמערכת, משתמש, חבילות ומיני-אפליקציות. `קוד`. | Keep Skill Center for enthusiasts; ordinary users see plain-language Capabilities & Connections. |
| `AGENT-02` | `ADVANCED` | חיפוש/סינון, הפעלה והשבתת Skill. `קוד`. |  |
| `AGENT-03` | `ADVANCED` | יצירת Skill חדש, שם/תיאור/הוראות/trigger hints/keywords/preferred tools. `קוד`. |  |
| `AGENT-04` | `ADVANCED` | ייבוא ZIP עם `SKILL.md`, בדיקה מוקדמת והתקנה. `קוד`. |  |
| `AGENT-05` | `ADVANCED` | ייבוא Skill מכתובת HTTPS, הורדה/בדיקת חבילה. `קוד`, `מותנה`. |  |
| `AGENT-06` | `ADVANCED` | הצגת מקור Skill, SHA-256, Integrity וגרסאות בממשק. `קוד`. |  |
| `AGENT-07` | `ADVANCED` | עריכת קובצי משאב טקסט, ייבוא קבצים, הוספת משאב ומחיקה. `קוד`. |  |
| `AGENT-08` | `ADVANCED` | תצוגת metadata של קבצים בינאריים. `קוד`. |  |
| `AGENT-09` | `ADVANCED` | Override על Skill מובנה והחזרה לברירת מחדל. `קוד`. |  |
| `AGENT-10` | `SHARED` | תיעדוף Skills ממקורות שונים (system, installed packages, compiled MiniApps, custom, override). `קוד`. |  |
| `AGENT-11` | `AUTO` | כלים `load_skill`, `read_skill_resource`, `tool_search`, `read_tool_result`. `קוד`. |  |
| `AGENT-12` | `AUTO` | חשיפת כלים מדורגת ועל פי בקשת `tool_search`, במקום להעמיס את כל הסכמות. `קוד`. |  |
| `AGENT-13` | `AUTO` | `report_progress` להודעות התקדמות בתמליל. `קוד`. |  |
| `AGENT-14` | `SHARED` | Canonical Tool Authority שמאגד Native Tools, MCP, Legacy, Script, MiniApps. `קוד`. |  |
| `AGENT-15` | `SHARED` | טיפול בהתנגשויות שמות, החלטה על alias ו-route לכלי. `קוד`. |  |
| `AGENT-16` | `ADVANCED` | רישום NativeTool ואפשרות הפעלה/כיבוי לפי קבוצה או כלי. `קוד`. |  |
| `AGENT-17` | `AUTO` | כלי מחשבון מקומי `QuickCalculateTool`. `קוד`. |  |
| `AGENT-18` | `ADVANCED` | בחירת שרתי MCP ברמת שיחה, מספר שרתים פעילים, Select All ו-Disable All. `קוד`. | Per-chat MCP selection belongs in advanced Connections, not composer strip. |
| `AGENT-19` | `ADVANCED` | הגדרת MCP גלובלית, והפעלת שרתים ברירת מחדל לצ'אטים חדשים. `קוד`. |  |
| `AGENT-20` | `ADVANCED` | התקנת MCP לפי חבילת NPM / `.tgz` URL או ייבוא `.tgz`. `קוד`, `מותנה`. | Install untrusted packages only after review and explicit approval. |
| `AGENT-21` | `ADVANCED` | תצוגת תאימות והחלטת entrypoint לפני התקנה. `קוד`. |  |
| `AGENT-22` | `ADVANCED` | עריכת שם/bin/סביבת משתנים של שרת MCP. `קוד`. |  |
| `AGENT-23` | `ADVANCED` | עדכון/Repair/Reinstall/Uninstall של שרת MCP. `קוד`. |  |
| `AGENT-24` | `ADVANCED` | דיאגנוסטיקה, סטטוס, יומנים, כלי שרת ופירוט בעיות. `קוד`. |  |
| `AGENT-25` | `ADVANCED` | אחסון סודות נפרד ל-MCP ו-registry של חבילות מותקנות. `קוד`. |  |

### RUNTIME — כלים מקומיים וסביבות הרצה

| ID | Decision | Current feature from audit | Redesign note |
|---|---|---|---|
| `RUNTIME-01` | `AUTO` | סביבות הרצה: Node, TypeScript, Python מקומי, JavaScriptCore, Shell. `קוד`. |  |
| `RUNTIME-02` | `AUTO` | סטטוס Lifecycle: לא זמין, לא הוכן, מכין, מוכן, מריץ, כשל, restart נדרש. `קוד`. |  |
| `RUNTIME-03` | `ADVANCED` | התחל/עצור Runtime באמצעות מתגים, ובדיקת זמינות. `קוד`. |  |
| `RUNTIME-04` | `ADVANCED` | Smoke tests לסביבה. `קוד`. |  |
| `RUNTIME-05` | `ADVANCED` | Node Package Manager ו-Python Package Manager, התקנה/ניהול חבילות. `קוד`. |  |
| `RUNTIME-06` | `ADVANCED` | קונסולת Runtime Environment ו-logs. `קוד`. |  |
| `RUNTIME-07` | `ADVANCED` | ניקוי caches הניתנים לשחזור. `קוד`. |  |
| `RUNTIME-08` | `ADVANCED` | כלי הרצה `execute_shell_command`, `execute_javascript`, `execute_typescript`, `execute_local_python` — שמות בפועל יש לאמת מול סכמות הכלים. `קוד` לקבצי implementations. | Retain execution for agent, but gate shell/local code by scope, sensitivity and confirmation. |
| `RUNTIME-09` | `ADVANCED` | קטלוג כלים מקומיים, מידע על יכולות runtime, ניהול חבילות. `קוד`. |  |
| `RUNTIME-10` | `ADVANCED` | אזהרת כלי רגיש ויכולת השבתה פרטנית. `קוד`. |  |
| `RUNTIME-11` | `SHARED` | שירות קבצים עם scope ל-Agent/App/Package/Shared/System. `קוד`. |  |
| `RUNTIME-12` | `SHARED` | שירות SQLite עם scope והפרדת data/app/package/agent. `קוד`. |  |
| `RUNTIME-13` | `SHARED` | Capability authorization ו-grants/revocation ברמת package/app. `קוד`. |  |
| `RUNTIME-14` | `SHARED` | שירותי Host לקריאת Contacts, מצלמה, מיקרופון, דיבור, Translation, WeatherKit, Keychain, LocalAuthentication, CloudKit, Share Sheet, MapKit, PDF/Vision. `קוד`; `מותנה` ב-entitlements והרשאות. |  |

### MINI — MiniApps

| ID | Decision | Current feature from audit | Redesign note |
|---|---|---|---|
| `MINI-01` | `MINI` | גלריה של אפליקציות לפי מנוע: Swift, ScriptUI, NativeScript, Expo. `קוד`. |  |
| `MINI-02` | `MINI` | חיפוש לפי שם, סיכום, תיאור, מזהה וקטגוריה. `קוד`. |  |
| `MINI-03` | `MINI` | כרטיסי אפליקציה, launch והצגת תצוגת detail. `קוד`. |  |
| `MINI-04` | `MINI` | Edit Mode, Hide App, הצגת Hidden Apps והחזרה. `קוד`. |  |
| `MINI-05` | `MINI` | Add App/Import Package. `קוד`. |  |
| `MINI-06` | `MINI` | יבוא `.scripting`, `.hanlinNativeScript`, `.hanlinExpo`, `.zip`. `קוד`. |  |
| `MINI-07` | `MINI` | Preview מאובטח לפני הרצת קוד החבילה. `קוד`. |  |
| `MINI-08` | `MINI` | בחירת entrypoint, תצוגת תאימות והתרעות. `קוד`. |  |
| `MINI-09` | `MINI` | אישורי Capabilities נדרשים ברמת חבילה. `קוד`. |  |
| `MINI-10` | `MINI` | ביטול grants ושינוי Enabled של חבילה. `קוד`. |  |
| `MINI-11` | `MINI` | פרטי גרסאות/generation וחבילה מותקנת. `קוד`. |  |
| `MINI-12` | `MINI` | Runtime Profiles: JavaScript/TypeScript-compatible, QuickJS, Node, Python, NativeScript, Expo. `קוד`. |  |
| `MINI-13` | `MINI` | רישום MiniApps מובנות: ספריא, ויקיפדיה, TextStudio, parity demo. `קוד` לקבצי packages/registries. | Move built-in MiniApps catalog to MiniApps; maintain Sefaria/Wikipedia tools if the agent depends on them. |
| `MINI-14` | `MINI` | Native App Action Bus ו-routing חזרה למארח. `קוד`. |  |
| `MINI-15` | `MINI` | ממשקי מערכת שהסקריפטים יכולים לבקש: alerts/confirm/prompt/action sheets, Safari, editor, image/document picker, text/PDF/file preview, camera. `קוד`. |  |
| `MINI-16` | `SHARED` | חשיפת כלי Skills/תוצאות embedding/רכיבי UI חזרה לסוכן. `קוד`; **לשמר ממשק משותף גם כשהאפליקציה נפרדת**. | Do not sever agent Skills, UI result adapters, or native tools exposed by apps. |
| `MINI-17` | `SHARED` | הצגת MiniApp המופעלת מהשיחה ב-sheet/full screen/new window במוצר המאוחד הקיים. `קוד`; `אימות` לתכנון בין שתי אפליקציות. | Define resilient app-to-app launch and return behavior when companion app is missing. |

### SYS — הרחבות, פרטיות, נתונים והגדרות

| ID | Decision | Current feature from audit | Redesign note |
|---|---|---|---|
| `SYS-01` | `CONTEXT` | Share Extension שמקבלת טקסט, URL וקובץ ומשמרת רשומות באחסון App Group. `קוד`. |  |
| `SYS-02` | `FIX_FIRST` | Inbox לנתוני Share עם `pendingItems()` ו-`clear()`. `קוד`; **לא אומתה צריכה דרך מסך שיחה**, אין להניח שימוש מלא. | Share extension writes an inbox; verify that agent actually consumes it. |
| `SYS-03` | `AUTO` | Notification Service Extension שמורידה `media-url` להתראה עשירה כאשר קיים. `קוד`; לא אישור שליחה מקצה לקצה. |  |
| `SYS-04` | `AUTO` | רישום קטגוריית `CHAVRUSA_REMINDER` להתראות. `קוד`. |  |
| `SYS-05` | `AUTO` | App Intent להפעלת התראות ו-Push registration. `קוד`. |  |
| `SYS-06` | `RETIRE` | App Intent ליצירת אזעקת לימוד באמצעות AlarmKit. `קוד`, `מותנה` באישור. | Legacy domain-specific study alarm should move into a study MiniApp or retire if not a supported product goal. |
| `SYS-07` | `RETIRE` | App Shortcuts להפעלת התראות ואזעקת לימוד. `קוד`. | Remove Chavrusa-specific shortcuts from general agent default; keep only generic useful intents. |
| `SYS-08` | `FIX_FIRST` | OpenVisionIntent להפעלת מסך ראייה דרך `chavrusachat://openVisionView`, תומך ווידג'ט כפעולת Intent. `קוד`. | Remap old Vision deep link to new camera/attach path; preserve shortcut behavior. |
| `SYS-09` | `CONTEXT` | Translation Provider Extension מובנה המציע MiniChat, MiniApps ותצוגות תרגום. `קוד`; `אימות` בתרחיש מערכת. | Preserve system Translation Extension if reliable; keep independent from MiniApps navigation. |
| `SYS-10` | `SHARED` | סנכרון SwiftData עם CloudKit (`.automatic` ב-app, `.none` בטסט). `קוד`, `מותנה` בהגדרה. | Do not change existing CloudKit identifier without migration and backup strategy. |
| `SYS-11` | `SHARED` | אחסון ההודעות כולל טקסט, תמונות, תרגום, reasoning, כלי, URL/מסמכים, מפות, routes, events, health, code, knowledge cards, HTML, audio, UI blocks, AgentRun JSON. `קוד`. | Preserve full multimodal message schema, agent events and embedded results during migration. |
| `SYS-12` | `SHARED` | שימוש ב-App Groups, iCloud/CloudDocuments, HealthKit, Siri, Translation App, time-sensitive notifications, WeatherKit ב-entitlements. `קוד` ברמת פרויקט; עצם ה-entitlement אינו מבטיח הרשאה או פעולה. | Review each target entitlement before changing BundleID/App Groups/Keychain. |
| `SYS-13` | `CONTEXT` | General Settings: שם משתמש, מידע עצמי, דרישות אישיות. `קוד`. |  |
| `SYS-14` | `CONTEXT` | הגדרות שפה דרך Settings, רטט, סגנון Model Selector. `קוד`. |  |
| `SYS-15` | `ADVANCED` | כלים בהגדרות: search/knowledge/map/weather/calendar/health/code/canvas עם toggles ותתי-אפשרויות. `קוד`. | Technical integration toggles in advanced; sensitive permissions in accessible Privacy/Connections. |
| `SYS-16` | `RETIRE` | Docs guide, cost guide, version, release notes, about, contact email, copy email, send email. `קוד`. | Replace legacy contact/branding/help; retain real app info, help, support and export controls. |
| `SYS-17` | `ADVANCED` | Developer Diagnostics: off/metadata/full logs, מדיניות שמירת 10/25/50/100 או ללא מחיקה אוטומטית, הצגת round status, token usage, redaction, העתקת נתיב, פתיחת Files, מחיקת קובץ/מחיקת הכול. `קוד`. | Diagnostics belong in Developer & Support, default off and scrub secrets. |
| `SYS-18` | `AUTO` | `Localizable.xcstrings`, שפות קיימות בפרויקט (EN, ZH, HE וכו'). `קוד` לנכסים; **אין להסיק מכך שהתרגום לעברית מלא**. |  |

## סיכום כמותי

| החלטה | פריטים |
|---|---:|
| `VISIBLE` | 12 |
| `AUTO` | 48 |
| `CONTEXT` | 119 |
| `ADVANCED` | 52 |
| `MINI` | 15 |
| `SHARED` | 17 |
| `REMOVE_UI` | 6 |
| `FIX_FIRST` | 5 |
| `RETIRE` | 4 |
| **סה״כ** | **278** |

**כלל Non-Regression:** שום feature ID אינו נמחק ממסלול המשתמש/הליבה לפני שקיבל יעד owner חדש, fallback, תיעוד בדיקה ואישור. אין לסמן feature כ־PASS על בסיס code presence בלבד.
