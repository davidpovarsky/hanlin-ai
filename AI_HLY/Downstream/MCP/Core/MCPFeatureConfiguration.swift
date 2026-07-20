import Foundation

struct MCPFeatureConfiguration: Codable, Hashable, Sendable {
    var isEnabled: Bool
    var debugLoggingEnabled: Bool

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
