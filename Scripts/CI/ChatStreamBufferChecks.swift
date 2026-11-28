import Foundation

/// Executes the production MainActor buffer with the portable StreamData shape
/// emitted by verify_chat_stream_buffer.py. No Apple UI or provider is simulated.
@main
@MainActor
struct ChatStreamBufferChecks {
    struct Failure: Error { let name: String }
    static func main() async throws {
        var passed: [String] = []
        func check(_ name: String, _ condition: @autoclosure () -> Bool) throws {
            guard condition() else { throw Failure(name: name) }
            passed.append(name)
        }
        var events: [StreamData] = []
        let buffer = HanlinChatStreamBuffer(interval: .seconds(10)) { events.append($0) }
        buffer.append(.init(content: "First"))
        try check("first token is immediate", events.count == 1 && events[0].content == "First")
        buffer.append(.init(content: " שלום"))
        buffer.append(.init(content: " e\u{301}👨‍👩‍👧‍👦"))
        try check("burst does not repeatedly invalidate the transcript", events.count == 1)
        buffer.append(.init(toolName: "search_online", operationalState: "approval"))
        try check("approval follows its exact text and is never delayed", events.count == 3 &&
            events[1].content == " שלום e\u{301}👨‍👩‍👧‍👦" && events[2].toolName == "search_online")
        buffer.append(.init(reasoning: "reason"))
        buffer.append(.init(reasoning: "ing"))
        buffer.append(.init(content: "answer"))
        buffer.flush()
        try check("reasoning and answer boundaries retain order", events.suffix(2).map { $0.reasoning ?? $0.content ?? "" } == ["reasoning", "answer"])
        buffer.append(.init(content: "tail"))
        buffer.append(.init(content: "round", modelRoundID: UUID()))
        try check("round boundary flushes pending text immediately", events.suffix(2).map { $0.content ?? "" } == ["tail", "round"] && events.last?.modelRoundID != nil)
        buffer.append(.init(content: "before error"))
        buffer.append(.init(errorInfo: "length"))
        try check("errors retain the partial answer before the error", events[events.count - 2].content == "before error" && events.last?.errorInfo == "length")
        var deadlineEvents: [String] = []
        let deadlineBuffer = HanlinChatStreamBuffer(interval: .milliseconds(15)) { deadlineEvents.append($0.content ?? "") }
        deadlineBuffer.append(.init(content: "first"))
        deadlineBuffer.append(.init(content: "silent tail"))
        try await Task.sleep(for: .milliseconds(150))
        try check("a silent provider still publishes its final pending token", deadlineEvents == ["first", "silent tail"])
        deadlineBuffer.append(.init(content: "accepted"))
        deadlineBuffer.append(.init(content: "cancelled tail"))
        let accepted = deadlineEvents
        deadlineBuffer.cancel()
        try await Task.sleep(for: .milliseconds(100))
        try check("cancel revokes the pending timer without losing accepted text", deadlineEvents == accepted && !deadlineEvents.contains("cancelled tail"))
        var stress: [String] = []
        let stressBuffer = HanlinChatStreamBuffer(interval: .seconds(10)) { stress.append($0.content ?? "") }
        for _ in 0..<5000 { stressBuffer.append(.init(content: "ש e\u{301}🙂\n")) }
        stressBuffer.flush()
        let expected = String(repeating: "ש e\u{301}🙂\n", count: 5000)
        try check("5000 multilingual deltas are byte exact with two publications", stress.count == 2 && stress.joined().utf8.elementsEqual(expected.utf8))
        let data = try JSONSerialization.data(withJSONObject: ["status": "PASS", "count": passed.count, "checks": passed], options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
