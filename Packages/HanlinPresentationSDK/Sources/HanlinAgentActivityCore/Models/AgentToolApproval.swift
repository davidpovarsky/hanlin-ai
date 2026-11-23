import Foundation

/// A receipt of a real approval request. Persisted presentation never grants
/// permission; only the current Host consent continuation can answer it.
public struct AgentToolApproval: Codable, Hashable, Sendable, Identifiable {
  public enum Disposition: String, Codable, Sendable { case awaiting, allowedOnce, allowedAlways, notApproved, providerRequired }
  public let id: String
  public let canonicalRunID: UUID?
  public let callID: String
  public let toolName: String
  public let reviewText: String
  public var disposition: Disposition

    public init(
        id: String,
        canonicalRunID: UUID?,
        callID: String,
        toolName: String,
        reviewText: String,
        disposition: Disposition
    ) {
        self.id = id
        self.canonicalRunID = canonicalRunID
        self.callID = callID
        self.toolName = toolName
        self.reviewText = reviewText
        self.disposition = disposition
    }
}
