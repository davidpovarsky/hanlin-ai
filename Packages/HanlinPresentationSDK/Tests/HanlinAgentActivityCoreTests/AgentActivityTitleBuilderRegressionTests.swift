import Foundation
import Testing
import HanlinPresentationKit
import HanlinAgentActivityCore

@MainActor
@Suite("Original activity-title SDK regressions")
struct AgentActivityTitleBuilderRegressionTests {
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
