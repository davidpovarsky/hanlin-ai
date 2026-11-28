# ארכיטקטורה

האפליקציה היא פרויקט Scripting נייטיבי. `index.tsx` מציג `TransitNearbyApp` דרך `Navigation.present`; אין WebView ואין שכבת HTML.

הזרימה היא:

`Views → transitRepository → typed clients → fetch`

- `src/domain` מכיל מודלים מנורמלים בלבד. רכיבי UI אינם קוראים שדות גולמיים של KavNav או BusNearby.
- `src/data/clients.ts` מרכז נתיבים, פרמטרים והחלטה אם נדרש Bearer.
- `src/data/http.ts` מספק timeout, ניסיון חוזר מוגבל ל־GET, שגיאות מסווגות וסינון פרטי שגיאה רגישים.
- `src/data/transitRepository.ts` מאחד לוחות זמנים, זמן אמת, דפוסי קו, גאומטריה, התראות ותכנון מסע.
- `src/storage/transitStorage.ts` מפריד בין מועדפים, חיפושים אחרונים, העדפות ומטמון מעטוף בגרסה ו־TTL. אסימון BusNearby נשמר רק ב־Keychain דרך `src/data/auth.ts`.
- מסכי הטלפון משתמשים ב־TabView ו־NavigationStack. ב־iPad נעשה שימוש ב־NavigationSplitView עם סרגל צד, תוכן ופרטי מפה.
- Widget ו־Live Activity צורכים את אותם מודלים ומטמון משותף, בלי לשכפל חוזי API.

ספי טריות זמן אמת מרוכזים במאגר: עד 90 שניות חי, 90–300 שניות מתעכב, ומעל 300 שניות מיושן. ספירות לאחור מתעדכנות מקומית; רשת אינה מתושאלת בכל שנייה.
