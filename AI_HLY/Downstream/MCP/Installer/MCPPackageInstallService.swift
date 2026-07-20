import Foundation

actor MCPPackageInstallService {
    private let runtime: NodeMobileRuntimeProvider
    private let registry: MCPServerRegistryStore
    private let fileLayout: MCPFileLayout

    init(
        runtime: NodeMobileRuntimeProvider,
        registry: MCPServerRegistryStore = MCPServerRegistryStore(),
        fileLayout: MCPFileLayout = .default
    ) {
        self.runtime = runtime
        self.registry = registry
        self.fileLayout = fileLayout
    }

    func preview(_ spec: MCPPackageSpec) async throws -> MCPPackageManifestPreview {
        if case .localArchive(let url) = spec.source {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            return try MCPPackageManifestPreview.readTGZ(at: url)
        }
        return try await runtime.preview(spec: spec)
    }

    func install(
        _ spec: MCPPackageSpec,
        entryPointOverride: String? = nil,
        progress: @escaping @Sendable (MCPInstallProgress) async -> Void
    ) async throws -> MCPServerDescriptor {
        try fileLayout.prepareIfNeeded()
        let operationID = UUID()
        await progress(.init(operationID: operationID, phase: .resolving, fraction: nil))
        do {
            let response = try await runtime.install(
                spec: spec,
                operationID: operationID,
                entryPointOverride: entryPointOverride
            )
            await progress(.init(operationID: operationID, phase: .registering, fraction: 0.95))
            _ = try await registry.upsert(response)
            await progress(.init(operationID: operationID, phase: .completed, fraction: 1))
            return response
        } catch is CancellationError {
            try? await runtime.cancelInstall(operationID: operationID)
            throw CancellationError()
        } catch {
            try? await runtime.cancelInstall(operationID: operationID)
            throw error
        }
    }

    func cancel(operationID: UUID) async {
        try? await runtime.cancelInstall(operationID: operationID)
    }
}
