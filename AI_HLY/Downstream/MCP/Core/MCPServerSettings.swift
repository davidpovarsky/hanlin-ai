import Foundation

/// Editable metadata from the original server detail screen. Installed package
/// identity, paths, versions and protected environment references remain owned
/// by the original installer and registry.
public struct MCPServerSettings: Hashable, Sendable {
    private let installedPackageIdentity: InstalledPackageIdentity

    private struct InstalledPackageIdentity: Hashable, Sendable {
        let id: UUID
        let name: String
        let version: String
        let root: String
        let integrity: String?
        let entryPoints: [MCPEntryPointOption]?

        init(_ server: MCPServerDescriptor) {
            id = server.id
            name = server.packageName
            version = server.resolvedVersion
            root = server.packageRoot
            integrity = server.integrity
            entryPoints = server.entryPointOptions
        }
    }

    public var displayName: String
    public var entryPoint: String
    public var entryPointRelativePath: String?
    public var binName: String?
    public var arguments: [String]
    public var isGloballyEnabled: Bool
    public var isEnabledForNewChats: Bool
    public var autoStart: Bool

    public init(server: MCPServerDescriptor) {
        installedPackageIdentity = InstalledPackageIdentity(server)
        displayName = server.displayName
        entryPoint = server.entryPoint
        entryPointRelativePath = server.entryPointRelativePath
        binName = server.binName
        arguments = server.arguments
        isGloballyEnabled = server.isGloballyEnabled
        isEnabledForNewChats = server.isEnabledForNewChats
        autoStart = server.autoStart
    }

    func apply(to server: inout MCPServerDescriptor) throws {
        guard installedPackageIdentity == InstalledPackageIdentity(server) else {
            throw HanlinApplicationMCPError.installationChanged
        }
        server.displayName = displayName
        server.entryPoint = entryPoint
        server.entryPointRelativePath = entryPointRelativePath
        server.binName = binName
        server.arguments = arguments
        server.isGloballyEnabled = isGloballyEnabled
        server.isEnabledForNewChats = isEnabledForNewChats
        server.autoStart = autoStart
        server.updatedAt = .now
    }
}

/// A request-specific administration error, independent of the UI's lastError.
public enum HanlinApplicationMCPError: LocalizedError, Sendable {
    case storageUnavailable(String)
    case operationInProgress
    case installationChanged
    case installationFailed(message: String, rollbackMessage: String?)

    public var errorDescription: String? {
        switch self {
        case .storageUnavailable(let reason):
            "The original MCP persistent store is unavailable: \(reason)"
        case .operationInProgress:
            "An MCP administration operation is already in progress."
        case .installationChanged:
            "The installed MCP package changed. Reload its settings before saving."
        case .installationFailed(let message, let rollback):
            [message, rollback].compactMap { $0 }.joined(separator: "\n")
        }
    }
}
