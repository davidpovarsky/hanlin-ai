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

