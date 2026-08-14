import Foundation

public enum HanlinContractError: Error, Hashable, Sendable {
    case invalidIdentifier(kind: String, value: String, reason: String)
    case invalidVersion(kind: String, value: String)
    case invalidVersionRange(minimum: String, maximum: String)
    case invalidRevision(kind: String, value: UInt64)
    case unsupportedVersion(kind: String, received: String, supported: String)
    case invalidLocalizedValue(reason: String)
    case invalidNumber(Double)
    case integerOutOfRange(value: String, destination: String, path: String)
    case integerNotExact(value: String, destination: String, path: String)
    case binaryNotRepresentable(destination: String, path: String)
    case duplicateObjectKey(key: String, path: String)
    case depthLimitExceeded(maximum: Int, path: String)
    case sizeLimitExceeded(kind: String, measured: Int, maximum: Int, path: String)
    case invalidJSON(reason: String, byteOffset: Int)
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
        case let .invalidRevision(kind, value):
            "\(kind) revision '\(value)' is invalid. Revisions begin at one."
        case let .unsupportedVersion(kind, received, supported):
            "Unsupported \(kind) version '\(received)'; supported: \(supported)."
        case let .invalidLocalizedValue(reason):
            "Localized value is invalid: \(reason)"
        case let .invalidNumber(value):
            "Non-finite number '\(value)' cannot cross a Hanlin contract boundary."
        case let .integerOutOfRange(value, destination, path):
            "Integer '\(value)' at '\(path)' is outside the exact range of \(destination)."
        case let .integerNotExact(value, destination, path):
            "Integer '\(value)' at '\(path)' is not exactly representable by \(destination)."
        case let .binaryNotRepresentable(destination, path):
            "Binary data at '\(path)' is not representable by \(destination) without an explicit schema transform."
        case let .duplicateObjectKey(key, path):
            "Object key '\(key)' is duplicated at '\(path)'."
        case let .depthLimitExceeded(maximum, path):
            "Value nesting at '\(path)' exceeds the maximum depth of \(maximum)."
        case let .sizeLimitExceeded(kind, measured, maximum, path):
            "\(kind) at '\(path)' measures \(measured); maximum is \(maximum)."
        case let .invalidJSON(reason, byteOffset):
            "JSON is invalid at UTF-8 byte offset \(byteOffset): \(reason)"
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
    case invalidIdentifier = "invalid_identifier"
    case invalidVersion = "invalid_version"
    case nonFiniteNumber = "non_finite_number"
    case integerOutOfRange = "integer_out_of_range"
    case integerNotExact = "integer_not_exact"
    case binaryNotRepresentable = "binary_not_representable"
    case duplicateObjectKey = "duplicate_object_key"
    case unsupportedSchemaKeyword = "unsupported_schema_keyword"
    case schemaProjectionWidensInput = "schema_projection_widens_input"
    case depthLimitExceeded = "depth_limit_exceeded"
    case sizeLimitExceeded = "size_limit_exceeded"
    case invalidJSON = "invalid_json"
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
