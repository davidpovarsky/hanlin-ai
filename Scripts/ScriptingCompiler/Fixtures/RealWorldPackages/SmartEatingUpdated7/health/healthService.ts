// health/healthService.ts — HealthKit data fetching service
// Health, HealthUnit, DateComponents are globals — do NOT import from "scripting"
import { DailyHealthSummary, WorkoutSummary, HealthSnapshot } from "./healthTypes"
import { loadCustomConfig } from "../model/customConfig"

declare const Health: any
declare const HealthUnit: any
declare const DateComponents: any

// ── Helpers ─────────────────────────────────────────────────

function dateString(d: Date): string {
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, "0")
  const day = String(d.getDate()).padStart(2, "0")
  return `${y}-${m}-${day}`
}

function startOfDay(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0)
}

function endOfDay(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 23, 59, 59)
}

// ── Check Availability ──────────────────────────────────────

export function isHealthAvailable(): boolean {
  try {
    return Health.isHealthDataAvailable === true
  } catch {
    return false
  }
}

// ── Fetch Daily Steps ───────────────────────────────────────

async function fetchDailySteps(date: Date): Promise<number> {
  try {
    const stats = await Health.queryStatistics("stepCount", {
      startDate: startOfDay(date),
      endDate: endOfDay(date),
      statisticsOptions: ["cumulativeSum"],
    })
    if (stats) {
      return stats.sumQuantity(HealthUnit.count()) || 0
    }
    return 0
  } catch (e) {
    console.error("Error fetching steps:", e)
    return 0
  }
}

// ── Fetch Daily Active Calories ─────────────────────────────

async function fetchDailyCalories(date: Date): Promise<number> {
  try {
    const stats = await Health.queryStatistics("activeEnergyBurned", {
      startDate: startOfDay(date),
      endDate: endOfDay(date),
      statisticsOptions: ["cumulativeSum"],
    })
    if (stats) {
      return Math.round(stats.sumQuantity(HealthUnit.kilocalorie()) || 0)
    }
    return 0
  } catch (e) {
    console.error("Error fetching calories:", e)
    return 0
  }
}

// ── Fetch Daily Heart Rate Average ──────────────────────────

async function fetchDailyHeartRate(date: Date): Promise<number | null> {
  try {
    const stats = await Health.queryStatistics("heartRate", {
      startDate: startOfDay(date),
      endDate: endOfDay(date),
      statisticsOptions: ["discreteAverage"],
    })
    if (stats) {
      const avg = stats.averageQuantity(HealthUnit.count().divided(HealthUnit.minute()))
      return avg ? Math.round(avg) : null
    }
    return null
  } catch (e) {
    console.error("Error fetching heart rate:", e)
    return null
  }
}

// ── Fetch Activity Summary (Apple Watch rings) ──────────────

async function fetchActivitySummary(date: Date): Promise<{ exerciseMin: number; standHrs: number }> {
  try {
    const dc = DateComponents.fromDate(date)
    const summaries = await Health.queryActivitySummaries({
      start: dc,
      end: dc,
    })
    if (summaries && summaries.length > 0) {
      const s = summaries[0]
      return {
        exerciseMin: Math.round(s.appleExerciseTime(HealthUnit.minute()) || 0),
        standHrs: Math.round(s.appleStandHours(HealthUnit.count()) || 0),
      }
    }
    return { exerciseMin: 0, standHrs: 0 }
  } catch (e) {
    console.error("Error fetching activity summary:", e)
    return { exerciseMin: 0, standHrs: 0 }
  }
}

// ── Fetch Workouts for a Day ────────────────────────────────

async function fetchDailyWorkouts(date: Date): Promise<WorkoutSummary[]> {
  try {
    const workouts = await Health.queryWorkouts({
      startDate: startOfDay(date),
      endDate: endOfDay(date),
      sortDescriptors: [{ key: "startDate", order: "reverse" }],
    })
    if (!workouts || workouts.length === 0) return []

    return workouts.map((w: any) => {
      let avgHR: number | null = null
      try {
        const hrStat = w.allStatistics && w.allStatistics["heartRate"]
        if (hrStat) {
          avgHR = Math.round(hrStat.averageQuantity(HealthUnit.count().divided(HealthUnit.minute())) || 0)
        }
      } catch {}

      let cal = 0
      try {
        const calStat = w.allStatistics && w.allStatistics["activeEnergyBurned"]
        if (calStat) {
          cal = Math.round(calStat.sumQuantity(HealthUnit.kilocalorie()) || 0)
        }
      } catch {}

      return {
        activityType: w.workoutActivityType || "unknown",
        durationMinutes: Math.round((w.duration || 0) / 60),
        calories: cal,
        avgHeartRate: avgHR,
        startDate: w.startDate ? new Date(w.startDate).toISOString() : dateString(date),
      }
    })
  } catch (e) {
    console.error("Error fetching workouts:", e)
    return []
  }
}

// ── Fetch Full Day Summary ──────────────────────────────────

async function fetchDaySummary(date: Date, config: ReturnType<typeof loadCustomConfig>): Promise<DailyHealthSummary> {
  const hc = config.healthConfig
  const ds = dateString(date)

  const [steps, calories, heartRate, activity, workouts] = await Promise.all([
    hc.trackSteps ? fetchDailySteps(date) : Promise.resolve(0),
    hc.trackCalories ? fetchDailyCalories(date) : Promise.resolve(0),
    hc.trackHeartRate ? fetchDailyHeartRate(date) : Promise.resolve(null as number | null),
    hc.trackActivityRings ? fetchActivitySummary(date) : Promise.resolve({ exerciseMin: 0, standHrs: 0 }),
    hc.trackWorkouts ? fetchDailyWorkouts(date) : Promise.resolve([] as WorkoutSummary[]),
  ])

  return {
    date: ds,
    steps,
    activeCalories: calories,
    exerciseMinutes: activity.exerciseMin,
    standHours: activity.standHrs,
    avgHeartRate: heartRate,
    workouts,
  }
}

// ── Main: Fetch Health Snapshot ──────────────────────────────

export async function fetchHealthSnapshot(daysBack?: number): Promise<HealthSnapshot> {
  const config = loadCustomConfig()
  const numDays = daysBack ?? config.healthConfig.daysToFetch

  const days: DailyHealthSummary[] = []
  const today = new Date()

  for (let i = numDays - 1; i >= 0; i--) {
    const d = new Date(today.getFullYear(), today.getMonth(), today.getDate() - i)
    const summary = await fetchDaySummary(d, config)
    days.push(summary)
  }

  const totalSteps = days.reduce((s, d) => s + d.steps, 0)
  const totalCalories = days.reduce((s, d) => s + d.activeCalories, 0)
  const totalExerciseMinutes = days.reduce((s, d) => s + d.exerciseMinutes, 0)
  const totalWorkouts = days.reduce((s, d) => s + d.workouts.length, 0)

  return {
    days,
    totalSteps,
    totalCalories,
    totalExerciseMinutes,
    totalWorkouts,
    avgDailySteps: numDays > 0 ? Math.round(totalSteps / numDays) : 0,
    avgDailyCalories: numDays > 0 ? Math.round(totalCalories / numDays) : 0,
    fetchDate: dateString(today),
  }
}

// ── Cached fetch (avoid re-fetching within same session) ────

let cachedSnapshot: HealthSnapshot | null = null
let cacheTimestamp = 0
const CACHE_TTL = 5 * 60 * 1000 // 5 minutes

export async function getCachedHealthSnapshot(): Promise<HealthSnapshot | null> {
  const config = loadCustomConfig()
  if (!config.healthConfig.enabled || !isHealthAvailable()) {
    return null
  }

  const now = Date.now()
  if (cachedSnapshot && (now - cacheTimestamp) < CACHE_TTL) {
    return cachedSnapshot
  }

  try {
    cachedSnapshot = await fetchHealthSnapshot()
    cacheTimestamp = now
    return cachedSnapshot
  } catch (e) {
    console.error("Error fetching health snapshot:", e)
    return null
  }
}

export function clearHealthCache(): void {
  cachedSnapshot = null
  cacheTimestamp = 0
}
