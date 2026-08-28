// model/symbols.ts — כל ה-SF Symbols של האפליקציה במקום אחד
// שנה כאן בלבד כדי לעדכן אייקונים בכל האפליקציה והווידג׳ט

// סימבולים לתחנות לפי ID
export const STATION_SYMBOLS: Record<number, string> = {
  1: "sunrise.fill",        // ארוחת בוקר
  2: "leaf.fill",           // נשנוש בוקר
  3: "fork.knife",          // ארוחת צהריים
  4: "cup.and.saucer.fill", // נשנוש אחה"צ
  5: "moon.stars.fill",     // ארוחת ערב
}

// סימבולים לצבעי תחנות לפי ID
export const STATION_COLORS: Record<number, string> = {
  1: "systemOrange",
  2: "systemGreen",
  3: "systemBlue",
  4: "systemTeal",
  5: "systemIndigo",
}

// סימבולים כלליים של האפליקציה
export const APP_SYMBOLS = {
  completed:    "checkmark.circle.fill",
  incomplete:   "circle",
  streak:       "flame.fill",
  points:       "star.fill",
  appTitle:     "leaf.circle.fill",
  nextStation:  "arrow.right.circle.fill",
  allDone:      "checkmark.seal.fill",
  clock:        "clock.fill",
  note:         "note.text",
  nowAlert:     "alarm.fill",
}