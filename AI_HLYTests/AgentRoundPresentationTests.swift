import Foundation
import Testing
@testable import AI_Hanlin

@Suite("Source-correlated Thinking hierarchy")
struct AgentRoundPresentationTests {
    @Test func actualRoundMarkersOwnReasoningAndParallelSameNameTools() throws {
        let run = AgentRun(groupID: UUID(), providerID: "fixture", modelID: "fixture")
        var adapter = HanlinStreamEventAdapter(runID: run.id)
        var accumulator = AgentEventAccumulator(run: run)
        let first = UUID(), second = UUID()
        let callA = AgentToolCall.parse(id: "call-A", name: "search", argumentsJSON: #"{"query":"one"}"#)
        let callB = AgentToolCall.parse(id: "call-B", name: "search", argumentsJSON: #"{"query":"two"}"#)
        for data in [
            StreamData(reasoning: "First provider reasoning", modelRoundID: first),
            StreamData(agentEvents: [.toolCallStarted(callA), .toolCallStarted(callB)]),
            StreamData(reasoning: "Second provider reasoning", modelRoundID: second)
        ] {
            for event in adapter.events(from: data) { accumulator.apply(event) }
        }
        let items = accumulator.run.transcriptItems
        #expect(items.first(where: { $0.callID == "call-A" })?.roundID == first.uuidString)
        #expect(items.first(where: { $0.callID == "call-B" })?.roundID == first.uuidString)
        #expect(items.first(where: { $0.text == "Second provider reasoning" })?.roundID == second.uuidString)
        let rounds = AgentActivityComposer.rounds(for: accumulator.run, timeline: AgentActivityComposer.compose(accumulator.run))
        #expect(rounds.map(\.roundID) == [first.uuidString, second.uuidString])
        let tools = try #require(rounds.first).activities.filter { $0.id == "call-A" || $0.id == "call-B" }
        #expect(Set(tools.map(\.id)) == Set(["call-A", "call-B"]))
    }

    @Test func legacyActivitiesNeverAcquireAParentFromTheirTimeOrName() throws {
        let run = AgentRun(groupID: UUID(), providerID: nil, modelID: nil)
        var accumulator = AgentEventAccumulator(run: run)
        accumulator.apply(.toolCallStarted(.parse(id: "legacy-call", name: "search", argumentsJSON: "{}")))
        let actual = UUID().uuidString
        accumulator.apply(.modelRoundStarted(id: actual))
        accumulator.apply(.toolCallStarted(.parse(id: "actual-call", name: "search", argumentsJSON: "{}")))
        let rounds = AgentActivityComposer.rounds(for: accumulator.run, timeline: AgentActivityComposer.compose(accumulator.run))
        let legacy = try #require(rounds.first(where: { $0.roundID == nil }))
        #expect(legacy.activities.map(\.id) == ["legacy-call"])
        #expect(rounds.first(where: { $0.roundID == actual })?.activities.map(\.id) == ["actual-call"])
    }
}
