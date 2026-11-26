import { cloneDefaultSearchOptions, cloneDefaultTextOptions, getSearchEngine } from "../engines/registry.js"

export const SNIPPET_RESULT_LIMIT = 6
export const SNIPPET_PAGE_SIZE = 6
export const SNIPPET_MAX_RESULTS = 72

export function clampSnippetSize(value) {
  const numericValue = Number(value || SNIPPET_RESULT_LIMIT)
  if (!Number.isFinite(numericValue) || numericValue < 1) return SNIPPET_RESULT_LIMIT
  return Math.min(Math.max(Math.floor(numericValue), 1), SNIPPET_MAX_RESULTS)
}

export function makeSnippetSearchOptions(query, overrides = {}) {
  const engine = getSearchEngine(overrides.engineId)
  const defaults = cloneDefaultSearchOptions(engine)
  const size = clampSnippetSize(overrides.size)

  return {
    ...defaults,
    query,
    type: defaults.type || "text",
    field: defaults.field || "naive_lemmatizer",
    size,
    slop: defaults.slop ?? 10,
    sort_method: defaults.sort_method || "score",
    sort_fields: Array.isArray(defaults.sort_fields) && defaults.sort_fields.length
      ? [...defaults.sort_fields]
      : ["pagesheetrank"],
    filters: [],
    filter_fields: [],
    aggs: Array.isArray(defaults.aggs) && defaults.aggs.length ? [...defaults.aggs] : ["path"],
    ...overrides,
    size
  }
}

export function makeSnippetTextOptions(overrides = {}) {
  const engine = getSearchEngine(overrides.engineId)
  const defaults = cloneDefaultTextOptions(engine)

  return {
    ...defaults,
    versionMode: defaults.versionMode || "source_translation",
    return_format: defaults.return_format || "text_only",
    fill_in_missing_segments: defaults.fill_in_missing_segments || "1",
    ...overrides
  }
}
