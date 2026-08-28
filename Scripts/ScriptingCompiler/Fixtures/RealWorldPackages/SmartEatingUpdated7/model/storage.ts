// model/storage.ts — All business logic and storage access
// Storage is a global — do NOT import it from "scripting"
import { Station, StationLog, DayLog, AppData } from "./types"
import { STATIONS, POINTS_ON_TIME, POINTS_LATE_SMALL, POINTS_LATE_BIG } from "./constants"

// Global Storage declaration
declare const Storage: {
  get<T>(key: string): T | null
  set<T>(key: string, value: T): void
}

const KEY_APP_DATA = "nutrition_app_data"
const KEY_TODAY_LOG = "nutrition_today_log"
const KEY_AI_PROCESSING = "ai_processing_enabled"
const KEY_AI_GENERAL_PROCESSING = "ai_general_processing"
const KEY_AI_MEAL_MENU_CREATION = "ai_meal_menu_creation"

function parseTime(t: string): number {
  try {
    const parts = t.split(":")
    if (parts.length !== 2) throw new Error(`Invalid time format: ${t}`)
    
    const [h, m] = parts.map(Number)
    if (isNaN(h) || isNaN(m) || h < 0 || h > 23 || m < 0 || m > 59) {
      throw new Error(`Invalid time values: ${t}`)
    }
    
    return h * 60 + m
  } catch (error) {
    console.error(`Error parsing time "${t}":`, error)
    return 0 // fallback to midnight
  }
}

function nowMinutes(): number {
  const n = new Date()
  return n.getHours() * 60 + n.getMinutes()
}

export function getTodayString(): string {
  const now = new Date()
  const y = now.getFullYear()
  const m = String(now.getMonth() + 1).padStart(2, "0")
  const d = String(now.getDate()).padStart(2, "0")
  return `${y}-${m}-${d}`
}

export function getHebrewDayName(dateStr: string): string {
  const days = ["ראשון", "שני", "שלישי", "רביעי", "חמישי", "שישי", "שבת"]
  const d = new Date(dateStr + "T12:00:00")
  return days[d.getDay()]
}

export function calculatePoints(station: Station): number {
  const now = nowMinutes()
  const end = parseTime(station.timeEnd)
  const lateSmall = end + 60
  if (now <= end) return POINTS_ON_TIME
  if (now <= lateSmall) return POINTS_LATE_SMALL
  return POINTS_LATE_BIG
}

// Get next station by sequential order (first uncompleted)
export function getNextStation(todayLog: DayLog): Station | null {
  const completedIds = new Set(todayLog.stations.map(s => s.stationId))
  for (const station of STATIONS) {
    if (!completedIds.has(station.id)) return station
  }
  return null
}

// Get next station by TIME — the next upcoming station based on current time
export function getNextStationByTime(todayLog: DayLog): Station | null {
  const now = nowMinutes()
  const completedIds = new Set(todayLog.stations.map(s => s.stationId))

  // First: find the next uncompleted station whose timeStart is in the future or ongoing
  for (const station of STATIONS) {
    if (completedIds.has(station.id)) continue
    const end = parseTime(station.timeEnd)
    // Station is still relevant if we haven't passed its end time + 60 min grace
    if (now <= end + 60) return station
  }

  // Fallback: any uncompleted station (all times have passed)
  for (const station of STATIONS) {
    if (!completedIds.has(station.id)) return station
  }

  return null
}

// Get stations that were skipped — their time window has passed and they are not completed
export function getSkippedStations(todayLog: DayLog): Station[] {
  const now = nowMinutes()
  const completedIds = new Set(todayLog.stations.map(s => s.stationId))
  const skipped: Station[] = []

  for (const station of STATIONS) {
    if (completedIds.has(station.id)) continue
    const end = parseTime(station.timeEnd)
    // If we've passed the end time, it's skipped
    if (now > end) {
      skipped.push(station)
    }
  }

  return skipped
}

// Get station time status: "upcoming", "active", "late", "passed"
export function getStationTimeStatus(station: Station): "upcoming" | "active" | "late" | "passed" {
  const now = nowMinutes()
  const start = parseTime(station.timeStart)
  const end = parseTime(station.timeEnd)

  if (now < start) return "upcoming"
  if (now <= end) return "active"
  if (now <= end + 60) return "late"
  return "passed"
}

export function minutesUntilStation(station: Station): number {
  const now = nowMinutes()
  const start = parseTime(station.timeStart)
  return start - now
}

export function loadAppData(): AppData {
  try {
    const data = Storage.get<AppData>(KEY_APP_DATA)
    if (data) return data
    return { streak: 0, lastStreakDate: "", history: [] }
  } catch (error) {
    console.error("Error loading app data:", error)
    return { streak: 0, lastStreakDate: "", history: [] }
  }
}

export function saveAppData(data: AppData): void {
  Storage.set(KEY_APP_DATA, data)
}

export function loadTodayLog(): DayLog {
  const today = getTodayString()
  const log = Storage.get<DayLog>(KEY_TODAY_LOG)
  if (log && log.date === today) return log
  return { date: today, stations: [], totalPoints: 0 }
}

export function saveTodayLog(log: DayLog): void {
  Storage.set(KEY_TODAY_LOG, log)
}

export function completeStation(stationId: number, note: string): {
  points: number
  todayLog: DayLog
  appData: AppData
} {
  const station = STATIONS.find(s => s.id === stationId)
  if (!station) {
    console.error(`Station with id ${stationId} not found`)
    return { points: 0, todayLog: loadTodayLog(), appData: loadAppData() }
  }
  
  const points = calculatePoints(station)
  const todayLog = loadTodayLog()

  if (todayLog.stations.find(s => s.stationId === stationId)) {
    return { points: 0, todayLog, appData: loadAppData() }
  }

  todayLog.stations.push({ stationId, completedAt: Date.now(), note, points })
  todayLog.totalPoints += points
  saveTodayLog(todayLog)

  const appData = loadAppData()
  const today = getTodayString()

  const existingIdx = appData.history.findIndex(d => d.date === today)
  if (existingIdx >= 0) {
    appData.history[existingIdx] = todayLog
  } else {
    appData.history.push(todayLog)
  }
  if (appData.history.length > 30) {
    appData.history = appData.history.slice(-30)
  }

  if (todayLog.stations.length >= 3) {
    if (appData.lastStreakDate !== today) {
      const yesterday = new Date()
      yesterday.setDate(yesterday.getDate() - 1)
      const yStr = `${yesterday.getFullYear()}-${String(yesterday.getMonth() + 1).padStart(2, "0")}-${String(yesterday.getDate()).padStart(2, "0")}`
      if (appData.lastStreakDate === yStr || appData.streak === 0) {
        appData.streak += 1
      } else {
        appData.streak = 1
      }
      appData.lastStreakDate = today
    }
  }

  saveAppData(appData)
  return { points, todayLog, appData }
}

// Update note for a station that was already completed
export function updateStationNote(stationId: number, newNote: string): {
  todayLog: DayLog
  appData: AppData
} {
  const todayLog = loadTodayLog()
  const stationLog = todayLog.stations.find(s => s.stationId === stationId)
  if (stationLog) {
    stationLog.note = newNote
    saveTodayLog(todayLog)

    // Also update in history
    const appData = loadAppData()
    const today = getTodayString()
    const existingIdx = appData.history.findIndex(d => d.date === today)
    if (existingIdx >= 0) {
      appData.history[existingIdx] = todayLog
    }
    saveAppData(appData)
    return { todayLog, appData }
  }
  return { todayLog, appData: loadAppData() }
}

export function getEncouragement(todayLog: DayLog, appData: AppData): string {
  const count = todayLog.stations.length
  const streak = appData.streak
  if (count === 5) return streak > 1 ? "יום מושלם! " + streak + " ימים ברצף!" : "כל הכבוד, השלמת את כל התחנות היום!"
  if (count >= 3) return "יופי! עוד קצת והיום מושלם!"
  if (count >= 1) return "התחלה מצוינת, המשך ככה!"
  if (streak > 2) return streak + " ימים ברצף — אל תפסיק היום!"
  return "בוקר טוב! הגיע הזמן לתחנה הראשונה"
}

export function getWeekHistory(appData: AppData): { day: string; count: number; points: number }[] {
  const result: { day: string; count: number; points: number }[] = []
  for (let i = 6; i >= 0; i--) {
    const d = new Date()
    d.setDate(d.getDate() - i)
    const dateStr = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`
    const dayLog = appData.history.find(h => h.date === dateStr)
    result.push({
      day: getHebrewDayName(dateStr),
      count: dayLog ? dayLog.stations.length : 0,
      points: dayLog ? dayLog.totalPoints : 0,
    })
  }
  return result
}

export function getNotificationTimes(): { stationId: number; hour: number; minute: number }[] {
  return STATIONS.map(s => {
    const [h, m] = s.timeStart.split(":").map(Number)
    let notifH = h
    let notifM = m - 15
    if (notifM < 0) { notifM += 60; notifH -= 1 }
    return { stationId: s.id, hour: notifH, minute: notifM }
  })
}

// AI processing toggle
export function isAIProcessingEnabled(): boolean {
  const enabled = Storage.get<boolean>(KEY_AI_PROCESSING)
  return enabled === null ? true : enabled // default to enabled
}

export function setAIProcessingEnabled(enabled: boolean): void {
  Storage.set(KEY_AI_PROCESSING, enabled)
}

// AI general processing toggle (master switch)
export function isAIGeneralProcessingEnabled(): boolean {
  const enabled = Storage.get<boolean>(KEY_AI_GENERAL_PROCESSING)
  return enabled === null ? true : enabled // default to enabled
}

export function setAIGeneralProcessingEnabled(enabled: boolean): void {
  Storage.set(KEY_AI_GENERAL_PROCESSING, enabled)
  // If general AI is enabled, automatically enable both sub-features
  if (enabled) {
    setAIProcessingEnabled(true)
    setAIMealMenuCreationEnabled(true)
  }
}

// AI meal menu creation & analysis for history toggle
export function isAIMealMenuCreationEnabled(): boolean {
  const enabled = Storage.get<boolean>(KEY_AI_MEAL_MENU_CREATION)
  return enabled === null ? true : enabled // default to enabled
}

export function setAIMealMenuCreationEnabled(enabled: boolean): void {
  // If general AI is enabled, don't allow disabling this sub-feature
  if (isAIGeneralProcessingEnabled()) {
    return
  }
  Storage.set(KEY_AI_MEAL_MENU_CREATION, enabled)
}

// Helper to check if meal menu creation should be active (considering master switch)
export function isMealMenuCreationActive(): boolean {
  return isAIGeneralProcessingEnabled() || isAIMealMenuCreationEnabled()
}

// Helper to check if AI processing should be active (considering master switch)
export function isAIProcessingActive(): boolean {
  return isAIGeneralProcessingEnabled() || isAIProcessingEnabled()
}