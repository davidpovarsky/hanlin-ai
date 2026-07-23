import Foundation
import Security
import ZIPFoundation

private struct RuntimeHostReadyFile: Codable, Sendable {
    let port: Int
    let nodeVersion: String
    let protocolVersion: Int
    let modulePolicyHooksAvailable: Bool
}

struct RuntimeHostConnection: Sendable {
    let baseURL: URL
    private let token: String

    init(baseURL: URL, token: String) {
        self.baseURL = baseURL
        self.token = token
    }

    func request(path: String, method: String = "GET", body: Data? = nil, timeout: TimeInterval = 60) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = timeout
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }

    func data(path: String, method: String = "GET", body: Data? = nil, timeout: TimeInterval = 60) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request(path: path, method: method, body: body, timeout: timeout))
        guard let http = response as? HTTPURLResponse else { throw RuntimeCoreError.runtimeFailure("The runtime host returned an invalid response.") }
        guard 200..<300 ~= http.statusCode else {
            let decoded = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw RuntimeCoreError.requestFailed(http.statusCode, decoded ?? String(decoding: data.prefix(16_384), as: UTF8.self))
        }
        return data
    }

    func decode<T: Decodable>(_ type: T.Type, path: String, method: String = "GET", body: Data? = nil, timeout: TimeInterval = 60) async throws -> T {
        try JSONDecoder().decode(T.self, from: await data(path: path, method: method, body: body, timeout: timeout))
    }
}

struct TypeScriptCompilationResult: Codable, Sendable {
    struct Diagnostic: Codable, Sendable, Identifiable {
        let code: Int
        let message: String
        let line: Int?
        let column: Int?
        var id: String { "\(code):\(line ?? 0):\(column ?? 0):\(message)" }
    }

    let javaScript: String?
    let sourceMap: String?
    let diagnostics: [Diagnostic]
    let succeeded: Bool
}

struct TypeScriptProjectCompilationResult: Codable, Sendable {
    let diagnostics: [TypeScriptCompilationResult.Diagnostic]
    let emittedFiles: [String]
    let succeeded: Bool
}

enum NodeHostHealthFailure: String, Sendable {
    case cancelled
    case transient
    case unreachable
    case protocolFailure
}

actor NodeRuntimeService {
    static let expectedNodeVersion = "24.5.0"
    static let hostProtocolVersion = 2

    private struct HostExecutionResponse: Decodable {
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

    private let fileLayout: RuntimeFileLayout
    private var connection: RuntimeHostConnection?
    private var snapshotValue = RuntimeSnapshot.stopped(.node)
    private var launchAttempted = false
    private var nativeLaunchSucceeded = false
    private var launchTask: Task<RuntimeHostConnection, Error>?

    init(fileLayout: RuntimeFileLayout = .default) {
        self.fileLayout = fileLayout
    }

    func snapshot() -> RuntimeSnapshot { snapshotValue }

    func ensureRunning(debug: Bool = false) async throws -> RuntimeHostConnection {
        if let connection {
            return try await verifyExistingConnection(connection)
        }
        if let launchTask {
            return try await launchTask.value
        }
        guard !launchAttempted else {
            if nativeLaunchSucceeded {
                snapshotValue.state = .appRestartRequired
                snapshotValue.healthCategory = NodeHostHealthFailure.unreachable.rawValue
                snapshotValue.lastErrorCode = "node_process_unreachable"
                throw RuntimeCoreError.appRestartRequired(.node)
            }
            throw RuntimeCoreError.runtimeUnavailable(.node)
        }
        launchAttempted = true
        snapshotValue.state = .preparing
        let task = Task { [weak self] () throws -> RuntimeHostConnection in
            guard let self else { throw CancellationError() }
            return try await self.launchHost(debug: debug)
        }
        launchTask = task
        do {
            return try await task.value
        } catch is CancellationError {
            snapshotValue.healthCategory = NodeHostHealthFailure.cancelled.rawValue
            snapshotValue.lastDiagnostic = "Node host startup observation was cancelled; the shared launch continues."
            throw CancellationError()
        } catch {
            snapshotValue.state = .failed
            snapshotValue.lastErrorCode = String(describing: error)
            throw error
        }
    }

    func healthCheck() async throws -> RuntimeSnapshot {
        _ = try await ensureRunning()
        snapshotValue.lastHealthCheck = .now
        return snapshotValue
    }

    func healthCheckIfLaunched() async throws -> RuntimeSnapshot {
        guard launchAttempted else { return snapshotValue }
        if let launchTask {
            _ = try await launchTask.value
            return snapshotValue
        }
        guard let connection else { return snapshotValue }
        _ = try await verifyExistingConnection(connection)
        return snapshotValue
    }

    func executeJavaScript(_ request: RuntimeExecutionRequest, moduleKind: String = "esm") async throws -> RuntimeExecutionResult {
        let workspace = try fileLayout.validatedDescendant(request.workspace, of: fileLayout.clients, allowRoot: false)
        let host = try await ensureRunning()
        snapshotValue.state = .executing
        snapshotValue.activeExecutionCount += 1
        defer {
            snapshotValue.activeExecutionCount = max(0, snapshotValue.activeExecutionCount - 1)
            snapshotValue.state = .ready
        }
        let milliseconds = request.limits.timeout.components.seconds * 1_000
            + Int64(request.limits.timeout.components.attoseconds / 1_000_000_000_000_000)
        let body = try JSONSerialization.data(withJSONObject: [
            "executionID": request.id.uuidString.lowercased(),
            "source": request.source,
            "arguments": request.arguments,
            "workspace": workspace.path,
            "environment": request.environment,
            "moduleKind": moduleKind,
            "timeoutMilliseconds": milliseconds,
            "maximumOutputBytes": request.limits.maximumOutputBytes
        ])
        let payload = try await host.decode(
            HostExecutionResponse.self,
            path: "/v1/executions",
            method: "POST",
            body: body,
            timeout: TimeInterval(max(5, milliseconds / 1_000 + 5))
        )
        return RuntimeExecutionResult(
            executionID: payload.executionID,
            stdout: payload.stdout,
            stderr: payload.stderr,
            value: payload.value,
            exitCode: payload.exitCode,
            durationMilliseconds: payload.durationMilliseconds,
            didTimeOut: payload.didTimeOut,
            wasCancelled: payload.wasCancelled,
            outputWasTruncated: payload.outputWasTruncated
        )
    }

    func cancelExecution(id: UUID) async {
        guard let connection else { return }
        _ = try? await connection.data(path: "/v1/executions/\(id.uuidString.lowercased())/cancel", method: "POST", body: Data("{}".utf8), timeout: 3)
    }

    func compileTypeScript(source: String, fileName: String = "main.ts", tsconfig: [String: RuntimeJSONValue]? = nil) async throws -> TypeScriptCompilationResult {
        let host = try await ensureRunning()
        var body: [String: Any] = ["source": source, "fileName": fileName]
        if let tsconfig {
            let encoded = try JSONEncoder().encode(tsconfig)
            body["tsconfig"] = try JSONSerialization.jsonObject(with: encoded)
        }
        let encodedBody = try JSONSerialization.data(withJSONObject: body)
        return try await host.decode(TypeScriptCompilationResult.self, path: "/v1/typescript/compile", method: "POST", body: encodedBody)
    }

    func compileTypeScriptProject(workspace: URL, arguments: [String]) async throws -> TypeScriptProjectCompilationResult {
        let scopedWorkspace = try fileLayout.validatedDescendant(workspace, of: fileLayout.clients, allowRoot: false)
        let host = try await ensureRunning()
        let body = try JSONSerialization.data(withJSONObject: [
            "workspace": scopedWorkspace.path,
            "arguments": arguments
        ])
        return try await host.decode(
            TypeScriptProjectCompilationResult.self,
            path: "/v1/typescript/project",
            method: "POST",
            body: body,
            timeout: 300
        )
    }

    func currentConnection() async throws -> RuntimeHostConnection {
        try await ensureRunning()
    }

    private func launchHost(debug: Bool) async throws -> RuntimeHostConnection {
        defer { launchTask = nil }
        try fileLayout.prepareIfNeeded()
        let hostURL = try prepareHostRuntime()
        let readyURL = fileLayout.nodeRuntime.appending(path: "ready-\(UUID().uuidString).json")
        let token = try makeToken()
        let arguments = [
            "node",
            hostURL.appending(path: "host.mjs").path,
            fileLayout.root.path,
            readyURL.path,
            token,
            fileLayout.logs.appending(path: "node-runtime.log").path,
            debug ? "1" : "0"
        ]
        try NodeRuntimeBridge.start(arguments: arguments)
        nativeLaunchSucceeded = true
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while ContinuousClock.now < deadline {
            if FileManager.default.fileExists(atPath: readyURL.path) {
                let ready = try JSONDecoder().decode(
                    RuntimeHostReadyFile.self,
                    from: Data(contentsOf: readyURL)
                )
                try? FileManager.default.removeItem(at: readyURL)
                guard ready.nodeVersion == Self.expectedNodeVersion,
                      ready.protocolVersion == Self.hostProtocolVersion else {
                    throw RuntimeCoreError.runtimeFailure(
                        "Expected Node \(Self.expectedNodeVersion) and host protocol \(Self.hostProtocolVersion), received Node \(ready.nodeVersion) and protocol \(ready.protocolVersion)."
                    )
                }
                guard ready.modulePolicyHooksAvailable else {
                    throw RuntimeCoreError.runtimeFailure(
                        "Embedded Node \(ready.nodeVersion) does not provide module.registerHooks; MCP package code will not run unguarded."
                    )
                }
                guard let url = URL(string: "http://127.0.0.1:\(ready.port)") else {
                    throw RuntimeCoreError.runtimeFailure(
                        "The runtime host produced an invalid loopback address."
                    )
                }
                let host = RuntimeHostConnection(baseURL: url, token: token)
                _ = try await host.data(path: "/health", timeout: 3)
                connection = host
                snapshotValue.state = .ready
                snapshotValue.version = ready.nodeVersion
                snapshotValue.source = "heylogin/nodejs-mobile"
                snapshotValue.lastHealthCheck = .now
                snapshotValue.lastErrorCode = nil
                snapshotValue.healthCategory = nil
                snapshotValue.lastDiagnostic = "Embedded Node host launched once and passed its health check."
                return host
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        snapshotValue.healthCategory = NodeHostHealthFailure.unreachable.rawValue
        snapshotValue.lastDiagnostic = "The launched Node host did not publish readiness before the bounded deadline."
        throw RuntimeCoreError.runtimeFailure("Embedded Node startup timed out.")
    }

    private func verifyExistingConnection(
        _ existing: RuntimeHostConnection
    ) async throws -> RuntimeHostConnection {
        var lastFailure: Error?
        var category = NodeHostHealthFailure.transient
        for attempt in 1...3 {
            do {
                _ = try await existing.data(path: "/health", timeout: 3)
                connection = existing
                snapshotValue.state = .ready
                snapshotValue.lastHealthCheck = .now
                snapshotValue.lastErrorCode = nil
                snapshotValue.healthCategory = nil
                snapshotValue.lastDiagnostic = attempt == 1
                    ? "Node host health check passed."
                    : "Node host health check recovered on bounded retry \(attempt)."
                return existing
            } catch is CancellationError {
                snapshotValue.healthCategory = NodeHostHealthFailure.cancelled.rawValue
                snapshotValue.lastDiagnostic = "Node host health check was cancelled; the existing connection was preserved."
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                snapshotValue.healthCategory = NodeHostHealthFailure.cancelled.rawValue
                snapshotValue.lastDiagnostic = "Node host health check was cancelled; the existing connection was preserved."
                throw CancellationError()
            } catch {
                lastFailure = error
                category = classifyHealthFailure(error)
                snapshotValue.healthCategory = category.rawValue
                snapshotValue.lastDiagnostic = "Node host health attempt \(attempt) failed (\(category.rawValue))."
                if attempt < retryCount(for: category) {
                    try await Task.sleep(for: .milliseconds(150))
                    continue
                }
                break
            }
        }

        connection = nil
        snapshotValue.state = nativeLaunchSucceeded ? .appRestartRequired : .failed
        snapshotValue.healthCategory = category.rawValue
        snapshotValue.lastErrorCode = "node_process_unreachable"
        snapshotValue.lastDiagnostic = "The already-launched Node host remained unreachable after bounded verification."
        if nativeLaunchSucceeded {
            throw RuntimeCoreError.appRestartRequired(.node)
        }
        throw lastFailure ?? RuntimeCoreError.runtimeUnavailable(.node)
    }

    private func classifyHealthFailure(_ error: Error) -> NodeHostHealthFailure {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost:
                return .transient
            default:
                return .unreachable
            }
        }
        if let runtimeError = error as? RuntimeCoreError,
           case .requestFailed = runtimeError {
            return .protocolFailure
        }
        return .unreachable
    }

    private func retryCount(for category: NodeHostHealthFailure) -> Int {
        category == .transient ? 3 : 2
    }

    private func prepareHostRuntime() throws -> URL {
        let version = "4"
        let destination = fileLayout.nodeRuntime.appending(path: "host-v\(version)", directoryHint: .isDirectory)
        let marker = destination.appending(path: ".ready")
        if FileManager.default.fileExists(atPath: marker.path) { return destination }
        guard let archive = Bundle.main.url(forResource: "RuntimeHostResources", withExtension: "zip") else {
            throw RuntimeCoreError.runtimeFailure("RuntimeHostResources.zip is missing. Run Scripts/Runtime/prepare-runtime-core.sh before building.")
        }
        let staging = fileLayout.staging.appending(path: "host-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            try FileManager.default.unzipItem(at: archive, to: staging)
            try Data(version.utf8).write(to: staging.appending(path: ".ready"), options: .atomic)
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.moveItem(at: staging, to: destination)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    private func makeToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw RuntimeCoreError.runtimeFailure("Could not create a runtime launch token.")
        }
        return Data(bytes).base64EncodedString()
    }
}
