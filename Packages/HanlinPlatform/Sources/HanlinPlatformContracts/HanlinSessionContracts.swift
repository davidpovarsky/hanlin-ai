import Foundation

public enum HanlinAppSessionState: String, Codable, Hashable, Sendable {
    case created
    case activating
    case active
    case suspending
    case suspended
    case resuming
    case closing
    case closed
    case failed

    public var isTerminal: Bool {
        self == .closed || self == .failed
    }
}

public struct HanlinAppSessionDescriptor: Codable, Hashable, Sendable {
    public let id: HanlinAppSessionID
    public let appID: HanlinAppID
    public let installedPackageID: HanlinInstalledPackageID?
    public let launchID: HanlinLaunchID?
    public let presentation: HanlinPresentationIntent
    public let initialRoute: HanlinRouteRequest?
    public let state: HanlinAppSessionState
    public let createdAt: Date
    public let stateChangedAt: Date
    public let activeChildOperationCount: Int?

    public init(
        id: HanlinAppSessionID,
        appID: HanlinAppID,
        installedPackageID: HanlinInstalledPackageID? = nil,
        launchID: HanlinLaunchID? = nil,
        presentation: HanlinPresentationIntent,
        initialRoute: HanlinRouteRequest? = nil,
        state: HanlinAppSessionState,
        createdAt: Date,
        stateChangedAt: Date,
        activeChildOperationCount: Int? = nil
    ) {
        self.id = id
        self.appID = appID
        self.installedPackageID = installedPackageID
        self.launchID = launchID
        self.presentation = presentation
        self.initialRoute = initialRoute
        self.state = state
        self.createdAt = createdAt
        self.stateChangedAt = stateChangedAt
        self.activeChildOperationCount = activeChildOperationCount
    }
}

public struct HanlinAppSessionEvent: Codable, Hashable, Sendable {
    public let sessionID: HanlinAppSessionID
    public let sequence: UInt64
    public let previousState: HanlinAppSessionState?
    public let state: HanlinAppSessionState
    public let timestamp: Date
    public let error: HanlinPlatformError?

    public init(
        sessionID: HanlinAppSessionID,
        sequence: UInt64,
        previousState: HanlinAppSessionState?,
        state: HanlinAppSessionState,
        timestamp: Date,
        error: HanlinPlatformError? = nil
    ) {
        self.sessionID = sessionID
        self.sequence = sequence
        self.previousState = previousState
        self.state = state
        self.timestamp = timestamp
        self.error = error
    }
}

public enum HanlinRuntimeKind: String, Codable, Hashable, Sendable {
    case node
    case typeScript
    case localPython
    case javaScriptCore
    case shell
    case mcp
    case native
}

public enum HanlinRuntimeSessionState: String, Codable, Hashable, Sendable {
    case allocating
    case preparing
    case ready
    case executing
    case suspending
    case suspended
    case resuming
    case stopping
    case stopped
    case failed
    case restartRequired

    public var isTerminal: Bool {
        self == .stopped || self == .failed || self == .restartRequired
    }
}

public struct HanlinRuntimeFeatureSet: Codable, Hashable, Sendable {
    public let features: Set<String>
    public let limits: [String: Int64]

    public init(features: Set<String> = [], limits: [String: Int64] = [:]) {
        self.features = features
        self.limits = limits
    }
}

public struct HanlinRuntimeSessionDescriptor: Codable, Hashable, Sendable {
    public let id: HanlinRuntimeSessionID
    public let providerInstanceID: HanlinProviderInstanceID
    public let parentAppSessionID: HanlinAppSessionID?
    public let replacesSessionID: HanlinRuntimeSessionID?
    public let kind: HanlinRuntimeKind
    public let runtimeVersion: String?
    public let compilerVersion: String?
    public let protocolVersion: HanlinWireProtocolVersion?
    public let features: HanlinRuntimeFeatureSet
    public let state: HanlinRuntimeSessionState
    public let createdAt: Date
    public let stateChangedAt: Date
    public let activeExecutionCount: Int
    public let failureCode: String?

    public init(
        id: HanlinRuntimeSessionID,
        providerInstanceID: HanlinProviderInstanceID,
        parentAppSessionID: HanlinAppSessionID? = nil,
        replacesSessionID: HanlinRuntimeSessionID? = nil,
        kind: HanlinRuntimeKind,
        runtimeVersion: String? = nil,
        compilerVersion: String? = nil,
        protocolVersion: HanlinWireProtocolVersion? = nil,
        features: HanlinRuntimeFeatureSet = .init(),
        state: HanlinRuntimeSessionState,
        createdAt: Date,
        stateChangedAt: Date,
        activeExecutionCount: Int,
        failureCode: String? = nil
    ) {
        self.id = id
        self.providerInstanceID = providerInstanceID
        self.parentAppSessionID = parentAppSessionID
        self.replacesSessionID = replacesSessionID
        self.kind = kind
        self.runtimeVersion = runtimeVersion
        self.compilerVersion = compilerVersion
        self.protocolVersion = protocolVersion
        self.features = features
        self.state = state
        self.createdAt = createdAt
        self.stateChangedAt = stateChangedAt
        self.activeExecutionCount = activeExecutionCount
        self.failureCode = failureCode
    }
}

public enum HanlinOperationState: String, Codable, Hashable, Sendable {
    case created
    case accepted
    case running
    case completed
    case failed
    case denied
    case cancelled
    case timedOut

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .denied, .cancelled, .timedOut: true
        case .created, .accepted, .running: false
        }
    }
}

public enum HanlinCancellationPropagation: String, Codable, Hashable, Sendable {
    case operationOnly
    case descendants
}

public struct HanlinCancellationRequest: Codable, Hashable, Sendable {
    public let id: HanlinCancellationID
    public let operationID: HanlinRequestID
    public let requester: HanlinPermissionSubject?
    public let reason: String
    public let requestedAt: Date
    public let propagation: HanlinCancellationPropagation

    public init(
        id: HanlinCancellationID,
        operationID: HanlinRequestID,
        requester: HanlinPermissionSubject? = nil,
        reason: String,
        requestedAt: Date,
        propagation: HanlinCancellationPropagation = .descendants
    ) {
        self.id = id
        self.operationID = operationID
        self.requester = requester
        self.reason = reason
        self.requestedAt = requestedAt
        self.propagation = propagation
    }
}

public enum HanlinCancellationAcknowledgement: String, Codable, Hashable, Sendable {
    case accepted
    case alreadyTerminal
    case atSafePointPending
    case notCancellable
    case unknownOperation
}
