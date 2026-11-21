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
}
