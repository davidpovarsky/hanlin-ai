import Foundation
import WidgetKit

/// Captured with timeline props under the state lock. A reused source string
/// cannot make a prior installation generation current again.
public struct HanlinExpoWidgetTimelineProof: Equatable, Sendable {
  let namespace: String
  let generation: UInt64
  let layoutSHA256: String

  var environment: [String: Any] {
    ["__hanlinNamespace": namespace, "__hanlinGeneration": String(generation),
     "__hanlinLayoutRevision": layoutSHA256]
  }
}

public struct WidgetsTimelineEntry: WidgetKit.TimelineEntry {
  public let date: Date
  public let name: String
  public let props: [String: Any]?
  public let entryIndex: Int?
  public let snapshotProof: HanlinExpoWidgetTimelineProof?

  public init(date: Date, name: String, props: [String: Any]?, entryIndex: Int?,
              snapshotProof: HanlinExpoWidgetTimelineProof? = nil) {
    self.date = date; self.name = name; self.props = props; self.entryIndex = entryIndex
    self.snapshotProof = snapshotProof
  }
}
