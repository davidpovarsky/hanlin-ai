import Foundation
import HanlinHostContracts
import SwiftData

/// One application entry point may own a conversation turn at a time. The
/// original UI and the headless facade acquire this before inserting rows.
/// Destructive original-row mutations revoke both active turns and idle owners.
@MainActor
final class HanlinConversationRunLease {
    private struct Key: Hashable {
        let container: ObjectIdentifier
        let conversationID: UUID
    }
    private final class Entry {
        weak var lease: HanlinConversationRunLease?
        init(_ lease: HanlinConversationRunLease) { self.lease = lease }
    }
    /// A weak association with the original owner, including preparation/history
    /// and inline tools between turns. This is not another Session or data store.
    final class OwnerRegistration {
        fileprivate weak var owner: HanlinAppAgentSessionOwner?
        fileprivate weak var container: ModelContainer?
        fileprivate let conversationID: UUID
        fileprivate(set) var isRevoked = false

        fileprivate init(owner: HanlinAppAgentSessionOwner, container: ModelContainer, conversationID: UUID) {
            self.owner = owner
            self.container = container
            self.conversationID = conversationID
        }
    }
    private static var active: [Key: Entry] = [:]
    private static var owners: [ObjectIdentifier: OwnerRegistration] = [:]
    private let key: Key
    private let token = UUID()
    private var onRevocation: (@MainActor () -> Void)?
    private(set) var isRevoked = false

    private init(key: Key) { self.key = key }

    static func acquire(container: ModelContainer, conversationID: UUID) throws -> HanlinConversationRunLease {
        let key = Key(container: ObjectIdentifier(container), conversationID: conversationID)
        guard active[key]?.lease == nil else { throw HanlinHostError.duplicateInvocation }
        let lease = HanlinConversationRunLease(key: key)
        active[key] = Entry(lease)
        return lease
    }

    static func acquire(owner: HanlinAppAgentSessionOwner) throws -> HanlinConversationRunLease {
        guard let registration = owners[ObjectIdentifier(owner)], registration.owner === owner,
              !registration.isRevoked, let container = registration.container else {
            throw HanlinHostError.staleContext
        }
        return try acquire(container: container, conversationID: registration.conversationID)
    }

    @discardableResult
    static func register(owner: HanlinAppAgentSessionOwner, container: ModelContainer,
                         conversationID: UUID) -> OwnerRegistration {
        owners = owners.filter { $0.value.owner != nil && $0.value.container != nil }
        let key = ObjectIdentifier(owner)
        if let existing = owners[key], existing.container === container,
           existing.conversationID == conversationID, !existing.isRevoked { return existing }
        owners[key]?.isRevoked = true
        let registration = OwnerRegistration(owner: owner, container: container, conversationID: conversationID)
        owners[key] = registration
        return registration
    }

    func onRevoke(_ action: @escaping @MainActor () -> Void) {
        guard !isRevoked else { action(); return }
        onRevocation = action
    }

    /// Remove authority first, before invoking callbacks or scheduling any async
    /// cleanup. A late release or completion cannot act on a new owner's token.
    static func revoke(container: ModelContainer, conversationID: UUID) {
        let key = Key(container: ObjectIdentifier(container), conversationID: conversationID)
        let lease = active.removeValue(forKey: key)?.lease
        lease?.isRevoked = true
        let matching = owners.filter {
            $0.value.container === container && $0.value.conversationID == conversationID
        }
        for (ownerKey, registration) in matching {
            owners.removeValue(forKey: ownerKey)
            registration.isRevoked = true
        }
        for registration in matching.values { registration.owner?.cancel() }
        let callback = lease?.onRevocation
        lease?.onRevocation = nil
        callback?()
    }

    func release() {
        onRevocation = nil
        guard Self.active[key]?.lease?.token == token else { return }
        Self.active.removeValue(forKey: key)
    }
}
