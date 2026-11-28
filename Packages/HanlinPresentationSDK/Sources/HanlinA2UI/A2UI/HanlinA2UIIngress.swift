import Foundation

/// Shared ingress bounds. Transcript identity and transport remain with the host; schema validation stays upstream.
public enum HanlinA2UIIngress {
    public static let upstreamRevision = "3ed9601862ecc78027e20ac80ad8b1b98a5d9079"
    public static let catalogID = "https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json"
    public static let mediaCatalogID = "https://hanlin.ai/a2ui/catalogs/media/v1"
    public static let maximumMessageBytes = 65_536
    public static let maximumComponentsPerMessage = 64

    public enum Operation: String, Sendable {
        case createSurface, updateComponents, updateDataModel, deleteSurface
    }

    public struct Frame: Equatable, Sendable {
        public let operation: Operation
        public let surfaceID: String

        public init(operation: Operation, surfaceID: String) {
            self.operation = operation
            self.surfaceID = surfaceID
        }
    }

    public enum Failure: String, Error, Sendable {
        case messageTooLarge, malformedEnvelope, unsupportedVersion, unsupportedOperation
        case invalidSurfaceID, unsupportedCatalog, tooManyComponents
        case surfaceLimit, sessionBudget, sdkValidation, inputSealed, closed
    }

    /// Finite SDK codes only. Never store a raw path, message, identifier or unknown code.
    public struct SDKDiagnostic: Equatable, Sendable {
        private enum Code: String, Sendable {
            case invalidIdentifier = "invalid_identifier", invalidValue = "invalid_value"
            case typeMismatch = "type_mismatch", missingField = "missing_field"
            case unknownComponent = "unknown_component", unknownFunction = "unknown_function"
            case invalidFunctionCall = "invalid_function_call", tooManyArguments = "too_many_arguments"
            case validationFailed = "VALIDATION_FAILED", unallowedParent = "UNALLOWED_PARENT"
            case unallowedChild = "UNALLOWED_CHILD", integrityError = "INTEGRITY_ERROR"
            case recursionLimit = "RECURSION_LIMIT_EXCEEDED", dataError = "DATA_ERROR"
            case internalError = "INTERNAL_ERROR", expressionError = "EXPRESSION_ERROR"
            case parsingFailed = "PARSING_FAILED", invalidCall = "INVALID_FUNCTION_CALL"
            case surfaceNotFound = "SURFACE_NOT_FOUND", sdkError = "SDK_ERROR"
        }
        private let kind: Code
        public var code: String { kind.rawValue }

        public init(code: String) {
            kind = Code(rawValue: code) ?? .sdkError
        }
    }

    private static func safeSDKErrorType(_ raw: String) -> String {
        for name in ["A2UIValidationError", "A2UIIntegrityError", "A2UIRecursionError",
                     "A2UICatalogError", "A2UIDataError", "A2UIParseError"] {
            if raw == name || raw == "A2UICore." + name { return name }
        }
        return "A2UIError"
    }

    public struct Rejection: Error, Equatable, Sendable {
        public let failure: Failure
        public let surfaceID: String?
        public let sdkErrorType: String?
        public let diagnostics: [SDKDiagnostic]

        public init(_ failure: Failure, surfaceID: String? = nil,
             sdkErrorType: String? = nil, diagnostics: [SDKDiagnostic] = []) {
            self.failure = failure
            self.surfaceID = surfaceID
            self.sdkErrorType = sdkErrorType.map { HanlinA2UIIngress.safeSDKErrorType($0) }
            self.diagnostics = Array(diagnostics.prefix(8))
        }
    }

    /// Accepts one complete UTF-8 message. The official SDK owns all component/schema validation.
    /// Framing of a network stream and transport routing deliberately remain with the caller.
    public static func inspect(_ data: Data) throws -> Frame {
        guard data.count <= maximumMessageBytes else { throw Rejection(.messageTooLarge) }
        guard String(data: data, encoding: .utf8) != nil,
              let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw Rejection(.malformedEnvelope) }

        let operationKeys = envelope.keys.filter { $0 != "version" }
        guard operationKeys.count == 1, let key = operationKeys.first,
              let payload = envelope[key] as? [String: Any]
        else { throw Rejection(.malformedEnvelope) }
        let surfaceID = payload["surfaceId"] as? String
        guard let operation = Operation(rawValue: key) else {
            // Unknown operation semantics cannot establish a target, even with a plausible ID.
            throw Rejection(.unsupportedOperation)
        }
        guard let surfaceID, !surfaceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              surfaceID.utf8.count <= 128
        else { throw Rejection(.invalidSurfaceID) }
        guard envelope["version"] as? String == "1.0" else {
            throw Rejection(.unsupportedVersion)
        }
        // The shared ingress accepts the original negotiated catalogs; it does not add RPC authority.
        if operation == .createSurface {
            guard let requested = payload["catalogId"] as? String,
                  [catalogID, mediaCatalogID].contains(requested) else { throw Rejection(.unsupportedCatalog) }
        }
        if let components = payload["components"] as? [Any],
           components.count > maximumComponentsPerMessage {
            throw Rejection(.tooManyComponents)
        }
        return Frame(operation: operation, surfaceID: surfaceID)
    }
}
