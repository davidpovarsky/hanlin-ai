import { SEFARIA_BASE_URL, SEARCH_ENDPOINT, TEXTS_ENDPOINT } from "./constants.js"
import { buildSearchPayload, versionsForMode } from "./searchPayload.js"
import { flattenText, getBestSnippet, inferDirectionFromLanguage, makeStableId } from "../../logic/textUtils.js"

async function requestJson(url, options = {}) {
  const response = await fetch(url, options)
  const text = await response.text()

  let json = null
  try {
    json = text ? JSON.parse(text) : null
  } catch (error) {
    throw new Error(`Sefaria returned non-JSON response (${response.status}).`)
  }

  if (!response.ok) {
    const detail = json?.error || json?.detail || json?.message || response.statusText
    throw new Error(`Sefaria API error ${response.status}: ${detail}`)
  }

  return json
}

export async function search(options = {}) {
  const payload = buildSearchPayload(options)
  const json = await requestJson(`${SEFARIA_BASE_URL}${SEARCH_ENDPOINT}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Accept": "application/json"
    },
    body: JSON.stringify(payload)
  })

  return normalizeSearchResponse(json)
}

export async function getText(tref, textOptions = {}) {
  if (!tref) {
    throw new Error("Cannot fetch full text without a source ref.")
  }

  const params = new URLSearchParams()
  for (const version of versionsForMode(textOptions)) {
    params.append("version", version)
  }

  if (textOptions.return_format) {
    params.set("return_format", textOptions.return_format)
  }

  params.set(
    "fill_in_missing_segments",
    textOptions.fill_in_missing_segments === "1" || textOptions.fillInMissingSegments ? "1" : "0"
  )

  const encodedRef = encodeURIComponent(String(tref))
  const url = `${SEFARIA_BASE_URL}${TEXTS_ENDPOINT}/${encodedRef}?${params.toString()}`
  const json = await requestJson(url)

  return normalizeTextResponse(json)
}

export function normalizeSearchResponse(json) {
  const hits = json?.hits?.hits ?? []

  return {
    took: json?.took ?? null,
    timedOut: Boolean(json?.timed_out),
    total: json?.hits?.total ?? hits.length,
    maxScore: json?.hits?.max_score ?? null,
    aggregations: json?.aggregations ?? {},
    raw: json,
    results: hits.map((hit, index) => normalizeHit(hit, index))
  }
}

export function normalizeHit(hit, index = 0) {
  const source = hit?._source ?? {}
  const categories = Array.isArray(source.categories) ? source.categories : []
  const ref = source.ref || source.title || source.sheetId || ""

  return {
    id: makeStableId(hit, index),
    index,
    ref,
    heRef: source.heRef || "",
    version: source.version || source.hebrew_version_title || "",
    lang: source.lang || "",
    versionPriority: source.version_priority ?? null,
    categories,
    path: source.path || categories.join(" / "),
    score: hit?._score ?? null,
    order: source.order || "",
    compDate: source.comp_date ?? null,
    pagesheetrank: source.pagesheetrank ?? null,
    snippet: getBestSnippet(hit),
    source,
    raw: hit
  }
}

export function normalizeTextResponse(json) {
  const versions = Array.isArray(json?.versions) ? json.versions : []
  const availableVersions = Array.isArray(json?.available_versions) ? json.available_versions : []

  return {
    ref: json?.ref || "",
    heRef: json?.heRef || "",
    sectionRef: json?.sectionRef || "",
    heSectionRef: json?.heSectionRef || "",
    next: json?.next || "",
    prev: json?.prev || "",
    title: json?.title || json?.book || "",
    book: json?.book || "",
    categories: Array.isArray(json?.categories) ? json.categories : [],
    warnings: Array.isArray(json?.warnings) ? json.warnings : [],
    availableVersions,
    versions: versions.map((version, index) => {
      const text = flattenText(version.text)
      return {
        id: `${version.language || version.actualLanguage || "version"}-${index}`,
        versionTitle: version.versionTitle || version.shortVersionTitle || "גרסה ללא שם",
        versionTitleInHebrew: version.versionTitleInHebrew || "",
        language: version.actualLanguage || version.language || "",
        direction: version.direction || inferDirectionFromLanguage(version.actualLanguage || version.language, text),
        license: version.license || "",
        isSource: Boolean(version.isSource),
        isPrimary: Boolean(version.isPrimary),
        text,
        raw: version
      }
    }),
    raw: json
  }
}
