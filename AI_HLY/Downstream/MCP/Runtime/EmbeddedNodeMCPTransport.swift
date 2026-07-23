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
    private let maximumMessageBytes = 8 * 1_024 * 1_024
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
                if let connectTask { _ = try? await connectTask.value }
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
        guard data.count <= maximumMessageBytes else { throw MCPError.resultTooLarge }
        var framed = data
        framed.append(0x0A)
        let body = try JSONSerialization.data(withJSONObject: ["data": framed.base64EncodedString()])
        _ = try await connection.data(
            path: "/v1/servers/\(server.serverID.uuidString.lowercased())/stdin",
            method: "POST",
            body: body,
            timeout: 30
        )
    }

    func receive() -> AsyncThrowingStream<Data, Swift.Error> { messageStream }

    private func performConnect() async throws {
        let body = try JSONEncoder.mcp.encode(server)
        _ = try await connection.data(
            path: "/v1/servers/\(server.serverID.uuidString.lowercased())/start",
            method: "POST",
            body: body,
            timeout: 20
        )
        hostStarted = true
        guard state == .connecting else { throw CancellationError() }
        let request = connection.request(
            path: "/v1/servers/\(server.serverID.uuidString.lowercased())/events",
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

        if hostStarted {
            hostStarted = false
            _ = try? await connection.data(
                path: "/v1/servers/\(server.serverID.uuidString.lowercased())/stop",
                method: "POST",
                body: Data("{}".utf8),
                timeout: 10
            )
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
                guard line.utf8.count <= maximumMessageBytes,
                      let data = line.data(using: .utf8),
                      let event = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let channel = event["channel"] as? String else { continue }
                if channel == "stdout",
                   let encoded = event["data"] as? String,
                   let message = Data(base64Encoded: encoded),
                   message.count <= maximumMessageBytes {
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
}
