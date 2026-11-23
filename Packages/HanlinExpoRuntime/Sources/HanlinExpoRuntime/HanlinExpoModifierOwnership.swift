/// Process-wide ExpoUI modifiers stay registered until their last session closes.
/// Session identities make retries, failed starts and repeated shutdown idempotent.
@MainActor
final class HanlinExpoModifierOwnership {
    private(set) var owners: Set<String> = []

    @discardableResult
    func acquire(sessionID: String) -> Bool {
        let wasEmpty = owners.isEmpty
        let inserted = owners.insert(sessionID).inserted
        return inserted && wasEmpty
    }

    @discardableResult
    func release(sessionID: String) -> Bool {
        let removed = owners.remove(sessionID) != nil
        return removed && owners.isEmpty
    }
}
