import Foundation
import Testing
@testable import AI_Hanlin

@Suite("Source-correlated Thinking hierarchy")
struct AgentRoundPresentationTests {
    @MainActor @Test func asyncCancellationCannotClearANewerRunWhileRecorderDrains() async throws {
        let recorder = try #require(await AgentDiagnosticsRecorder.start(runID: UUID(), groupID: UUID(), providerID: "fixture", modelID: "fixture"))
        let gate = RecorderDrainGate()
        let coordinator = AgentRunLifecycleCoordinator(completeCancelledRecorder: { _ in await gate.drain() })
        let first = UUID(), second = UUID()
        beginSynchronously(coordinator, id: first, recorder: recorder)
        let cancellation = Task { await coordinator.cancelRun(runID: first) }
        await gate.waitUntilEntered()
        beginSynchronously(coordinator, id: second)
        await gate.release()
        await cancellation.value
        #expect(coordinator.isCurrentRun(second))
        await recorder.complete(status: "cancelled")
    }

    @MainActor @Test func suspendedBeginCannotReclaimOwnershipFromANewerRun() async throws {
        let recorder = try #require(await AgentDiagnosticsRecorder.start(runID: UUID(), groupID: UUID(), providerID: "fixture", modelID: "fixture"))
        let gate = RecorderDrainGate()
        let coordinator = AgentRunLifecycleCoordinator(completeCancelledRecorder: { _ in await gate.drain() })
        let first = UUID(), second = UUID(), third = UUID()
        beginSynchronously(coordinator, id: first, recorder: recorder)
        let supersession = Task { await coordinator.beginRun(runID: second, recorder: nil) }
        await gate.waitUntilEntered()
        beginSynchronously(coordinator, id: third)
        await gate.release()
        await supersession.value
        #expect(coordinator.isCurrentRun(third))
        #expect(!coordinator.attachRecorder(recorder, for: first))
        #expect(coordinator.isCurrentRun(third))
        await recorder.complete(status: "cancelled")
    }

    @MainActor private func beginSynchronously(_ coordinator: AgentRunLifecycleCoordinator, id: UUID,
                                               recorder: AgentDiagnosticsRecorder? = nil) {
        coordinator.beginRun(runID: id, recorder: recorder)
    }
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

private actor RecorderDrainGate {
    private var entered = false
    private var released = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func drain() async {
        entered = true
        entryWaiters.forEach { $0.resume() }
        entryWaiters.removeAll()
        if !released { await withCheckedContinuation { releaseWaiters.append($0) } }
    }
    func waitUntilEntered() async {
        if !entered { await withCheckedContinuation { entryWaiters.append($0) } }
    }
    func release() {
        released = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}
