import Foundation

/// Only synthetic fixture stores implement this adapter here. No production
/// stores, live databases, AppGroup bindings or secrets are accessed.
public struct SplitDurableFixtureMigration: Sendable {
    public enum RecoveryPolicy: Sendable { case finishIntent, restoreBeforeIntent }
    private let store: SplitFixtureStore
    public init(store: SplitFixtureStore) { self.store = store }

    public func initialize(plan: SplitMigrationPlan) throws {
        try store.locked {
            // Never overwrite an existing transaction or destination fixture.
            for slot in [SplitFixtureStore.Slot.source, .destination, .journal, .migrationIntent] {
                guard !FileManager.default.fileExists(atPath: try store.url(slot).path) else { throw SplitDurabilityError.recoveryConflict }
            }
            let journal = try SplitMigrationJournal(plan: plan)
            try store.write(plan.source, to: .source)
            try store.write(plan.destination, to: .destination)
            try store.write(journal, to: .journal)
        }
    }

    public func apply(interruptAt: SplitMigrationInterruption? = nil) throws -> SplitStoreSnapshot {
        try transition(kind: .apply, interruptAt: interruptAt)
    }

    public func rollback(interruptAt: SplitMigrationInterruption? = nil) throws -> SplitStoreSnapshot {
        try transition(kind: .rollback, interruptAt: interruptAt)
    }

    private func transition(kind: SplitMigrationIntent.Kind, interruptAt: SplitMigrationInterruption?) throws -> SplitStoreSnapshot {
        try store.locked {
            // Every new operation first completes any valid outstanding intent.
            _ = try recoverLocked(policy: .finishIntent)
            let source = try store.read(SplitStoreSnapshot.self, from: .source)
            let destination = try store.read(SplitStoreSnapshot.self, from: .destination)
            let before = try store.read(SplitMigrationJournal.self, from: .journal)
            guard source == before.plan.source, destination == before.output else { throw SplitDurabilityError.recoveryConflict }
            var after = before
            switch kind {
            case .apply: _ = try after.apply(source: source, current: destination)
            case .rollback: _ = try after.rollback(current: destination)
            case .checkpoint: throw SplitDurabilityError.corruptState
            }
            let intent = SplitMigrationIntent(kind: kind, before: before, after: after)
            try intent.validate()
            try store.write(intent, to: .migrationIntent)
            if interruptAt == .afterIntent { throw SplitDurabilityError.interrupted }
            try store.write(after.output, to: .destination)
            if interruptAt == .afterDestination { throw SplitDurabilityError.interrupted }
            try store.write(after, to: .journal)
            if interruptAt == .afterJournal { throw SplitDurabilityError.interrupted }
            guard try store.read(SplitStoreSnapshot.self, from: .destination) == after.output,
                  try store.read(SplitMigrationJournal.self, from: .journal) == after
            else { throw SplitDurabilityError.corruptState }
            return after.output
        }
    }

    public func recover(policy: RecoveryPolicy) throws -> SplitStoreSnapshot {
        try store.locked { try recoverLocked(policy: policy) }
    }

    private func recoverLocked(policy: RecoveryPolicy) throws -> SplitStoreSnapshot {
        let source = try store.read(SplitStoreSnapshot.self, from: .source)
        let current = try store.read(SplitStoreSnapshot.self, from: .destination)
        let journal = try store.read(SplitMigrationJournal.self, from: .journal)
        let path = try store.url(.migrationIntent)
        guard FileManager.default.fileExists(atPath: path.path) else {
            // Validates a decoded journal even before the first transaction.
            try journal.validate()
            guard source == journal.plan.source, current == journal.output else { throw SplitDurabilityError.recoveryConflict }
            return current
        }
        let intent = try store.read(SplitMigrationIntent.self, from: .migrationIntent)
        try intent.validate()
        guard source == intent.before.plan.source,
              current == intent.before.output || current == intent.after.output,
              journal == intent.before || journal == intent.after else { throw SplitDurabilityError.recoveryConflict }
        let target = policy == .finishIntent ? intent.after : intent.before
        // Keep a settled self-transition intent as a durable checkpoint. No
        // source or backup is deleted, and another recovery is idempotent.
        try store.write(target.output, to: .destination)
        try store.write(target, to: .journal)
        let checkpoint = SplitMigrationIntent(kind: .checkpoint, before: target, after: target)
        try store.write(checkpoint, to: .migrationIntent)
        return target.output
    }
}
