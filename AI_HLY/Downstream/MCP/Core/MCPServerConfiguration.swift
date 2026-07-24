import Foundation

struct MCPServerConfiguration: Codable, Hashable, Sendable {
    var serverID: UUID
    var entryPoint: String
    var packageRoot: String
    var arguments: [String]
    var environment: [String: String]

    static func make(
        descriptor: MCPServerDescriptor,
        resolvedPaths: MCPResolvedServerPaths,
        secrets: [String: String] = [:],
        environment: [String: String] = [:]
    ) -> MCPServerConfiguration {
        let serverEnvironment = Dictionary(
            uniqueKeysWithValues: descriptor.environment.compactMap { variable in
                if let reference = variable.secretReference, let secret = secrets[reference] {
                    return (variable.name, secret)
                }
                return variable.value.map { (variable.name, $0) }
            }
        )
        return MCPServerConfiguration(
            serverID: descriptor.id,
            entryPoint: resolvedPaths.entryPoint.path,
            packageRoot: resolvedPaths.packageRoot.path,
            arguments: descriptor.arguments,
            environment: environment.merging(serverEnvironment) { _, serverValue in
                serverValue
            }
        )
    }

    private init(
        serverID: UUID,
        entryPoint: String,
        packageRoot: String,
        arguments: [String],
        environment: [String: String]
    ) {
        self.serverID = serverID
        self.entryPoint = entryPoint
        self.packageRoot = packageRoot
        self.arguments = arguments
        self.environment = environment
    }
}
