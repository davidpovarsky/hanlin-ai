import Foundation

struct MCPPackageInstallation: Sendable {
    var operationID: UUID
    var descriptor: MCPServerDescriptor
}

actor MCPPackageInstallService {
    private let runtime: NodeRuntimeService
    private let fileLayout: MCPFileLayout

    init(
        runtime: NodeRuntimeService,
        fileLayout: MCPFileLayout = .default
    ) {
        self.runtime = runtime
        self.fileLayout = fileLayout
    }

    func preview(_ spec: MCPPackageSpec) async throws -> MCPPackageManifestPreview {
        if case .localArchive(let url) = spec.source {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            return try MCPPackageManifestPreview.readTGZ(at: url)
        }
        return try await runtime.previewMCPPackage(spec: spec)
    }

    func install(
        _ spec: MCPPackageSpec,
        serverID: UUID = UUID(),
        entryPointOverride: String? = nil,
        arguments: [String] = [],
        progress: @escaping @Sendable (MCPInstallProgress) async -> Void
    ) async throws -> MCPPackageInstallation {
        try fileLayout.prepareIfNeeded()
        let operationID = UUID()
        await progress(.init(operationID: operationID, phase: .resolving, fraction: nil))
        let progressTask = Task {
            while !Task.isCancelled {
                if let latest = try? await runtime.mcpInstallProgress(operationID: operationID) {
                    await progress(latest)
                }
                try? await Task.sleep(for: .milliseconds(150))
            }
        }
        defer { progressTask.cancel() }
        do {
            let response = try await runtime.installMCPPackage(
                spec: spec,
                operationID: operationID,
                serverID: serverID,
                entryPointOverride: entryPointOverride,
                arguments: arguments
            )
            await progress(.init(operationID: operationID, phase: .registering, fraction: 0.95))
            await progress(.init(operationID: operationID, phase: .completed, fraction: 1))
            return MCPPackageInstallation(operationID: operationID, descriptor: response)
        } catch is CancellationError {
            try? await runtime.cancelMCPInstall(operationID: operationID)
            throw CancellationError()
        } catch {
            if let latest = try? await runtime.mcpInstallProgress(operationID: operationID) {
                await progress(latest)
            }
            try? await runtime.cancelMCPInstall(operationID: operationID)
            throw error
        }
    }

    func cancel(operationID: UUID) async {
        try? await runtime.cancelMCPInstall(operationID: operationID)
    }

    func commit(_ installation: MCPPackageInstallation) async throws {
        try await runtime.commitMCPInstall(
            operationID: installation.operationID,
            serverID: installation.descriptor.id
        )
    }

    func rollback(_ installation: MCPPackageInstallation) async throws {
        try await runtime.rollbackMCPInstall(
            operationID: installation.operationID,
            serverID: installation.descriptor.id
        )
    }
}
