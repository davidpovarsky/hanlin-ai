import Foundation

public enum HanlinPermissionSubject: Codable, Hashable, Sendable {
    case app(HanlinAppID, installedPackageID: HanlinInstalledPackageID?)
    case package(HanlinInstalledPackageID)
    case provider(HanlinProviderInstanceID)
}

public struct HanlinPermissionScope: Codable, Hashable, Sendable {
    public let capabilityID: HanlinCapabilityID
    public let constraints: HanlinValue

    public init(
        capabilityID: HanlinCapabilityID,
        constraints: HanlinValue = .object([:])
    ) {
        self.capabilityID = capabilityID
        self.constraints = constraints
    }
}

public struct HanlinPermissionRequestContext: Codable, Hashable, Sendable {
    public let origin: HanlinExecutionOrigin
    public let appSessionID: HanlinAppSessionID?
    public let runtimeSessionID: HanlinRuntimeSessionID?
    public let userGesturePresent: Bool
    public let canPresentUI: Bool

    public init(
        origin: HanlinExecutionOrigin,
        appSessionID: HanlinAppSessionID? = nil,
        runtimeSessionID: HanlinRuntimeSessionID? = nil,
        userGesturePresent: Bool,
        canPresentUI: Bool
    ) {
        self.origin = origin
        self.appSessionID = appSessionID
        self.runtimeSessionID = runtimeSessionID
        self.userGesturePresent = userGesturePresent
        self.canPresentUI = canPresentUI
    }
}

public enum HanlinPermissionDuration: Codable, Hashable, Sendable {
    case once
    case session(HanlinAppSessionID)
    case until(Date)
    case persistentLocalDevice
}

public struct HanlinPermissionRequest: Codable, Hashable, Sendable {
    public let id: HanlinPermissionRequestID
    public let subject: HanlinPermissionSubject
    public let scopes: [HanlinPermissionScope]
    public let purpose: String
    public let context: HanlinPermissionRequestContext
    public let desiredDuration: HanlinPermissionDuration
    public let createdAt: Date

    public init(
        id: HanlinPermissionRequestID,
        subject: HanlinPermissionSubject,
        scopes: [HanlinPermissionScope],
        purpose: String,
        context: HanlinPermissionRequestContext,
        desiredDuration: HanlinPermissionDuration,
        createdAt: Date
    ) {
        self.id = id
        self.subject = subject
        self.scopes = scopes
        self.purpose = purpose
        self.context = context
        self.desiredDuration = desiredDuration
        self.createdAt = createdAt
    }
}

public enum HanlinPermissionDecisionOutcome: String, Codable, Hashable, Sendable {
    case granted
    case denied
    case cancelled
    case expired
}

public enum HanlinGrantSource: String, Codable, Hashable, Sendable {
    case user
    case managedPolicy
    case system
}

public enum HanlinGrantStorageScope: String, Codable, Hashable, Sendable {
    case localDevice
}

public struct HanlinGrantCondition: Codable, Hashable, Sendable {
    public let origin: HanlinExecutionOrigin?
    public let requiresUserGesture: Bool
    public let expiresAt: Date?

    public init(
        origin: HanlinExecutionOrigin? = nil,
        requiresUserGesture: Bool = false,
        expiresAt: Date? = nil
    ) {
        self.origin = origin
        self.requiresUserGesture = requiresUserGesture
        self.expiresAt = expiresAt
    }
}

public struct HanlinPermissionGrant: Codable, Hashable, Sendable {
    public let id: HanlinGrantID
    public let requestID: HanlinPermissionRequestID
    public let subject: HanlinPermissionSubject
    public let scope: HanlinPermissionScope
    public let conditions: [HanlinGrantCondition]
    public let source: HanlinGrantSource
    public let storageScope: HanlinGrantStorageScope
    public let policyVersion: HanlinPolicyVersion
    public let issuedAt: Date

    public init(
        id: HanlinGrantID,
        requestID: HanlinPermissionRequestID,
        subject: HanlinPermissionSubject,
        scope: HanlinPermissionScope,
        conditions: [HanlinGrantCondition] = [],
        source: HanlinGrantSource,
        storageScope: HanlinGrantStorageScope = .localDevice,
        policyVersion: HanlinPolicyVersion,
        issuedAt: Date
    ) {
        self.id = id
        self.requestID = requestID
        self.subject = subject
        self.scope = scope
        self.conditions = conditions
        self.source = source
        self.storageScope = storageScope
        self.policyVersion = policyVersion
        self.issuedAt = issuedAt
    }
}

public struct HanlinPermissionDecision: Codable, Hashable, Sendable {
    public let id: HanlinPermissionDecisionID
    public let requestID: HanlinPermissionRequestID
    public let outcome: HanlinPermissionDecisionOutcome
    public let grantIDs: [HanlinGrantID]
    public let decidedAt: Date
    public let safeReason: String

    public init(
        id: HanlinPermissionDecisionID,
        requestID: HanlinPermissionRequestID,
        outcome: HanlinPermissionDecisionOutcome,
        grantIDs: [HanlinGrantID] = [],
        decidedAt: Date,
        safeReason: String
    ) {
        self.id = id
        self.requestID = requestID
        self.outcome = outcome
        self.grantIDs = grantIDs
        self.decidedAt = decidedAt
        self.safeReason = safeReason
    }
}

public enum HanlinRevocationReason: String, Codable, Hashable, Sendable {
    case user
    case policyChanged
    case packageChanged
    case providerRemoved
    case expired
    case systemAuthorizationChanged
}

public struct HanlinPermissionRevocation: Codable, Hashable, Sendable {
    public let id: HanlinRevocationID
    public let grantID: HanlinGrantID
    public let reason: HanlinRevocationReason
    public let revokedAt: Date

    public init(
        id: HanlinRevocationID,
        grantID: HanlinGrantID,
        reason: HanlinRevocationReason,
        revokedAt: Date
    ) {
        self.id = id
        self.grantID = grantID
        self.reason = reason
        self.revokedAt = revokedAt
    }
}

public enum HanlinEffectivePermissionResult: String, Codable, Hashable, Sendable {
    case allowed
    case missingGrant
    case deniedByPolicy
    case deniedBySystem
    case expired
    case revoked
    case scopeMismatch
    case staleSubject
}

public struct HanlinEffectivePermission: Codable, Hashable, Sendable {
    public let subject: HanlinPermissionSubject
    public let scope: HanlinPermissionScope
    public let result: HanlinEffectivePermissionResult
    public let grantID: HanlinGrantID?
    public let policyEvaluationID: HanlinPolicyEvaluationID
    public let evaluatedAt: Date

    public init(
        subject: HanlinPermissionSubject,
        scope: HanlinPermissionScope,
        result: HanlinEffectivePermissionResult,
        grantID: HanlinGrantID? = nil,
        policyEvaluationID: HanlinPolicyEvaluationID,
        evaluatedAt: Date
    ) {
        self.subject = subject
        self.scope = scope
        self.result = result
        self.grantID = grantID
        self.policyEvaluationID = policyEvaluationID
        self.evaluatedAt = evaluatedAt
    }
}

public struct HanlinPolicyEvaluationRequest: Codable, Hashable, Sendable {
    public let id: HanlinPolicyEvaluationID
    public let subject: HanlinPermissionSubject
    public let operation: String
    public let scope: HanlinPermissionScope
    public let context: HanlinPermissionRequestContext
    public let grantIDs: [HanlinGrantID]

    public init(
        id: HanlinPolicyEvaluationID,
        subject: HanlinPermissionSubject,
        operation: String,
        scope: HanlinPermissionScope,
        context: HanlinPermissionRequestContext,
        grantIDs: [HanlinGrantID] = []
    ) {
        self.id = id
        self.subject = subject
        self.operation = operation
        self.scope = scope
        self.context = context
        self.grantIDs = grantIDs
    }
}

public enum HanlinPolicyDecisionResult: String, Codable, Hashable, Sendable {
    case allow
    case deny
}

public struct HanlinPolicyDecision: Codable, Hashable, Sendable {
    public let evaluationID: HanlinPolicyEvaluationID
    public let policyVersion: HanlinPolicyVersion
    public let result: HanlinPolicyDecisionResult
    public let matchedRuleIDs: [HanlinPolicyRuleID]
    public let obligations: [String]
    public let safeReason: String
    public let evaluatedAt: Date

    public init(
        evaluationID: HanlinPolicyEvaluationID,
        policyVersion: HanlinPolicyVersion,
        result: HanlinPolicyDecisionResult,
        matchedRuleIDs: [HanlinPolicyRuleID] = [],
        obligations: [String] = [],
        safeReason: String,
        evaluatedAt: Date
    ) {
        self.evaluationID = evaluationID
        self.policyVersion = policyVersion
        self.result = result
        self.matchedRuleIDs = matchedRuleIDs
        self.obligations = obligations
        self.safeReason = safeReason
        self.evaluatedAt = evaluatedAt
    }
}
