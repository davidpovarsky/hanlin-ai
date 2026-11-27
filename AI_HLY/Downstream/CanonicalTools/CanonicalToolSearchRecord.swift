import Foundation

public struct CanonicalToolSearchRecord: Hashable, Sendable {
  public let alias: String
  public let title: String
  public let summary: String
  public let source: String
  public let keywords: [String]
  public let schemaSizeBytes: Int
  public let category: String?
  public let owner: String?

  public init(
    alias: String,
    title: String,
    summary: String,
    source: String,
    keywords: [String] = [],
    schemaSizeBytes: Int = 0,
    category: String? = nil,
    owner: String? = nil
  ) {
    self.alias = alias
    self.title = title
    self.summary = summary
    self.source = source
    self.keywords = keywords
    self.schemaSizeBytes = schemaSizeBytes
    self.category = category
    self.owner = owner
  }
}


extension CanonicalToolSearchRecord {
    /// Original deterministic discovery ranking over the admitted catalog.
    public static func search(_ all: [CanonicalToolSearchRecord], query: String,
                              limit: Int = 10, offset: Int = 0,
                              preferredAliases: Set<String> = []) -> [CanonicalToolSearchRecord] {
      let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      let terms = trimmed.split(separator: " ").map(String.init)
      guard !terms.isEmpty else {
        let sorted = all.sorted {
          let p0 = preferredAliases.contains($0.alias) ? 1 : 0
          let p1 = preferredAliases.contains($1.alias) ? 1 : 0
          if p0 != p1 { return p0 > p1 }
          return $0.alias < $1.alias
        }
        let start = min(offset, sorted.count)
        let end = min(start + limit, sorted.count)
        return Array(sorted[start..<end])
      }
      let scored = all.compactMap { record -> (CanonicalToolSearchRecord, Int)? in
        var lexicalScore = 0
        let alias = record.alias.lowercased()
        let title = record.title.lowercased()
        let summary = record.summary.lowercased()
        let category = record.category?.lowercased() ?? ""

        // Exact match on full query gets highest priority (DISC-07)
        if alias == trimmed {
          lexicalScore += 1000
        }

        for term in terms {
          if alias == term {
            lexicalScore += 500
          } else if alias.contains(term) {
            lexicalScore += 50
          }
          if title.contains(term) { lexicalScore += 30 }
          if summary.contains(term) { lexicalScore += 20 }
          if category.contains(term) { lexicalScore += 15 }
          for kw in record.keywords where kw.lowercased().contains(term) {
            lexicalScore += 10
          }
        }

        // DISC-08: Genuine lexical match is required.
        // Boost alone does not return irrelevant tools when no terms match.
        guard lexicalScore > 0 else { return nil }

        var totalScore = lexicalScore
        if preferredAliases.contains(record.alias) {
          totalScore += 30
        }
        return (record, totalScore)
      }

      // Deterministic ranking: score descending, then alias ascending (DISC-21)
      let sorted = scored.sorted {
        if $0.1 != $1.1 { return $0.1 > $1.1 }
        return $0.0.alias < $1.0.alias
      }
      let start = min(offset, sorted.count)
      let end = min(start + limit, sorted.count)
      return Array(sorted[start..<end].map(\.0))
    }
}
