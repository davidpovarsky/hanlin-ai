export function splitLooseList(value) {
  if (!value) return []
  return String(value)
    .split(/[\n,|]+/)
    .map(item => item.trim())
    .filter(Boolean)
}

export function compactWhitespace(value) {
  return String(value ?? "")
    .replace(/[\t\r ]+/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim()
}

export function decodeHtmlEntities(value) {
  return String(value ?? "")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&#x27;/g, "'")
}

export function stripHtml(value) {
  return compactWhitespace(
    decodeHtmlEntities(String(value ?? ""))
      .replace(/<br\s*\/?\s*>/gi, "\n")
      .replace(/<\/?p[^>]*>/gi, "\n")
      .replace(/<[^>]+>/g, "")
  )
}

export function flattenText(value) {
  if (Array.isArray(value)) {
    return value
      .map(item => flattenText(item))
      .filter(Boolean)
      .join("\n")
  }

  if (value == null) return ""
  return stripHtml(value)
}

export function truncate(value, maxLength = 280) {
  const text = compactWhitespace(value)
  if (text.length <= maxLength) return text
  return text.slice(0, maxLength - 1).trimEnd() + "…"
}

export function inferDirectionFromLanguage(language, fallbackText = "") {
  const lang = String(language ?? "").toLowerCase()
  if (["he", "hebrew", "ar", "arabic", "fa", "persian", "yi", "yiddish"].includes(lang)) {
    return "rtl"
  }

  if (/[\u0590-\u05ff\u0600-\u06ff]/.test(String(fallbackText))) {
    return "rtl"
  }

  return "ltr"
}

export function getBestSnippet(hit) {
  const highlights = hit?.highlight ?? {}
  const firstHighlight = Object.values(highlights)
    .flat()
    .find(Boolean)

  if (firstHighlight) return stripHtml(firstHighlight)

  const source = hit?._source ?? {}
  return truncate(source.exact || source.naive_lemmatizer || source.content || "")
}

export function makeStableId(hit, index = 0) {
  return String(hit?._id || hit?._source?.ref || hit?._source?.sheetId || `result-${index}`)
}
