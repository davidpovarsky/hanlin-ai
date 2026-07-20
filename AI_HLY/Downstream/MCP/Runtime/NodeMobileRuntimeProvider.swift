import Foundation
import Security
import ZIPFoundation

private struct MCPReadyFile: Codable, Sendable {
    var port: Int
    var nodeVersion: String
    var protocolVersion: Int
}

struct MCPHostConnection: Sendable {
    let baseURL: URL
    let token: String

    func request(
        path: String,
        method: String = "GET",
        body: Data? = nil,
        timeout: TimeInterval = 60
    ) -> URLRequest {
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
        let (data, response) = try await URLSession.shared.data(for: request(
            path: path,
            method: method,
            body: body,
            timeout: timeout
        ))
        guard let http = response as? HTTPURLResponse else { throw MCPError.invalidHostResponse }
        guard 200..<300 ~= http.statusCode else {
            let message = String(decoding: data.prefix(16_384), as: UTF8.self)
            throw MCPError.requestFailed(http.statusCode, MCPLogRedactor.redact(message))
        }
        return data
    }
}

actor NodeMobileRuntimeProvider {
    private let fileLayout: MCPFileLayout
    private var connection: MCPHostConnection?
    private var snapshotValue: MCPRuntimeSnapshot = .stopped
    private var launchAttempted = false

    init(fileLayout: MCPFileLayout = .default) {
        self.fileLayout = fileLayout
    }

    func snapshot() -> MCPRuntimeSnapshot { snapshotValue }

    func ensureRunning(debug: Bool = false) async throws -> MCPHostConnection {
        if let connection {
            do {
                _ = try await connection.data(path: "/health", timeout: 3)
                return connection
            } catch {
                self.connection = nil
            }
        }
        guard !launchAttempted else {
            throw MCPError.runtimeUnavailable("Node runtime cannot be restarted within the same app process.")
        }
        launchAttempted = true
        snapshotValue = MCPRuntimeSnapshot(
            state: .starting,
            nodeVersion: nil,
            protocolVersion: nil,
            activeWorkerCount: 0,
            message: nil
        )

        do {
            try fileLayout.prepareIfNeeded()
            let hostURL = try prepareHostRuntime()
            let readyURL = fileLayout.runtime.appending(path: "ready-\(UUID().uuidString).json")
            let token = try makeToken()
            let arguments = [
                "node",
                hostURL.appending(path: "host.mjs").path,
                fileLayout.root.path,
                readyURL.path,
                token,
                fileLayout.runtimeLog.path,
                debug ? "1" : "0"
            ]
            try NodeRuntimeBridge.start(arguments: arguments)
            let deadline = ContinuousClock.now.advanced(by: .seconds(15))
            while ContinuousClock.now < deadline {
                if FileManager.default.fileExists(atPath: readyURL.path) {
                    let ready = try JSONDecoder().decode(MCPReadyFile.self, from: Data(contentsOf: readyURL))
                    try? FileManager.default.removeItem(at: readyURL)
                    guard ready.nodeVersion == "18.20.4", ready.protocolVersion == 1 else {
                        throw MCPError.runtimeUnavailable("Unexpected Node or host protocol version.")
                    }
                    guard let url = URL(string: "http://127.0.0.1:\(ready.port)") else {
                        throw MCPError.invalidHostResponse
                    }
                    let host = MCPHostConnection(baseURL: url, token: token)
                    _ = try await host.data(path: "/health", timeout: 3)
                    connection = host
                    snapshotValue = MCPRuntimeSnapshot(
                        state: .running,
                        nodeVersion: ready.nodeVersion,
                        protocolVersion: ready.protocolVersion,
                        activeWorkerCount: 0,
                        message: nil
                    )
                    return host
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            throw MCPError.startupTimedOut
        } catch {
            snapshotValue = MCPRuntimeSnapshot(
                state: .failed,
                nodeVersion: nil,
                protocolVersion: nil,
                activeWorkerCount: 0,
                message: error.localizedDescription
            )
            throw error
        }
    }

    func preview(spec: MCPPackageSpec) async throws -> MCPPackageManifestPreview {
        let host = try await ensureRunning()
        let data = try await host.data(
            path: "/v1/install/preview",
            method: "POST",
            json: ["source": spec.hostPayload],
            timeout: 120
        )
        return try JSONDecoder.mcp.decode(MCPPackageManifestPreview.self, from: data)
    }

    func install(
        spec: MCPPackageSpec,
        operationID: UUID,
        serverID: UUID,
        entryPointOverride: String?
    ) async throws -> MCPServerDescriptor {
        let host = try await ensureRunning()
        var source = spec.hostPayload
        if case .localArchive(let inputURL) = spec.source {
            let didAccess = inputURL.startAccessingSecurityScopedResource()
            defer { if didAccess { inputURL.stopAccessingSecurityScopedResource() } }
            let copy = fileLayout.staging.appending(path: "\(operationID.uuidString).tgz")
            try? FileManager.default.removeItem(at: copy)
            try FileManager.default.copyItem(at: inputURL, to: copy)
            source = ["kind": "file", "path": copy.path]
        }
        var body: [String: Any] = [
            "operationID": operationID.uuidString.lowercased(),
            "serverID": serverID.uuidString.lowercased(),
            "source": source
        ]
        if let entryPointOverride { body["entryPointOverride"] = entryPointOverride }
        let data = try await host.data(path: "/v1/install", method: "POST", json: body, timeout: 600)
        return try JSONDecoder.mcp.decode(MCPServerDescriptor.self, from: data)
    }

    func commitInstall(operationID: UUID, serverID: UUID) async throws {
        let host = try await ensureRunning()
        _ = try await host.data(
            path: "/v1/install/commit",
            method: "POST",
            json: [
                "operationID": operationID.uuidString.lowercased(),
                "serverID": serverID.uuidString.lowercased()
            ]
        )
    }

    func rollbackInstall(operationID: UUID, serverID: UUID) async throws {
        let host = try await ensureRunning()
        _ = try await host.data(
            path: "/v1/install/rollback",
            method: "POST",
            json: [
                "operationID": operationID.uuidString.lowercased(),
                "serverID": serverID.uuidString.lowercased()
            ]
        )
    }

    func cancelInstall(operationID: UUID) async throws {
        let host = try await ensureRunning()
        _ = try await host.data(
            path: "/v1/install/cancel",
            method: "POST",
            json: ["operationID": operationID.uuidString.lowercased()]
        )
    }

    func currentConnection() async throws -> MCPHostConnection {
        try await ensureRunning()
    }

    private func prepareHostRuntime() throws -> URL {
        let version = "1"
        let destination = fileLayout.runtime.appending(path: "host-v\(version)", directoryHint: .isDirectory)
        let marker = destination.appending(path: ".ready")
        if FileManager.default.fileExists(atPath: marker.path) { return destination }
        guard let archive = Bundle.main.url(forResource: "MCPHostResources", withExtension: "zip") else {
            throw MCPError.runtimeUnavailable("MCPHostResources.zip is missing. Run Scripts/MCP/bootstrap-node-mobile.sh before building.")
        }
        let staging = fileLayout.runtime.appending(path: "host-staging-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            try FileManager.default.unzipItem(at: archive, to: staging)
            try Data(version.utf8).write(to: staging.appending(path: ".ready"), options: .atomic)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
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
            throw MCPError.runtimeUnavailable("Could not create a launch token.")
        }
        return Data(bytes).base64EncodedString()
    }
}
