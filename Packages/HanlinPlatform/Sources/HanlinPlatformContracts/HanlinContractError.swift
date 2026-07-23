import Foundation

public enum HanlinContractError: Error, Hashable, Sendable {
    case invalidIdentifier(kind: String, value: String, reason: String)
    case invalidVersion(kind: String, value: String)
    case invalidVersionRange(minimum: String, maximum: String)
    case unsupportedVersion(kind: String, received: String, supported: String)
    case invalidLocalizedValue(reason: String)
    case invalidNumber(Double)
    case invalidSchema(reason: String)
    case invalidManifest([HanlinManifestIssue])
    case invalidWireEnvelope(reason: String)
}

extension HanlinContractError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .invalidIdentifier(kind, value, reason):
            "\(kind) identifier '\(value)' is invalid: \(reason)"
        case let .invalidVersion(kind, value):
            "\(kind) version '\(value)' is invalid."
        case let .invalidVersionRange(minimum, maximum):
            "Version range minimum '\(minimum)' exceeds maximum '\(maximum)'."
        case let .unsupportedVersion(kind, received, supported):
            "Unsupported \(kind) version '\(received)'; supported: \(supported)."
        case let .invalidLocalizedValue(reason):
            "Localized value is invalid: \(reason)"
        case let .invalidNumber(value):
            "Non-finite number '\(value)' cannot cross a Hanlin contract boundary."
        case let .invalidSchema(reason):
            "JSON schema is invalid: \(reason)"
        case let .invalidManifest(issues):
            "Manifest is invalid: \(issues.map(\.message).joined(separator: "; "))"
        case let .invalidWireEnvelope(reason):
            "Wire envelope is invalid: \(reason)"
        }
    }
}

public enum HanlinErrorCode: String, Codable, CaseIterable, Hashable, Sendable {
    case manifestInvalid = "manifest_invalid"
    case apiVersionUnsupported = "api_version_unsupported"
    case capabilityNotDeclared = "capability_not_declared"
    case permissionDenied = "permission_denied"
    case systemPermissionDenied = "system_permission_denied"
    case operationUnavailable = "operation_unavailable"
    case extensionContextUnsupported = "extension_context_unsupported"
    case distributionPolicyDenied = "distribution_policy_denied"
    case invalidArguments = "invalid_arguments"
    case resourceLimitExceeded = "resource_limit_exceeded"
    case cancelled
    case timedOut = "timed_out"
    case scriptException = "script_exception"
    case nativeFailure = "native_failure"
    case packageIntegrityFailed = "package_integrity_failed"
}

public struct HanlinPlatformError: Error, Codable, Hashable, Sendable {
    public let code: HanlinErrorCode
    public let userMessage: String
    public let diagnosticMessage: String?
    public let details: HanlinValue?

    public init(
        code: HanlinErrorCode,
        userMessage: String,
        diagnosticMessage: String? = nil,
        details: HanlinValue? = nil
    ) {
        self.code = code
        self.userMessage = userMessage
        self.diagnosticMessage = diagnosticMessage
        self.details = details
    }
}
