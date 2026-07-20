import Foundation
import Logging
import MCP

actor EmbeddedNodeMCPTransport: MCP.Transport {
    nonisolated let logger: Logger

    private let server: MCPServerConfiguration
    private let connection: MCPHostConnection
    private let maximumMessageBytes = 8 * 1_024 * 1_024
    private let messageStream: AsyncThrowingStream<Data, Swift.Error>
    private let continuation: AsyncThrowingStream<Data, Swift.Error>.Continuation
    private var eventTask: Task<Void, Never>?
    private var connected = false

    init(server: MCPServerConfiguration, connection: MCPHostConnection) {
        self.server = server
        self.connection = connection
        logger = Logger(label: "hanlin.mcp.transport.\(server.serverID.uuidString)")
        var streamContinuation: AsyncThrowingStream<Data, Swift.Error>.Continuation!
        messageStream = AsyncThrowingStream { streamContinuation = $0 }
        continuation = streamContinuation
    }

    func connect() async throws {
        guard !connected else { return }
        let body = try JSONEncoder.mcp.encode(server)
        let object = try JSONSerialization.jsonObject(with: body)
        _ = try await connection.data(
            path: "/v1/servers/\(server.serverID.uuidString.lowercased())/start",
            method: "POST",
            json: object,
            timeout: 20
        )
        connected = true
        let request = connection.request(
            path: "/v1/servers/\(server.serverID.uuidString.lowercased())/events",
            timeout: 86_400
        )
        eventTask = Task { [request] in
            await receiveEvents(request: request)
        }
    }

    func disconnect() async {
        guard connected else { return }
        connected = false
        eventTask?.cancel()
        eventTask = nil
        try? await connection.data(
            path: "/v1/servers/\(server.serverID.uuidString.lowercased())/stop",
            method: "POST",
            json: [:],
            timeout: 10
        )
        continuation.finish()
    }

    func send(_ data: Data) async throws {
        guard connected else { throw MCPError.runtimeUnavailable("The server transport is disconnected.") }
        guard data.count <= maximumMessageBytes else { throw MCPError.resultTooLarge }
        var framed = data
        framed.append(0x0A)
        _ = try await connection.data(
            path: "/v1/servers/\(server.serverID.uuidString.lowercased())/stdin",
            method: "POST",
            json: ["data": framed.base64EncodedString()],
            timeout: 30
        )
    }

    func receive() -> AsyncThrowingStream<Data, Swift.Error> { messageStream }

    private func receiveEvents(request: URLRequest) async {
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw MCPError.invalidHostResponse
            }
            for try await line in bytes.lines {
                if Task.isCancelled { break }
                guard line.utf8.count <= maximumMessageBytes,
                      let data = line.data(using: .utf8),
                      let event = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      event["channel"] as? String == "stdout",
                      let encoded = event["data"] as? String,
                      let message = Data(base64Encoded: encoded),
                      message.count <= maximumMessageBytes else { continue }
                continuation.yield(message)
            }
            continuation.finish()
        } catch is CancellationError {
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }
}
