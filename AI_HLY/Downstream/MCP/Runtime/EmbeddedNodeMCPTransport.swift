import Foundation
import Logging
import MCP

struct MCPTransportTermination: Sendable {
    let message: String
}

actor EmbeddedNodeMCPTransport: MCP.Transport {
    enum TransportState: Sendable {
        case disconnected
        case connecting
        case connected
        case disconnecting
        case finished
    }

    nonisolated let logger: Logger
    nonisolated let unexpectedTerminations: AsyncStream<MCPTransportTermination>

    private let server: MCPServerConfiguration
    private let connection: RuntimeHostConnection
    private let startOperationID = UUID()
    private var generation: Int?
    private let messageStream: AsyncThrowingStream<Data, Swift.Error>
    private let continuation: AsyncThrowingStream<Data, Swift.Error>.Continuation
    private let terminationContinuation: AsyncStream<MCPTransportTermination>.Continuation
    private var eventTask: Task<Void, Never>?
    private var connectTask: Task<Void, Error>?
    private var disconnectTask: Task<Void, Never>?
    private var state: TransportState = .disconnected
    private var hostStarted = false
    private var continuationFinished = false
    private var terminationFinished = false

    init(server: MCPServerConfiguration, connection: RuntimeHostConnection) {
        self.server = server
        self.connection = connection
        logger = Logger(label: "hanlin.mcp.transport.\(server.serverID.uuidString)")
        var streamContinuation: AsyncThrowingStream<Data, Swift.Error>.Continuation!
        messageStream = AsyncThrowingStream { streamContinuation = $0 }
        continuation = streamContinuation
        var lifecycleContinuation: AsyncStream<MCPTransportTermination>.Continuation!
        unexpectedTerminations = AsyncStream { lifecycleContinuation = $0 }
        terminationContinuation = lifecycleContinuation
    }

    func connect() async throws {
        while true {
            switch state {
            case .connected:
                return
            case .connecting:
                if let connectTask {
                    try await connectTask.value
                    return
                }
                state = .disconnected
            case .disconnecting:
                if let disconnectTask { await disconnectTask.value }
                throw MCPError.runtimeUnavailable("The server transport has finished.")
            case .finished:
                throw MCPError.runtimeUnavailable("The server transport has finished.")
            case .disconnected:
                state = .connecting
                let task = Task { [weak self] in
                    guard let self else { throw CancellationError() }
                    try await self.performConnect()
                }
                connectTask = task
                do {
                    try await task.value
                    return
                } catch {
                    if state == .connecting { state = .disconnected }
                    connectTask = nil
                    throw error
                }
            }
        }
    }

    func disconnect() async {
        while true {
            switch state {
            case .finished:
                return
            case .disconnecting:
                if let disconnectTask { await disconnectTask.value }
                return
            case .connecting:
                connectTask?.cancel()
                if let connectTask { _ = try? await connectTask.value }
                if state == .connecting { state = .disconnected }
            case .connected, .disconnected:
                state = .disconnecting
                let task = Task<Void, Never> { [weak self] in
                    guard let self else { return }
                    await self.performDisconnect()
                }
                disconnectTask = task
                await task.value
                return
            }
        }
    }

    func send(_ data: Data) async throws {
        guard state == .connected else {
            throw MCPError.runtimeUnavailable("The server transport is disconnected.")
        }
        guard let generation else { throw MCPError.invalidHostResponse }
        var framed = data
        framed.append(0x0A)
        let id = UUID()
        let body = try JSONSerialization.data(withJSONObject: ["data": framed.base64EncodedString(),
            "generation": generation, "executionID": id.uuidString.lowercased(), "detached": true])
        _ = try await connection.performOperation(
            path: "/v1/servers/\(server.serverID.uuidString.lowercased())/stdin",
            id: id, body: body
        )
    }

    func receive() -> AsyncThrowingStream<Data, Swift.Error> { messageStream }

    private func performConnect() async throws {
        let encoded = try JSONEncoder.mcp.encode(server)
        guard var configuration = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            throw MCPError.invalidHostResponse
        }
        configuration["executionID"] = startOperationID.uuidString.lowercased()
        configuration["detached"] = true
        let body = try JSONSerialization.data(withJSONObject: configuration)
        let result = try await connection.performOperation(
            path: "/v1/servers/\(server.serverID.uuidString.lowercased())/start",
            id: startOperationID, body: body
        )
        guard let value = result.value else { throw MCPError.invalidHostResponse }
        let identity = try JSONDecoder().decode(WorkerIdentity.self, from: JSONEncoder().encode(value))
        generation = identity.generation
        hostStarted = true
        guard state == .connecting else { throw CancellationError() }
        let request = connection.request(
            path: "/v1/servers/\(server.serverID.uuidString.lowercased())/events?generation=\(identity.generation)",
            timeout: 86_400
        )
        eventTask = Task { [weak self, request] in
            await self?.receiveEvents(request: request)
        }
        state = .connected
        connectTask = nil
    }

    private func performDisconnect() async {
        let task = eventTask
        eventTask = nil
        task?.cancel()
        if let task { await task.value }

        // A cancelled observer may miss the successful startup receipt. Recover
        // its exact generation before cleanup, never stop a newer connection.
        if !hostStarted {
            let connection = connection, id = startOperationID
            let recovered = await Task.detached { () -> Int? in
                let route = "/v1/executions/\(id.uuidString.lowercased())"
                _ = try? await connection.data(path: route + "/cancel", method: "POST", body: Data("{}".utf8), timeout: 5)
                while let job = try? await connection.decode(RuntimeJobSnapshot.self, path: route, timeout: 5) {
                    if job.state.isTerminal {
                        guard let value = job.result?.value else { return nil }
                        return try? JSONDecoder().decode(WorkerIdentity.self, from: JSONEncoder().encode(value)).generation
                    }
                    // Completion may be hashing/publishing its receipt after
                    // startup succeeded. Drain it before generation cleanup.
                    try? await Task.sleep(for: .milliseconds(25))
                }
                return nil
            }.value
            if let recovered { generation = recovered; hostStarted = true }
        }
        if hostStarted, let generation {
            hostStarted = false
            let connection = connection, serverID = server.serverID
            // Cleanup must survive cancellation of the connecting owner.
            await Task.detached {
                _ = try? await connection.data(
                    path: "/v1/servers/\(serverID.uuidString.lowercased())/stop",
                    method: "POST",
                    body: try? JSONSerialization.data(withJSONObject: ["generation": generation]),
                    timeout: 10)
            }.value
        }
        finishContinuation()
        finishTerminationEvents()
        connectTask = nil
        disconnectTask = nil
        state = .finished
    }

    private func receiveEvents(request: URLRequest) async {
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw MCPError.invalidHostResponse
            }
            for try await line in bytes.lines {
                if Task.isCancelled { break }
                guard let data = line.data(using: .utf8),
                      let event = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let channel = event["channel"] as? String else { continue }
                if channel == "stdout",
                   let encoded = event["data"] as? String,
                   let message = Data(base64Encoded: encoded) {
                    continuation.yield(message)
                } else if channel == "lifecycle",
                          let eventName = event["event"] as? String,
                          ["error", "exit", "failed", "stopped"].contains(eventName) {
                    reportUnexpectedTermination(
                        "The MCP Worker event stream reported \(eventName)."
                    )
                    return
                }
            }
            if !Task.isCancelled {
                reportUnexpectedTermination("The MCP Worker event stream ended unexpectedly.")
            }
        } catch is CancellationError {
            // The owner finishes the continuation after the host stop completes.
        } catch let error as URLError where error.code == .cancelled {
            // The owner finishes the continuation after the host stop completes.
        } catch {
            reportUnexpectedTermination(error.localizedDescription, error: error)
        }
    }

    private func finishContinuation(throwing error: Error? = nil) {
        guard !continuationFinished else { return }
        continuationFinished = true
        if let error { continuation.finish(throwing: error) }
        else { continuation.finish() }
    }

    private func reportUnexpectedTermination(_ message: String, error: Error? = nil) {
        guard state == .connected, !terminationFinished else { return }
        terminationFinished = true
        terminationContinuation.yield(MCPTransportTermination(message: message))
        terminationContinuation.finish()
        finishContinuation(throwing: error)
    }

    private func finishTerminationEvents() {
        guard !terminationFinished else { return }
        terminationFinished = true
        terminationContinuation.finish()
    }

    private struct WorkerIdentity: Decodable { let generation: Int }
}
