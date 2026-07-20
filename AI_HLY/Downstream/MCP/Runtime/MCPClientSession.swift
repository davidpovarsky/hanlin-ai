import Foundation
import MCP

struct MCPToolCallOutput: Sendable {
    var content: [Tool.Content]
    var isError: Bool
}

actor MCPClientSession {
    let server: MCPServerDescriptor
    private let client: Client
    private let transport: EmbeddedNodeMCPTransport
    private(set) var tools: [MCPToolDescriptor] = []

    init(server: MCPServerDescriptor, transport: EmbeddedNodeMCPTransport) {
        self.server = server
        self.transport = transport
        client = Client(
            name: "Hanlin",
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1",
            title: "Hanlin MCP Client"
        )
    }

    func connect() async throws -> [MCPToolDescriptor] {
        _ = try await client.connect(transport: transport)
        tools = try await loadTools()
        return tools
    }

    func refreshTools() async throws -> [MCPToolDescriptor] {
        tools = try await loadTools()
        return tools
    }

    func call(name: String, argumentsJSON: String) async throws -> MCPToolCallOutput {
        let arguments: [String: Value]?
        if argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arguments = nil
        } else {
            guard let data = argumentsJSON.data(using: .utf8),
                  case .object(let object) = try JSONDecoder().decode(Value.self, from: data) else {
                throw MCPError.invalidPackageSpec
            }
            arguments = object
        }
        let response = try await client.callTool(name: name, arguments: arguments)
        return MCPToolCallOutput(content: response.content, isError: response.isError ?? false)
    }

    func disconnect() async {
        await client.disconnect()
    }

    private func loadTools() async throws -> [MCPToolDescriptor] {
        var result: [Tool] = []
        var cursor: String?
        repeat {
            let page = try await client.listTools(cursor: cursor)
            result.append(contentsOf: page.tools)
            cursor = page.nextCursor
        } while cursor != nil

        return try result.map { tool in
            let exposed = MCPToolNameCodec.exposedName(
                serverSlug: server.slug,
                toolName: tool.name,
                discriminator: "\(server.id.uuidString):\(tool.name)"
            )
            return MCPToolDescriptor(
                serverID: server.id,
                serverSlug: server.slug,
                serverDisplayName: server.displayName,
                originalName: tool.name,
                exposedName: exposed,
                title: tool.title,
                summary: tool.description,
                inputSchemaJSON: try JSONEncoder().encode(tool.inputSchema)
            )
        }
    }
}
