import Foundation
import HanlinPlatformContracts

/// This envelope is transferred through an authenticated, bounded mailbox, never a URL.
/// A URL is only a foreground wake hint and confers no authority.
public struct SplitBridgeRequest: Codable, Equatable, Sendable {
    public let version: Int
    public let id: UUID
    public let caller: HanlinAppID
    public let target: HanlinAppID
    public let installedPackage: HanlinInstalledPackageID
    public let session: HanlinAppSessionID
    public let chat: UUID
    public let generation: UInt64
    public let entryPoint: HanlinEntryPointKind
    public let action: HanlinActionID
    public let capability: HanlinCapabilityID
    public let issuedAt: Date
    public let expiresAt: Date
    public let payload: HanlinValue

    public init(id: UUID = UUID(), caller: HanlinAppID, target: HanlinAppID,
                installedPackage: HanlinInstalledPackageID, session: HanlinAppSessionID,
                chat: UUID, generation: UInt64, entryPoint: HanlinEntryPointKind = .app,
                action: HanlinActionID, capability: HanlinCapabilityID,
                issuedAt: Date, expiresAt: Date, payload: HanlinValue) {
        version = 1
        self.id = id; self.caller = caller; self.target = target
        self.installedPackage = installedPackage; self.session = session; self.chat = chat
        self.generation = generation; self.entryPoint = entryPoint; self.action = action
        self.capability = capability; self.issuedAt = issuedAt; self.expiresAt = expiresAt
        self.payload = payload
    }
}

public enum SplitBridgeFailure: String, Error, Codable, CaseIterable, Sendable {
    case malformed, oversized, expired, correlationMismatch, staleGeneration
    case duplicate, outOfOrder, denied, cancelled, timedOut, offline, companionMissing
    case unsupportedRoute, transportUnavailable, capacityExceeded
}

public enum SplitBridgeOutcome: Codable, Equatable, Sendable {
    case result(HanlinValue)
    case failure(SplitBridgeFailure)
}

public struct SplitBridgeReturn: Codable, Equatable, Sendable {
    /// Repeats the full immutable request, including identity and payload, for exact comparison.
    public let request: SplitBridgeRequest
    public let outcome: SplitBridgeOutcome
    public init(request: SplitBridgeRequest, outcome: SplitBridgeOutcome) {
        self.request = request; self.outcome = outcome
    }
}

public enum SplitBridgeCodec {
    public static let maximumBytes = 65_536
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let data = try JSONEncoder().encode(value)
        guard data.count <= maximumBytes else { throw SplitBridgeFailure.oversized }
        return data
    }
    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        guard data.count <= maximumBytes else { throw SplitBridgeFailure.oversized }
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw SplitBridgeFailure.malformed }
    }

    /// Hosts are deployment configuration, not a claimed registered production domain.
    public static func wakeURL(requestID: UUID, host: String, returning: Bool) throws -> URL {
        guard !host.isEmpty, host.utf8.count <= 253,
              host.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 46 }),
              !host.hasPrefix("."), !host.hasSuffix(".") else { throw SplitBridgeFailure.malformed }
        let path = returning ? "return" : "open"
        guard let url = URL(string: "https://\(host)/hanlin/split/v1/\(path)/\(requestID.uuidString.lowercased())")
        else { throw SplitBridgeFailure.malformed }
        return url
    }
    public static func wakeRequestID(_ url: URL, allowedHost: String, returning: Bool) throws -> UUID {
        guard url.absoluteString.utf8.count <= 512,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "https", parts.host == allowedHost,
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.query == nil, parts.fragment == nil else { throw SplitBridgeFailure.malformed }
        let prefix = returning ? "/hanlin/split/v1/return/" : "/hanlin/split/v1/open/"
        guard parts.percentEncodedPath.hasPrefix(prefix),
              let id = UUID(uuidString: String(parts.percentEncodedPath.dropFirst(prefix.count))),
              try wakeURL(requestID: id, host: allowedHost, returning: returning) == url
        else { throw SplitBridgeFailure.malformed }
        return id
    }
}

/// Pure lifecycle, not a second permission engine. The composition root must supply
/// current catalog/package checks and the existing authority at both ends.
/// Persist this state with the authenticated mailbox before foreground dispatch.
public struct SplitBridgeLedger: Codable, Sendable {
    public enum Phase: String, Codable, Sendable { case pending, dispatched, finished }
    public struct Record: Codable, Sendable {
        public let request: SplitBridgeRequest
        public var phase: Phase
        public var outcome: SplitBridgeOutcome?
    }
    private var records: [UUID: Record] = [:]
    public init() {}
    public func record(_ id: UUID) -> Record? { records[id] }

    /// Validate the complete decoded sender database before any live transaction.
    public func validate() throws {
        guard records.count <= 1024 else { throw SplitBridgeFailure.capacityExceeded }
        for (id, record) in records {
            let request = record.request
            guard id == request.id, request.version == 1, request.entryPoint == .app,
                  request.expiresAt > request.issuedAt,
                  request.expiresAt.timeIntervalSince(request.issuedAt) <= 300 else {
                throw SplitDurabilityError.corruptState
            }
            _ = try SplitBridgeCodec.encode(request)
            if record.phase == .finished {
                guard let outcome = record.outcome else { throw SplitDurabilityError.corruptState }
                _ = try SplitBridgeCodec.encode(SplitBridgeReturn(request: request, outcome: outcome))
            } else if record.outcome != nil { throw SplitDurabilityError.corruptState }
        }
    }

    public mutating func begin(_ request: SplitBridgeRequest, now: Date,
                               routeAvailable: Bool, authorized: Bool) throws {
        guard records[request.id] == nil else { throw SplitBridgeFailure.duplicate }
        guard records.count < 1024 else { throw SplitBridgeFailure.capacityExceeded }
        guard request.version == 1, request.entryPoint == .app,
              request.issuedAt <= now, request.expiresAt > now,
              request.expiresAt.timeIntervalSince(request.issuedAt) <= 300
        else { throw SplitBridgeFailure.expired }
        guard routeAvailable else { throw SplitBridgeFailure.unsupportedRoute }
        guard authorized else { throw SplitBridgeFailure.denied }
        _ = try SplitBridgeCodec.encode(request)
        records[request.id] = Record(request: request, phase: .pending)
    }

    public mutating func dispatch(_ id: UUID, now: Date, currentGeneration: UInt64,
                                  authorized: Bool, companionInstalled: Bool,
                                  transportReady: Bool, online: Bool) throws {
        guard var record = records[id] else { throw SplitBridgeFailure.correlationMismatch }
        guard record.phase == .pending else { throw SplitBridgeFailure.outOfOrder }
        guard now < record.request.expiresAt else { throw SplitBridgeFailure.timedOut }
        guard record.request.generation == currentGeneration else { throw SplitBridgeFailure.staleGeneration }
        guard authorized else { throw SplitBridgeFailure.denied }
        guard companionInstalled else { throw SplitBridgeFailure.companionMissing }
        guard transportReady else { throw SplitBridgeFailure.transportUnavailable }
        guard online else { throw SplitBridgeFailure.offline }
        record.phase = .dispatched
        records[id] = record
    }

    /// Returns the immutable origin so the caller navigates to that chat/session only.
    public mutating func accept(_ response: SplitBridgeReturn, now: Date,
                                currentGeneration: UInt64, authenticatedSender: HanlinAppID,
                                authorized: Bool) throws -> SplitBridgeRequest {
        _ = try SplitBridgeCodec.encode(response)
        guard var record = records[response.request.id] else { throw SplitBridgeFailure.correlationMismatch }
        guard record.phase != .finished else { throw SplitBridgeFailure.duplicate }
        guard record.phase == .dispatched else { throw SplitBridgeFailure.outOfOrder }
        guard record.request == response.request, authenticatedSender == record.request.target
        else { throw SplitBridgeFailure.correlationMismatch }
        guard now < record.request.expiresAt else { throw SplitBridgeFailure.timedOut }
        guard record.request.generation == currentGeneration else { throw SplitBridgeFailure.staleGeneration }
        guard authorized else { throw SplitBridgeFailure.denied }
        record.phase = .finished; record.outcome = response.outcome
        records[response.request.id] = record
        return record.request
    }

    /// Local failures consume the request once; restarting requires a fresh request ID.
    public mutating func finish(_ id: UUID, failure: SplitBridgeFailure) throws {
        guard var record = records[id] else { throw SplitBridgeFailure.correlationMismatch }
        guard record.phase != .finished else { throw SplitBridgeFailure.duplicate }
        record.phase = .finished; record.outcome = .failure(failure); records[id] = record
    }
}
