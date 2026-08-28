// health/healthTypes.ts — Types for health data integration

export interface DailyHealthSummary {
  date: string                  // "YYYY-MM-DD"
  steps: number
  activeCalories: number        // kcal
  exerciseMinutes: number
  standHours: number
  avgHeartRate: number | null   // bpm, null if no data
  workouts: WorkoutSummary[]
}

export interface WorkoutSummary {
  activityType: string
  durationMinutes: number
  calories: number
  avgHeartRate: number | null
  startDate: string
}

export interface HealthSnapshot {
  days: DailyHealthSummary[]
  totalSteps: number
  totalCalories: number
  totalExerciseMinutes: number
  totalWorkouts: number
  avgDailySteps: number
  avgDailyCalories: number
  fetchDate: string
}
