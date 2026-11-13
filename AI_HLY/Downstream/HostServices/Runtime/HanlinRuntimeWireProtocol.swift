import Foundation

/// Shared NS/Expo JSON boundary into the existing runtime broker. Caller
/// identity and workspace always come from the bound host context.
enum HanlinRuntimeWireProtocol {
    private struct Request: Decodable {
        let kind: RuntimeKind
        let source: String
        let arguments: [String]?
        let environment: [String: String]?
        let limits: RuntimeExecutionLimits?
    }

    static func execute(_ payloadJSON: String, context: HanlinHostCallContext) async throws -> String {
        let request: Request
        do {
            request = try JSONDecoder().decode(Request.self, from: Data(payloadJSON.utf8))
        } catch {
            // Decoder descriptions may contain supplied source/environment data.
            throw HanlinHostServiceError.invalidRequest("Invalid runtime.execute request; use a canonical runtime kind, source string and typed options.")
        }
        if request.kind == .shell && !(request.arguments ?? []).isEmpty {
            throw HanlinHostServiceError.invalidRequest("Shell source is a complete approved command. Pass arguments in its source, not the separate runtime argv option.")
        }
        try Task.checkCancellation()
        let result = try await HanlinRuntimeBroker.shared.execute(kind: request.kind,
            source: request.source, context: context, arguments: request.arguments ?? [],
            environment: request.environment ?? [:], limits: request.limits)
        return String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
    }
}
