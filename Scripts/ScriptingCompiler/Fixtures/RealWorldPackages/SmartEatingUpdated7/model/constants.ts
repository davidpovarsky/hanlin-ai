// model/constants.ts — Stations list and points constants
import { Station } from "./types"

export const POINTS_ON_TIME = 10
export const POINTS_LATE_SMALL = 5
export const POINTS_LATE_BIG = 2

export const STATIONS: Station[] = [
  {
    id: 1,
    name: "ארוחת בוקר",
    iconKey: "breakfast",
    timeStart: "07:00",
    timeEnd: "09:00",
    suggestions: [
      "ביצים + לחם מלא",
      "שקשוקה + סלט",
      "גבינה לבנה + ירקות + לחם",
      "שיבולת שועל + פירות",
      "לאבנה + זיתים + ירקות",
    ],
  },
  {
    id: 2,
    name: "נשנוש בוקר",
    iconKey: "morningSnack",
    timeStart: "10:00",
    timeEnd: "11:00",
    suggestions: [
      "תפוח / בננה",
      "קומץ אגוזים",
      "גזר + חומוס",
      "יוגורט קטן",
      "פירות יבשים",
    ],
  },
  {
    id: 3,
    name: "ארוחת צהריים",
    iconKey: "lunch",
    timeStart: "13:00",
    timeEnd: "14:00",
    suggestions: [
      "עוף / דג + אורז + סלט",
      "פסטה + ירקות + חלבון",
      "מרק + לחם + סלט",
      "שניצל אפוי + תוספות",
      "בורגול + ירקות צלויים + טחינה",
    ],
  },
  {
    id: 4,
    name: "נשנוש אחה\"צ",
    iconKey: "afternoonSnack",
    timeStart: "16:00",
    timeEnd: "17:00",
    suggestions: [
      "יוגורט + גרנולה",
      "ירקות חתוכים",
      "חטיף בריאות",
      "גבינת קוטג׳ + עגבנייה",
      "שייק פירות",
    ],
  },
  {
    id: 5,
    name: "ארוחת ערב",
    iconKey: "dinner",
    timeStart: "19:00",
    timeEnd: "20:00",
    suggestions: [
      "סלט + ביצה + לחם",
      "מרק ירקות + גבינה",
      "טונה + ירקות",
      "אומלט ירקות",
      "חביתה + סלט ירוק",
    ],
  },
]