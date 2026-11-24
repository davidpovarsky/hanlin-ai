import Foundation
import HanlinPlatformContracts

/// One request/reply channel owned by one running MiniApp session. The native
/// invocation receipt completes only after the JavaScript handler returns.
/// Registration and transport do not create another JavaScript engine.
public actor HanlinMiniAppActionChannel {
    public struct Request: Sendable, Equatable {
        public let id: UUID
        public let action: String
        public let caller: String
        public let parameters: HanlinValue

        public func jsonData() throws -> Data {
            try HanlinJSONValue.object([
                "id": .string(id.uuidString),
                "action": .string(action),
                "caller": .string(caller),
                "parameters": parameters.jsonValue(destination: .javaScriptBinary64)
            ]).canonicalJSONData(limits: .unbounded)
        }
    }

    public enum ChannelError: Error, Equatable, Sendable {
        case closed
        case actionNotRegistered(String)
        case duplicateInvocation
        case duplicateReader
        case unknownInvocation
        case executionFailed(String)
    }

    private struct Pending {
        let request: Request
        let continuation: CheckedContinuation<HanlinValue, any Error>
        var delivered = false
    }
    private var actions: Set<String>?
    private var pending: [UUID: Pending] = [:]
    private var order: [UUID] = []
    private var reader: (id: UUID, continuation: CheckedContinuation<Request, any Error>)?
    private var isClosed = false

    public init() {}

    public func register(actions: Set<String>) throws {
        guard !isClosed else { throw ChannelError.closed }
        self.actions = actions
        // Registering a complete handler table is also an explicit readiness
        // signal. Missing implementations are errors, never silent successes.
        for id in order {
            guard let item = pending[id], !item.delivered,
                  !actions.contains(item.request.action) else { continue }
            pending.removeValue(forKey: id)
            item.continuation.resume(throwing: ChannelError.actionNotRegistered(item.request.action))
        }
        order.removeAll { pending[$0] == nil }
        deliverNext()
    }

    public func invoke(id: UUID = UUID(), action: String, caller: String,
                       parameters: HanlinValue) async throws -> HanlinValue {
        guard !isClosed else { throw ChannelError.closed }
        guard pending[id] == nil else { throw ChannelError.duplicateInvocation }
        if let actions, !actions.contains(action) { throw ChannelError.actionNotRegistered(action) }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                pending[id] = Pending(request: Request(id: id, action: action, caller: caller,
                    parameters: parameters), continuation: continuation)
                order.append(id)
                deliverNext()
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    public func next() async throws -> Request {
        guard !isClosed else { throw ChannelError.closed }
        guard reader == nil else { throw ChannelError.duplicateReader }
        let readerID = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                reader = (readerID, continuation)
                deliverNext()
            }
        } onCancel: {
            Task { await self.cancelReader(readerID) }
        }
    }

    public func complete(id: UUID, result: Result<HanlinValue, ChannelError>) throws {
        guard let item = pending[id], item.delivered else { throw ChannelError.unknownInvocation }
        pending.removeValue(forKey: id)
        order.removeAll { $0 == id }
        item.continuation.resume(with: result.mapError { $0 as any Error })
    }

    public func close() {
        isClosed = true
        let requests = Array(pending.values)
        pending.removeAll()
        order.removeAll()
        let previousReader = reader
        reader = nil
        previousReader?.continuation.resume(throwing: ChannelError.closed)
        for item in requests { item.continuation.resume(throwing: ChannelError.closed) }
    }

    private func deliverNext() {
        guard let actions, let reader,
              let id = order.first(where: { id in
                  guard let item = pending[id] else { return false }
                  return !item.delivered && actions.contains(item.request.action)
              }), var item = pending[id] else { return }
        item.delivered = true
        pending[id] = item
        self.reader = nil
        reader.continuation.resume(returning: item.request)
    }

    private func cancel(_ id: UUID) {
        guard let item = pending.removeValue(forKey: id) else { return }
        order.removeAll { $0 == id }
        item.continuation.resume(throwing: CancellationError())
    }

    private func cancelReader(_ id: UUID) {
        guard let reader, reader.id == id else { return }
        self.reader = nil
        reader.continuation.resume(throwing: CancellationError())
    }
}
