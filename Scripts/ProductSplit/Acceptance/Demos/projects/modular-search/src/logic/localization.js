const dictionaries = {
  he: {
    appTitle: "חיפוש טקסטים",
    close: "סגור",
    search: "חפש",
    searchNow: "חפש עכשיו",
    searching: "מחפש…",
    searchingSource: "מחפש ב{source}…",
    searchPrompt: "חפש מילה, ביטוי או מקור",
    searchFieldLabel: "שאילתת חיפוש",
    options: "אפשרויות",
    optionsTitle: "אפשרויות חיפוש",
    optionsSubtitle: "כל ההגדרות בחלון קטן כדי שהמסך יישאר נקי.",
    filtersButton: "סינון",
    filtersButtonWithCount: "סינון ({count})",
    activeFilters: "מסננים פעילים",
    reset: "אפס",
    done: "סיום",
    apply: "החל",
    language: "שפה",
    hebrew: "עברית",
    english: "English",
    tabEngine: "מנוע",
    tabSearch: "חיפוש",
    tabSort: "מיון",
    tabFilters: "פילטרים",
    tabText: "טקסט",
    tabDebug: "Debug",
    searchType: "סוג חיפוש",
    searchField: "שדה חיפוש",
    resultCount: "מספר תוצאות",
    slop: "Slop",
    sortMethod: "שיטת מיון",
    sortField: "שדה מיון",
    reverseSort: "מיון הפוך",
    scoreMissing: "sort_score_missing",
    sourceProjection: "source_proj",
    filters: "filters",
    filtersPrompt: "לדוגמה: Tanakh, Talmud/Bavli",
    filterFields: "filter_fields",
    filterFieldsPrompt: "topics_en, topics_he, collections",
    aggregations: "aggs",
    fullTextVersion: "גרסת טקסט מלא",
    customVersion: "version מותאם",
    customVersionPrompt: "hebrew|Miqra according to the Masorah",
    returnFormat: "return_format",
    fillMissing: "השלמת מקטעים חסרים",
    showPayload: "הצג Payload",
    hidePayload: "הסתר Payload",
    payload: "Payload",
    message: "הודעה",
    noQueryError: "צריך להקליד שאילתת חיפוש.",
    noResultsError: "לא נמצאו תוצאות. נסה לשנות field, slop או filters.",
    resultsTitle: "תוצאות",
    resultSummary: "סיכום תוצאות",
    shownResults: "{count} מוצגות",
    fromTotal: "מתוך {total}",
    searchResultsFor: "תוצאות עבור ״{query}״",
    totalResults: "{total} תוצאות",
    moreResults: "הצג עוד תוצאות",
    loadingMore: "טוען עוד תוצאות…",
    loadingMoreHint: "המשך לגלול כדי לטעון עוד",
    endOfResults: "הגעת לסוף התוצאות",
    moreVersions: "{count} גרסאות נוספות",
    hideVersions: "הסתר גרסאות",
    mainVersion: "גרסה ראשית",
    variantVersion: "גרסה נוספת",
    emptyTitle: "עדיין אין תוצאות",
    emptyMessage: "הקלד שאילתה ולחץ חפש. את כל האפשרויות המתקדמות תמצא בכפתור הסינון הקטן למעלה.",
    fullText: "טקסט מלא",
    refreshFullText: "רענן טקסט",
    openInSource: "פתח ב{source}",
    noRef: "אין ref לטקסט מלא",
    noSnippet: "אין תקציר לתוצאה הזו.",
    unnamedResult: "תוצאה ללא מקור",
    loadingFullText: "טוען טקסט מלא…",
    fullTextError: "שגיאה בטעינת הטקסט",
    noVersions: "לא חזרו גרסאות טקסט עבור המקור הזה.",
    untitledVersion: "גרסה ללא שם",
    source: "מקור",
    primary: "Primary",
    noVersionText: "אין טקסט זמין לגרסה הזו.",
    path: "מקורות",
    versionMore: "גרסה נוספת",
    versionsMore: "גרסאות נוספות",
    helpFilters: "filters מופרדים בפסיקים או שורות. בחיפוש טקסט הם מיושמים על path; בחיפוש sheets אפשר לציין filter_fields.",
    sourceTranslation: "מקור + תרגום",
    sourceOnly: "מקור",
    translationOnly: "תרגום",
    hebrewOnly: "עברית",
    englishOnly: "אנגלית",
    allVersions: "הכל",
    custom: "מותאם",
    noActiveFilters: "אין מסננים פעילים",
    quickExamples: "דוגמאות מהירות",
    enginePicker: "מנוע ומסד נתונים",
    capabilitySearch: "חיפוש",
    capabilityFullText: "טקסט מלא",
    capabilitySnippet: "Snippet"
  },
  en: {
    appTitle: "Text Search",
    close: "Close",
    search: "Search",
    searchNow: "Search now",
    searching: "Searching…",
    searchingSource: "Searching {source}…",
    searchPrompt: "Search a word, phrase, or source",
    searchFieldLabel: "Search query",
    options: "Options",
    optionsTitle: "Search options",
    optionsSubtitle: "All settings live in a compact popup so the main screen stays clean.",
    filtersButton: "Filter",
    filtersButtonWithCount: "Filter ({count})",
    activeFilters: "Active filters",
    reset: "Reset",
    done: "Done",
    apply: "Apply",
    language: "Language",
    hebrew: "עברית",
    english: "English",
    tabEngine: "Engine",
    tabSearch: "Search",
    tabSort: "Sort",
    tabFilters: "Filters",
    tabText: "Text",
    tabDebug: "Debug",
    searchType: "Search type",
    searchField: "Search field",
    resultCount: "Result count",
    slop: "Slop",
    sortMethod: "Sort method",
    sortField: "Sort field",
    reverseSort: "Reverse sort",
    scoreMissing: "sort_score_missing",
    sourceProjection: "source_proj",
    filters: "filters",
    filtersPrompt: "Example: Tanakh, Talmud/Bavli",
    filterFields: "filter_fields",
    filterFieldsPrompt: "topics_en, topics_he, collections",
    aggregations: "aggs",
    fullTextVersion: "Full text version",
    customVersion: "Custom version",
    customVersionPrompt: "hebrew|Miqra according to the Masorah",
    returnFormat: "return_format",
    fillMissing: "Fill missing segments",
    showPayload: "Show Payload",
    hidePayload: "Hide Payload",
    payload: "Payload",
    message: "Message",
    noQueryError: "Enter a search query first.",
    noResultsError: "No results found. Try changing the field, slop, or filters.",
    resultsTitle: "Results",
    resultSummary: "Results summary",
    shownResults: "{count} shown",
    fromTotal: "of {total}",
    searchResultsFor: "Results for “{query}”",
    totalResults: "{total} results",
    moreResults: "Show more results",
    loadingMore: "Loading more results…",
    loadingMoreHint: "Keep scrolling to load more",
    endOfResults: "End of results",
    moreVersions: "{count} more versions",
    hideVersions: "Hide versions",
    mainVersion: "Primary version",
    variantVersion: "Additional version",
    emptyTitle: "No results yet",
    emptyMessage: "Type a query and tap Search. Advanced settings are inside the small filter button above.",
    fullText: "Full text",
    refreshFullText: "Refresh text",
    openInSource: "Open in {source}",
    noRef: "No ref for full text",
    noSnippet: "No snippet is available for this result.",
    unnamedResult: "Result without a source",
    loadingFullText: "Loading full text…",
    fullTextError: "Full text loading error",
    noVersions: "No text versions were returned for this source.",
    untitledVersion: "Untitled version",
    source: "Source",
    primary: "Primary",
    noVersionText: "No text is available for this version.",
    path: "Sources",
    versionMore: "more version",
    versionsMore: "more versions",
    helpFilters: "Separate filters with commas or lines. Text search filters are applied to path; sheet search may use filter_fields.",
    sourceTranslation: "Source + translation",
    sourceOnly: "Source",
    translationOnly: "Translation",
    hebrewOnly: "Hebrew",
    englishOnly: "English",
    allVersions: "All",
    custom: "Custom",
    noActiveFilters: "No active filters",
    quickExamples: "Quick examples",
    enginePicker: "Engine and database",
    capabilitySearch: "Search",
    capabilityFullText: "Full text",
    capabilitySnippet: "Snippet"
  }
}

const quickQueries = {
  he: ["שמירת שבת", "בראשית", "אהבה", "הלכה", "צדקה"],
  en: ["Shabbat", "Genesis", "love", "justice", "charity"]
}

export const SUPPORTED_LOCALES = ["he", "en"]

export function normalizeLocale(value) {
  const raw = String(value || "").toLowerCase()
  if (raw.startsWith("he") || raw.includes("iw")) return "he"
  if (raw.startsWith("en")) return "en"
  return "he"
}

export function getInitialLocale(value) {
  return normalizeLocale(value)
}

export function isRtlLocale(locale) {
  return normalizeLocale(locale) === "he"
}

export function tFactory(locale) {
  const normalized = normalizeLocale(locale)
  const dictionary = dictionaries[normalized] || dictionaries.he

  return function t(key, params = {}) {
    const template = dictionary[key] ?? dictionaries.he[key] ?? key
    return Object.keys(params).reduce((text, param) => {
      return text.replaceAll(`{${param}}`, String(params[param]))
    }, template)
  }
}

export function formatNumber(value, locale = "he") {
  const normalized = normalizeLocale(locale)
  try {
    return new Intl.NumberFormat(normalized === "he" ? "he-IL" : "en-US").format(Number(value || 0))
  } catch {
    return String(value ?? 0)
  }
}

export function getQuickQueries(locale) {
  return quickQueries[normalizeLocale(locale)] || quickQueries.he
}

export function versionModeOptions(t) {
  return [
    { value: "source_translation", label: t("sourceTranslation") },
    { value: "primary", label: t("primary") },
    { value: "source", label: t("sourceOnly") },
    { value: "translation", label: t("translationOnly") },
    { value: "hebrew", label: t("hebrewOnly") },
    { value: "english", label: t("englishOnly") },
    { value: "all", label: t("allVersions") },
    { value: "custom", label: t("custom") }
  ]
}
