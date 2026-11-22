import Foundation

// Compile with the production AgentActivityHeaderPhase.swift and
// AgentActivityVisibilityPolicy.swift, ChatMotionConfiguration.swift and
// HanlinAnimatedDisclosure.swift. This does not replace Apple UI acceptance.
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
        // Regression from 145801: the tree, phase and owner must agree on a
        // real reasoning event before any tool invocation exists.
        let semanticReasoning = AgentActivityVisibilityPolicy.showsActivity(
            kind: "reasoning", toolName: nil, hasIdentity: true)
        check(semanticReasoning, "Provider reasoning must survive activity composition")
        check(!AgentActivityVisibilityPolicy.showsActivity(
            kind: "reasoning", toolName: nil, hasIdentity: false),
            "A generic waiting label cannot invent provider reasoning")
        let reasonPhase = AgentActivityHeaderPhase.resolve(isRunActive: true,
            hasPendingApproval: false, hasActiveReasoning: semanticReasoning)
        check(reasonPhase == .working && reasonPhase.showsShimmer,
            "A reasoning-only response must have a live activity header")
        let reasonMotion = AgentActivityVisibilityPolicy.animatesActivity(kind: "reasoning",
            status: "running", isRunActive: true, hasAnswerText: false, isAwaitingApproval: false)
        check(reasonMotion, "The active reasoning leaf keeps the canonical blue sweep")
        let reasonPath = Owner.Path(activityID: "reasoning-1", roundID: "round-1", isRoundExpanded: true)
        check(Owner.resolve(isWorking: reasonPhase.showsShimmer, isHierarchyExpanded: true,
            activePaths: reasonMotion ? [reasonPath] : []) == [.activity("reasoning-1")],
            "Reasoning-only expansion must not drop all animated owners")
        check(Owner.resolve(isWorking: reasonPhase.showsShimmer, isHierarchyExpanded: false,
            activePaths: reasonMotion ? [reasonPath] : []) == [.root],
            "Collapsing real reasoning transfers its sweep to the visible root")
        check(!AgentActivityVisibilityPolicy.animatesActivity(kind: "reasoning",
            status: "running", isRunActive: true, hasAnswerText: true, isAwaitingApproval: false),
            "First answer text suppresses a stale running reasoning row")
        check(AgentActivityHeaderPhase.resolve(isRunActive: true, hasPendingApproval: false,
            hasAnswerText: true, hasActiveReasoning: true) == .history,
            "An answer must not keep a misleading Thinking header alive")
        for status in ["pending", "completed", "failed", "cancelled"] {
            check(!AgentActivityVisibilityPolicy.animatesActivity(kind: "reasoning",
                status: status, isRunActive: true, hasAnswerText: false, isAwaitingApproval: false),
                "Only the real running reasoning lifetime animates")
        }
        check(!AgentActivityVisibilityPolicy.animatesActivity(kind: "reasoning",
            status: "running", isRunActive: false, hasAnswerText: false, isAwaitingApproval: false),
            "Historical reasoning must remain static even with stale persisted status")
        check(AgentActivityHeaderPhase.resolve(isRunActive: true, hasPendingApproval: true,
            hasActiveReasoning: true) == .awaitingApproval,
            "A consent wait must not be described as ongoing model reasoning")
        for kind in ["tool", "search", "source", "document", "code", "map", "calendar", "health"] {
            check(AgentActivityVisibilityPolicy.animatesActivity(kind: kind, status: "running",
                isRunActive: true, hasAnswerText: true, isAwaitingApproval: false),
                "Actual parallel tool execution may continue while answer text exists")
            check(!AgentActivityVisibilityPolicy.animatesActivity(kind: kind, status: "running",
                isRunActive: true, hasAnswerText: false, isAwaitingApproval: true),
                "Permission wait never masquerades as running execution")
        }
        check(!AgentActivityVisibilityPolicy.animatesActivity(kind: "narrative", status: "running",
            isRunActive: true, hasAnswerText: false, isAwaitingApproval: false),
            "Transport prose never owns the blue sweep")
        // Real SDK request admission is distinct from reasoning. It must stay
        // visible even when a provider sends no reasoning channel at all.
        let admittedRequest = AgentActivityHeaderPhase.showsModelRequestStatus(
            isRunActive: true, requestID: "provider-step-1", hasAnswerText: false, hasPendingApproval: false)
        check(admittedRequest, "A real dispatched request must not leave an empty assistant")
        check(!AgentActivityHeaderPhase.showsModelRequestStatus(
            isRunActive: true, requestID: nil, hasAnswerText: false, hasPendingApproval: false),
            "Creating a run without dispatch does not fabricate model activity")
        check(!AgentActivityHeaderPhase.showsModelRequestStatus(
            isRunActive: true, requestID: "", hasAnswerText: false, hasPendingApproval: false),
            "Empty transport identity is not a dispatch receipt")
        for (active, answer, approval) in [(false, false, false), (true, true, false), (true, false, true)] {
            check(!AgentActivityHeaderPhase.showsModelRequestStatus(isRunActive: active,
                requestID: "provider-step-1", hasAnswerText: answer, hasPendingApproval: approval),
                "History, answer text and consent wait end the pre-output label")
        }
        let requestPhase = AgentActivityHeaderPhase.resolve(isRunActive: true,
            hasPendingApproval: false, hasPendingModelRequest: admittedRequest)
        let requestPath = Owner.Path(activityID: "model-request:provider-step-1",
            roundID: nil, isRoundExpanded: true)
        check(requestPhase == .working, "An admitted request owns live motion before output")
        check(Owner.resolve(isWorking: requestPhase.showsShimmer, isHierarchyExpanded: false,
            activePaths: [requestPath]) == [.root], "Collapsed pending request has one visible owner")
        check(Owner.resolve(isWorking: requestPhase.showsShimmer, isHierarchyExpanded: true,
            activePaths: [requestPath]) == [.activity("model-request:provider-step-1")],
            "Expanded pending request animates its semantic leaf, not the parent")
        check(AgentActivityHeaderPhase.resolve(isRunActive: true, hasPendingApproval: false,
            hasAnswerText: true, hasPendingModelRequest: true) == .history,
            "First answer suppresses even a delayed request receipt")
        check(AgentActivityHeaderPhase.resolve(isRunActive: false, hasPendingApproval: false,
            hasPendingModelRequest: true) == .history, "Reloaded request receipt cannot animate history")
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
