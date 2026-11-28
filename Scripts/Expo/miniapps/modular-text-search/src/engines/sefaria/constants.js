export const SEFARIA_BASE_URL = "https://www.sefaria.org"
export const SEARCH_ENDPOINT = "/api/search-wrapper"
export const TEXTS_ENDPOINT = "/api/v3/texts"

export const SEARCH_TYPES = ["text", "sheet"]
export const SEARCH_FIELDS = ["naive_lemmatizer", "exact", "content"]
export const SORT_METHODS = ["score", "sort"]
export const SORT_FIELDS = ["pagesheetrank", "comp_date", "order", "dateCreated", "views"]
export const AGG_FIELDS = ["path", "group", "topics"]
export const RETURN_FORMATS = ["text_only", "strip_only_footnotes", "wrap_all_entities", "default"]

export const DEFAULT_SEARCH_OPTIONS = Object.freeze({
  query: "",
  type: "text",
  field: "naive_lemmatizer",
  start: 0,
  size: 20,
  slop: 10,
  sort_method: "score",
  sort_fields: ["pagesheetrank"],
  sort_reverse: false,
  sort_score_missing: 0.04,
  source_proj: true,
  filters: [],
  filter_fields: [],
  aggs: ["path"]
})

export const DEFAULT_TEXT_OPTIONS = Object.freeze({
  versionMode: "source_translation",
  customVersions: "",
  return_format: "text_only",
  fill_in_missing_segments: "1"
})

export const QUICK_QUERIES = [
  "שבת",
  "אהבה",
  "בראשית",
  "love",
  "justice"
]
