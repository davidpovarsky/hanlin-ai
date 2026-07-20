import Foundation

struct MCPEnvironmentVariable: Codable, Hashable, Sendable, Identifiable {
    var id: String { name }
    var name: String
    var value: String?
    var secretReference: String?

    var isSecret: Bool { secretReference != nil }
}

struct MCPServerDescriptor: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var slug: String
    var displayName: String
    var packageName: String
    var requestedVersion: String?
    var resolvedVersion: String
    var entryPoint: String
    var binName: String?
    var arguments: [String]
    var environment: [MCPEnvironmentVariable]
    var packageRoot: String
    var integrity: String?
    var installedAt: Date
    var updatedAt: Date
    var isGloballyEnabled: Bool
    var isEnabledForNewChats: Bool
    var autoStart: Bool
    var compatibility: MCPCompatibilityReport
    var installedSize: Int64
    var cachedToolCount: Int

    init(
        id: UUID = UUID(),
        slug: String,
        displayName: String,
        packageName: String,
        requestedVersion: String? = nil,
        resolvedVersion: String,
        entryPoint: String,
        binName: String? = nil,
        arguments: [String] = [],
        environment: [MCPEnvironmentVariable] = [],
        packageRoot: String,
        integrity: String? = nil,
        installedAt: Date = .now,
        updatedAt: Date = .now,
        isGloballyEnabled: Bool = true,
        isEnabledForNewChats: Bool = true,
        autoStart: Bool = false,
        compatibility: MCPCompatibilityReport,
        installedSize: Int64 = 0,
        cachedToolCount: Int = 0
    ) {
        self.id = id
        self.slug = slug
        self.displayName = displayName
        self.packageName = packageName
        self.requestedVersion = requestedVersion
        self.resolvedVersion = resolvedVersion
        self.entryPoint = entryPoint
        self.binName = binName
        self.arguments = arguments
        self.environment = environment
        self.packageRoot = packageRoot
        self.integrity = integrity
        self.installedAt = installedAt
        self.updatedAt = updatedAt
        self.isGloballyEnabled = isGloballyEnabled
        self.isEnabledForNewChats = isEnabledForNewChats
        self.autoStart = autoStart
        self.compatibility = compatibility
        self.installedSize = installedSize
        self.cachedToolCount = cachedToolCount
    }
}
