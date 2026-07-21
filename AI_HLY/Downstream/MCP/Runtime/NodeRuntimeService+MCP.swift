import Foundation

private struct MCPInstallProgressResponse: Decodable, Sendable {
    let progress: MCPInstallProgress?
}

extension NodeRuntimeService {
    func previewMCPPackage(spec: MCPPackageSpec) async throws -> MCPPackageManifestPreview {
        let host = try await ensureRunning()
        let data = try await host.data(
            path: "/v1/install/preview",
            method: "POST",
            json: ["source": spec.hostPayload],
            timeout: 120
        )
        return try JSONDecoder.mcp.decode(MCPPackageManifestPreview.self, from: data)
    }

    func installMCPPackage(
        spec: MCPPackageSpec,
        operationID: UUID,
        serverID: UUID,
        entryPointOverride: String?,
        fileLayout: MCPFileLayout = .default
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

    func commitMCPInstall(operationID: UUID, serverID: UUID) async throws {
        let host = try await ensureRunning()
        _ = try await host.data(path: "/v1/install/commit", method: "POST", json: [
            "operationID": operationID.uuidString.lowercased(),
            "serverID": serverID.uuidString.lowercased()
        ])
    }

    func mcpInstallProgress(operationID: UUID) async throws -> MCPInstallProgress? {
        let host = try await ensureRunning()
        let data = try await host.data(path: "/v1/install/status/\(operationID.uuidString.lowercased())", timeout: 5)
        return try JSONDecoder.mcp.decode(MCPInstallProgressResponse.self, from: data).progress
    }

    func rollbackMCPInstall(operationID: UUID, serverID: UUID) async throws {
        let host = try await ensureRunning()
        _ = try await host.data(path: "/v1/install/rollback", method: "POST", json: [
            "operationID": operationID.uuidString.lowercased(),
            "serverID": serverID.uuidString.lowercased()
        ])
    }

    func cancelMCPInstall(operationID: UUID) async throws {
        let host = try await ensureRunning()
        _ = try await host.data(path: "/v1/install/cancel", method: "POST", json: [
            "operationID": operationID.uuidString.lowercased()
        ])
    }
}
