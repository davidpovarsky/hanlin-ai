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
        let task = Task { try await channel.invoke(id: id, action: "search", caller: "hanlin.host",
            parameters: .object(["query": .string("שלום {{origin}}")])) }
        let request = try await channel.next()
        #expect(request.id == id)
        #expect(request.action == "search")
        #expect(request.parameters == .object(["query": .string("שלום {{origin}}")]))
        let wire = try HanlinJSONValue.decodeCanonicalJSON(request.jsonData())
        guard case let .object(object) = wire else { Issue.record("Expected object"); return }
        #expect(object["caller"] == .string("hanlin.host"))
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
