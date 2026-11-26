# מחברת המערכת — NativeScript

דוגמה עצמאית למיני־יישום: היא שומרת ספירה ותוצאה של פעולות שהתקבלו בפועל מ־Spotlight, מהמצלמה ומהתראה, ומספקת מקלדת מקורית להכנסת טקסט. מזהה החבילה הוא `hanlin.demo.system.nativescript`.

## שימוש

1. בנו את הפרויקט וייבאו את `system-notebook-nativescript.hanlinNativeScript` ל־Hanlin התומך בארבעת נתיבי המערכת החדשים. מסמך זה אינו הוכחה שהחבילה הותקנה או שהנתיבים הורצו במכשיר.
2. **Spotlight:** חפשו את שם החבילה ולחצו על התוצאה. הפעולה `spotlight.open` אמורה לפתוח את היישום ולעדכן את הספירה והתוצאה השמורה.
3. **צילום:** בפרטי החבילה, תחת **Camera**, לחצו **Use for Camera Control** ובחרו **Open camera**. לאחר צילום והמשך ליישום, `capture.receive` מקבל את זהות ההתקנה, הדור, הסשן וקובצי ה־JPEG. הדוגמה קוראת כל קובץ מתוך Documents של החבילה ומשווה את אורכו לערך שנמסר; היא אינה מייצרת רשומת צילום מדומה. Camera Control והכניסה מהמסך הנעול משתמשים באותה בחירה. הפעלתם תלויה במכשיר ובאפשרויות המערכת.
4. **מקלדת:** הוסיפו את מקלדת היישום המארח בהגדרות iOS; במקלדת בחרו בחבילה. השתמשו ב״שלום״, ״תודה רבה״, מחיקה, הזזת סמן והמקלדת הבאה בשדה הטקסט שבדוגמה או בשדה רגיל אחר. אלו פעולות של `textDocumentProxy` דרך `$presentation.keyboard`.
5. **התראה עשירה:** תחילה העבירו צילום אמיתי. אחר כך לחצו **יצירת התראה עשירה בעוד 10 שניות**, אשרו את בקשת ההתראות של iOS אם תופיע, ועברו לרקע. לחיצה ממושכת על ההתראה מציגה את ממשק ScriptWidget המקורי; **המשך במחברת** מבקש המשך ליישום והפעולה המוצהרת `notification.open`. **סגירת ההתראה** סוגרת את התצוגה. תשובת התזמון `scheduled: true` מאשרת רק שקבלת הבקשה אושרה ב־UserNotifications.

אחרי עדכון או התקנה מחדש יש להעביר צילום חדש לפני תזמון התראה: זהות ההתקנה והדור נלקחים מהעברת הצילום האחרונה, וה־Host בודק אותם שוב לפני ביצוע. אירוע ההתראה בדוגמה תקף ל־24 שעות. דחיית התראה בידי המערכת או סגירתה בלי המשך אינן נרשמות כהפעלת פעולה.

## חוזי המקור

| משטח | entrypoint | פעולה / מקור | קלט |
|---|---|---|---|
| Spotlight | `search` | `spotlight.open` | `NativeSpotlightInput`, כולל `source: 'spotlight'` |
| צילום | `photo` | `capture.receive` | `NativeCaptureInput`: זהויות, דור ורשימת קובצי JPEG אמיתיים |
| מקלדת | `keys` | `native/keyboard.tsx` | `$getenv('presentation')`, פעולות `$presentation.keyboard` |
| תוכן התראה | `notice` | `native/notification.tsx` | `NotificationPresentationUserInfoV1` |
| המשך מהתראה | `notice-action` | `notification.open` | `HanlinNotificationUserInfoV1`, מקור `notification` והודעה |

`notebook.ts` מאמת את קלט הצילום בזמן ריצה; הוא שומר את ערכי SHA256 שנמסרו מה־Host, אך אינו מבצע אימות גיבוב נוסף של התמונה. הקריאה בפועל וגודל התמונה מופיעים בתוצאה. המקור שומר מצב פרטי בקובץ `system-notebook.json`, ומעבד עדכונים לפי הסדר.

הממשקים של המקלדת וההתראה הם מקורות ScriptWidget עצמאיים. הם נבדקים בתוכנית TypeScript נפרדת מהיישום NativeScript; זה אינו מנוע Scripting הישן או מסך בית חלופי.

## בדיקת מקור ובנייה

נדרשים מקור CLI הנוכחי של Hanlin ותיקיית ה־SDK המסופקת. ה־SDK עצמו מכיל הצהרות וחבילות מקור; הוא אינו כולל את קובץ ה־CLI שבנתיב הריפו הבא. `HANLIN_REPO` מצביע לריפו ו־`HANLIN_SDK` לתיקייה המכילה `miniapp-sdk.json`. אין צורך להריץ `npm install` בפרויקט הזה.

```sh
node "$HANLIN_REPO/Scripts/MiniApps/miniapp.mjs" validate --sdk "$HANLIN_SDK" --engine nativescript --project . --report validate.json
node "$HANLIN_REPO/Scripts/MiniApps/miniapp.mjs" build --sdk "$HANLIN_SDK" --engine nativescript --project . --archive "../system-notebook-nativescript.hanlinNativeScript" --report build.json
```

בחרו שם קובץ חדש לפלט הבנייה; ה־CLI אינו דורס ארכיון קיים. הדוחות מספקים אבחוני מקור וזהויות קומפיילר/SDK. הדוחות שהופקו בפועל למסירה זו נמצאים בתיקיית `proofs` החיצונית, כדי שלא יהפכו לקלט של הפרויקט.

## גבול האימות

בדיקת TypeScript ובניית ארכיון אינן אימות של צילום, אינדוקס Spotlight, התקנת מקלדת, הצגת התראה, המשך מתוך התראה או הרשאות iOS. בדיקות מכשיר/מערכת עבור שתי הדוגמאות: **NOT_RUN**. יש להשתמש בגרסת היישום המארח הכוללת את ארבע ההרחבות/הנתיבים החדשים.
