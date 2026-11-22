import Foundation

// Compile with the production AgentActivityHeaderPhase.swift and
// ChatMotionConfiguration.swift and HanlinAnimatedDisclosure.swift. This does not replace Apple UI acceptance.
@main
struct AgentActivityHeaderChecks {
    static func main() {
        var checks = 0
        func check(_ condition: Bool, _ label: String) {
            precondition(condition, label)
            checks += 1
        }
        for pending in [false, true] {
            let history = AgentActivityHeaderPhase.resolve(isRunActive: false, hasPendingApproval: pending)
            check(history == .history, "A terminal/reopened message must be history")
            check(!history.showsShimmer, "A stale approval must not revive historical motion")
        }
        let working = AgentActivityHeaderPhase.resolve(isRunActive: true, hasPendingApproval: false,
            hasActiveOperation: true)
        check(working == .working && working.showsShimmer, "Only live work shimmers")
        let waiting = AgentActivityHeaderPhase.resolve(isRunActive: true, hasPendingApproval: true)
        check(waiting == .awaitingApproval && !waiting.showsShimmer, "Permission wait stops the live title")
        for active in [false, true] {
            for current in [false, true] {
                for hasHeader in [false, true] {
                    for hasAnswer in [false, true] {
                        let actual = AgentActivityHeaderPhase.showsStandaloneStatus(
                            isRunActive: active, isCurrentMessage: current,
                            hasActivityHeader: hasHeader, hasAnswerText: hasAnswer)
                        let expected = false
                        check(actual == expected, "Standalone status stops on the first answer text")
                    }
                }
            }
        }
        for active in [false, true] {
            for pending in [false, true] {
                for answer in [false, true] {
                    for operation in [false, true] {
                        let phase = AgentActivityHeaderPhase.resolve(isRunActive: active,
                            hasPendingApproval: pending, hasAnswerText: answer,
                            hasActiveOperation: operation)
                        let expected: AgentActivityHeaderPhase = !active ? .history
                            : pending && !operation ? .awaitingApproval : operation ? .working : .history
                        check(phase == expected, "Answer activity transition preserves real tool/approval lifetime")
                    }
                }
            }
        }
        typealias Owner = AgentActivityShimmerOwner
        let expandedPath = Owner.Path(activityID: "search", roundID: "round-1", isRoundExpanded: true)
        let collapsedPath = Owner.Path(activityID: "search", roundID: "round-1", isRoundExpanded: false)
        check(Owner.resolve(isWorking: true, isHierarchyExpanded: false,
            activePaths: [expandedPath]) == [.root], "Collapsed root owns active sweep")
        check(Owner.resolve(isWorking: true, isHierarchyExpanded: true,
            activePaths: [collapsedPath]) == [.round("round-1")], "Nearest collapsed parent owns active sweep")
        check(Owner.resolve(isWorking: true, isHierarchyExpanded: true,
            activePaths: [expandedPath]) == [.activity("search")], "Expanded hierarchy animates only the leaf")
        let parallel = [collapsedPath,
            Owner.Path(activityID: "read", roundID: "round-1", isRoundExpanded: false),
            Owner.Path(activityID: "python", roundID: "round-2", isRoundExpanded: true),
            Owner.Path(activityID: "legacy", roundID: nil, isRoundExpanded: false)]
        check(Owner.resolve(isWorking: true, isHierarchyExpanded: true,
            activePaths: parallel) == [.round("round-1"), .activity("python"), .activity("legacy")],
            "Parallel branches deduplicate ancestors and preserve unattributed calls")
        check(Owner.resolve(isWorking: false, isHierarchyExpanded: true,
            activePaths: parallel).isEmpty, "Terminal or approval wait has no animated owner")
        check(Owner.resolve(isWorking: true, isHierarchyExpanded: true,
            activePaths: []).isEmpty, "No real invocation means no synthetic active ancestor")
        check(AgentActivityHeaderPhase.resolve(isRunActive: true, hasPendingApproval: false) == .history,
            "Provider latency must not fabricate preparing-answer activity")
        for name in ["load_skill", "read_skill_resource", "tool_search", "report_progress", "read_tool_result"] {
            for kind in ["toolCall", "toolExecution", "codeExecution"] {
                check(!AgentActivityVisibilityPolicy.showsInvocation(kind: kind, toolName: name, hasIdentity: true),
                    "Internal capability preparation remains out of the activity tree")
            }
        }
        for name in ["search_online", "get_route", "python", "mcp__custom__load_skill_report"] {
            check(AgentActivityVisibilityPolicy.showsInvocation(kind: "toolExecution", toolName: name, hasIdentity: true),
                "Actual tool calls survive exact internal-name filtering")
            check(!AgentActivityVisibilityPolicy.showsInvocation(kind: "progress", toolName: name, hasIdentity: true),
                "Progress prose is not a new tool invocation")
            check(!AgentActivityVisibilityPolicy.showsInvocation(kind: "toolExecution", toolName: name, hasIdentity: false),
                "No fabricated call without lifecycle identity")
        }
        // UIKit's crash reports abort on a non-finite scroll/layer bound.
        // Check the production geometry including zero, invalid probes and reversal.
        for height in [0.0, 24, 280, 40_000, -.infinity, .infinity, .nan, -1] {
            for progress in [0.0, 0.2, 0.9, 1, 0.7, 0, -0.5, 1.5, .nan, .infinity] {
                let revealed = ChatDisclosureGeometry.revealedHeight(naturalHeight: height,
                    spacing: 6, progress: progress)
                check(revealed.isFinite && revealed >= 0, "Disclosure geometry must remain finite on collapse/reversal")
            }
        }
        check(ChatDisclosureGeometry.revealedHeight(naturalHeight: 280, spacing: 6, progress: 0) == 0,
            "Collapsed outer mask consumes no height")
        check(ChatDisclosureGeometry.revealedHeight(naturalHeight: 280, spacing: 6, progress: 1) == 286,
            "Full reveal preserves natural height and spacing")
        check(ChatDisclosureGeometry.extent(280) == 280, "Child keeps full viewport while parent collapses")
        check(ChatMotionConfiguration.forPreset(.relaxed).shimmerDuration == 1.95, "Canonical V17 default sweep")
        check(ChatMotionConfiguration.forPreset(.heightReveal).shimmerDuration == 2.2, "User-selected tempo preserved")
        check(ChatMotionConfiguration.forPreset(.quietFade).shimmerDuration == 2.6, "Quiet tempo preserved")
        check(!ChatMotionConfiguration.forPreset(.none).showsShimmer, "Motion-off stays off")
        check(!ChatMotionConfiguration.forPreset(.relaxed, reduceMotion: true).showsShimmer, "Reduce Motion stays static")
        print("PASS: \(checks) production activity lifetime and motion-policy checks")
    }
}
