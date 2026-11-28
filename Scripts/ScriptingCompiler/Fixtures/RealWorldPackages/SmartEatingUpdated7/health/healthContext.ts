// health/healthContext.ts — Build health context for AI prompts
import { HealthSnapshot, DailyHealthSummary } from "./healthTypes"
import { getCachedHealthSnapshot } from "./healthService"
import { loadCustomConfig } from "../model/customConfig"

// Hebrew day names for context
const DAY_NAMES = ["ראשון", "שני", "שלישי", "רביעי", "חמישי", "שישי", "שבת"]

function dayName(dateStr: string): string {
  const d = new Date(dateStr + "T12:00:00")
  return DAY_NAMES[d.getDay()]
}

function formatWorkout(w: { activityType: string; durationMinutes: number; calories: number }): string {
  return `${w.activityType} (${w.durationMinutes} דק׳, ${w.calories} קק״ל)`
}

function formatDaySummary(day: DailyHealthSummary): string {
  const parts: string[] = []
  parts.push(`${dayName(day.date)} (${day.date})`)
  if (day.steps > 0) parts.push(`צעדים: ${day.steps}`)
  if (day.activeCalories > 0) parts.push(`קלוריות פעילות: ${day.activeCalories}`)
  if (day.exerciseMinutes > 0) parts.push(`דקות פעילות: ${day.exerciseMinutes}`)
  if (day.standHours > 0) parts.push(`שעות עמידה: ${day.standHours}`)
  if (day.avgHeartRate !== null) parts.push(`דופק ממוצע: ${day.avgHeartRate}`)
  if (day.workouts.length > 0) {
    parts.push(`אימונים: ${day.workouts.map(formatWorkout).join(", ")}`)
  }
  return parts.join(" | ")
}

export async function buildHealthContextString(): Promise<string> {
  const config = loadCustomConfig()
  if (!config.aiConfig.useHealthData || !config.healthConfig.enabled) {
    return ""
  }

  const snapshot = await getCachedHealthSnapshot()
  if (!snapshot || snapshot.days.length === 0) {
    return ""
  }

  const lines: string[] = [
    "",
    "── נתוני בריאות וכושר ──",
    `תקופה: ${snapshot.days.length} ימים אחרונים`,
    `ממוצע צעדים יומי: ${snapshot.avgDailySteps}`,
    `ממוצע קלוריות פעילות: ${snapshot.avgDailyCalories}`,
    `סה״כ דקות אימון: ${snapshot.totalExerciseMinutes}`,
    `סה״כ אימונים: ${snapshot.totalWorkouts}`,
    "",
    "פירוט יומי:",
  ]

  for (const day of snapshot.days) {
    lines.push(formatDaySummary(day))
  }

  lines.push("")
  lines.push("השתמש בנתוני הבריאות האלה כדי להציע ארוחות וזמני אכילה מותאמים לרמת הפעילות.")

  return lines.join("\n")
}

// Build a short health summary for quick actions
export async function buildShortHealthSummary(): Promise<string> {
  const snapshot = await getCachedHealthSnapshot()
  if (!snapshot || snapshot.days.length === 0) {
    return ""
  }

  // Just today's data
  const today = snapshot.days[snapshot.days.length - 1]
  if (!today) return ""

  const parts: string[] = ["נתוני היום:"]
  if (today.steps > 0) parts.push(`${today.steps} צעדים`)
  if (today.activeCalories > 0) parts.push(`${today.activeCalories} קק״ל נשרפו`)
  if (today.exerciseMinutes > 0) parts.push(`${today.exerciseMinutes} דק׳ פעילות`)
  if (today.workouts.length > 0) parts.push(`${today.workouts.length} אימונים`)

  return parts.join(", ")
}
