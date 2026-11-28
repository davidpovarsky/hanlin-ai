import Foundation

public struct MCPFeatureConfiguration: Codable, Hashable, Sendable {
    public internal(set) var isEnabled: Bool
    public internal(set) var debugLoggingEnabled: Bool

    static let `default` = MCPFeatureConfiguration(
        isEnabled: false,
        debugLoggingEnabled: false
    )
}

actor MCPFeatureConfigurationStore {
    private let fileLayout: MCPFileLayout

    init(fileLayout: MCPFileLayout = .default) {
        self.fileLayout = fileLayout
    }

    func load() throws -> MCPFeatureConfiguration {
        try fileLayout.prepareIfNeeded()
        guard FileManager.default.fileExists(atPath: fileLayout.featureConfiguration.path) else {
            return .default
        }
        return try JSONDecoder().decode(
            MCPFeatureConfiguration.self,
            from: Data(contentsOf: fileLayout.featureConfiguration)
        )
    }

    func save(_ configuration: MCPFeatureConfiguration) throws {
        try fileLayout.prepareIfNeeded()
        let data = try JSONEncoder.mcp.encode(configuration)
        try data.write(to: fileLayout.featureConfiguration, options: .atomic)
    }
}
