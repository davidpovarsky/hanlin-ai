import Foundation

actor MCPToolCatalog {
    private var descriptorsByName: [String: MCPToolDescriptor] = [:]
    private var lastKnownDescriptorsByName: [String: MCPToolDescriptor] = [:]

    func replace(server: MCPServerDescriptor, tools: [MCPToolDescriptor]) -> [MCPToolDescriptor] {
        descriptorsByName = descriptorsByName.filter { $0.value.serverID != server.id }
        lastKnownDescriptorsByName = lastKnownDescriptorsByName.filter {
            $0.value.serverID != server.id
        }
        var registered: [MCPToolDescriptor] = []
        for var tool in tools.sorted(by: { $0.originalName < $1.originalName }) {
            let discriminator = "\(server.id.uuidString):\(tool.originalName)"
            if let existing = descriptorsByName[tool.exposedName],
               existing.serverID != server.id || existing.originalName != tool.originalName {
                tool.exposedName = MCPToolNameCodec.collisionName(tool.exposedName, discriminator: discriminator)
            }
            descriptorsByName[tool.exposedName] = tool
            lastKnownDescriptorsByName[tool.exposedName] = tool
            registered.append(tool)
        }
        return registered
    }

    func remove(serverID: UUID) {
        descriptorsByName = descriptorsByName.filter { $0.value.serverID != serverID }
    }

    func forget(serverID: UUID) {
        remove(serverID: serverID)
        lastKnownDescriptorsByName = lastKnownDescriptorsByName.filter {
            $0.value.serverID != serverID
        }
    }

    func descriptor(exposedName: String) -> MCPToolDescriptor? {
        descriptorsByName[exposedName] ?? lastKnownDescriptorsByName[exposedName]
    }

    func liveDescriptor(exposedName: String) -> MCPToolDescriptor? {
        descriptorsByName[exposedName]
    }

    func descriptors(serverIDs: Set<UUID>) -> [MCPToolDescriptor] {
        descriptorsByName.values
            .filter { serverIDs.contains($0.serverID) }
            .sorted { $0.exposedName < $1.exposedName }
    }
}
