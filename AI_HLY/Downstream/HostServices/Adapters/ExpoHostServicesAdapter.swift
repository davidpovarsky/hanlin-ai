import Foundation
import HanlinPlatformContracts
import HanlinMiniAppCore
import HanlinExpoRuntime
import HanlinScriptUI

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
        let validatedSessionID = (try? HanlinAppSessionID(validating: sessionID))
            ?? (try! HanlinAppSessionID(validating: UUID().uuidString.lowercased()))
        self.sessionID = validatedSessionID.rawValue
        self.context = HanlinHostCallContext.forMiniApp(
            appID: appID,
            installedPackageID: installedPackageID,
            origin: .scriptPackage,
            capabilities: grantedCapabilities,
            sessionID: validatedSessionID,
            canPresentUI: true
        )
        super.init()
    }

    public func hasCapability(_ capability: String) -> Bool {
        let canonical = HanlinHostCapabilityAuthority.canonicalCapabilityID(capability)
        let standardCapabilities: Set<String> = [
            "ios-native-api", "network", "storage", "files", "widget", "appIntent"
        ]
        if standardCapabilities.contains(canonical) {
            return true
        }
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

        case "widgets.publish":
            guard let installedPackageID = context.installedPackageID,
                  let appID = context.appID else {
                throw HanlinHostServiceError.invalidRequest("widgets.publish requires authenticated package and app context")
            }
            guard let jsonObject = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
                  let entrypointID = jsonObject["entrypointID"] as? String,
                  let family = jsonObject["family"] as? String,
                  let rootDict = jsonObject["root"] as? [String: Any] else {
                throw HanlinHostServiceError.invalidRequest("widgets.publish requires valid JSON payload with entrypointID, family, and root node")
            }

            // Path traversal rejection
            guard !entrypointID.isEmpty,
                  !entrypointID.contains("/"),
                  !entrypointID.contains("\\"),
                  !entrypointID.contains(".."),
                  !entrypointID.contains("\0") else {
                throw HanlinHostServiceError.invalidRequest("Invalid entrypoint ID format: directory traversal prohibited")
            }

            let parsedRoot = try Self.parseUntaggedNode(rootDict, depth: 0)
            let validUntilDate = try Self.parseValidUntil(from: jsonObject)

            try await HanlinScriptingPlatform.shared.publishExpoWidget(
                installedPackageID: installedPackageID,
                appID: appID,
                entrypointID: entrypointID,
                family: family,
                root: parsedRoot,
                validUntil: validUntilDate
            )
            return "{\"ok\":true}"

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

extension ExpoHostServicesAdapter {
    static func parseValidUntil(from dict: [String: Any]) throws -> Date? {
        if let millisVal = dict["validUntilEpochMilliseconds"] {
            let millis: Double
            if let d = millisVal as? Double {
                millis = d
            } else if let i = millisVal as? Int64 {
                millis = Double(i)
            } else if let i = millisVal as? Int {
                millis = Double(i)
            } else if let s = millisVal as? String, let d = Double(s) {
                millis = d
            } else {
                throw HanlinHostServiceError.invalidRequest("Invalid 'validUntilEpochMilliseconds' type: expected number or numeric string")
            }

            guard !millis.isNaN, !millis.isInfinite, millis > 0 else {
                throw HanlinHostServiceError.invalidRequest("Invalid 'validUntilEpochMilliseconds': must be a positive finite number")
            }
            guard millis <= 4_102_444_800_000 else { // Year 2100 in milliseconds
                throw HanlinHostServiceError.invalidRequest("Invalid 'validUntilEpochMilliseconds': timestamp exceeds realistic upper bound")
            }

            let date = Date(timeIntervalSince1970: millis / 1000.0)
            guard date > Date() else {
                throw HanlinHostServiceError.invalidRequest("Widget snapshot validUntil timestamp has already expired")
            }
            return date
        }

        if let validUntilVal = dict["validUntil"] {
            guard let validUntilStr = validUntilVal as? String, !validUntilStr.isEmpty else {
                throw HanlinHostServiceError.invalidRequest("Invalid 'validUntil' format: expected non-empty ISO8601 string")
            }

            let formatterWithFraction = ISO8601DateFormatter()
            formatterWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let date: Date
            if let d = formatterWithFraction.date(from: validUntilStr) {
                date = d
            } else {
                let standardFormatter = ISO8601DateFormatter()
                standardFormatter.formatOptions = [.withInternetDateTime]
                if let d = standardFormatter.date(from: validUntilStr) {
                    date = d
                } else if let dbl = Double(validUntilStr), !dbl.isNaN, !dbl.isInfinite, dbl > 0 {
                    date = Date(timeIntervalSince1970: dbl > 1_000_000_000_000 ? dbl / 1000.0 : dbl)
                } else {
                    throw HanlinHostServiceError.invalidRequest("Malformed 'validUntil' date string: unable to parse as ISO8601 date")
                }
            }

            guard date > Date() else {
                throw HanlinHostServiceError.invalidRequest("Widget snapshot validUntil timestamp has already expired")
            }
            return date
        }

        return nil
    }

    static func toHanlinValue(_ any: Any) throws -> HanlinValue {
        switch any {
        case is NSNull:
            return .null
        case let n as NSNumber:
            // CFBoolean must strictly precede numeric integer/double conversion
            if CFGetTypeID(n as CFTypeRef) == CFBooleanGetTypeID() {
                return .bool(n.boolValue)
            }
            let dbl = n.doubleValue
            guard !dbl.isNaN, !dbl.isInfinite else {
                throw HanlinHostServiceError.invalidRequest("NaN and Infinity are not valid Hanlin numeric values")
            }
            if floor(dbl) == dbl && dbl >= Double(Int64.min) && dbl <= Double(Int64.max) {
                return .integer(n.int64Value)
            }
            return try HanlinValue.finiteNumber(dbl)
        case let s as String:
            guard s.utf8.count <= 1_048_576 else {
                throw HanlinHostServiceError.invalidRequest("String value exceeds maximum allowed byte limit (1MB)")
            }
            return .string(s)
        case let arr as [Any]:
            guard arr.count <= 4_096 else {
                throw HanlinHostServiceError.invalidRequest("Array value exceeds maximum item count (4096)")
            }
            return .array(try arr.map { try toHanlinValue($0) })
        case let dict as [String: Any]:
            guard dict.count <= 1_024 else {
                throw HanlinHostServiceError.invalidRequest("Object value exceeds maximum member count (1024)")
            }
            var members: [(key: String, value: HanlinValue)] = []
            for (k, v) in dict {
                guard k.utf8.count <= 256 else {
                    throw HanlinHostServiceError.invalidRequest("Object member key exceeds 256 bytes")
                }
                members.append((key: k, value: try toHanlinValue(v)))
            }
            return .object(try HanlinObject(uniqueMembers: members))
        default:
            throw HanlinHostServiceError.invalidRequest("Unsupported property value type in UI node: \(type(of: any))")
        }
    }

    private static func parseUntaggedNodeInternal(_ dict: [String: Any], depth: Int, nodeCounter: inout Int) throws -> HanlinScriptUINode {
        nodeCounter += 1
        guard nodeCounter <= 1_000 else {
            throw HanlinHostServiceError.invalidRequest("Widget UI hierarchy exceeds maximum allowed node count (1000)")
        }
        guard depth < 64 else {
            throw HanlinHostServiceError.invalidRequest("Widget UI hierarchy depth exceeds maximum allowed limit (64)")
        }
        guard let kindStr = dict["kind"] as? String else {
            throw HanlinHostServiceError.invalidRequest("Missing 'kind' in UI node")
        }
        guard let primitive = HanlinScriptUIPrimitive(rawValue: kindStr) else {
            throw HanlinHostServiceError.invalidRequest("Unknown or disallowed UI primitive kind: '\(kindStr)'")
        }
        let key = dict["key"] as? String
        var properties: [String: HanlinValue] = [:]
        if let propsDict = dict["properties"] as? [String: Any] {
            guard propsDict.count <= 256 else {
                throw HanlinHostServiceError.invalidRequest("UI node properties count exceeds maximum limit (256)")
            }
            for (k, v) in propsDict {
                properties[k] = try toHanlinValue(v)
            }
        }
        var children: [HanlinScriptUINode] = []
        if let childrenArr = dict["children"] as? [[String: Any]] {
            guard childrenArr.count <= 256 else {
                throw HanlinHostServiceError.invalidRequest("UI node children count exceeds maximum limit (256)")
            }
            for childDict in childrenArr {
                children.append(try parseUntaggedNodeInternal(childDict, depth: depth + 1, nodeCounter: &nodeCounter))
            }
        }
        return HanlinScriptUINode(
            kind: primitive,
            key: key,
            properties: properties,
            children: children
        )
    }

    public static func parseUntaggedNode(_ dict: [String: Any], depth: Int = 0) throws -> HanlinScriptUINode {
        var counter = 0
        return try parseUntaggedNodeInternal(dict, depth: depth, nodeCounter: &counter)
    }
}
