// model/customConfig.ts — Editable configuration stored in Storage
// Storage is a global — do NOT import from "scripting"
import {
  AppCustomConfig, CustomStation, CustomAIConfig, HealthIntegrationConfig,
} from "./configTypes"
import { STATIONS } from "./constants"

declare const Storage: {
  get<T>(key: string): T | null
  set<T>(key: string, value: T): void
}

const CONFIG_KEY = "nutrition_custom_config"
const CONFIG_VERSION = 1

// ── Default Values ──────────────────────────────────────────

function defaultStations(): CustomStation[] {
  return STATIONS.map(s => ({
    id: s.id,
    name: s.name,
    iconKey: s.iconKey,
    timeStart: s.timeStart,
    timeEnd: s.timeEnd,
    suggestions: [...s.suggestions],
    enabled: true,
  }))
}

function defaultAIConfig(): CustomAIConfig {
  return {
    systemPrompt: "אתה יועץ תזונה מנוסה. דבר בעברית. ענה בקצרה עם ניתוח קונקרטי.",
    encouragementPrompt: "אתה מעודד אישי חם. כתוב בעברית, קצר וחם עם אמוג׳י.",
    menuSuggestPrompt: "אתה דיאטן מנוסה. הצע תפריט בריא ומעשי. כתוב בעברית, קצר וקולע.",
    analysisPrompt: "נתח את דפוסי האכילה ותן 3 המלצות קונקרטיות.",
    provider: "deepseek",
    useHealthData: true,
  }
}

function defaultHealthConfig(): HealthIntegrationConfig {
  return {
    enabled: false,
    trackSteps: true,
    trackCalories: true,
    trackWorkouts: true,
    trackHeartRate: false,
    trackActivityRings: true,
    daysToFetch: 7,
  }
}

function defaultConfig(): AppCustomConfig {
  return {
    stations: defaultStations(),
    aiConfig: defaultAIConfig(),
    healthConfig: defaultHealthConfig(),
    version: CONFIG_VERSION,
  }
}

// ── Load / Save ─────────────────────────────────────────────

export function loadCustomConfig(): AppCustomConfig {
  try {
    const saved = Storage.get<AppCustomConfig>(CONFIG_KEY)
    if (saved && saved.version === CONFIG_VERSION) {
      return saved
    }
    // Migration or first run — merge with defaults
    if (saved) {
      return migrateConfig(saved)
    }
    return defaultConfig()
  } catch (e) {
    console.error("Error loading custom config:", e)
    return defaultConfig()
  }
}

export function saveCustomConfig(config: AppCustomConfig): void {
  Storage.set(CONFIG_KEY, config)
}

// ── Individual Section Updates ──────────────────────────────

export function updateStation(stationId: number, updates: Partial<CustomStation>): AppCustomConfig {
  const config = loadCustomConfig()
  const idx = config.stations.findIndex(s => s.id === stationId)
  if (idx !== -1) {
    config.stations[idx] = { ...config.stations[idx], ...updates }
  }
  saveCustomConfig(config)
  return config
}

export function updateAIConfig(updates: Partial<CustomAIConfig>): AppCustomConfig {
  const config = loadCustomConfig()
  config.aiConfig = { ...config.aiConfig, ...updates }
  saveCustomConfig(config)
  return config
}

export function updateHealthConfig(updates: Partial<HealthIntegrationConfig>): AppCustomConfig {
  const config = loadCustomConfig()
  config.healthConfig = { ...config.healthConfig, ...updates }
  saveCustomConfig(config)
  return config
}

export function addStation(): AppCustomConfig {
  const config = loadCustomConfig()
  const maxId = config.stations.reduce((max, s) => Math.max(max, s.id), 0)
  const newStation: CustomStation = {
    id: maxId + 1,
    name: "ארוחה חדשה",
    iconKey: "lunch",
    timeStart: "12:00",
    timeEnd: "13:00",
    suggestions: [],
    enabled: true,
  }
  config.stations.push(newStation)
  saveCustomConfig(config)
  return config
}

export function removeStation(stationId: number): AppCustomConfig {
  const config = loadCustomConfig()
  config.stations = config.stations.filter(s => s.id !== stationId)
  saveCustomConfig(config)
  return config
}

export function reorderStations(orderedIds: number[]): AppCustomConfig {
  const config = loadCustomConfig()
  const stationMap = new Map(config.stations.map(s => [s.id, s]))
  config.stations = orderedIds
    .map(id => stationMap.get(id))
    .filter((s): s is CustomStation => s !== undefined)
  saveCustomConfig(config)
  return config
}

export function resetConfigToDefaults(): AppCustomConfig {
  const config = defaultConfig()
  saveCustomConfig(config)
  return config
}

// Get the active (enabled) stations in order — to replace STATIONS usage
export function getActiveStations(): CustomStation[] {
  const config = loadCustomConfig()
  return config.stations.filter(s => s.enabled)
}

// ── Migration ───────────────────────────────────────────────

function migrateConfig(old: any): AppCustomConfig {
  const def = defaultConfig()
  return {
    stations: old.stations || def.stations,
    aiConfig: { ...def.aiConfig, ...(old.aiConfig || {}) },
    healthConfig: { ...def.healthConfig, ...(old.healthConfig || {}) },
    version: CONFIG_VERSION,
  }
}
