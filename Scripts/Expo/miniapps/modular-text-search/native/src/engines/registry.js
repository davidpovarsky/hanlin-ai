import { sefariaSearchEngine } from "./sefaria/engine.js"

const engines = [sefariaSearchEngine]
const engineById = new Map(engines.map(engine => [engine.id, engine]))

export const DEFAULT_SEARCH_ENGINE_ID = sefariaSearchEngine.id

function cloneOptions(options = {}) {
  const clone = { ...options }
  for (const key of Object.keys(clone)) {
    if (Array.isArray(clone[key])) clone[key] = [...clone[key]]
  }
  return clone
}

export function listSearchEngines() {
  return [...engines]
}

export function getSearchEngine(engineId = DEFAULT_SEARCH_ENGINE_ID) {
  return engineById.get(String(engineId || "")) || sefariaSearchEngine
}

export function cloneDefaultSearchOptions(engineOrId = DEFAULT_SEARCH_ENGINE_ID) {
  const engine = typeof engineOrId === "string" ? getSearchEngine(engineOrId) : engineOrId
  if (typeof engine?.cloneDefaultSearchOptions === "function") {
    return engine.cloneDefaultSearchOptions()
  }
  return cloneOptions(engine?.defaultSearchOptions)
}

export function cloneDefaultTextOptions(engineOrId = DEFAULT_SEARCH_ENGINE_ID) {
  const engine = typeof engineOrId === "string" ? getSearchEngine(engineOrId) : engineOrId
  if (typeof engine?.cloneDefaultTextOptions === "function") {
    return engine.cloneDefaultTextOptions()
  }
  return cloneOptions(engine?.defaultTextOptions)
}
