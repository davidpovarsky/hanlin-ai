import Foundation
import HanlinPlatformContracts

/// Only an entitlement/integrity-bound integration adapter may implement this for
/// live delivery. The reference is untrusted; the returned record must be verified.
public protocol SplitTrustedRequestSource: Sendable {
    func verifiedRequest(reference: UUID) async throws -> SplitBridgeRequest
}

public struct SplitReceiverContext: Sendable {
    public let caller: HanlinAppID
    public let target: HanlinAppID
    public let package: HanlinInstalledPackageID
    public let session: HanlinAppSessionID
    public let chat: UUID
    public let generation: UInt64
    public let authorized: Bool
    public let routeAvailable: Bool
    public let online: Bool

    /// Values come from current canonical host state, not from a URL or bundle ID
    /// asserted by the caller. `authorized` preserves the existing host/OS policy.
    public init(caller: HanlinAppID, target: HanlinAppID, package: HanlinInstalledPackageID,
                session: HanlinAppSessionID, chat: UUID, generation: UInt64,
                authorized: Bool, routeAvailable: Bool, online: Bool) {
        self.caller = caller; self.target = target; self.package = package
        self.session = session; self.chat = chat; self.generation = generation
        self.authorized = authorized; self.routeAvailable = routeAvailable; self.online = online
    }

    func validate(_ request: SplitBridgeRequest) throws {
        guard request.version == 1, request.entryPoint == .app else { throw SplitBridgeFailure.unsupportedRoute }
        guard request.caller == caller, request.target == target, request.installedPackage == package,
              request.session == session, request.chat == chat else { throw SplitBridgeFailure.correlationMismatch }
        guard request.generation == generation else { throw SplitBridgeFailure.staleGeneration }
    }
}

public enum SplitDurabilityError: Error, Equatable, Sendable {
    case busy, corruptState, unsupportedVersion, outcomeUnknown, attemptMismatch
    case recoveryConflict, persistenceUnavailable, interrupted
    case encodedSizeExceeded
}

public struct SplitReceiverRecord: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable { case reserved, executing, outcomeUnknown, completed }
    public let request: SplitBridgeRequest
    public private(set) var phase: Phase
    public private(set) var attempt: UUID?
    public private(set) var outcome: SplitBridgeOutcome?
    public private(set) var interruption: SplitBridgeFailure?

    init(request: SplitBridgeRequest) { self.request = request; phase = .reserved }

    mutating func start() throws {
        guard phase == .reserved else {
            if phase == .outcomeUnknown { throw SplitDurabilityError.outcomeUnknown }
            throw SplitBridgeFailure.outOfOrder
        }
        attempt = UUID(); phase = .executing
    }

    mutating func complete(attempt expected: UUID, outcome: SplitBridgeOutcome, reconciliation: Bool) throws {
        guard attempt == expected else { throw SplitDurabilityError.attemptMismatch }
        if phase == .completed {
            guard self.outcome == outcome else { throw SplitDurabilityError.recoveryConflict }
            return
        }
        guard phase == (reconciliation ? .outcomeUnknown : .executing) else {
            throw SplitBridgeFailure.outOfOrder
        }
        self.outcome = outcome; phase = .completed
    }

    mutating func interrupt(_ reason: SplitBridgeFailure) {
        guard phase != .completed else { return }
        interruption = reason
        if phase == .reserved { outcome = .failure(reason); phase = .completed }
        else { phase = .outcomeUnknown }
    }

    func validate() throws {
        _ = try SplitBridgeCodec.encode(request)
        guard request.version == 1, request.entryPoint == .app,
              request.expiresAt > request.issuedAt,
              request.expiresAt.timeIntervalSince(request.issuedAt) <= 300 else { throw SplitDurabilityError.corruptState }
        switch phase {
        case .reserved: guard attempt == nil, outcome == nil, interruption == nil else { throw SplitDurabilityError.corruptState }
        case .executing, .outcomeUnknown:
            guard attempt != nil, outcome == nil else { throw SplitDurabilityError.corruptState }
        case .completed:
            guard let outcome else { throw SplitDurabilityError.corruptState }
            if attempt == nil {
                guard case let .failure(reason) = outcome, interruption == reason else { throw SplitDurabilityError.corruptState }
            }
            _ = try SplitBridgeCodec.encode(SplitBridgeReturn(request: request, outcome: outcome))
        }
    }
}

public struct SplitReceiverDatabase: Codable, Equatable, Sendable {
    public let version: Int
    public private(set) var records: [UUID: SplitReceiverRecord]
    public init() { version = 1; records = [:] }

    public func validate() throws {
        guard version == 1 else { throw SplitDurabilityError.unsupportedVersion }
        guard records.count <= 128 else { throw SplitBridgeFailure.capacityExceeded }
        for (id, record) in records {
            guard id == record.request.id else { throw SplitDurabilityError.corruptState }
            try record.validate()
        }
    }

    mutating func reserve(_ request: SplitBridgeRequest) throws -> SplitReceiverRecord {
        if let existing = records[request.id] {
            guard existing.request == request else { throw SplitBridgeFailure.correlationMismatch }
            return existing
        }
        guard records.count < 128 else { throw SplitBridgeFailure.capacityExceeded }
        let record = SplitReceiverRecord(request: request)
        records[request.id] = record; return record
    }

    mutating func update(_ request: SplitBridgeRequest,
                         _ operation: (inout SplitReceiverRecord) throws -> Void) throws -> SplitReceiverRecord {
        guard var record = records[request.id], record.request == request else { throw SplitBridgeFailure.correlationMismatch }
        try operation(&record)
        records[request.id] = record; return record
    }
}

/// Implementations must serialize the read/validate/update/atomic-persist operation
/// across all instances/processes, and return only after persistence succeeds.
public protocol SplitReceiverPersistence: Sendable {
    func transaction(_ operation: @Sendable (inout SplitReceiverDatabase) throws -> SplitReceiverRecord) throws -> SplitReceiverRecord
}

/// No broker is invoked here. A successful start persists a unique attempt before
/// exposing it to an executor. After ambiguous execution, only reconciliation may
/// produce a terminal result; redelivery never grants another attempt.
public struct SplitDurableReceiver: Sendable {
    private let persistence: any SplitReceiverPersistence
    private let source: (any SplitTrustedRequestSource)?
    public init(persistence: any SplitReceiverPersistence, source: (any SplitTrustedRequestSource)? = nil) {
        self.persistence = persistence; self.source = source
    }

    private func trusted(_ reference: UUID, context: SplitReceiverContext) async throws -> SplitBridgeRequest {
        guard let source else { throw SplitBridgeFailure.transportUnavailable }
        let request = try await source.verifiedRequest(reference: reference)
        guard request.id == reference else { throw SplitBridgeFailure.correlationMismatch }
        _ = try SplitBridgeCodec.encode(request)
        try context.validate(request)
        return request
    }

    private func executionFailure(_ request: SplitBridgeRequest, context: SplitReceiverContext, now: Date) -> SplitBridgeFailure? {
        if !context.authorized { return .denied }
        if !context.routeAvailable { return .unsupportedRoute }
        if !context.online { return .offline }
        if request.issuedAt > now { return .expired }
        if request.expiresAt <= now { return .timedOut }
        return nil
    }

    public func receive(reference: UUID, context: SplitReceiverContext, now: Date) async throws -> SplitReceiverRecord {
        let request = try await trusted(reference, context: context)
        let failure = executionFailure(request, context: context, now: now)
        return try persistence.transaction { database in
            _ = try database.reserve(request)
            return try database.update(request) { record in
                if let failure { record.interrupt(failure) }
            }
        }
    }

    public func start(reference: UUID, context: SplitReceiverContext, now: Date) async throws -> SplitReceiverRecord {
        let request = try await trusted(reference, context: context)
        if let failure = executionFailure(request, context: context, now: now) { throw failure }
        return try persistence.transaction { database in
            try database.update(request) { try $0.start() }
        }
    }

    public func complete(reference: UUID, attempt: UUID, outcome: SplitBridgeOutcome,
                         context: SplitReceiverContext) async throws -> SplitReceiverRecord {
        let request = try await trusted(reference, context: context)
        guard context.authorized else { throw SplitBridgeFailure.denied }
        _ = try SplitBridgeCodec.encode(SplitBridgeReturn(request: request, outcome: outcome))
        return try persistence.transaction { database in
            try database.update(request) { try $0.complete(attempt: attempt, outcome: outcome, reconciliation: false) }
        }
    }

    /// Use on restart or loss of executor ownership. This never assumes a side
    /// effect was absent, even if interruption happened before the actual call.
    public func interrupt(reference: UUID, reason: SplitBridgeFailure,
                          context: SplitReceiverContext) async throws -> SplitReceiverRecord {
        let request = try await trusted(reference, context: context)
        return try persistence.transaction { database in
            try database.update(request) { $0.interrupt(reason) }
        }
    }

    /// `outcome` must be reconciled from the existing executor/authority's trusted
    /// operation result. This method is not proof that an external side effect ran.
    public func reconcile(reference: UUID, attempt: UUID, outcome: SplitBridgeOutcome,
                          context: SplitReceiverContext) async throws -> SplitReceiverRecord {
        let request = try await trusted(reference, context: context)
        guard context.authorized else { throw SplitBridgeFailure.denied }
        _ = try SplitBridgeCodec.encode(SplitBridgeReturn(request: request, outcome: outcome))
        return try persistence.transaction { database in
            try database.update(request) { try $0.complete(attempt: attempt, outcome: outcome, reconciliation: true) }
        }
    }
}
