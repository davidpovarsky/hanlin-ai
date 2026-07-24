import Foundation

struct MCPEnvironmentVariable: Codable, Hashable, Sendable, Identifiable {
    var id: String { name }
    var name: String
    var value: String?
    var secretReference: String?

    var isSecret: Bool { secretReference != nil }
}

struct MCPEntryPointOption: Codable, Hashable, Sendable, Identifiable {
    var id: String { binName ?? entryPoint }
    var binName: String?
    var entryPoint: String
}

struct MCPServerDescriptor: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var slug: String
    var displayName: String
    var packageName: String
    var requestedVersion: String?
    var resolvedVersion: String
    var entryPoint: String
    var entryPointRelativePath: String?
    var binName: String?
    var entryPointOptions: [MCPEntryPointOption]?
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

    var preloadOnLaunch: Bool {
        get { autoStart }
        set { autoStart = newValue }
    }

    init(
        id: UUID = UUID(),
        slug: String,
        displayName: String,
        packageName: String,
        requestedVersion: String? = nil,
        resolvedVersion: String,
        entryPoint: String,
        entryPointRelativePath: String? = nil,
        binName: String? = nil,
        entryPointOptions: [MCPEntryPointOption]? = nil,
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
        self.entryPointRelativePath = entryPointRelativePath
        self.binName = binName
        self.entryPointOptions = entryPointOptions
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

    private enum CodingKeys: String, CodingKey {
        case id
        case slug
        case displayName
        case packageName
        case requestedVersion
        case resolvedVersion
        case entryPoint
        case entryPointRelativePath
        case binName
        case entryPointOptions
        case arguments
        case environment
        case packageRoot
        case integrity
        case installedAt
        case updatedAt
        case isGloballyEnabled
        case isEnabledForNewChats
        case autoStart
        case compatibility
        case installedSize
        case cachedToolCount
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        // These values identify installed code and must never be fabricated when
        // persisted data is damaged.
        id = try values.decode(UUID.self, forKey: .id)
        packageName = try values.decode(String.self, forKey: .packageName)
        resolvedVersion = try values.decode(String.self, forKey: .resolvedVersion)
        entryPoint = try values.decode(String.self, forKey: .entryPoint)
        entryPointRelativePath = try values.decodeIfPresent(
            String.self,
            forKey: .entryPointRelativePath
        )

        slug = try values.decodeIfPresent(String.self, forKey: .slug) ?? packageName
        displayName = try values.decodeIfPresent(String.self, forKey: .displayName) ?? packageName
        requestedVersion = try values.decodeIfPresent(String.self, forKey: .requestedVersion)
        binName = try values.decodeIfPresent(String.self, forKey: .binName)
        entryPointOptions = try values.decodeIfPresent([MCPEntryPointOption].self, forKey: .entryPointOptions)
        arguments = try values.decodeIfPresent([String].self, forKey: .arguments) ?? []
        environment = try values.decodeIfPresent([MCPEnvironmentVariable].self, forKey: .environment) ?? []
        packageRoot = try values.decodeIfPresent(String.self, forKey: .packageRoot)
            ?? URL(fileURLWithPath: entryPoint).deletingLastPathComponent().path
        integrity = try values.decodeIfPresent(String.self, forKey: .integrity)
        installedAt = try values.decodeIfPresent(Date.self, forKey: .installedAt) ?? .distantPast
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? installedAt
        isGloballyEnabled = try values.decodeIfPresent(Bool.self, forKey: .isGloballyEnabled) ?? true
        isEnabledForNewChats = try values.decodeIfPresent(Bool.self, forKey: .isEnabledForNewChats) ?? true
        autoStart = try values.decodeIfPresent(Bool.self, forKey: .autoStart) ?? false
        compatibility = try values.decodeIfPresent(MCPCompatibilityReport.self, forKey: .compatibility) ?? .pendingProbe
        installedSize = try values.decodeIfPresent(Int64.self, forKey: .installedSize) ?? 0
        cachedToolCount = try values.decodeIfPresent(Int.self, forKey: .cachedToolCount) ?? 0
    }
}
