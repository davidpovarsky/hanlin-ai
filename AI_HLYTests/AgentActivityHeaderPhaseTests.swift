import Foundation
import Testing
@testable import AI_Hanlin

@MainActor
@Suite("V17 activity presentation lifetime")
struct AgentActivityHeaderPhaseTests {
    @Test func completedHistoryNeverRevivesThinkingFromStaleApproval() {
        for hasPendingApproval in [false, true] {
            let phase = AgentActivityHeaderPhase.resolve(isRunActive: false, hasPendingApproval: hasPendingApproval)
            #expect(phase == .history)
            #expect(!phase.showsShimmer)
        }
    }

    @Test func permissionWaitPausesShimmerAndCanResumeOnlyWhileActive() {
        #expect(AgentActivityHeaderPhase.resolve(isRunActive: true, hasPendingApproval: false,
            hasActiveOperation: true) == .working)
        let waiting = AgentActivityHeaderPhase.resolve(isRunActive: true, hasPendingApproval: true)
        #expect(waiting == .awaitingApproval)
        #expect(!waiting.showsShimmer)
        #expect(AgentActivityHeaderPhase.resolve(isRunActive: true, hasPendingApproval: false,
            hasActiveOperation: true).showsShimmer)
        #expect(!AgentActivityHeaderPhase.resolve(isRunActive: false, hasPendingApproval: false).showsShimmer)
    }

    @Test func historicalFooterAndDuplicateActivityStatusAreHidden() {
        #expect(!AgentActivityHeaderPhase.showsStandaloneStatus(
            isRunActive: false, isCurrentMessage: true, hasActivityHeader: false))
        #expect(!AgentActivityHeaderPhase.showsStandaloneStatus(
            isRunActive: true, isCurrentMessage: false, hasActivityHeader: false))
        #expect(!AgentActivityHeaderPhase.showsStandaloneStatus(
            isRunActive: true, isCurrentMessage: true, hasActivityHeader: true))
        #expect(!AgentActivityHeaderPhase.showsStandaloneStatus(
            isRunActive: true, isCurrentMessage: true, hasActivityHeader: false))
    }

    @Test func completedToolDoesNotReuseItsEarlierRunningSummary() {
        let stale = "Searching for the requested information"
        let step = AgentActivityStep(sequence: 0, kind: .webSearch,
            title: stale, subtitle: "search_online", userFacingSummary: stale,
            status: .completed)
        let title = AgentActivityTitleBuilder.title(for: [step], kind: .search,
            queries: ["weather"], status: .completed)
        #expect(title == String(format: String(localized: "Searched the web for %@"), "weather"))
        #expect(step.userFacingSummary == stale, "Presentation must not rewrite persisted events")
        #expect(step.status == .completed)
    }

    @Test func failureCancellationAndConsentDoNotImplyLiveWorkOrSuccess() {
        for status in [AgentActivityStatus.failed, .cancelled, .pending] {
            let step = AgentActivityStep(sequence: 0, kind: .toolExecution,
                title: "Searching for the requested information", subtitle: "search_online",
                userFacingSummary: "Allowed once", status: status)
            let title = AgentActivityTitleBuilder.title(for: [step], kind: .search,
                queries: ["weather"], status: status)
            #expect(title == ToolPresentationRegistry.presentation(for: "search_online", profile: nil).title)
            #expect(title != "Allowed once")
        }
    }
    @Test func firstAnswerTextStopsWorkingWithoutFalsifyingConcurrentExecution() {
        #expect(AgentActivityHeaderPhase.resolve(isRunActive: true, hasPendingApproval: false,
            hasAnswerText: true, hasActiveOperation: false) == .history)
        #expect(AgentActivityHeaderPhase.resolve(isRunActive: true, hasPendingApproval: false,
            hasAnswerText: true, hasActiveOperation: true) == .working)
        #expect(AgentActivityHeaderPhase.resolve(isRunActive: true, hasPendingApproval: true,
            hasAnswerText: true, hasActiveOperation: true) == .working)
        #expect(!AgentActivityHeaderPhase.showsStandaloneStatus(isRunActive: true,
            isCurrentMessage: true, hasActivityHeader: false, hasAnswerText: true))
    }

    @Test func shimmerMovesBetweenLeafAndNearestVisibleAncestor() {
        typealias Owner = AgentActivityShimmerOwner
        let leaf = Owner.Path(activityID: "search", roundID: "round", isRoundExpanded: true)
        let closed = Owner.Path(activityID: "search", roundID: "round", isRoundExpanded: false)
        #expect(Owner.resolve(isWorking: true, isHierarchyExpanded: true,
            activePaths: [leaf]) == [.activity("search")])
        #expect(Owner.resolve(isWorking: true, isHierarchyExpanded: true,
            activePaths: [closed]) == [.round("round")])
        #expect(Owner.resolve(isWorking: true, isHierarchyExpanded: false,
            activePaths: [leaf]) == [.root])
        #expect(Owner.resolve(isWorking: false, isHierarchyExpanded: true,
            activePaths: [leaf]).isEmpty)
    }

    @Test func internalPreparationDoesNotCreateToolActivityOrRewriteHistory() {
        let steps = [
            AgentActivityStep(externalID: "call:discovery", sequence: 0, kind: .toolCall,
                title: "Using Tools", subtitle: "load_skill", status: .completed, output: "Loading skill..."),
            AgentActivityStep(externalID: "execution:discovery", sequence: 1, kind: .toolExecution,
                title: "Loading skill...", subtitle: "load_skill", status: .completed),
            AgentActivityStep(externalID: "progress:transport", sequence: 2, kind: .progress,
                title: "Preparing your answer", status: .running),
            AgentActivityStep(externalID: "execution:route", sequence: 3, kind: .map,
                title: "Route", subtitle: "get_route", status: .failed, errorDescription: "Route unavailable")
        ]
        let run = AgentRun(groupID: UUID(), steps: steps)
        let timeline = AgentActivityComposer.compose(run)
        #expect(timeline.activities.map(\.id) == ["route"])
        #expect(timeline.activities.first?.status == .failed)
        #expect(run.steps == steps)
    }

    @Test func mountedDetailsKeepCallIdentityAndPayloadIndependentOfExpansion() {
        let first = AgentActivityStep(externalID: "execution:first", sequence: 0,
            kind: .toolExecution, title: "Search", status: .completed,
            output: "First long result\nSecond line")
        let second = AgentActivityStep(externalID: "execution:second", sequence: 1,
            kind: .toolExecution, title: "Search", status: .completed,
            output: "Unrelated result")
        let run = AgentRun(groupID: UUID(), steps: [first, second])
        let full = ClassicChatAgentProjection.projectToolEntries(from: run)
        let mounted = ClassicChatAgentProjection.projectToolEntries(from: run, callID: "first")
        #expect(mounted.count == 1)
        #expect(mounted.first?.callID == "first")
        #expect(mounted.first?.id == full.first(where: { $0.callID == "first" })?.id)
        #expect(mounted.first?.output == "First long result\nSecond line")
        #expect(ClassicChatAgentProjection.projectToolEntries(from: run, callID: "missing").isEmpty)
        #expect(run.steps.count == 2, "Lazy detail projection must not mutate the run")
    }

    @Test func providerReasoningSurvivesCompositionAndEndsAtTheFirstAnswer() throws {
        let run = AgentRun(groupID: UUID(), providerID: "fixture", modelID: "fixture")
        var adapter = HanlinStreamEventAdapter(runID: run.id)
        var accumulator = AgentEventAccumulator(run: run)
        for event in adapter.events(from: .init(reasoning: "Checking the requested route.",
                                               modelRoundID: UUID())) {
            accumulator.apply(event)
        }
        let live = try #require(AgentActivityComposer.compose(accumulator.run).activities.first)
        #expect(live.kind == .reasoning)
        #expect(live.status == .running)
        #expect(live.id.hasPrefix("reasoning:"))
        #expect(AgentActivityVisibilityPolicy.animatesActivity(kind: live.kind.rawValue,
            status: live.status.rawValue, isRunActive: true, hasAnswerText: false, isAwaitingApproval: false))
        let liveRounds = AgentActivityComposer.rounds(for: accumulator.run,
            timeline: AgentActivityComposer.compose(accumulator.run))
        #expect(liveRounds.flatMap(\.activities).map(\.id) == [live.id])

        for event in adapter.events(from: .init(content: "The route is ready.")) { accumulator.apply(event) }
        let history = try #require(AgentActivityComposer.compose(accumulator.run).activities.first)
        #expect(history.id == live.id, "Answer streaming must preserve the activity's disclosure identity")
        #expect(history.status == .completed)
        #expect(history.completedAt != nil)
        #expect(!AgentActivityVisibilityPolicy.animatesActivity(kind: history.kind.rawValue,
            status: history.status.rawValue, isRunActive: true, hasAnswerText: true, isAwaitingApproval: false))
        #expect(accumulator.run.transcriptItems.contains { $0.kind == .assistantText && $0.text == "The route is ready." })
    }

    @Test func reasoningAndRealToolLifecyclesSurviveWhileDiscoveryStaysHidden() throws {
        var accumulator = AgentEventAccumulator(run: .init(groupID: UUID()))
        let startedAt = Date()
        accumulator.apply(.reasoningStarted(.init(id: "reasoning-real", title: String(localized: "Thinking"),
                                                startedAt: startedAt)))
        accumulator.apply(.reasoningDelta(id: "reasoning-real", text: "Checking route options."))
        accumulator.apply(.reasoningCompleted(id: "reasoning-real"))
        accumulator.apply(.toolCallStarted(.parse(id: "load", name: "load_skill", argumentsJSON: "{}")))
        accumulator.apply(.toolCallStarted(.parse(id: "route", name: "get_route", argumentsJSON: "{}")))
        accumulator.apply(.toolExecutionStarted(.init(id: "route:execution", callID: "route",
            name: "get_route", startedAt: startedAt)))

        let active = AgentActivityComposer.compose(accumulator.run).activities
        #expect(active.map(\.id) == ["reasoning-real", "route"])
        #expect(active.first?.status == .completed)
        let route = try #require(active.last)
        #expect(route.status == .running)
        #expect(AgentActivityVisibilityPolicy.animatesActivity(kind: route.kind.rawValue,
            status: route.status.rawValue, isRunActive: true, hasAnswerText: false, isAwaitingApproval: false))
        #expect(accumulator.run.steps.contains { $0.toolCallID == "load" },
            "Hiding preparation must not delete the canonical audit")

        accumulator.apply(.toolExecutionFailed(id: "route:execution", error: .init(message: "Route unavailable")))
        let failed = try #require(AgentActivityComposer.compose(accumulator.run).activities.last)
        #expect(failed.id == route.id && failed.status == .failed)
        #expect(failed.errorDescription == "Route unavailable")
        #expect(!AgentActivityVisibilityPolicy.animatesActivity(kind: failed.kind.rawValue,
            status: failed.status.rawValue, isRunActive: true, hasAnswerText: false, isAwaitingApproval: false))
    }

    @Test func onlyActualRequestReceiptShowsWaitingAndFirstSemanticOutputClearsIt() throws {
        var accumulator = AgentEventAccumulator(run: .init(groupID: UUID()))
        accumulator.apply(.modelRoundStarted(id: "inline-tool-round"))
        #expect(accumulator.run.pendingModelRequestID == nil,
            "A round may be an inline tool and is not evidence of a model request")
        accumulator.apply(.modelRequestStarted(id: "provider-step-1"))
        #expect(accumulator.run.pendingModelRequestID == "provider-step-1")
        #expect(accumulator.run.steps.isEmpty, "Request latency must not become a fabricated tool stage")
        let restored = try JSONDecoder().decode(AgentRun.self, from: JSONEncoder().encode(accumulator.run))
        #expect(restored.pendingModelRequestID == "provider-step-1")

        accumulator.apply(.modelRequestStarted(id: "provider-step-2"))
        accumulator.apply(.modelRequestEnded(id: "provider-step-1"))
        #expect(accumulator.run.pendingModelRequestID == "provider-step-2",
            "A delayed older request end cannot stop the current indicator")
        accumulator.apply(.reasoningStarted(.init(id: "reasoning", title: String(localized: "Thinking"), startedAt: .now)))
        #expect(accumulator.run.pendingModelRequestID == nil)
        #expect(AgentActivityComposer.compose(accumulator.run).activities.first?.kind == .reasoning)

        accumulator.apply(.modelRequestStarted(id: "provider-step-3"))
        accumulator.apply(.answerSegmentStarted(.init(id: "answer", title: "Answer", startedAt: .now)))
        #expect(accumulator.run.pendingModelRequestID == nil,
            "A provider without reasoning still removes waiting at its first answer")
        accumulator.apply(.modelRequestStarted(id: "provider-step-4"))
        accumulator.apply(.toolCallStarted(.parse(id: "search", name: "search_online", argumentsJSON: "{}")))
        #expect(accumulator.run.pendingModelRequestID == nil)
        accumulator.apply(.modelRequestStarted(id: "provider-step-5"))
        accumulator.apply(.modelRequestEnded(id: "provider-step-5"))
        #expect(accumulator.run.pendingModelRequestID == nil)
        accumulator.apply(.modelRequestStarted(id: "provider-step-6"))
        accumulator.apply(.runCancelled)
        #expect(accumulator.run.pendingModelRequestID == nil)
        accumulator.apply(.modelRequestStarted(id: "late-start"))
        #expect(accumulator.run.pendingModelRequestID == nil, "A terminal run cannot be revived")
    }

    @Test func olderStoredRunsDoNotInventPendingRequestReceipt() throws {
        let data = try JSONEncoder().encode(AgentRun(groupID: UUID(), status: .completed))
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "pendingModelRequestID")
        let restored = try JSONDecoder().decode(AgentRun.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(restored.pendingModelRequestID == nil)
        #expect(!AgentActivityHeaderPhase.showsModelRequestStatus(isRunActive: false,
            requestID: restored.pendingModelRequestID, hasAnswerText: false, hasPendingApproval: false))
    }

    @Test func admittedNonTextOutputEndsReasoningWithoutDemotingTheFinalAnswer() throws {
        let run = AgentRun(groupID: UUID())
        var adapter = HanlinStreamEventAdapter(runID: run.id)
        var accumulator = AgentEventAccumulator(run: run)
        let round = UUID()
        for event in adapter.events(from: .init(reasoning: "Preparing the requested image.", modelRoundID: round)) {
            accumulator.apply(event)
        }
        for event in adapter.events(from: .init(agentEvents: [.modelRequestEnded(id: "older-round")])) {
            accumulator.apply(event)
        }
        #expect(AgentActivityComposer.compose(accumulator.run).activities.first?.status == .running)
        // API emits this receipt only after an image is decoded/admitted or a
        // real SDK step finishes. Metadata alone is not visible output.
        for event in adapter.events(from: .init(agentEvents: [.modelRequestEnded(id: round.uuidString)])) {
            accumulator.apply(event)
        }
        #expect(AgentActivityComposer.compose(accumulator.run).activities.first?.status == .completed)
        for event in adapter.events(from: .init(content: "Here is the image.")) { accumulator.apply(event) }
        for event in adapter.completionEvents() { accumulator.apply(event) }
        #expect(AgentTranscriptValidation.finalAnswer(in: accumulator.run.transcriptItems) == "Here is the image.")
    }

}
