export function resultGroupKey(result) {
  if (!result) return ""
  return String(
    result.ref ||
    result.source?.ref ||
    result.source?.sheetId ||
    result.id ||
    ""
  )
}

export function versionLabel(result) {
  const parts = [
    result?.version,
    result?.lang
  ].filter(Boolean)

  return parts.join(" · ")
}

export function groupSearchResults(results = []) {
  const groups = []
  const byKey = new Map()

  for (const result of results) {
    const key = resultGroupKey(result)
    if (!key) continue

    let group = byKey.get(key)
    if (!group) {
      group = {
        id: `group-${groups.length}-${key}`,
        key,
        primary: result,
        variants: [],
        variantIds: [result.id]
      }
      byKey.set(key, group)
      groups.push(group)
      continue
    }

    if (group.variantIds.includes(result.id)) continue

    group.variants.push(result)
    group.variantIds.push(result.id)
  }

  return groups.map(group => ({
    id: group.id,
    key: group.key,
    primary: group.primary,
    variants: group.variants
  }))
}

export function appendUniqueResults(current = [], incoming = []) {
  const seen = new Set(current.map(item => String(item.id)))
  const next = [...current]
  const added = []

  for (const item of incoming) {
    const id = String(item?.id ?? "")
    if (!id || seen.has(id)) continue
    seen.add(id)
    next.push(item)
    added.push(item)
  }

  return {
    results: next,
    added
  }
}
