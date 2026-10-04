import Foundation
import HanlinPlatformContracts
import HanlinMiniAppCore
import HanlinExpoRuntime

/// Host services adapter for Expo/React Native Mini Apps.
/// Bridges Expo native modules into Unified Host Services and Capability Authority.
public final class ExpoHostServicesAdapter: NSObject, @unchecked Sendable, HanlinExpoHostServicesProvider {
    public let sessionID: String
    public let context: HanlinHostCallContext

    public init(
        appID: HanlinAppID,
        installedPackageID: HanlinInstalledPackageID? = nil,
        grantedCapabilities: Set<String>,
        sessionID: String = UUID().uuidString.lowercased()
    ) {
        self.sessionID = sessionID
        let appSession = try! HanlinAppSessionID(validating: sessionID)
        self.context = HanlinHostCallContext.forMiniApp(
            appID: appID,
            installedPackageID: installedPackageID,
            origin: .scriptPackage,
            capabilities: grantedCapabilities,
            sessionID: appSession,
            canPresentUI: true
        )
        super.init()
    }

    public func hasCapability(_ capability: String) -> Bool {
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

    public func invoke(operation: String, payloadJSON: String) async throws -> String {
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

    // MARK: - HanlinExpoHostServicesProvider Conformance

    public func executeRuntime(kind: String, source: String) async throws -> String {
        let runtimeKind: RuntimeKind = switch kind.lowercased() {
        case "node": .node
        case "python": .localPython
        default: .javaScriptCore
        }
        let result = try await HanlinRuntimeBroker.shared.execute(
            kind: runtimeKind,
            source: source,
            context: context
        )
        let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if output.isEmpty, let val = result.value {
            switch val {
            case let .string(s): return s
            case let .number(n): return n.truncatingRemainder(dividingBy: 1) == 0 ? String(Int64(n)) : String(n)
            case let .boolean(b): return String(b)
            case .null: return "null"
            default: break
            }
        }
        return output.isEmpty ? "OK" : output
    }

    public func executeNode(source: String) async throws -> String {
        return try await executeRuntime(kind: "node", source: source)
    }

    public func executePython(source: String) async throws -> String {
        return try await executeRuntime(kind: "python", source: source)
    }

    public func readFile(path: String, area: String) async throws -> String {
        let dataArea: HanlinMiniAppDataArea = switch area.lowercased() {
        case "documents": .documents
        case "state": .state
        case "cache": .cache
        default: .data
        }
        let data = try await HanlinHostServicesBroker.shared.readFile(virtualPath: path, area: dataArea, context: context)
        guard let str = String(data: data ?? Data(), encoding: .utf8) else {
            throw HanlinHostServiceError.invalidRequest("Failed to decode file as UTF-8 string: \(path)")
        }
        return str
    }

    public func writeFile(path: String, content: String, area: String) async throws {
        let dataArea: HanlinMiniAppDataArea = switch area.lowercased() {
        case "documents": .documents
        case "state": .state
        case "cache": .cache
        default: .data
        }
        let data = content.data(using: .utf8) ?? Data()
        try await HanlinHostServicesBroker.shared.writeFile(virtualPath: path, area: dataArea, data: data, context: context)
    }

    public func executeSQLite(sql: String, params: [String]?) async throws -> String {
        return try await HanlinSQLiteHostAdapter.shared.fetchAllJSON(handle: "default", sql: sql, arguments: params, context: context)
    }

    public func fetchURL(urlString: String) async throws -> String {
        try await HanlinHostServicesBroker.shared.requireCapability("network", context: context)
        guard let url = URL(string: urlString), url.scheme?.lowercased() == "https" else {
            throw HanlinHostServiceError.invalidRequest("Invalid or non-HTTPS URL: \(urlString)")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HanlinHostServiceError.invalidRequest("Invalid server response.")
        }
        guard (200...299).contains(http.statusCode) else {
            throw HanlinHostServiceError.invalidRequest("HTTP \(http.statusCode) error")
        }
        return "HTTPS \(http.statusCode), \(data.count) bytes"
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
