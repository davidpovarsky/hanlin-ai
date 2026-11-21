import Foundation
import Testing
@testable import AI_Hanlin

@MainActor
@Suite("Historical AgentRun read cache")
struct AgentRunReadCacheTests {
    @Test func unchangedJSONDecodesOnceAndEveryReplacementInvalidates() {
        var decodes = 0
        let cache = HanlinAgentRunReadCache(decode: { message in
            decodes += 1
            return message.agentRun
        })
        let message = ChatMessages(id: UUID(), role: "assistant", text: "")
        let first = AgentRun(groupID: UUID())
        message.agentRun = first
        #expect(cache.run(for: message)?.id == first.id)
        #expect(cache.run(for: message)?.id == first.id)
        #expect(decodes == 1)

        message.agentRunJSON = "{malformed"
        #expect(cache.run(for: message) == nil)
        #expect(cache.run(for: message) == nil)
        #expect(decodes == 2)
        message.agentRunJSON = nil
        #expect(cache.run(for: message) == nil)
        #expect(cache.run(for: message) == nil)
        #expect(decodes == 2) // Nil rows bypass decoding and do not occupy the cache.

        let replacement = AgentRun(groupID: first.groupID, modelID: "Café")
        message.agentRun = replacement
        #expect(cache.run(for: message)?.id == replacement.id)
        #expect(decodes == 3)
        // Even semantically equivalent JSON with changed bytes gets a fresh read.
        message.agentRunJSON = " " + (message.agentRunJSON ?? "")
        #expect(cache.run(for: message)?.id == replacement.id)
        #expect(decodes == 4)
        let composedJSON = message.agentRunJSON ?? ""
        message.agentRunJSON = composedJSON.replacingOccurrences(of: "é", with: "e\u{301}")
        #expect(message.agentRunJSON == composedJSON) // Swift String equality normalizes Unicode.
        #expect(cache.run(for: message)?.id == replacement.id)
        #expect(decodes == 5) // The cache requires exact UTF-8, not normalized equality.
    }

    @Test func messageIdentityLRUAndByteBudgetBoundRetainedSnapshots() {
        var decodes = 0
        let cache = HanlinAgentRunReadCache(capacity: 2, decode: { message in
            decodes += 1
            return message.agentRun
        })
        let messages = (0..<3).map { _ in ChatMessages(id: UUID(), role: "assistant", text: "") }
        let run = AgentRun(groupID: UUID())
        for message in messages { message.agentRun = run }
        _ = cache.run(for: messages[0])
        _ = cache.run(for: messages[1])
        #expect(decodes == 2) // Same JSON on different message IDs has separate ownership.
        _ = cache.run(for: messages[0])
        _ = cache.run(for: messages[2])
        _ = cache.run(for: messages[0])
        #expect(decodes == 3)
        _ = cache.run(for: messages[1])
        #expect(decodes == 4) // Least recently read entry was evicted.

        var oversizedDecodes = 0
        let small = HanlinAgentRunReadCache(maximumSourceBytes: 1, decode: { message in
            oversizedDecodes += 1
            return message.agentRun
        })
        #expect(small.run(for: messages[0])?.id == run.id)
        #expect(small.run(for: messages[0])?.id == run.id)
        #expect(oversizedDecodes == 2) // An oversized value is decoded, never retained.
    }

    @Test func cachedValueDoesNotRetainItsSwiftDataModel() {
        let cache = HanlinAgentRunReadCache()
        weak var weakMessage: ChatMessages?
        do {
            let message = ChatMessages(id: UUID(), role: "assistant", text: "")
            weakMessage = message
            message.agentRun = AgentRun(groupID: UUID())
            _ = cache.run(for: message)
        }
        #expect(weakMessage == nil)
    }
}
