# תוכנית ביצוע — סביבת Runtime פתוחה ואוטונומית ב־Hanlin

**תאריך:** 10.11.2026

**תפקיד:** [איתן | ARCH] [MAIN_SESSION] — תכנון ישיר, ללא סוכני משנה

**מצב:** BACKLOG — ממתין לסיום העבודה הנוכחית ולמעבר לשלב הבא בידי הבעלים

**משימת מדיניות קיימת:** [CAPABILITY-POLICY](https://app.asana.com/0/1219603102275846/1220016619489134)

**בסיס הבדיקה:** `fix/hanlin-approved-plan-20261108`, commit `d04afe3db2883efc77e54494a4c911833c78b1d7`, המבוסס על Pass 7.

**ענף המסמך בלבד:** `codex/runtime-autonomy-plan-20261110`.

> הוראת הבעלים: להכין כעת מסמך ומשימת המשך. להתחיל במימוש רק לאחר שהסוכן בשיחה הראשית מסיים את עבודתו. אין להפעיל עבודה זו אוטומטית בעקבות סיום CI, לשנות את הענף הפעיל, לבטל עבודות קיימות או להוסיף לתוכן דרישות במהלך ההרצה.

## 1. התוצאה הנדרשת

Hanlin היא סביבת פיתוח אישית. הסוכן, Skills, סקריפטים, חבילות Python/npm, שרתי MCP ו־Native API צריכים לפעול אוטונומית ללא אישורי Hanlin נוספים, רשימות חסימה שרירותיות או תקרות עבודה חבויות.

- הסוכן ממשיך עד השלמת הבקשה, ביטול מפורש של המשתמש או כשל אמיתי ומדווח.
- פעולות ארוכות הן עבודות ניתנות למעקב ולביטול; אין עצירה אוטומטית אחרי 40 צעדים או 300 שניות.
- תוצאות נשמרות במלואן ומועברות בזרימה, בדפים או כקבצים; אין איבוד נתונים בגלל מגבלת זיכרון פנימית.
- התקנה והרצה מתבססות על יכולות שנבדקו בפועל, ולא על הנחות גורפות כגון ״כל קוד נייטיבי בלתי אפשרי ב־iOS״.
- משלימים את תמיכת WASM ו־Fetch, התקנת החבילות, Shell ומתאמי ההרצה לפי הסדר שבהמשך.
- אין להציג סביבה כ״ללא מגבלות״ או כתואמת לכל חבילת מחשב לפני שיש ראיה לכל יכולת.

הרשאות חובה של מערכת ההפעלה, זמינות API, חתימת קוד, מגבלות זיכרון/דיסק אמיתיות והשבתה מפורשת בידי המשתמש נשארות עובדות מערכת. שמירת זהות הריצה ונתוני החבילה, בדיקת שלמות, TLS ותקינות פורמט אינן מנגנון אישור נוסף. אין להחליפן בבקשות רשות חדשות.

## 2. שער כניסה — לאחר סיום הסוכן הנוכחי

לפני כל שינוי יישום:

1. לקבל מסירת עבודה מהשיחה הראשית: ענף, SHA סופי, שינויים שלא נחתמו, מצב הבניות, hash של הבינארי ומצב הבדיקות. אין להסיק סיום מלוח Asana או מהיעדר פלט בטרמינל.
2. לשמר את תוצרי עבודת Pass 7 וה־Runtime הנוכחית. ענף הביצוע ייגזר מה־SHA הסופי שנמסר, לא אוטומטית מבסיס הבדיקה `d04afe3d`.
3. לאמת מחדש כל ממצא בטבלה מול ה־HEAD הסופי ולמחוק כפילויות שכבר תוקנו. אין לבצע מחדש תיקון שנמצא כבר בקוד.
4. לעדכן את מטריצת ההשפעה והראיות: תיקון FD/V8, HTTPS, argv של Skills, נתיבי fs, הרשאות, חבילות, UI ואימותי מכשיר.
5. להסכים על מקור תיעוד אחד ליכולות ולהגדרות. מצב התחלתי של כל דרישה במסמך הוא NOT_RUN; המסמך אינו הוכחת מימוש.
6. הבעלים יעבור לביצוע לאחר סיום העבודה הנוכחית. אין במסמך הוראת תזמון, watcher, שחרור או מיזוג אוטומטיים.

משימות קשורות נשארות בעלות היקף וראיות משלהן: [Skills](https://app.asana.com/0/1219603102275846/1219603005959542), [Node HTTPS/FD](https://app.asana.com/0/1219603102275846/1220016668944519), [Dependency audit](https://app.asana.com/0/1219603102275846/1219718259933043). אין לשנות את סטטוס העבודה הנוכחית כדי לסמן את תוכנית ההמשך.

## 3. ממצאי בסיס שנקראו בקוד

| מזהה | הממצא בבסיס הבדיקה | מקור עיקרי |
|---|---|---|
| AUT-01 | ברירת מחדל של 40 צעדי סוכן; נתיב הצ׳אט משתמש בברירת המחדל | `Packages/HanlinPlatform/Sources/HanlinChatCore/HanlinAISDKAgentEngine.swift`; `AI_HLY/Services/ChatServices/APIManager.swift` |
| AUT-02 | תקציבי סכמות של 24,000/28,000 bytes דוחים או מסתירים כלים מהצעד הנוכחי | `AI_HLY/Downstream/AgentSkills/AssistantToolExposurePlanner.swift`; `HanlinAISDKToolAdapter.swift` |
| AUT-03 | מאגר תוצאות בזיכרון: 50 תוצאות ו־10MiB, פינוי תוצאות ישנות; קריאה בדפים של עד 16KiB | `AI_HLY/Downstream/AgentSkills/ToolResultStore.swift`; `ReadToolResultTool.swift` |
| AUT-04 | Python/Node/TS: ברירת מחדל 30s, clamp עד 300s; פלט ברירת מחדל 1MiB ותקרה 8MiB. ב־Node מגבלת בקשה 10MiB ומגבלות שורות/פרוטוקול | `RuntimeCore/Core/RuntimeModels.swift`; `Tools/RuntimeToolSupport.swift`; `Node/Host/host.mjs` |
| AUT-05 | מתקין Python מותאם: רק wheels אוניברסליים מסוג py3-none-any, ללא מסלול sdist; extras מסוננים; פתרון גרסאות/markers חלקי; תקרה של 512 תלויות | `RuntimeCore/Python/PythonPackageManager.swift` |
| AUT-06 | מתקין Python דוחה סיומות בינאריות בכל מקום בארכיון, לרבות חומר שאינו בהכרח נטען. אין במתקין הקיים מסלול מלא להרחבות iOS ארוזות | אותו קובץ |
| AUT-07 | Worker של שרתי MCP חוסם cluster, קריאות child_process וטעינת .node. זה אינו איסור גורף על כל Node API בכל מנוע | `RuntimeCore/Node/Host/server-worker.mjs`; `package-compatibility.mjs` |
| AUT-08 | בדיקות תאימות npm מקבעות Node 24.5.0 / darwin / arm64; סריקת ארכיון מוגבלת ל־25,000 קבצים ו־256MiB לקובץ | `RuntimeCore/Node/Host/package-compatibility.mjs` |
| AUT-09 | broker לסקריפטי התקנה אינו Shell מלא: דחיית pipes, chaining, redirection ו־expansion. קטלוג Shell כולל 23 פקודות ובנפרד pwd; בכלי עד 127 ארגומנטים | `Node/Host/lifecycle-planner.mjs`; `Shell/ShellRuntimeService.swift`; `Tools/ExecuteShellCommandTool.swift` |
| AUT-10 | ייבוא Skills: הורדה עד 25MiB, קובץ מקומי עד 256MiB, גבולות מספר קבצים/עומק/פריסה | `AgentSkills/SkillImporter.swift` |
| AUT-11 | תוצאות ScriptUI המוטמעות בצ׳אט עדיין תלויות ב־grants לקבצים/אחסון, בעוד שבנתיבי ההפעלה הרגילים מועבר true | `EmbeddedResults/ScriptUIEmbeddedResultAdapter.swift:70`; `ScriptingPlatform/HanlinScriptingPlatform.swift` |
| AUT-12 | נתיב KV של Scripting מוגבל ל־1MiB ודוחה shared. זו אינה מגבלה כללית של אחסון ה־MiniApps, שברירות המחדל שלו ללא quota | `HanlinScriptingApplicationRuntime/HanlinScriptingApplicationSession.swift`; `HanlinMiniAppCore/HanlinMiniAppDataStore.swift` |
| AUT-13 | חסימת שמות משתני סביבה בממשק ההגדרה, לרבות PATH/HOME/PYTHONPATH, לצד נתיב Node שמאפשר overrides | `RuntimeCore/Core/RuntimePolicy.swift`; `Environment/RuntimeEnvironment.swift`; `Node/Host/host.mjs` |
| AUT-14 | כלי דיווח היכולות מציג Ready וגרסאות/מגבלות מקובעות. מגבלת Python של 500MB המדווחת אינה מופעלת ב־AppRuntimeCore: maximumWheelSizeBytes=nil | `RuntimeCore/Tools/GetRuntimeCapabilitiesTool.swift`; `Core/AppRuntimeCore.swift` |
| AUT-15 | WASM אינו חשוף בבנייה הנוכחית. Fetch compatibility דוחה integrity ואינו מעביר dispatcher | `RuntimeCore/Node/Host/fetch-compatibility.mjs`; מקור Node/V8 הנעול |
| AUT-16 | מגבלות רקע, הרשאות וחתימת קוד הן תלויות פלטפורמה; עצם הסרת guard אינה יוצרת subprocess או טעינת בינארי תואם | מקורות רשמיים בסעיף 10 |

החסימות הישנות כבר הוסרו בחלק מהמסלולים: `HanlinHostCapabilityAuthority.authorize` מחזיר allowed, ובדיקת המילים `rejectUnsafeSource` היא no-op. אין להחזיר אותן, ואין לדווח עליהן בטעות כחסימות פעילות רק מפני ששמן נשאר בקוד.

## 4. סדר הביצוע

### שלב A — חוזה יכולות אחיד ואיחוד הרשאות

- למפות כל נתיב כניסה: כלי סוכן, Skill, MCP, MiniApp, ScriptUI, Expo, NativeScript, Widget ו־Intent.
- להסיר את תלות ה־grants שנותרה ב־ScriptUI embedded results ולבדוק גם את הספקים/המתאמים המקבילים.
- לשמר בחירת משתמש מפורשת להפסיק/להשבית, זהות session, generation ותקינות handler. אלה אינם pop-up של הרשאה.
- להפיק דיווח חי: version, readiness, active engine, supported operations, native-extension catalog, background/cancellation abilities, ו־configured limits אם המשתמש בחר כאלה.
- להבחין בשגיאות בין פער מימוש, תלות בפלטפורמה, חבילה בלתי תואמת, משאב שאזל וביטול משתמש. אין לכנות כל שגיאה permission denied.
- להסיר תיאורים ישנים ו־UI שממציאים מגבלות או אישורים.

### שלב B — עבודות ארוכות, לולאת סוכן ותוצאות מלאות

- להחליף את תקרת 40 הצעדים במדיניות המשך עד השלמה/ביטול; גבול משתמש, אם נבחר, יהיה מפורש ולא מוסתר.
- להגדיר JobID ומצב עבודה משותפים למנועים: queued/running/completed/failed/cancelled/interrupted, התקדמות, stdout/stderr בזרימה, וקובצי תוצאה מלאים.
- timeout יהיה אופציונלי; ברירת המחדל החדשה לא תכניס תקרת Hanlin שרירותית. לעדכן יחד schemas, Swift models, JS protocol, Python bridge ו־callers. אין להחליף 300 ב־Int.max ולהשאיר overflow או מגבלה בשכבה אחרת.
- להחליף truncation ופינוי תוצאות במאגר קבצים מתמשך עם references יציבים וקריאה בדפים/זרימה. לתעד מחיקה מפורשת ושגיאות דיסק אמיתיות.
- תקציב prompt אינו הרשאה: כל כלי צריך להיות ניתן לגילוי ולהרצה בלי starvation גם כאשר כל הסכמות אינן מתאימות לבקשת מודל אחת.
- לתעד יכולת interrupt אמיתית לכל מנוע. אין להבטיח ביטול מיידי של קוד C או JavaScriptCore שאינו ניתן להפסקה בטוחה; להפנות עבודה מתאימה ל־Worker או למסלול תומך, בלי לשנות תוצאות בשקט.

### שלב C — התקנת Python מלאה ככל שהפלטפורמה מאפשרת

- להחליף את פתרון התלויות החלקי במימוש תקני שנבחר לאחר בדיקת packaging/pip: PEP 440/508, extras, markers, Requires-Python, backtracking ו־wheel tags אמיתיים.
- לתמוך בחבילות מקומיות, wheel/ארכיון/מקור ומקורות שהמשתמש הגדיר. לא להוסיף סינון אוניברסלי של מקור חבילה ללא צורך פונקציונלי.
- להוסיף מסלול ל־sdist של חבילת Python טהורה ול־build backends תואמים, בלי להניח שקיים subprocess במכשיר.
- להסיר את תקרת 512 ואת קיבוע פרטי ה־interpreter; להשתמש בנתוני המנוע בפועל ובפתרון תלויות מדווח וניתן לביטול.
- להבחין בין קובץ בינארי לא פעיל בארכיון לבין הרחבה שאמורה להיטען. לא לדחות חבילה רק בגלל קובץ דוגמה שאינו במסלול ההרצה.
- להוסיף registry להרחבות נייטיביות שנבנו ל־iOS/Simulator, נארזו ונחתמו כחלק מהאפליקציה, עם imports תואמים ו־provenance. אין לטעון ש־wheel למחשב ייטען במכשיר אחרי הסרת guard.
- לשמר staging, שלמות, import probe, rollback ונתוני התקנות קיימות. סיום התקנה פירושו import והרצה אמיתיים, לא רק חילוץ ZIP.

### שלב D — npm, MCP, Shell וסקריפטי התקנה

- לאחד התנהגות התקנה גלובלית/כלי סוכן/שרת MCP. לבדוק engines/platform/architecture לפי המנוע בפועל, בלי קיבוע darwin כאשר runtime מדווח ios.
- להרחיב את תכנון סקריפטי ההתקנה: סדר פעולות, quoting, משתנים, pipes, redirection, chaining, exit status, cwd ו־stdio. להשתמש במנוע Shell/מתאם אמיתי שנבדק, לא בפיצול טקסט שמעמיד פנים שהוא Shell.
- להרחיב את קטלוג ios_system בהתאם לפקודות שניתן לקשר ולהריץ בפועל. לא לדווח על Bash/כל פקודת Unix לפני שבוצעה.
- להגדיר מתאמים מפורשים להפעלת Node/Python וכלים מקושרים מתוך חבילות. Workers הם threads, לא תהליכי POSIX.
- עבור child_process/cluster ותוספי .node: למפות את הצרכים, להוסיף מתאמים/מודולים שנבנו מראש היכן שאפשר, ולבחון תאימות מלאה של stdio, IPC, exit, cancellation ולייפסייקל. אין להסיר guard ולהחזיר הצלחה מדומה.
- במקרה שמימוש מקומי אמיתי אינו אפשרי, לספק מסלול משלים לסביבת שרת בשליטת המשתמש, לאחר שמקור החיבור וההרשאה הוגדרו. אין לשלוח קוד או נתונים בשקט לשרת ציבורי קיים או להחליף הרצה מקומית בהרצה מרוחקת ללא גילוי.
- להחליף מגבלות ספירה/גודל שרירותיות בהתקנה וסריקה מבוססות זרימה ומשאבים אמיתיים, תוך זיהוי כשל/ביטול ושמירת rollback.

### שלב E — WASM, Undici ו־Fetch

- לבדוק את קוד Node/V8 הסופי ואת מערכת GYP בפועל לפני בנייה מלאה. במקור שנבדק DrumBrake קיים אך אינו מחובר כמסלול בנייה פעיל במערכת Node שנבדקה.
- בגרסה שנבדקה דגל wasm_jitless של DrumBrake מוגדר experimental; אין להציגו כיכולת ייצור מאומתת לפני הוכחת השילוב והקבלה.
- להכין הוכחת שילוב מצומצמת ל־ARM64 ללא JIT: מודול WASM אמיתי, Promise APIs, זיכרון ו־imports. לוודא שאינו זקוק ליכולת executable-memory שאינה זמינה למסלול האפליקציה.
- לבחור בין שילוב DrumBrake בגרסה הנעולה לבין עדכון engine נתמך, לפי ראיות תאימות. עדכון Node אינו ברירת מחדל עיוורת.
- לבדוק את parser ה־WASM של Undici ואחר כך את Fetch המקורי; להשלים integrity ו־dispatcher ברמת ההתנהגות המלאה. אין להתעלם בשקט מ־Proxy/Agent שהוגדרו.
- אם נחוצה שכבת תאימות, להגדיר חוזה מלא ולבדוק class identity, streams, clone, abort, redirects, compression, multipart, SRI ו־connection management.
- לרכז את כל שינויי הליבה המאומתים לפני בניית שתי הפרוסות המלאה. שילוב WASM משנה את המנוע ולכן מחייב בדיקה חדשה של FD, HTTPS והצרכנים המושפעים; אין למחזר עבורו PASS מבינארי אחר.

### שלב F — Skills, סביבה, אחסון ושיתוף מכוון

- להסיר תקרות ייבוא שרירותיות באמצעות הורדה/חילוץ בזרימה, דיווח אחסון וביטול; לשמר תקינות ארכיון ונתיבי קבצים.
- לאחד שינויי environment בין UI, Node, Python ו־Shell; לאפשר הגדרות משתמש בלי חסימה לפי שם בלבד. פרטי אתחול פנימיים יקבלו חוזה נפרד כדי ששינוי PATH לא יהרוס את חיבור המארח.
- להחליף אחסון KV מוגבל בנתיב canonical המתאים לכמות הנתונים, ולהשלים shared storage לפי כוונת המשתמש וזהות החבילה. לא לפתור תקרה בהעתקת נתונים למקום זמני שנמחק.
- לשמר נתוני אפליקציות, מופעי Widgets, חבילות ו־references במיגרציה. להימנע מאיפוס גורף או מחיקה כדי ״לתקן״ תאימות.

### שלב G — רקע, חידוש ואימות מכשיר

- להגדיר מה ממשיך כשהאפליקציה ברקע ומה מחודש לאחר suspension או termination.
- לבדוק תמיכה ב־BGContinuedProcessingTask ובמנגנונים המתאימים לגרסת היעד, עם דיווח התקדמות ושמירת מצב.
- הפסקה בידי iOS תדווח interrupted ולא ככשל הרשאה או success. לתמוך בחידוש עבודות שניתן לחדש באופן תקין, בלי לשכפל פעולות צד.
- לבצע אימות באייפד פיזי של עבודה ארוכה, נעילה/רקע/חזרה, התקנות, networking ו־UI/Widgets/Intents המושפעים.

## 5. מטריצת קבלה מחייבת

| דרישה | ראיה נדרשת לפני PASS |
|---|---|
| A — הרשאות מאוחדות | אותה חבילה ללא grants מריצה פעולת קבצים/אחסון במסלול רגיל ובתוצאה מוטמעת. זהות ריצה ישנה וביטול משתמש עדיין מתנהגים נכון. |
| B1 — סוכן מתמשך | ריצה דטרמיניסטית אמיתית של יותר מ־40 צעדים עד השלמה, כולל גילוי כלים ותוצאות; ביטול מפורש עוצר אותה. |
| B2 — עבודה ארוכה | Node ו־Python משלימים עבודות שעוברות בפועל את 300 השניות; בדיקות נפרדות של timeout מפורש, ביטול והפסקת מערכת. שעון מזויף לבדו אינו הוכחת שילוב. |
| B3 — תוצאות וכלים | יותר מ־50 תוצאות ותוכן גדול מ־10MiB נשארים נגישים ושלמים לפי digest; כלים מעבר לתקציב הסכמות מתגלים ומבוצעים. |
| C1 — Python resolver | fixtures ל־extras/markers/Requires-Python/backtracking/wheel tags; חבילת wheel, חבילת מקור טהורה ומקור מקומי מותקנים ומיובאים. |
| C2 — הרחבה נייטיבית | הרחבה אמיתית שנבנתה ל־iOS נטענת במכשיר ומחזירה תוצאת nonce; ABI וחתימה מתועדים. חומר לא פעיל בארכיון אינו גורם לדחייה גורפת. |
| D1 — npm/lifecycle | התקנה/עדכון/הסרה אמיתיים עם סקריפט מורכב, cwd/env/stdio/exit תקינים ו־rollback לאחר כשל. |
| D2 — MCP/מתאמים | חבילות אמיתיות מפעילות כל יכולת נתמכת; לא רק import. מיפוי child_process/cluster/native modules מציין local/adapter/external או חסם מערכת מוכח. |
| E1 — WASM | instantiate והרצה אמיתיים במנוע iOS ללא JIT, כולל imports/זיכרון ולייפסייקל. |
| E2 — Fetch | TLS GET/POST, SRI תקין/שגוי, dispatcher/Proxy מבוקר שמוכיח את נתיב הבקשה, streams/clone/abort/compression/multipart; שגיאות TLS נשארות שגיאות. |
| E3 — מנוע חדש | שני יעדי Node, hashes מקור/patch/binary אמיתיים, FD ownership עם tracking פעיל, Host startup ושילוב הצרכנים שהשתנו. |
| F — Skills/אחסון | ייבוא גדול מהתקרות הישנות, שיתוף מכוון, environment overrides ושימור נתונים לאחר שדרוג/רענון. |
| G — אמת בדיווח | get_runtime_capabilities תואם ל־runtime בפועל במצבי ready/stopped/failed וליכולות שבוצעו; אין מספרי מגבלות מקובעים שגויים. |
| H — מכשיר | אייפד פיזי: עבודות ארוכות, חזרה מרקע/נעילה וצרכני Widget/Intent/Expo/ScriptUI שהושפעו; simulator אינו תחליף. |

אין לסמן ״כל חבילות npm/PyPI נתמכות״ על סמך דוגמאות בודדות. יש לפרסם מטריצת יכולות עם שמות חבילות וגרסאות שבוצעו בפועל, ואת המסלול של כל יכולת תלוית פלטפורמה.

## 6. מדיניות מגבלות ומשאבים

- ברירת המחדל לא תכיל תקרת Hanlin חבויה על צעדי סוכן, משך עבודה או שמירת תוצאה.
- גבול שהמשתמש בחר יהיה נגיש, מתועד ומדווח לכל המנועים באופן עקבי.
- pagination, streaming ו־backpressure הם אמצעי העברה, לא סיבה לאבד נתונים או למנוע הרצה.
- אין להבטיח זיכרון/דיסק אינסופיים. כשל משאב ממשי יקבל קוד שגיאה, תוצאה חלקית שמורה ומסלול חידוש כשאפשר.
- שדה legacy כגון requiresApproval אינו אישור חדש. לשמר קריאה של נתונים קיימים בלי להחזיר gate.
- לא להסיר בדיקות digest, TLS, ABI או תקינות חבילה כדי לגרום למבחן לעבור. צריך לספק יכולת פועלת.

## 7. תלויות, בנייה ושימוש חוזר בראיות

1. להפיק impact map לפני כל קבוצת שינוי ולהתבסס על SHA המסירה הסופי.
2. לבדוק סטטית/מקומית תחילה; API/SDK/Swift Apple-only יאומתו באמצעות apple-devtools ותיעוד רשמי.
3. בדיקות כשל חדשות מוכיחות התנהגות חסרה, לא משקפות רק את מבנה המימוש. שינויי תיעוד אינם מצדיקים CI.
4. לא לשדרג יחד engines, React/Expo וכל תלות אחרת ללא צורך. לקבע גרסאות תואמות, lockfiles, רישיונות ו־provenance.
5. לא לבצע בניית Node מלאה מחדש בגלל שינוי Host JS/Swift בלבד. להכין proof ממוקד, לרכז שינויי engine, ואז לבנות את היעדים הנדרשים.
6. שינוי V8/WASM/ABI או runtime inputs מבטל ראיות קודמות של הצרכנים המושפעים. אחרת reuse מותר רק עם זהות test/assertions/fixtures/dependencies/toolchain/platform מתועדת.
7. להפריד EXECUTED_PASS, REUSED_VERIFIED_PASS, FAILED, NOT_RUN, BLOCKED_DEVICE ו־BLOCKED_EXTERNAL. סיום תהליך build אינו PASS של פונקציה.
8. GitHub מנוהל ב־CLI/API בלבד, עם watcher יחיד לכל ריצה. אין הרחבת automatic triggers.
9. עדכון hashes ו־verified status רק מתוצר שנוצר ונבדק בפועל. אין העתקת hash מבינארי קודם.
10. merge/release/TestFlight אינם פעולה אוטומטית של תוכנית זו; לבצע בהתאם לבקשת הבעלים ושערי ההפצה הקיימים.

## 8. תוצרים וסדר מסירה

- T0: מסירת עבודה קודמת, בסיס סופי ומיפוי פערים מעודכן.
- T1: חוזה יכולות חי, איחוד הרשאות ותיקון embedded results.
- T2: סוכן ועבודות מתמשכות, זרימת פלט ומאגר תוצאות מלא.
- T3: פתרון והתקנת חבילות Python; עדכון npm/MCP/Shell ולייפסייקל.
- T4: הוכחת WASM ומתאמים נייטיביים, הכרעה ארכיטקטונית ותכנון חתימת התוספים.
- T5: בנייה מאוחדת של השינויים הנייטיביים ואימות engine/Host/צרכנים.
- T6: Skills, environment, אחסון משותף ומיגרציות נתונים.
- T7: אימות משולב ומכשיר, מטריצת יכולות ודו״ח סיום מדויק.

הסדר ניתן לעדכון לאחר T0 אם התלויות מחייבות זאת; אין לדחות תיעוד של חסם מערכת לאחר בנייה יקרה. כאשר יכולת מקומית אינה אפשרית, יש למסור הוכחה ומסלול חלופי מפורש, לא להסתפק במילה ״אסור״ ולא להמציא הצלחה.

## 9. תנאי סיום

המשימה נשארת פתוחה עד שהדרישות יושמו ונבדקו במסלולים שנבחרו, המידע לסוכן מדויק, נתונים קיימים נשמרו, והתוצאות והפערים מתועדים ב־Asana עם SHA וראיות. יכולת המחייבת שרת/חתימה/מכשיר ואינה זמינה מסומנת חסומה במפורש; אין לסגור אותה כחלק מספירת PASS כללית.

המסמך עצמו הוא תוצר תכנון בלבד. במועד כתיבתו לא בוצעו שינויי יישום, בדיקות חדשות, שינוי תלויות או הפצה עבור משימה זו.

## 10. מקורות והקשר

- [V8 WebAssembly architecture / DrumBrake](https://github.com/v8/v8/blob/main/docs/wasm/architecture.md).
- [V8 BUILD.gn ב־Node Mobile המדויק שנבדק](https://github.com/nodejs-mobile/nodejs-mobile/blob/4768489cd0cfa3bb0c27786e958c6446c004f1bd/deps/v8/BUILD.gn#L405).
- [דגלי Wasm interpreter בגרסה הנעולה](https://github.com/nodejs-mobile/nodejs-mobile/blob/4768489cd0cfa3bb0c27786e958c6446c004f1bd/deps/v8/src/flags/flag-definitions.h#L1969).
- [Undici Fetch ו־dispatcher/integrity](https://github.com/nodejs/undici/blob/main/docs/docs/api/Fetch.md).
- [Python on iOS — אריזה, הרחבות ו־AppleFrameworkLoader](https://docs.python.org/3.14/using/ios.html).
- [PEP 730 — subprocess ותלות בפלטפורמת iOS](https://peps.python.org/pep-0730/).
- [Apple — BGContinuedProcessingTask](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask).
- [Apple — Security of runtime process](https://support.apple.com/guide/security/security-of-runtime-process-sec15bfe098e/web).
- דוח העבודה הקודמת: [APPROVED_PLAN_2026-11-08.md](../voice-recording/APPROVED_PLAN_2026-11-08.md). לקרוא את הגרסה הסופית שנמסרת מהסוכן הנוכחי, לא לפרש רשומות היסטוריות כסטטוס חי.
