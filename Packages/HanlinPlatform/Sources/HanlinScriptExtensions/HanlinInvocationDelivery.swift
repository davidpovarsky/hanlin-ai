import Foundation
import HanlinPlatformContracts

/// Delivery metadata for the existing identity/action/parameters envelope.
/// These are provenance claims, not OS permissions or permission grants.
public struct HanlinInvocationDelivery: Codable, Hashable, Sendable {
    public enum Source: String, Codable, Hashable, Sendable { case share, shortcuts, translation, widget, notification, foreground, appIntent, liveActivity }
    public enum ExpectedResult: String, Codable, Hashable, Sendable { case value, text, file, none }
    public let schemaVersion: UInt32
    public let appID: HanlinAppID
    public let source: Source
    public let expiresAt: Date
    public let expectedResult: ExpectedResult
    public let userGesturePresent: Bool
    public let canPresentUI: Bool
    /// Automatic recovery is allowed only for actions declared idempotent by
    /// the installed action registration, never by an incoming extension alone.
    public let idempotent: Bool
    public let maximumAttempts: Int

    public init(appID: HanlinAppID, source: Source, expiresAt: Date,
                expectedResult: ExpectedResult = .value, userGesturePresent: Bool = false,
                canPresentUI: Bool = false, idempotent: Bool = false, maximumAttempts: Int = 1) {
        self.schemaVersion = 1
        self.appID = appID
        self.source = source
        self.expiresAt = expiresAt
        self.expectedResult = expectedResult
        self.userGesturePresent = userGesturePresent
        self.canPresentUI = canPresentUI
        self.idempotent = idempotent
        self.maximumAttempts = maximumAttempts
    }
}

public struct HanlinInvocationReceipt: Codable, Hashable, Sendable {
    public enum Status: String, Codable, Hashable, Sendable {
        case queued, running, succeeded, failed, cancelled, stale, expired, deferred, needsForeground, acknowledged
        public var isTerminal: Bool { self != .queued && self != .running }
    }
    public enum Failure: String, Codable, Hashable, Sendable {
        case invalidTarget, staleGeneration, disabledPackage, unsupportedEntrypoint, unavailableHost
        case actionFailed, interruptedOutcomeUnknown, attemptsExhausted, invalidEnvelope, deadlineExceeded
    }
    public let invocationID: UUID
    public internal(set) var status: Status
    public internal(set) var updatedAt: Date
    public internal(set) var attempt: Int
    public internal(set) var value: HanlinValue?
    public internal(set) var failure: Failure?
    public internal(set) var cancellationRequested: Bool
    public internal(set) var leaseID: UUID?
    public internal(set) var leaseExpiresAt: Date?

    init(id: UUID, at date: Date) {
        invocationID = id; status = .queued; updatedAt = date; attempt = 0
        cancellationRequested = false
    }
}

public struct HanlinInvocationClaim: Sendable {
    public let command: HanlinScriptResumeCommand
    public let leaseID: UUID
}

public enum HanlinInvocationQueueError: Error, Equatable, Sendable {
    case duplicateIdentity, invalidEnvelope, missingCommand, staleLease, invalidTransition, queueFull
}

/// Unreadable records remain unchanged. Without a validated command identity
/// this is a scan rejection, never a fabricated action failure/success receipt.
public struct HanlinInvocationQueueRejection: Sendable, Equatable {
    public let invocationID: UUID?
    public let failure: HanlinInvocationReceipt.Failure
}

public struct HanlinInvocationQueueScan: Sendable {
    public let commands: [HanlinScriptResumeCommand]
    public let rejections: [HanlinInvocationQueueRejection]
}

// The same record moves from ResumeQueue into its Receipts directory after
// completion. Historical pending readers cannot replay completed outbox files.
struct HanlinInvocationRecord: Codable {
    let id: UUID
    let createdAt: Date
    let invocation: HanlinScriptIntentInvocation
    var deliverySchemaVersion: UInt32?
    var receipt: HanlinInvocationReceipt?

    init(_ command: HanlinScriptResumeCommand) {
        id = command.id; createdAt = command.createdAt; invocation = command.invocation
        deliverySchemaVersion = 1
        receipt = .init(id: command.id, at: command.createdAt)
    }

    var command: HanlinScriptResumeCommand { .init(id: id, createdAt: createdAt, invocation: invocation) }
    var currentReceipt: HanlinInvocationReceipt { receipt ?? .init(id: id, at: createdAt) }
}
