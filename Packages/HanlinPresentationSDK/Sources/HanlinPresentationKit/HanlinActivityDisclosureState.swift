import Foundation

/// Presentation preference for one real run, stored with the existing message.
/// Only lifecycle transitions change expansion automatically; incoming tokens do not.
public struct HanlinActivityDisclosureState: Codable, Hashable, Sendable {
    public enum Phase: String, Codable, Hashable, Sendable {
        case active
        case answering
        case finished
    }

    public let runID: UUID
    public private(set) var phase: Phase
    public var isExpanded: Bool

    public init(runID: UUID, phase: Phase, isExpanded: Bool? = nil) {
        self.runID = runID
        self.phase = phase
        self.isExpanded = isExpanded ?? (phase == .active)
    }

    public func reconciled(runID: UUID, phase: Phase) -> Self {
        guard self.runID == runID else { return .init(runID: runID, phase: phase) }
        guard self.phase != phase else { return self }
        var next = self
        next.phase = phase
        if phase == .active { next.isExpanded = true }
        else if self.phase == .active { next.isExpanded = false }
        // A user may reopen history while the final answer streams. Finishing
        // that answer is not a second reason to override the user's choice.
        return next
    }
}
