import Foundation
import HanlinMiniAppCore
import HanlinPlatformContracts
import Testing

@Suite("Prepared MiniApp action delivery")
struct HanlinMiniAppActionChannelTests {
    @Test("An invocation returns its actual registered JavaScript result")
    func requestReplyPreservesIdentityAndPayload() async throws {
        let channel = HanlinMiniAppActionChannel()
        try await channel.register(actions: ["search"])
        let id = UUID()
        var nested: HanlinValue = .bool(true)
        for _ in 0..<65 { nested = .array([nested]) }
        let parameters: HanlinValue = .object([
            "query": .string("שלום {{origin}}"),
            "document": .string(String(repeating: "x", count: 1_048_577)),
            "nested": nested,
            "items": .array(Array(repeating: .null, count: 100_001))
        ])
        let task = Task { try await channel.invoke(id: id, action: "search", caller: "hanlin.host",
            parameters: parameters) }
        let request = try await channel.next()
        #expect(request.id == id)
        #expect(request.action == "search")
        #expect(request.parameters == parameters)
        let wire = try HanlinJSONValue.decodeCanonicalJSON(request.jsonData(), limits: .unbounded)
        guard case let .object(object) = wire else { Issue.record("Expected object"); return }
        #expect(object["caller"] == .string("hanlin.host"))
        #expect(try HanlinValue(jsonValue: #require(object["parameters"])) == parameters)
        try await channel.complete(id: id, result: .success(.object(["total": .integer(7)])))
        #expect(try await task.value == .object(["total": .integer(7)]))
        await channel.close()
    }

    @Test("Registration rejects missing handlers rather than claiming success")
    func missingHandlerIsAnError() async throws {
        let channel = HanlinMiniAppActionChannel()
        try await channel.register(actions: ["search"])
        await #expect(throws: HanlinMiniAppActionChannel.ChannelError.actionNotRegistered("missing")) {
            try await channel.invoke(action: "missing", caller: "hanlin.host", parameters: .null)
        }
        await channel.close()
    }

    @Test("Session teardown completes pending readers and invokes with an error")
    func closeDoesNotLeakSuspendedInvocation() async throws {
        let channel = HanlinMiniAppActionChannel()
        try await channel.register(actions: ["search"])
        let task = Task { try await channel.invoke(action: "search", caller: "hanlin.host", parameters: .null) }
        let request = try await channel.next()
        await channel.close()
        await #expect(throws: HanlinMiniAppActionChannel.ChannelError.closed) { try await task.value }
        await #expect(throws: HanlinMiniAppActionChannel.ChannelError.unknownInvocation) {
            try await channel.complete(id: request.id, result: .success(.null))
        }
        await #expect(throws: HanlinMiniAppActionChannel.ChannelError.closed) { try await channel.next() }
    }

    @Test("A late result from a cancelled call cannot complete another invocation")
    func cancellationInvalidatesOnlyItsOwnRequest() async throws {
        let channel = HanlinMiniAppActionChannel()
        try await channel.register(actions: ["search"])
        let first = Task { try await channel.invoke(action: "search", caller: "hanlin.host", parameters: .string("first")) }
        let request = try await channel.next()
        first.cancel()
        await #expect(throws: CancellationError.self) { try await first.value }
        await #expect(throws: HanlinMiniAppActionChannel.ChannelError.unknownInvocation) {
            try await channel.complete(id: request.id, result: .success(.null))
        }
        let second = Task { try await channel.invoke(action: "search", caller: "hanlin.host", parameters: .string("second")) }
        let next = try await channel.next()
        #expect(next.id != request.id)
        try await channel.complete(id: next.id, result: .success(.string("second-result")))
        #expect(try await second.value == .string("second-result"))
        await channel.close()
    }
}
