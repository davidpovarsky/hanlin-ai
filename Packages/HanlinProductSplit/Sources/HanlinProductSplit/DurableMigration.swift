import Foundation

/// Write-ahead intent stores both known states. Destination and journal are
/// separate writes; recovery explicitly reconciles either side of that gap.
public struct SplitMigrationIntent: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case apply, rollback, checkpoint }
    public let version: Int
    public let kind: Kind
    public let before: SplitMigrationJournal
    public let after: SplitMigrationJournal

    init(kind: Kind, before: SplitMigrationJournal, after: SplitMigrationJournal) {
        version = 1; self.kind = kind; self.before = before; self.after = after
    }

    public func validate() throws {
        guard version == 1 else { throw SplitDurabilityError.unsupportedVersion }
        guard before.plan == after.plan else { throw SplitDurabilityError.corruptState }
        try before.validate(); try after.validate()
        // A reconstructed transition validates both journals and the intent.
        var reproduced = before
        switch kind {
        case .apply: _ = try reproduced.apply(source: before.plan.source, current: before.output)
        case .rollback: _ = try reproduced.rollback(current: before.output)
        case .checkpoint: break
        }
        guard reproduced == after else { throw SplitDurabilityError.corruptState }
    }
}

public enum SplitMigrationInterruption: String, CaseIterable, Sendable {
    case afterIntent, afterDestination, afterJournal
}
