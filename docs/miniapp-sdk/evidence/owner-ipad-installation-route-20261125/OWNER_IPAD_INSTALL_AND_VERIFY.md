# התקנה ובדיקה על iPad של הבעלים

מדריך זה מספק מסלול עבודה קונקרטי לשתי אפליקציות Hanlin ולחבילות המיני־אפליקציות המצורפות. הוא נבדק מול קוד המקור והתוצרים המפורטים כאן; **הרצה על iPad פיזי עדיין לא בוצעה במסגרת ההוכחות של מדריך זה**. תוצאות הסימולטור והקבלה המלאה מתועדות בנפרד.

## 1. התוצרים שאליהם המדריך מתייחס

גרסת המקור של התוצרים היא `f33a0d41f6367b01d63bdb5fcba8bbc5fa474b51`; מפיק הפרויקט המקורי הוא `1d5e598614f2bc7c689f34f5d7b364f67e1d5ae1`. זו זהות SDK18, לא מספר גרסה של מערכת ההפעלה.

| קובץ | שימוש |
|---|---|
| `Hanlin-MiniApp-SDK-2026-11-25.zip` | מקורות JavaScript, טיפוסים, תיעוד וכלי ה־SDK המדויקים שהופקו מה־Host |
| `SDKOnlyDepartureBudget.hanlinExpo` | דוגמת Expo: חישוב זמן יציאה והכנות |
| `SDKOnlyTableShare.hanlinNativeScript` | דוגמת NativeScript: חלוקת חשבון |
| `ModularTextSearch.hanlinExpo` | חיפוש הטקסטים המודולרי עם תוצאות ותוכן אמיתי |
| `MiniAppTypeError.hanlinNativeScript` | חבילת בדיקה מכוונת עם שגיאת TypeScript ומקורות לתיקון |

זהויות SHA256, גדלים, קבלות המפיק ושמות הקבצים המדויקים מופיעים ב־[artifact-identities.json](artifact-identities.json). קובץ ה־SDK הוא 68,726,436 בתים, SHA256:
`78e8a83d42ebfba2c9c8194acf6a0c16d3c7aab92d0ad2fbc4ecc137930226dd`.

לקובץ Modular הנוכחי עדיין יש גרסת manifest של `1.4.0`; זיהויו נעשה לפי שם הקובץ ו־SHA256, לא לפי מספר הגרסה לבדו. הוא בנוי כעת עם SHA256 `3476c670b551dcf2b8d1df5642d18470876feb1bbd0eecb0c1b7dacf8e0673f0`.

ה־SDK וארכיוני המיני־אפליקציות מיועדים ל־Host שתואם להם. הם אינם קובצי התקנה חתומים של Hanlin עצמה. מודולים נייטיביים מקוריים מוטמעים בעת בניית ה־Host; הסוכן יכול לבנות ולייבא חבילות TypeScript/JavaScript שמשתמשות במודולים וב־API הזמינים בו.

## 2. הכנת מסלול המכשיר

יש להשתמש ב־Mac עם Xcode התואם לפרויקט ול־iPadOS של המכשיר, וב־checkout הנייטיבי המוכן של הפרויקט. רישומי הפרויקט מתארים Xcode27.2, Swift6 ויעד iOS/iPadOS27. הקבצים המוכנים, המסגרות המקוריות ומשאבי ה־Host צריכים להיות תואמים לזהות התוצר; פתיחת ארכיון ה־SDK לבדו אינה מספקת את סביבת הבנייה הנייטיבית.

1. פתח ב־Xcode את `AI_HLY.xcodeproj` מתוך ה־checkout המוכן.
2. חבר או צמד את ה־iPad ל־Mac. בחר אותו כיעד פיזי בתפריט Run Destination; אם צריך, פתח Manage Devices / Device Hub.
3. הפעל Developer Mode ב־iPad לפי ההנחיות שמציגים Xcode והמכשיר. Apple מתעדת את ההפעלה ב־Settings → Privacy & Security → Developer Mode, כולל האתחול והאישור במכשיר.
4. ב־Signing & Capabilities השתמש בצוות הבעלים הקיים ובפרופילי הפיתוח המתאימים לשני היישומים ולהרחבותיהם. בהגדרות Debug המקוריות מוגדר Automatic Signing וצוות `NA6HPWARQ2`. אם Xcode מציג שגיאת חתימה, שמור את ההודעה המדויקת ואת היעד שנכשל; המדריך אינו מניח שפרופיל מתאים כבר זמין.

המסלול נשען על [הוראות Apple לבנייה והרצה על מכשיר](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices) ועל [Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device). ההוראות נקראו בגרסאות Markdown הרשמיות ב־2026-11-25.

## 3. בנייה, התקנה ופתיחה של שתי האפליקציות

| אפליקציה | Scheme ב־Xcode | Bundle ID |
|---|---|---|
| Hanlin MiniApps | `HanlinMiniApps` | `com.itorah.hanlinminiapps` |
| Hanlin AI | `AI_HLY` | `com.itorah.chavrusachat` |

בחר את ה־scheme הראשון ואת ה־iPad הפיזי, ודא שפעולת Run משתמשת ב־Debug, והפעל **Product → Run**. המתן לסיום הבנייה, ההתקנה ופתיחת האפליקציה על המכשיר. חזור על הפעולה עם ה־scheme השני. שם מוצר הבנייה של AI הוא `AI_Hanlin`.

לשני המוצרים משמשות קבוצות המקור `group.com.itorah.chavrusachat` ו־`group.com.itorah.shared`; יש לשמור על ה־Bundle IDs, קבוצות האפליקציות וההרחבות המקוריות כדי שהעברת חבילות ותיקונים תפעל. CloudKit ו־Keychain של AI נשארים בבעלות יעד AI.

הסקריפט הקיים `Scripts/ProductSplit/prepare_signed_products.py` יוצר ארכיוני Release ולאחר מכן ייצוא `app-store-connect`. הוא אינו מסלול התקנת Debug ישירה המתואר כאן. גם הצלחת build של סימולטור אינה מוכיחה חתימה או התקנה על iPad פיזי.

מקור ההגדרות: [CURRENT_BUILD_AND_RUN.md](https://github.com/davidpovarsky/hanlin-ai/blob/f33a0d41f6367b01d63bdb5fcba8bbc5fa474b51/docs/product-split/CURRENT_BUILD_AND_RUN.md) ו־[הפרויקט המקורי](https://github.com/davidpovarsky/hanlin-ai/blob/f33a0d41f6367b01d63bdb5fcba8bbc5fa474b51/AI_HLY.xcodeproj/project.pbxproj).

## 4. ייבוא ובדיקה של הדוגמאות

העבר ל־Files ב־iPad את שלוש החבילות התקינות מהערכה. לכל חבילה:

1. פתח את קטלוג האפליקציות, לחצן הוספה, ואז **Import Package**. לחלופין, במסך Packages של MiniApps השתמש ב־**Import package**.
2. במסך הייבוא לחץ **Import Script Package** ובחר את הקובץ המדויק. המתן לתצוגה המקדימה או לאבחון שגיאה. באתחול הראשון מתבצעת גם הכנת משאבי Host; עצם הופעת מסך הייבוא עדיין אינה התקנה.
3. כשתצוגת החבילה מוכנה, לחץ **Install**. פתח את הפריט שהותקן בפועל מתוך הקטלוג.
4. בצע את הבדיקה בטבלה, צא מהחבילה ופתח אותה שוב. רשום איזו אפליקציית Host ביצעה את הייבוא.

| חבילה | בדיקה שימושית על המכשיר |
|---|---|
| Departure Budget | שנה זמן יעד, זמן נסיעה, הכנה ומרווח; בדוק שהחישוב והבקרים הנייטיביים מגיבים ושהתצוגה מתעדכנת. |
| Table Share | שנה סכום, מס, טיפ ומספר משתתפים; בדוק שהסכום לאדם מתאים לנתונים, שניתן לאפס ושקלט לא תקין מציג הודעה ברורה. |
| Modular Text Search | בצע חיפוש אמיתי, פתח תוצאה וגרסת מקור, בדוק תוכן בעברית ובאנגלית, פתיחה/סגירה של קבוצת גרסה וחזרה למסך הקודם. שמור את מראה התוצאה וההפניה בפועל; שגיאת רשת אינה תוצאת תוכן מוצלחת. |

התוויות עשויות להופיע בתרגום. מזהי הממשק המקוריים לצורך זיהוי הם `hanlin-apps-add`, `hanlin-import-script-package`, `hanlin-miniapps-package-import`, `hanlin-file-importer` ו־`hanlin-package-install`.

## 5. בדיקת שגיאת טיפוסים והעברה לסוכן

ייבא את `MiniAppTypeError.hanlinNativeScript` כפי שהוא. זו חבילה עם `hanlin.authoring.json` ומקורות; בשורה הראשונה של `source/index.ts` מופיעה בכוונה ההשמה:

```typescript
export const answer: number = "wrong";
```

1. ודא שהייבוא מציג את **Package diagnostics** או **Review package diagnostics**, עם קוד השגיאה `TS2322`, שם הקובץ, חומרה ומיקום. חבילה שנכשלה בבדיקת המקורות אינה אמורה לקבל תוצאת התקנה מוצלחת.
2. פתח את ה־sheet ובדוק שהטקסט קריא ומסודר. השתמש ב־**Copy diagnostic report** לשמירת הדוח, וב־**Send to Hanlin AI to fix** להעברת החבילה המקורית והדוח המובנה.
3. ודא שנפתחה שיחת התיקון המקורית ב־Hanlin AI עם ההקשר המצורף. בקש מהסוכן לתקן את ההשמה ל־`42`, להשתמש ב־SDK המותקן ולבצע validation, build ו־import דרך הכלים המקוריים.
4. בדוק שהתקבל מצב **installed** עם `installedPackageID` שאינו ריק. מצבי `queued`, `received` או `submitted`, או פתיחת קישור בין האפליקציות, אינם תחליף לכך.
5. פתח את החבילה המתוקנת ב־MiniApps וודא תוצאה נייטיבית **MiniApp repair result 42**, ואז פתח אותה שוב. שמור צילום sheet, שיחת התיקון, תוצאת ההתקנה והמסך המתוקן.

הזרימה משתמשת ב־composer ובמסלול הסוכן הקיימים. קבלות ההעברה ומקורות החבילה מאפשרים להבחין בין שליחה, תיקון, בנייה והתקנה. המקור המדויק: [IMPORT_REPAIR.md](https://github.com/davidpovarsky/hanlin-ai/blob/f33a0d41f6367b01d63bdb5fcba8bbc5fa474b51/docs/miniapp-sdk/IMPORT_REPAIR.md).

## 6. תיעוד תוצאת הבדיקה והמצב הנוכחי

מלא עותק של [owner-verification-template.json](owner-verification-template.json): תאריך, דגם iPad, גרסת iPadOS, מזהה מכשיר בפלט המקומי, גרסת Xcode, זהות מקור/SDK, תוצאות התקנת שני המוצרים ותוצאות ארבעת המסלולים לעיל. הוסף את תוצאות ההתקנה, מזהי החבילות, צילומים ואבחונים. התבנית מתחילה ב־`NOT_RUN` ואינה קבלה על בדיקה שכבר קרתה.

במסלול שנצפה ב־2026-11-25T05:00:15.976606Z היו 52 סימולטורי iOS, חמישה סימולטורי Watch ו־Mac פיזי אחד; לא נחשף iPad/iPhone פיזי. לכן לא נבדקו במסלול זה: זהות iPad וגרסתו, הצימוד שלו, פרופילי הפיתוח התקפים למכשיר, או התקנה והרצה של תוצרי device חתומים. אי־זמינות המכשיר מתועדת בנפרד מהשלמת מסלול ההתקנה ומהוכחות הסימולטור.

בדיקות התראות APNs, הרחבת שירות, רקע, נעילה ויכולות חומרה דורשות תוצאות נפרדות אם בודקים אותן. הצלחת הדוגמאות או תהליך התיקון אינה מוכיחה אותן אוטומטית. אין צורך בפרסום אוטומטי ל־TestFlight כדי להשתמש במסלול הבעלים הזה.

## מקור המדריך

זהו תיעוד נוסף בלבד, תחת תיקיית `evidence` המוחרגת במפורש מקלטי ה־SDK ומהעתקת תיעוד ה־SDK. הוא אינו משנה מקור אפליקציה, חתימה, טיפוסים או תוצאת בדיקה. קבלות המפיק המקוריות נשמרות ללא שינוי בתיקיית `raw`; [source-bindings.json](source-bindings.json) קושר את המקורות שנקראו ל־commit ול־SHA256 המדויקים.

החלטת המוצר נשארת: APIs וטיפוסים מקוריים ומתוחזקים של Expo, NativeScript ו־ScriptWidget; פיתוח תכונות Scripting/ScriptUI הישן מוקפא, עם שמירת התאימות והנתונים; אין נקודת כניסה לממשק בית מותאם.
