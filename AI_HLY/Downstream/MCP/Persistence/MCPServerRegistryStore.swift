import Foundation

actor MCPServerRegistryStore {
    private let fileLayout: MCPFileLayout

    init(fileLayout: MCPFileLayout = .default) {
        self.fileLayout = fileLayout
    }

    func load() throws -> [MCPServerDescriptor] {
        try fileLayout.prepareIfNeeded()
        guard FileManager.default.fileExists(atPath: fileLayout.serverRegistry.path) else { return [] }
        return try JSONDecoder.mcp.decode(
            [MCPServerDescriptor].self,
            from: Data(contentsOf: fileLayout.serverRegistry)
        )
    }

    func save(_ servers: [MCPServerDescriptor]) throws {
        try fileLayout.prepareIfNeeded()
        try JSONEncoder.mcp.encode(servers).write(to: fileLayout.serverRegistry, options: .atomic)
    }

    func upsert(_ server: MCPServerDescriptor) throws -> [MCPServerDescriptor] {
        var servers = try load()
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
        } else {
            servers.append(server)
        }
        servers.sort { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        try save(servers)
        return servers
    }

    func remove(id: UUID) throws -> [MCPServerDescriptor] {
        var servers = try load()
        servers.removeAll { $0.id == id }
        try save(servers)
        return servers
    }
}
