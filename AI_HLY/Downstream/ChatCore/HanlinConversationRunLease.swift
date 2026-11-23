import Foundation
import HanlinHostContracts
import SwiftData

/// One application entry point may own a conversation turn at a time. The
/// original UI and the headless facade acquire this before inserting rows.
/// Releasing an old token cannot revoke a subsequently admitted owner.
@MainActor
final class HanlinConversationRunLease {
    private struct Key: Hashable {
        let container: ObjectIdentifier
        let conversationID: UUID
    }
    private static var active: [Key: UUID] = [:]
    private let key: Key
    private let token = UUID()

    private init(key: Key) { self.key = key }

    static func acquire(container: ModelContainer, conversationID: UUID) throws -> HanlinConversationRunLease {
        let key = Key(container: ObjectIdentifier(container), conversationID: conversationID)
        guard active[key] == nil else { throw HanlinHostError.duplicateInvocation }
        let lease = HanlinConversationRunLease(key: key)
        active[key] = lease.token
        return lease
    }

    func release() {
        guard Self.active[key] == token else { return }
        Self.active.removeValue(forKey: key)
    }
}
