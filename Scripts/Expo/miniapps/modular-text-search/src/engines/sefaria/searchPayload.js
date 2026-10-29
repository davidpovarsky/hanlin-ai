import { DEFAULT_SEARCH_OPTIONS } from "./constants.js"
import { splitLooseList } from "../../logic/textUtils.js"

function numberOrDefault(value, fallback) {
  const n = Number(value)
  return Number.isFinite(n) ? n : fallback
}

export function normalizeSearchOptions(options = {}) {
  const merged = {
    ...DEFAULT_SEARCH_OPTIONS,
    ...options
  }

  const filters = Array.isArray(merged.filters)
    ? merged.filters.filter(Boolean)
    : splitLooseList(merged.filters)

  const filterFields = Array.isArray(merged.filter_fields)
    ? merged.filter_fields.filter(Boolean)
    : splitLooseList(merged.filter_fields)

  const sortFields = Array.isArray(merged.sort_fields)
    ? merged.sort_fields.filter(Boolean)
    : splitLooseList(merged.sort_fields)

  const aggs = Array.isArray(merged.aggs)
    ? merged.aggs.filter(Boolean)
    : splitLooseList(merged.aggs)

  return {
    query: String(merged.query ?? "").trim(),
    type: merged.type === "sheet" ? "sheet" : "text",
    field: String(merged.field || "naive_lemmatizer"),
    start: Math.max(0, Math.floor(numberOrDefault(merged.start, DEFAULT_SEARCH_OPTIONS.start ?? 0))),
    size: Math.max(1, Math.min(100, numberOrDefault(merged.size, DEFAULT_SEARCH_OPTIONS.size))),
    slop: Math.max(0, numberOrDefault(merged.slop, DEFAULT_SEARCH_OPTIONS.slop)),
    sort_method: merged.sort_method === "sort" ? "sort" : "score",
    sort_fields: sortFields.length ? sortFields : ["pagesheetrank"],
    sort_reverse: Boolean(merged.sort_reverse),
    sort_score_missing: numberOrDefault(
      merged.sort_score_missing,
      DEFAULT_SEARCH_OPTIONS.sort_score_missing
    ),
    source_proj: merged.source_proj === false ? false : true,
    filters,
    filter_fields: filterFields,
    aggs
  }
}

export function buildSearchPayload(options = {}) {
  const normalized = normalizeSearchOptions(options)

  const payload = {
    query: normalized.query,
    type: normalized.type,
    field: normalized.field,
    start: normalized.start,
    size: normalized.size,
    slop: normalized.slop,
    sort_method: normalized.sort_method,
    sort_fields: normalized.sort_fields,
    sort_reverse: normalized.sort_reverse,
    sort_score_missing: normalized.sort_score_missing,
    source_proj: normalized.source_proj,
    filters: normalized.filters,
    filter_fields: normalized.filter_fields,
    aggs: normalized.aggs
  }

  if (normalized.type === "text") {
    payload.filter_fields = []
  }

  return payload
}

export function hasSearchQuery(options = {}) {
  return /\S+/.test(String(options.query ?? ""))
}

export function versionsForMode(textOptions = {}) {
  const mode = textOptions.versionMode || "source_translation"
  const custom = splitLooseList(textOptions.customVersions)

  if (mode === "custom") return custom.length ? custom : ["primary"]
  if (mode === "source_translation") return ["source", "translation"]
  if (mode === "source") return ["source"]
  if (mode === "translation") return ["translation"]
  if (mode === "all") return ["all"]
  if (mode === "hebrew") return ["hebrew"]
  if (mode === "english") return ["english"]

  return ["primary"]
}
