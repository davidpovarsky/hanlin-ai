import Foundation
import HanlinPlatformContracts
import HanlinProductSplit
import HanlinScriptExtensions

/// Production adapter for the explicitly trusted first-party App Group principal.
/// Membership is not per-app writer authentication. Bundle IDs/URLs grant nothing.
/// One bounded state file reuses the existing store's lock, path checks and atomic IO.
struct HanlinSplitMailbox: SplitReceiverPersistence, SplitTrustedRequestSource {
    static let maximumBytes = 16_777_216
    private let container: URL

    private struct State: Codable {
        var version = 1
        var sender = SplitBridgeLedger()
        var receiver = SplitReceiverDatabase()
        var catalog: [SplitTargetRegistration]?

        func validate() throws {
            guard version == 1 else { throw SplitDurabilityError.unsupportedVersion }
            try sender.validate()
            try receiver.validate()
            if let catalog {
                guard catalog.count <= 1024, Set(catalog.map { $0.descriptor.id }).count == catalog.count else {
                    throw SplitDurabilityError.corruptState
                }
                for item in catalog { try item.validate() }
            }
            for record in receiver.records.values {
                guard let original = sender.record(record.request.id), original.request == record.request else {
                    throw SplitBridgeFailure.correlationMismatch
                }
            }
        }
    }

    func publishCatalog(_ items: [SplitTargetRegistration]) throws {
        try transact { $0.catalog = items.sorted { $0.descriptor.id.rawValue < $1.descriptor.id.rawValue } }
    }

    func registration(for target: HanlinAppID) throws -> SplitTargetRegistration {
        try transact { state in
            guard let item = state.catalog?.first(where: { $0.descriptor.id == target }) else {
                throw SplitBridgeFailure.unsupportedRoute
            }
            return item
        }
    }

    init() throws {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: HanlinScriptExtensionStore.appGroupIdentifier
        ) else { throw SplitBridgeFailure.transportUnavailable }
        try self.init(trustedGroupContainer: container)
    }

    /// Internal injection for owned tests; production resolves the OS container above.
    init(trustedGroupContainer: URL) throws {
        container = trustedGroupContainer.resolvingSymlinksInPath().standardizedFileURL
        _ = try SplitAppStorageLayout.transportRoot(appGroupContainer: container)
    }

    private func transact<Result>(_ operation: (inout State) throws -> Result) throws -> Result {
        // Revalidate the fixed namespace on every read/write, including cold reopen.
        let root = try SplitAppStorageLayout.transportRoot(appGroupContainer: container)
        let store = HanlinScriptExtensionStore(root: root)
        do {
            return try store.transactManagedState(fileName: "mailbox.json", maximumBytes: Self.maximumBytes) { bytes in
                var state: State
                if let bytes {
                    do { state = try JSONDecoder().decode(State.self, from: bytes) }
                    catch { throw SplitDurabilityError.corruptState }
                } else { state = State() }
                try state.validate()
                let result = try operation(&state)
                try state.validate()
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys]
                let encoded = try encoder.encode(state)
                guard encoded.count <= Self.maximumBytes else { throw SplitDurabilityError.encodedSizeExceeded }
                bytes = encoded
                return result
            }
        } catch HanlinScriptExtensionStoreError.storageBusy { throw SplitDurabilityError.busy }
    }

    /// Must complete before UIApplication.open. Handler availability is advisory;
    /// an OS open/canOpenURL result never authenticates the companion app.
    func prepareDispatch(_ request: SplitBridgeRequest, now: Date, currentGeneration: UInt64,
                         authorized: Bool, routeAvailable: Bool, handlerAvailable: Bool) throws {
        try transact { state in
            try state.sender.begin(request, now: now, routeAvailable: routeAvailable, authorized: authorized)
            try state.sender.dispatch(request.id, now: now, currentGeneration: currentGeneration,
                authorized: authorized, companionInstalled: handlerAvailable, transportReady: true, online: true)
        }
    }

    func verifiedRequest(reference: UUID) async throws -> SplitBridgeRequest {
        try original(reference)
    }

    func original(_ reference: UUID) throws -> SplitBridgeRequest {
        try transact { state in
            guard let record = state.sender.record(reference) else { throw SplitBridgeFailure.correlationMismatch }
            guard record.phase == .dispatched else { throw SplitBridgeFailure.outOfOrder }
            return record.request
        }
    }

    func transaction(_ operation: @Sendable (inout SplitReceiverDatabase) throws -> SplitReceiverRecord) throws -> SplitReceiverRecord {
        try transact { try operation(&$0.receiver) }
    }

    func finishDispatchFailure(_ reference: UUID, reason: SplitBridgeFailure) throws {
        try transact { try $0.sender.finish(reference, failure: reason) }
    }

    /// One transaction fences any reserved/executing receiver and the sender.
    /// An executing attempt becomes outcomeUnknown; no absent effect is assumed.
    func cancelDispatch(_ reference: UUID) throws {
        try transact { state in
            guard let record = state.sender.record(reference) else { throw SplitBridgeFailure.correlationMismatch }
            guard record.phase != .finished else { throw SplitBridgeFailure.duplicate }
            _ = try state.receiver.interruptIfPresent(record.request, reason: .cancelled)
            try state.sender.finish(reference, failure: .cancelled)
        }
    }

    private func completed(_ reference: UUID, state: State, context: SplitReceiverContext) throws -> SplitBridgeReturn {
        guard let sender = state.sender.record(reference), let record = state.receiver.records[reference],
              record.phase == .completed, let outcome = record.outcome,
              sender.request == record.request else { throw SplitBridgeFailure.correlationMismatch }
        try context.validate(sender.request)
        guard context.routeAvailable, context.online else { throw SplitBridgeFailure.transportUnavailable }
        return SplitBridgeReturn(request: record.request, outcome: outcome)
    }

    /// Validate before the existing conversation store persists its idempotent
    /// receipt. A failed conversation save must not consume the mailbox result.
    func previewCompleted(_ reference: UUID, context: SplitReceiverContext, now: Date) throws -> SplitBridgeReturn {
        try transact { state in
            let response = try completed(reference, state: state, context: context)
            var validation = state.sender
            _ = try validation.accept(response, now: now, currentGeneration: context.generation,
                authenticatedSender: response.request.target, authorized: context.authorized)
            return response
        }
    }

    /// A return URL only requests lookup. Consume after the original conversation
    /// store has committed its receipt; outcome/origin never come from URL fields.
    func acceptCompleted(_ reference: UUID, context: SplitReceiverContext, now: Date) throws -> SplitBridgeReturn {
        try transact { state in
            let response = try completed(reference, state: state, context: context)
            // Policy adaptation: authenticatedSender means the trusted GROUP
            // principal supplied this matching target record, not per-app identity.
            _ = try state.sender.accept(response, now: now, currentGeneration: context.generation,
                authenticatedSender: response.request.target, authorized: context.authorized)
            return response
        }
    }
}
