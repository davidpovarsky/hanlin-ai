import Foundation

/// Bounds for the isolated POC, not a persisted chat envelope or an A2UI implementation.
enum HanlinA2UIIngress {
    static let upstreamRevision = "3ed9601862ecc78027e20ac80ad8b1b98a5d9079"
    static let catalogID = "https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json"
    static let maximumMessageBytes = 65_536
    static let maximumComponentsPerMessage = 64

    enum Operation: String, Sendable {
        case createSurface, updateComponents, updateDataModel, deleteSurface
    }

    struct Frame: Equatable, Sendable {
        let operation: Operation
        let surfaceID: String
    }

    enum Failure: String, Error, Sendable {
        case messageTooLarge, malformedEnvelope, unsupportedVersion, unsupportedOperation
        case invalidSurfaceID, unsupportedCatalog, tooManyComponents
        case surfaceLimit, sessionBudget, sdkValidation, closed
    }

    /// SDK diagnostic metadata only; never payload values or an alternative routing authority.
    struct SDKDiagnostic: Equatable, Sendable {
        let code: String
        let path: String

        init(code: String, path: String) {
            self.code = String(code.prefix(96))
            self.path = String(path.prefix(256))
        }
    }

    struct Rejection: Error, Equatable, Sendable {
        let failure: Failure
        let surfaceID: String?
        let sdkErrorType: String?
        let diagnostics: [SDKDiagnostic]

        init(_ failure: Failure, surfaceID: String? = nil,
             sdkErrorType: String? = nil, diagnostics: [SDKDiagnostic] = []) {
            self.failure = failure
            self.surfaceID = surfaceID
            self.sdkErrorType = sdkErrorType.map { String($0.prefix(96)) }
            self.diagnostics = Array(diagnostics.prefix(8))
        }
    }

    /// Accepts one complete UTF-8 message. The official SDK owns all component/schema validation.
    /// Framing of a network stream and transport routing deliberately remain with the caller.
    static func inspect(_ data: Data) throws -> Frame {
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
        // This POC deliberately does not negotiate custom/defaultless catalogs or RPC.
        if operation == .createSurface, payload["catalogId"] as? String != catalogID {
            throw Rejection(.unsupportedCatalog)
        }
        if let components = payload["components"] as? [Any],
           components.count > maximumComponentsPerMessage {
            throw Rejection(.tooManyComponents)
        }
        return Frame(operation: operation, surfaceID: surfaceID)
    }
}
