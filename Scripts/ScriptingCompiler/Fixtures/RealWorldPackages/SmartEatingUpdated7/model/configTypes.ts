// model/configTypes.ts — Types for user-editable configuration
// These types define the structure of customizable app data stored in Storage

export interface CustomStation {
  id: number
  name: string
  iconKey: string
  timeStart: string   // "HH:mm"
  timeEnd: string     // "HH:mm"
  suggestions: string[]
  enabled: boolean
}

export interface CustomAIConfig {
  systemPrompt: string
  encouragementPrompt: string
  menuSuggestPrompt: string
  analysisPrompt: string
  provider: "deepseek" | "openai" | "anthropic" | "gemini"
  useHealthData: boolean
}

export interface HealthIntegrationConfig {
  enabled: boolean
  trackSteps: boolean
  trackCalories: boolean
  trackWorkouts: boolean
  trackHeartRate: boolean
  trackActivityRings: boolean
  daysToFetch: number    // how many days of history to include in AI context
}

export interface AppCustomConfig {
  stations: CustomStation[]
  aiConfig: CustomAIConfig
  healthConfig: HealthIntegrationConfig
  version: number  // for future migrations
}
