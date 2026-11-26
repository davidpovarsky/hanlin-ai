import { DEFAULT_SEARCH_ENGINE_ID, getSearchEngine } from "./registry.js"

const ACTIVE_ENGINE_KEY = "text-search:active-engine:v1"
const STORAGE_OPTIONS = { shared: false }

function storageApi() {
  return globalThis?.Storage ?? null
}

export function readActiveSearchEngineId() {
  try {
    const stored = storageApi()?.get?.(ACTIVE_ENGINE_KEY, STORAGE_OPTIONS)
    return getSearchEngine(stored || DEFAULT_SEARCH_ENGINE_ID).id
  } catch {
    return DEFAULT_SEARCH_ENGINE_ID
  }
}

export function saveActiveSearchEngineId(engineId) {
  const normalizedId = getSearchEngine(engineId).id
  try {
    storageApi()?.set?.(ACTIVE_ENGINE_KEY, normalizedId, STORAGE_OPTIONS)
  } catch {
    // Non-fatal: the app can still use the selected engine during this session.
  }
  return normalizedId
}
