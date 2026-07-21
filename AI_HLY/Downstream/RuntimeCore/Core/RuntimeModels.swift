import Foundation

enum RuntimeKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case node
    case typeScript
    case localPython
    case javaScriptCore
    case shell

    var id: String { rawValue }
}

enum RuntimeOperationalState: String, Codable, Sendable {
    case unavailable
    case stopped
    case preparing
    case ready
    case executing
    case failed
    case appRestartRequired
}

struct RuntimeSnapshot: Codable, Identifiable, Sendable {
    var id: RuntimeKind { kind }
    let kind: RuntimeKind
    var state: RuntimeOperationalState
    var version: String?
    var source: String?
    var lastHealthCheck: Date?
    var lastErrorCode: String?
    var storageBytes: Int64?
    var cacheBytes: Int64?
    var activeExecutionCount: Int
    var packageCount: Int?

    static func stopped(_ kind: RuntimeKind) -> RuntimeSnapshot {
        RuntimeSnapshot(
            kind: kind,
            state: .stopped,
            version: nil,
            source: nil,
            lastHealthCheck: nil,
            lastErrorCode: nil,
            storageBytes: nil,
            cacheBytes: nil,
            activeExecutionCount: 0,
            packageCount: nil
        )
    }
}

struct RuntimeExecutionLimits: Codable, Hashable, Sendable {
    let timeout: Duration
    let maximumOutputBytes: Int

    init(timeout: Duration = .seconds(30), maximumOutputBytes: Int = 1_048_576) {
        self.timeout = min(max(timeout, .seconds(1)), .seconds(300))
        self.maximumOutputBytes = min(max(maximumOutputBytes, 1_024), 8 * 1_024 * 1_024)
    }

    private enum CodingKeys: String, CodingKey {
        case timeoutMilliseconds
        case maximumOutputBytes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            timeout: .milliseconds(try container.decode(Int64.self, forKey: .timeoutMilliseconds)),
            maximumOutputBytes: try container.decode(Int.self, forKey: .maximumOutputBytes)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timeout.components.seconds * 1_000 + Int64(timeout.components.attoseconds / 1_000_000_000_000_000), forKey: .timeoutMilliseconds)
        try container.encode(maximumOutputBytes, forKey: .maximumOutputBytes)
    }
}

struct RuntimeExecutionRequest: Sendable {
    let id: UUID
    let source: String
    let arguments: [String]
    let workspace: URL
    let environment: [String: String]
    let limits: RuntimeExecutionLimits

    init(
        id: UUID = UUID(),
        source: String,
        arguments: [String] = [],
        workspace: URL,
        environment: [String: String] = [:],
        limits: RuntimeExecutionLimits = RuntimeExecutionLimits()
    ) {
        self.id = id
        self.source = source
        self.arguments = arguments
        self.workspace = workspace
        self.environment = environment
        self.limits = limits
    }
}

struct RuntimeExecutionResult: Codable, Sendable {
    let executionID: UUID
    let stdout: String
    let stderr: String
    let value: RuntimeJSONValue?
    let exitCode: Int?
    let durationMilliseconds: Int64
    let didTimeOut: Bool
    let wasCancelled: Bool
    let outputWasTruncated: Bool
}

enum RuntimeJSONValue: Codable, Hashable, Sendable {
    case null
    case boolean(Bool)
    case number(Double)
    case string(String)
    case array([RuntimeJSONValue])
    case object([String: RuntimeJSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .boolean(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([RuntimeJSONValue].self) { self = .array(value) }
        else if let value = try? container.decode([String: RuntimeJSONValue].self) { self = .object(value) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value") }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .boolean(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

enum RuntimeCoreError: Error, Equatable, Sendable {
    case invalidPath
    case pathEscapesRoot
    case symbolicLinkRejected
    case invalidIdentifier
    case invalidEnvironmentName
    case reservedEnvironmentName
    case runtimeUnavailable(RuntimeKind)
    case appRestartRequired(RuntimeKind)
    case executionTimedOut
    case executionCancelled
    case outputLimitExceeded
    case invalidDependencyManifest
    case invalidRequest(String)
    case requestFailed(Int, String)
    case runtimeFailure(String)
}

extension RuntimeCoreError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidPath: "The requested path is invalid."
        case .pathEscapesRoot: "The requested path is outside the permitted workspace."
        case .symbolicLinkRejected: "Symbolic links may not escape the permitted workspace."
        case .invalidIdentifier: "The identifier is invalid."
        case .invalidEnvironmentName: "The environment variable name is invalid."
        case .reservedEnvironmentName: "That environment variable is managed by RuntimeCore."
        case .runtimeUnavailable(let kind): "The \(kind.rawValue) runtime is unavailable."
        case .appRestartRequired(let kind): "The \(kind.rawValue) runtime stopped and the app must be restarted."
        case .executionTimedOut: "Execution timed out."
        case .executionCancelled: "Execution was cancelled."
        case .outputLimitExceeded: "Execution output exceeded the configured limit."
        case .invalidDependencyManifest: "The bundled runtime manifest is invalid."
        case .invalidRequest(let message), .runtimeFailure(let message): message
        case .requestFailed(let status, let message): "Runtime request failed (HTTP \(status)): \(message)"
        }
    }
}

struct RuntimeManifest: Codable, Sendable {
    struct BundleRecord: Codable, Sendable {
        let formatVersion: Int
        let releaseRepository: String
        let releaseTagPrefix: String
        let sha256: String?
        let verificationStatus: String
    }

    struct RuntimeRecord: Codable, Identifiable, Sendable {
        let id: String
        let sourceProject: String
        let version: String
        let revision: String
        let license: String
        let bundleHash: String?
        let componentHashes: [String: String]?
        let verificationStatus: String
    }

    let schemaVersion: Int
    let runtimeBundle: BundleRecord
    let runtimes: [RuntimeRecord]
}
