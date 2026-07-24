import Foundation

struct MCPServerResolutionFailure: Sendable, Identifiable {
    var id: UUID { serverID }
    let serverID: UUID
    let packageName: String
    let displayName: String
    let errorCode: String
    let message: String
}

struct MCPToolResolutionResult: Sendable {
    var descriptors: [MCPToolDescriptor]
    var failures: [MCPServerResolutionFailure]

    var successfulServerCount: Int {
        Set(descriptors.map(\.serverID)).count
    }
}
