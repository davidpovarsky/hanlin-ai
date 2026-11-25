import { formatNumber, normalizeLocale, tFactory } from "../logic/localization.js"
import { getSearchEngine } from "../engines/registry.js"
import { readActiveSearchEngineId } from "../engines/preferences.js"
import {
  clampSnippetSize,
  makeSnippetSearchOptions,
  SNIPPET_MAX_RESULTS,
  SNIPPET_PAGE_SIZE,
  SNIPPET_RESULT_LIMIT
} from "./snippetDefaults.js"

function resultGroupKey(result) {
  const ref = String(result?.ref || "").trim()
  if (ref) return `ref:${ref.toLowerCase()}`

  const heRef = String(result?.heRef || "").trim()
  if (heRef) return `heref:${heRef}`

  return `fallback:${String(result?.path || "")}:${String(result?.snippet || "").slice(0, 60)}`
}

function primaryRank(result) {
  const source = result?.source || {}
  const versionPriority = Number(source.version_priority ?? 999)
  const score = Number(result?.score ?? 0)
  const pageRank = Number(result?.pagesheetrank ?? source.pagesheetrank ?? 0)

  return {
    versionPriority: Number.isFinite(versionPriority) ? versionPriority : 999,
    score: Number.isFinite(score) ? score : 0,
    pageRank: Number.isFinite(pageRank) ? pageRank : 0
  }
}

function choosePrimary(results) {
  return [...results].sort((a, b) => {
    const ar = primaryRank(a)
    const br = primaryRank(b)

    if (ar.versionPriority !== br.versionPriority) {
      return ar.versionPriority - br.versionPriority
    }

    if (ar.score !== br.score) return br.score - ar.score
    return br.pageRank - ar.pageRank
  })[0]
}

function totalValue(total, fallback = 0) {
  if (typeof total === "number") return total
  if (typeof total?.value === "number") return total.value
  return fallback
}

export function groupSnippetResults(results = []) {
  const groupsByKey = new Map()

  for (const result of results) {
    const key = resultGroupKey(result)
    if (!groupsByKey.has(key)) groupsByKey.set(key, [])
    groupsByKey.get(key).push(result)
  }

  return Array.from(groupsByKey.entries()).map(([key, groupResults]) => {
    const primary = choosePrimary(groupResults)
    const versions = groupResults.filter(result => result !== primary)

    return {
      id: key,
      primary,
      versions,
      versionCount: versions.length
    }
  })
}

export function nextSnippetSize(currentSize = SNIPPET_RESULT_LIMIT) {
  return clampSnippetSize(Number(currentSize || SNIPPET_RESULT_LIMIT) + SNIPPET_PAGE_SIZE)
}

export async function buildSnippetSearchModel({ query, locale = "he", size = SNIPPET_RESULT_LIMIT, engineId = readActiveSearchEngineId() } = {}) {
  const engine = getSearchEngine(engineId)
  const normalizedLocale = normalizeLocale(locale)
  const t = tFactory(normalizedLocale)
  const normalizedQuery = String(query || "").trim()
  const requestedSize = clampSnippetSize(size)

  if (!/\S+/.test(normalizedQuery)) {
    return {
      query: normalizedQuery,
      locale: normalizedLocale,
      engineId: engine.id,
      engineLabel: engine.label,
      total: 0,
      groups: [],
      error: t("noQueryError"),
      took: null,
      resultSize: requestedSize,
      hasMore: false
    }
  }

  try {
    const response = await engine.search(
      makeSnippetSearchOptions(normalizedQuery, { size: requestedSize, engineId: engine.id })
    )

    const rawResults = Array.isArray(response.results) ? response.results : []
    const groups = groupSnippetResults(rawResults)
    const total = totalValue(response.total, rawResults.length)
    const hasMore = requestedSize < SNIPPET_MAX_RESULTS && rawResults.length < total

    return {
      query: normalizedQuery,
      locale: normalizedLocale,
      engineId: engine.id,
      engineLabel: engine.label,
      total,
      totalText: t("totalResults", {
        total: formatNumber(total, normalizedLocale)
      }),
      shownText: t("shownResults", {
        count: formatNumber(groups.length, normalizedLocale)
      }),
      groups,
      error: groups.length ? "" : t("noResultsError"),
      took: response.took ?? null,
      resultSize: requestedSize,
      hasMore,
      raw: response
    }
  } catch (error) {
    return {
      query: normalizedQuery,
      locale: normalizedLocale,
      engineId: engine.id,
      engineLabel: engine.label,
      total: 0,
      totalText: t("totalResults", { total: formatNumber(0, normalizedLocale) }),
      shownText: t("shownResults", { count: formatNumber(0, normalizedLocale) }),
      groups: [],
      error: error?.message ?? String(error),
      took: null,
      resultSize: requestedSize,
      hasMore: false
    }
  }
}
