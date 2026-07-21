import Foundation
import Security
import ZIPFoundation

private struct RuntimeHostReadyFile: Codable, Sendable {
    let port: Int
    let nodeVersion: String
    let protocolVersion: Int
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

    func data(path: String, method: String = "GET", json: Any? = nil, timeout: TimeInterval = 60) async throws -> Data {
        let body = try json.map { try JSONSerialization.data(withJSONObject: $0) }
        let (data, response) = try await URLSession.shared.data(for: request(path: path, method: method, body: body, timeout: timeout))
        guard let http = response as? HTTPURLResponse else { throw RuntimeCoreError.runtimeFailure("The runtime host returned an invalid response.") }
        guard 200..<300 ~= http.statusCode else {
            let decoded = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw RuntimeCoreError.requestFailed(http.statusCode, decoded ?? String(decoding: data.prefix(16_384), as: UTF8.self))
        }
        return data
    }

    func decode<T: Decodable>(_ type: T.Type, path: String, method: String = "GET", json: Any? = nil, timeout: TimeInterval = 60) async throws -> T {
        try JSONDecoder().decode(T.self, from: await data(path: path, method: method, json: json, timeout: timeout))
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

    init(fileLayout: RuntimeFileLayout = .default) {
        self.fileLayout = fileLayout
    }

    func snapshot() -> RuntimeSnapshot { snapshotValue }

    func ensureRunning(debug: Bool = false) async throws -> RuntimeHostConnection {
        if let connection {
            do {
                _ = try await connection.data(path: "/health", timeout: 3)
                snapshotValue.lastHealthCheck = .now
                return connection
            } catch {
                self.connection = nil
                snapshotValue.state = .appRestartRequired
                snapshotValue.lastErrorCode = "node_process_unreachable"
                throw RuntimeCoreError.appRestartRequired(.node)
            }
        }
        guard !launchAttempted else {
            snapshotValue.state = .appRestartRequired
            throw RuntimeCoreError.appRestartRequired(.node)
        }
        launchAttempted = true
        snapshotValue.state = .preparing

        do {
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
            let deadline = ContinuousClock.now.advanced(by: .seconds(20))
            while ContinuousClock.now < deadline {
                if FileManager.default.fileExists(atPath: readyURL.path) {
                    let ready = try JSONDecoder().decode(RuntimeHostReadyFile.self, from: Data(contentsOf: readyURL))
                    try? FileManager.default.removeItem(at: readyURL)
                    guard ready.nodeVersion == Self.expectedNodeVersion,
                          ready.protocolVersion == Self.hostProtocolVersion else {
                        throw RuntimeCoreError.runtimeFailure("Expected Node \(Self.expectedNodeVersion) and host protocol \(Self.hostProtocolVersion), received Node \(ready.nodeVersion) and protocol \(ready.protocolVersion).")
                    }
                    guard let url = URL(string: "http://127.0.0.1:\(ready.port)") else {
                        throw RuntimeCoreError.runtimeFailure("The runtime host produced an invalid loopback address.")
                    }
                    let host = RuntimeHostConnection(baseURL: url, token: token)
                    _ = try await host.data(path: "/health", timeout: 3)
                    connection = host
                    snapshotValue.state = .ready
                    snapshotValue.version = ready.nodeVersion
                    snapshotValue.source = "heylogin/nodejs-mobile"
                    snapshotValue.lastHealthCheck = .now
                    snapshotValue.lastErrorCode = nil
                    return host
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            throw RuntimeCoreError.runtimeFailure("Embedded Node startup timed out.")
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
        let payload = try await host.decode(
            HostExecutionResponse.self,
            path: "/v1/executions",
            method: "POST",
            json: [
                "executionID": request.id.uuidString.lowercased(),
                "source": request.source,
                "arguments": request.arguments,
                "workspace": workspace.path,
                "environment": request.environment,
                "moduleKind": moduleKind,
                "timeoutMilliseconds": milliseconds,
                "maximumOutputBytes": request.limits.maximumOutputBytes
            ],
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
        _ = try? await connection.data(path: "/v1/executions/\(id.uuidString.lowercased())/cancel", method: "POST", json: [:], timeout: 3)
    }

    func compileTypeScript(source: String, fileName: String = "main.ts", tsconfig: [String: Any]? = nil) async throws -> TypeScriptCompilationResult {
        let host = try await ensureRunning()
        var body: [String: Any] = ["source": source, "fileName": fileName]
        if let tsconfig { body["tsconfig"] = tsconfig }
        return try await host.decode(TypeScriptCompilationResult.self, path: "/v1/typescript/compile", method: "POST", json: body)
    }

    func currentConnection() async throws -> RuntimeHostConnection {
        try await ensureRunning()
    }

    private func prepareHostRuntime() throws -> URL {
        let version = "3"
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
