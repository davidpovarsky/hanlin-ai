import Foundation
import MCP

struct MCPToolCallOutput: Sendable {
    var content: [Tool.Content]
    var isError: Bool
    var structuredContent: Value? = nil
}

actor MCPClientSession {
    nonisolated let toolListChanges: AsyncStream<Void>

    let server: MCPServerDescriptor
    private let client: Client
    private let transport: EmbeddedNodeMCPTransport
    private let toolListChangeContinuation: AsyncStream<Void>.Continuation
    private(set) var tools: [MCPToolDescriptor] = []
    private var disconnectTask: Task<Void, Never>?
    private var disconnected = false

    init(server: MCPServerDescriptor, transport: EmbeddedNodeMCPTransport) {
        self.server = server
        self.transport = transport
        var continuation: AsyncStream<Void>.Continuation!
        toolListChanges = AsyncStream { continuation = $0 }
        toolListChangeContinuation = continuation
        client = Client(
            name: "Hanlin",
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1",
            title: "Hanlin MCP Client"
        )
    }

    func connect() async throws -> [MCPToolDescriptor] {
        await client.onNotification(ToolListChangedNotification.self) { [toolListChangeContinuation] _ in
            toolListChangeContinuation.yield()
        }
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
        // The pinned SDK's async convenience returns a tuple that discards
        // structuredContent. Its public RequestContext preserves the full result.
        let owner = RuntimeUserOperation.current
        try owner?.checkInterruption()
        try Task.checkCancellation()
        let context: RequestContext<CallTool.Result> = try await client.callTool(name: name, arguments: arguments)
        let client = client
        let interruption = owner?.registerInterruption { reason in
            Task.detached { try? await client.cancelRequest(context.requestID, reason: reason) }
        }
        defer { if let interruption { owner?.unregisterInterruption(interruption) } }
        let response = try await withTaskCancellationHandler {
            try owner?.checkInterruption()
            try Task.checkCancellation()
            let value = try await context.value
            try owner?.checkInterruption()
            try Task.checkCancellation()
            return value
        } onCancel: {
            Task.detached { try? await client.cancelRequest(context.requestID, reason: "The owning operation was cancelled.") }
        }
        return MCPToolCallOutput(content: response.content, isError: response.isError ?? false,
                                 structuredContent: response.structuredContent)
    }

    func disconnect() async {
        if let disconnectTask {
            await disconnectTask.value
            return
        }
        guard !disconnected else { return }
        let task = Task { [weak self] in
            guard let self else { return }
            // The pinned MCP Swift SDK's Client.disconnect() owns transport
            // disconnection; calling transport.disconnect() here as well would
            // duplicate the host stop request.
            await self.client.disconnect()
            await self.finishDisconnect()
        }
        disconnectTask = task
        await task.value
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

    private func finishDisconnect() {
        disconnected = true
        disconnectTask = nil
        toolListChangeContinuation.finish()
    }
}
