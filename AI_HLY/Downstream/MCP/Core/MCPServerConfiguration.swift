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
    ) throws -> MCPServerConfiguration {
        var serverEnvironment: [String: String] = [:]
        var names = Set<String>()
        for variable in descriptor.environment {
            guard names.insert(variable.name).inserted else {
                throw MCPError.duplicateEnvironmentName(variable.name)
            }
            if let reference = variable.secretReference, let secret = secrets[reference] {
                serverEnvironment[variable.name] = secret
            } else if let value = variable.value {
                serverEnvironment[variable.name] = value
            }
        }
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
