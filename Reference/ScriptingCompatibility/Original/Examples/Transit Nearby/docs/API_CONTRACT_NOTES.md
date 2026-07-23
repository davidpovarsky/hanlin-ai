# הערות חוזה API

המסמך מבוסס על הלכידות שסופקו ב־22 ביולי 2026. הקוד אינו מניח שדות שלא הופיעו בלכידות, ואינו כולל אסימונים, Cookies או כותרות פרטיות.

## KavNav

בסיס: `https://kavnav.com`. כל הקריאות שנלכדו היו `GET` והחזירו `200` ללא כותרת אימות ייעודית.

| נתיב | פרמטרים שמומשו | מבנה/הערה |
| --- | --- | --- |
| `/api/realtime` | `stopCode` או `routeCode` (או ללא סינון) | אובייקט עם `lastSnapshot`, `lastVehicleReport`, `vehicles` ו־`appliedFilters`. לכל רכב `lastReported`, `geo`, `trip`, `nextCall` ו־`onwardCalls`. עצם ההגעה מהנתיב אינה מבטיחה שהמידע טרי. |
| `/api/stopSummary` | `stopCode` | מערך; הפריט הראשון כולל `stopId`, `routes`, `shapeIdsByRoute`, `headways`, `neighbors`, `restrictions`. |
| `/api/stopSchedule` | `stopCode`, `date=YYYY-MM-DD` | אובייקט עם `stopSchedule[]`, ובכל תחנה `trips[]`; שעות שירות עשויות לעבור את 24:00. |
| `/api/route` | `routeId`, `date=YYYY-MM-DD` | `routes[]`, `routeChanges`, `headways`, `pois`, `neighbors`, `minDate`, `maxDate`. אין בו גאומטריית קו מוכנה לציור. |
| `/api/routeSchedule` | `routeId`, `date=YYYY-MM-DD` | `trips[]`, `stopTimes` לפי `tripId`, ו־`serviceExceptions[]`. |
| `/api/alerts` | `stopId` או `routeId` | `alerts[]` ו־`lastUpdatedAt`; הטקסט רב־לשוני תחת `header`/`description`. |
| `/api/stopPOIs` | `stopCode` | מערך. הלכידה שנבדקה הייתה ריקה, לכן אינו מוצג כרגע ב־UI הראשי. |

`stopValidations` נלכד אך לא מומש בחוויית המשתמש, משום שהמידע נראה היסטורי ולא הוכח כמידע תפעולי עדכני.

## BusNearby

בסיס API: `https://api.busnearby.co.il`; חיפוש תחנות: `https://app.busnearby.co.il`.

קריאות שנצפו ללא Authorization:

- `GET /stopSearch?query={query}&locale=he` — מערך עם `latitude`, `longitude`, `stop_name`, `stop_id`, `stop_code`, `address`, `location_type`, `vehicle_type`.
- `GET /geocode?query={query}&locale=he` — מערך עם `description`, `lat`, `lng`.
- `GET /directions/index/patterns/byshortname/{line}?locale=he` — מערך דפוסי קו.
- `GET /directions/index/patterns/{patternId}?locale=he` — דפוס, תחנות, `pickups` ו־`dropoffs`.
- `GET /directions/patch/routeAlerts/{routeId}?locale=he` נצפה ללא אימות, אך התשובה שנלכדה לא סיפקה סכימה שימושית; KavNav הוא מקור ההתראות העיקרי.

קריאות שנצפו עם Bearer ולכן הקוד שולח אותן רק כשקיים אסימון ב־Keychain:

- `/directions/index/stops?lat&lon&radius&max&locale=he`
- `/directions/index/stops/{stopId}`
- `/directions/index/stops/{stopId}/routes`
- `/directions/index/stops/{stopId}/stoptimes`
- `/directions/index/patterns/{patternId}/geometry`
- `/directions/patch/stopAlerts/{stopId}`
- `/directions/plan`

ב־`stoptimes`, הפרמטר `startTime` נשלח בשניות Unix; זמני התשובה הם מספרים ונורמלים למילישניות לפי הגודל. גאומטריית מסלול מוחזרת ב־`points6` ומפוענחת בדיוק 6. בקשת תכנון מסע משתמשת ב־`fromPlace`/`toPlace` בפורמט `name::lat,lon`, יחד עם `arriveBy`, `date`, `time`, `wheelchair`, `maxWalkDistance`, `mode=TRANSIT,WALK` ו־`showIntermediateStops=true`.

## אימות ואי־ודאות

- בלכידה לא נמצא אסימון קבוע ב־localStorage ולא חוזה ציבורי יציב להנפקת אסימון. הקוד תומך בהזנה ידנית מאובטחת ב־Settings ושומר רק ב־Keychain.
- `401`/`403` מסירים את האסימון המקומי כדי למנוע לולאת אימות.
- גאומטריית BusNearby נצפתה עם Authorization. ללא אסימון מסך הקו מציג את סדר התחנות, לוחות KavNav ורכבים, אך ייתכן שלא יוצג קו מצויר.
- סכימות התראות BusNearby שנלכדו היו ריקות; אין ניחוש של שדות. התראות KavNav משמשות כברירת מחדל.
- לא נעשה שימוש ב־Mapbox, במפתח שנלכד או בקואורדינטות משתמש מהלכידה.
