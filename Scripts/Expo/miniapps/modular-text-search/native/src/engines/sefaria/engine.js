import {
  AGG_FIELDS,
  DEFAULT_SEARCH_OPTIONS,
  DEFAULT_TEXT_OPTIONS,
  RETURN_FORMATS,
  SEARCH_FIELDS,
  SEARCH_TYPES,
  SEFARIA_BASE_URL,
  SORT_FIELDS,
  SORT_METHODS
} from "./constants.js"
import { buildSearchPayload } from "./searchPayload.js"
import { getText, search } from "./client.js"

function cloneOptions(options) {
  const clone = { ...options }
  for (const key of Object.keys(clone)) {
    if (Array.isArray(clone[key])) clone[key] = [...clone[key]]
  }
  return clone
}

function buildWebUrl(ref) {
  if (!ref) return SEFARIA_BASE_URL
  return `${SEFARIA_BASE_URL}/${encodeURIComponent(String(ref).replace(/ /g, "_"))}`
}

export const sefariaSearchEngine = {
  id: "sefaria",
  label: "Sefaria",
  sourceLabel: "Sefaria",
  description: "Searches the Sefaria API and loads full source text from Sefaria texts v3.",

  capabilities: {
    search: true,
    fullText: true,
    searchOptions: true,
    textVersions: true,
    webUrl: true,
    snippets: true
  },

  defaultSearchOptions: DEFAULT_SEARCH_OPTIONS,
  defaultTextOptions: DEFAULT_TEXT_OPTIONS,

  optionMetadata: {
    searchTypes: SEARCH_TYPES,
    searchFields: SEARCH_FIELDS,
    sortMethods: SORT_METHODS,
    sortFields: SORT_FIELDS,
    aggregationFields: AGG_FIELDS,
    returnFormats: RETURN_FORMATS,
    fieldByType: {
      text: "naive_lemmatizer",
      sheet: "content"
    }
  },

  cloneDefaultSearchOptions() {
    return cloneOptions(DEFAULT_SEARCH_OPTIONS)
  },

  cloneDefaultTextOptions() {
    return cloneOptions(DEFAULT_TEXT_OPTIONS)
  },

  buildSearchPayload,
  search,
  getText,
  buildWebUrl
}
