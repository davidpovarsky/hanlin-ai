import Foundation

// Executes the production lifecycle, disclosure and summary policies without
// an app host. Full SwiftUI layout and transcript integration have separate gates.
@main
struct AgentActivityLifecycleChecks {
    static func main() throws {
        var count = 0
        func check(_ value: Bool, _ message: String) {
            precondition(value, message)
            count += 1
        }
        for request in [false, true] {
            for reasoning in [false, true] {
                let phase = AgentActivityHeaderPhase.resolve(isRunActive: true,
                    hasPendingApproval: false, hasActiveReasoning: reasoning,
                    hasPendingModelRequest: request)
                check(phase == .working, "Live work cannot become history between events")
            }
        }
        for approval in [false, true] {
            let phase = AgentActivityHeaderPhase.resolve(isRunActive: false,
                hasPendingApproval: approval, hasActiveOperation: true, hasActiveReasoning: true)
            check(phase == .history && !phase.showsShimmer, "History never revives from stale receipts")
        }
        check(AgentActivityHeaderPhase.resolve(isRunActive: true, hasPendingApproval: true) == .awaitingApproval,
            "Approval pauses the model indicator")
        check(AgentActivityHeaderPhase.resolve(isRunActive: true, hasPendingApproval: false,
            hasAnswerText: true) == .history, "A confirmed final answer ends work")
        check(AgentActivityHeaderPhase.resolve(isRunActive: true, hasPendingApproval: false,
            hasAnswerText: true, hasActiveOperation: true) == .working,
            "A genuine concurrent tool must not be marked completed")
        check(AgentActivityShimmerOwner.resolve(isWorking: true,
            isHierarchyExpanded: true, activePaths: []).isEmpty,
            "A live gap has no fabricated thinking or tool animation")
        for status in ["pending", "completed", "failed", "cancelled"] {
            check(!AgentActivityVisibilityPolicy.animatesActivity(kind: "reasoning",
                status: status, isRunActive: true, hasAnswerText: false, isAwaitingApproval: false),
                "Thinking only animates its real running lifetime")
        }
        let run = UUID()
        var state = HanlinActivityDisclosureState(runID: run, phase: .active)
        check(state.isExpanded, "A new run automatically expands")
        state.isExpanded = false
        for _ in 0..<50 {
            state = state.reconciled(runID: run, phase: .active)
            check(!state.isExpanded, "Streaming deltas respect manual collapse")
        }
        let restored = try JSONDecoder().decode(HanlinActivityDisclosureState.self,
            from: JSONEncoder().encode(state))
        check(!restored.reconciled(runID: run, phase: .active).isExpanded,
            "Stored preference survives remount")
        state.isExpanded = true
        state = state.reconciled(runID: run, phase: .answering)
        check(!state.isExpanded, "Final answer automatically collapses")
        state.isExpanded = true
        state = state.reconciled(runID: run, phase: .finished)
        check(state.isExpanded, "Manual history reopening persists")
        check(state.reconciled(runID: UUID(), phase: .active).isExpanded,
            "A new run opens independently of previous choice")
        check(!HanlinActivityDisclosureState(runID: UUID(), phase: .finished).isExpanded,
            "History is initially collapsed")
        state = HanlinActivityDisclosureState(runID: run, phase: .active)
        check(!state.reconciled(runID: run, phase: .finished).isExpanded,
            "Cancellation or failure closes an active tree once")
        let part = "Checking the requested dates and comparing available appointments."
        let longSummary = Array(repeating: part, count: 20).joined(separator: "\n\n")
        check(longSummary.count > 140, "Fixture exceeds the prior disappearing-text limit")
        for prefixLength in [20, 100, 140, 141, 280, 800, longSummary.count] {
            let value = String(longSummary.prefix(prefixLength))
            check(ProgressSummarySanitizer.sanitizeProviderReasoningDisplay(value) ==
                value.trimmingCharacters(in: .whitespacesAndNewlines),
                "Safe growing summary survives every display threshold")
        }
        check(ProgressSummarySanitizer.sanitizeProviderReasoningDisplay(longSummary) == longSummary,
            "Paragraphs remain intact in long displayable summaries")
        let hebrew = "בודק את התאריכים שהתבקשו ומשווה את פרטי הפגישות."
        check(ProgressSummarySanitizer.sanitizeProviderReasoningDisplay(hebrew) == hebrew,
            "Hebrew summary is preserved")
        for unsafe in [
            "Internal reasoning: I need to check a private plan.",
            "<think>Hidden details</think>",
            "{\"private\":true}",
            " "
        ] {
            check(ProgressSummarySanitizer.sanitizeProviderReasoningDisplay(unsafe) == nil,
                "Private reasoning, credentials, JSON and blank receipts are not displayable summaries")
        }
        let accepted = "Checking the appointments returned by the calendar."
        let casual = accepted + "\nI need to check the last appointment before replying."
        check(ProgressSummarySanitizer.sanitizeProviderReasoningDisplay(casual) == casual,
            "Casual phrasing in a public provider channel must not erase visible output")
        for suffix in ["<", "<thi", "<think>", "<think>Private payload",
                       "<think><reasoning>Nested private payload</reasoning>"] {
            check(ProgressSummarySanitizer.sanitizeProviderReasoningDisplay(accepted + "\n" + suffix) == accepted,
                "A later partial or nested private block cannot erase preceding public text")
        }
        let closedPrivate = accepted + "\n<think>Private payload</think>\nThe result is ready."
        let publicText = ProgressSummarySanitizer.sanitizeProviderReasoningDisplay(closedPrivate) ?? ""
        check(publicText.hasPrefix(accepted) && publicText.hasSuffix("The result is ready."),
            "Public text on both sides of a closed private block is retained")
        check(!publicText.contains("Private payload"), "Private block body stays hidden")
        let redacted = ProgressSummarySanitizer.sanitizeProviderReasoningDisplay(
            accepted + "\napi_key=sk-testfixture123456789\nThe result is ready.") ?? ""
        check(redacted.hasPrefix(accepted) && redacted.hasSuffix("The result is ready."),
            "A later credential is redacted without losing public paragraphs")
        check(!redacted.contains("sk-testfixture123456789"), "Credential values remain redacted")
        check(ProgressSummarySanitizer.sanitizeProviderReasoningDisplay(
            accepted + "\nInternal reasoning:\nPrivate section.") == accepted,
            "Explicit private section preserves preceding accepted summary")
        print("PASS: \(count) production activity lifecycle, disclosure and summary checks")
    }
}
