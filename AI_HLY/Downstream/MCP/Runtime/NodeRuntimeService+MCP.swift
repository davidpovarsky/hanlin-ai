import Foundation

private struct MCPInstallProgressResponse: Decodable, Sendable {
    let progress: MCPInstallProgress?
}

extension NodeRuntimeService {
    func previewMCPPackage(spec: MCPPackageSpec) async throws -> MCPPackageManifestPreview {
        let host = try await ensureRunning()
        let body = try JSONSerialization.data(withJSONObject: ["source": spec.hostPayload])
        let data = try await host.data(
            path: "/v1/install/preview",
            method: "POST",
            body: body,
            timeout: 120
        )
        return try JSONDecoder.mcp.decode(MCPPackageManifestPreview.self, from: data)
    }

    func installMCPPackage(
        spec: MCPPackageSpec,
        operationID: UUID,
        serverID: UUID,
        entryPointOverride: String?,
        arguments: [String] = [],
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
            "source": source,
            "arguments": arguments
        ]
        if let entryPointOverride { body["entryPointOverride"] = entryPointOverride }
        let encodedBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await host.data(path: "/v1/install", method: "POST", body: encodedBody, timeout: 600)
        return try JSONDecoder.mcp.decode(MCPServerDescriptor.self, from: data)
    }

    func commitMCPInstall(operationID: UUID, serverID: UUID) async throws {
        let host = try await ensureRunning()
        let body = try JSONSerialization.data(withJSONObject: [
            "operationID": operationID.uuidString.lowercased(),
            "serverID": serverID.uuidString.lowercased()
        ])
        _ = try await host.data(path: "/v1/install/commit", method: "POST", body: body)
    }

    func mcpInstallProgress(operationID: UUID) async throws -> MCPInstallProgress? {
        let host = try await ensureRunning()
        let data = try await host.data(path: "/v1/install/status/\(operationID.uuidString.lowercased())", timeout: 5)
        return try JSONDecoder.mcp.decode(MCPInstallProgressResponse.self, from: data).progress
    }

    func rollbackMCPInstall(operationID: UUID, serverID: UUID) async throws {
        let host = try await ensureRunning()
        let body = try JSONSerialization.data(withJSONObject: [
            "operationID": operationID.uuidString.lowercased(),
            "serverID": serverID.uuidString.lowercased()
        ])
        _ = try await host.data(path: "/v1/install/rollback", method: "POST", body: body)
    }

    func cancelMCPInstall(operationID: UUID) async throws {
        let host = try await ensureRunning()
        let body = try JSONSerialization.data(withJSONObject: [
            "operationID": operationID.uuidString.lowercased()
        ])
        _ = try await host.data(path: "/v1/install/cancel", method: "POST", body: body)
    }
}
