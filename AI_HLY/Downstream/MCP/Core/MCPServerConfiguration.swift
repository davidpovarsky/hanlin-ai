import Foundation

struct MCPServerConfiguration: Codable, Hashable, Sendable {
    var serverID: UUID
    var entryPoint: String
    var packageRoot: String
    var arguments: [String]
    var environment: [String: String]

    init(descriptor: MCPServerDescriptor, secrets: [String: String] = [:]) {
        serverID = descriptor.id
        entryPoint = descriptor.entryPoint
        packageRoot = descriptor.packageRoot
        arguments = descriptor.arguments
        environment = Dictionary(uniqueKeysWithValues: descriptor.environment.compactMap { variable in
            if let reference = variable.secretReference, let secret = secrets[reference] {
                return (variable.name, secret)
            }
            return variable.value.map { (variable.name, $0) }
        })
    }
}
