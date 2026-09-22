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

    public func executeRuntime(
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
        let data = try await HanlinHostServicesBroker.shared.readFile(at: path, area: dataArea, context: context)
        guard let str = String(data: data, encoding: .utf8) else {
            throw HanlinHostServiceError.fileOperationFailed("Failed to decode file as UTF-8 string: \(path)")
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
        try await HanlinHostServicesBroker.shared.writeFile(at: path, data: data, area: dataArea, context: context)
    }

    public func executeSQLite(sql: String, params: [Any]?) async throws -> [[String: Any]] {
        return try await HanlinSQLiteHostAdapter.shared.fetchAll(handle: "default", sql: sql, arguments: params, context: context)
    }

    public func fetchURL(urlString: String) async throws -> String {
        try await HanlinHostServicesBroker.shared.requireCapability("network", context: context)
        guard let url = URL(string: urlString), url.scheme?.lowercased() == "https" else {
            throw HanlinHostServiceError.invalidPath("Invalid or non-HTTPS URL: \(urlString)")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw HanlinHostServiceError.runtimeExecutionFailed("Invalid server response.")
        }
        guard (200...299).contains(http.statusCode) else {
            throw HanlinHostServiceError.runtimeExecutionFailed("HTTP \(http.statusCode) error")
        }
        return "HTTPS \(http.statusCode), \(data.count) bytes"
    }
}
