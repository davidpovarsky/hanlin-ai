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
        #expect(AgentActivityHeaderPhase.resolve(isRunActive: true, hasPendingApproval: false) == .working)
        let waiting = AgentActivityHeaderPhase.resolve(isRunActive: true, hasPendingApproval: true)
        #expect(waiting == .awaitingApproval)
        #expect(!waiting.showsShimmer)
        #expect(AgentActivityHeaderPhase.resolve(isRunActive: true, hasPendingApproval: false).showsShimmer)
        #expect(!AgentActivityHeaderPhase.resolve(isRunActive: false, hasPendingApproval: false).showsShimmer)
    }

    @Test func historicalFooterAndDuplicateActivityStatusAreHidden() {
        #expect(!AgentActivityHeaderPhase.showsStandaloneStatus(
            isRunActive: false, isCurrentMessage: true, hasActivityHeader: false))
        #expect(!AgentActivityHeaderPhase.showsStandaloneStatus(
            isRunActive: true, isCurrentMessage: false, hasActivityHeader: false))
        #expect(!AgentActivityHeaderPhase.showsStandaloneStatus(
            isRunActive: true, isCurrentMessage: true, hasActivityHeader: true))
        #expect(AgentActivityHeaderPhase.showsStandaloneStatus(
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

}
