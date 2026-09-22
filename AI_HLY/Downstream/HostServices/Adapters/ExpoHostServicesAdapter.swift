import Foundation
import HanlinPlatformContracts
import HanlinMiniAppCore

/// Host services adapter for Expo/React Native Mini Apps.
/// Provides the first capability-gated host service bridge for the Expo engine.
@MainActor
final class ExpoHostServicesAdapter {
    let context: HanlinHostCallContext

    init(
        appID: HanlinAppID,
        installedPackageID: HanlinInstalledPackageID,
        grantedCapabilities: Set<String>
    ) {
        self.context = HanlinHostCallContext.forMiniApp(
            appID: appID,
            installedPackageID: installedPackageID,
            origin: .scriptPackage,
            capabilities: grantedCapabilities,
            canPresentUI: true
        )
    }

    func hasCapability(_ capability: String) -> Bool {
        let canonical = HanlinHostCapabilityAuthority.canonicalCapabilityID(capability)
        return context.effectiveCapabilities.contains(canonical)
            || context.effectiveCapabilities.contains("all")
    }

    func executeRuntime(
        _ kind: RuntimeKind,
        source: String,
        arguments: [String] = [],
        environment: [String: String] = [:],
        limits: RuntimeExecutionLimits? = nil
    ) async throws -> RuntimeExecutionResult {
        try await HanlinRuntimeBroker.shared.execute(
            kind: kind,
            source: source,
            context: context,
            arguments: arguments,
            environment: environment,
            limits: limits
        )
    }

    func invoke(operation: String, payloadJSON: String) async throws -> String {
        let payloadData = Data(payloadJSON.utf8)
        switch operation {
        case "capabilities.has":
            let request = try JSONDecoder().decode(CapabilityRequest.self, from: payloadData)
            return try Self.encode(["value": hasCapability(request.capability)])

        case "runtime.execute":
            let request = try JSONDecoder().decode(RuntimeRequest.self, from: payloadData)
            guard let kind = RuntimeKind(rawValue: request.kind) else {
                throw HanlinHostServiceError.invalidRequest("Unknown runtime kind: \(request.kind)")
            }
            let result = try await executeRuntime(
                kind,
                source: request.source,
                arguments: request.arguments ?? [],
                environment: request.environment ?? [:],
                limits: request.limits
            )
            return try Self.encode(result)

        case "files.read":
            let request = try JSONDecoder().decode(FileRequest.self, from: payloadData)
            let data = try await HanlinHostServicesBroker.shared.readFile(
                virtualPath: request.path,
                area: try Self.area(request.area),
                context: context
            )
            return try Self.encode(["base64": data?.base64EncodedString()])

        case "files.write":
            let request = try JSONDecoder().decode(FileWriteRequest.self, from: payloadData)
            guard let data = Data(base64Encoded: request.base64) else {
                throw HanlinHostServiceError.invalidRequest("files.write requires valid base64 data")
            }
            try await HanlinHostServicesBroker.shared.writeFile(
                virtualPath: request.path,
                area: try Self.area(request.area),
                data: data,
                context: context
            )
            return "{\"ok\":true}"

        case "files.delete":
            let request = try JSONDecoder().decode(FileRequest.self, from: payloadData)
            try await HanlinHostServicesBroker.shared.deleteFile(
                virtualPath: request.path,
                area: try Self.area(request.area),
                context: context
            )
            return "{\"ok\":true}"

        case "files.list":
            let request = try JSONDecoder().decode(FileListRequest.self, from: payloadData)
            let files = try await HanlinHostServicesBroker.shared.listFiles(
                area: try Self.area(request.area),
                context: context
            )
            return try Self.encode(["files": files])

        default:
            throw HanlinHostServiceError.invalidRequest("Unknown Expo Host Services operation: \(operation)")
        }
    }

    private static func area(_ value: String) throws -> HanlinMiniAppDataArea {
        switch value.lowercased() {
        case "data": .data
        case "documents": .documents
        case "state": .state
        case "cache": .cache
        default: throw HanlinHostServiceError.invalidRequest("Unknown MiniApp data area: \(value)")
        }
    }

    private static func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let result = String(data: data, encoding: .utf8) else {
            throw HanlinHostServiceError.invalidRequest("Host Services produced invalid UTF-8 JSON")
        }
        return result
    }
}

private struct CapabilityRequest: Decodable {
    let capability: String
}

private struct RuntimeRequest: Decodable {
    let kind: String
    let source: String
    let arguments: [String]?
    let environment: [String: String]?
    let limits: RuntimeExecutionLimits?
}

private struct FileRequest: Decodable {
    let path: String
    let area: String
}

private struct FileWriteRequest: Decodable {
    let path: String
    let area: String
    let base64: String
}

private struct FileListRequest: Decodable {
    let area: String
}
