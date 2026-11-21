import Foundation

// Compile with the production AgentActivityHeaderPhase.swift and
// ChatMotionConfiguration.swift. This does not replace Apple UI acceptance.
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
        let working = AgentActivityHeaderPhase.resolve(isRunActive: true, hasPendingApproval: false)
        check(working == .working && working.showsShimmer, "Only live work shimmers")
        let waiting = AgentActivityHeaderPhase.resolve(isRunActive: true, hasPendingApproval: true)
        check(waiting == .awaitingApproval && !waiting.showsShimmer, "Permission wait stops the live title")
        for active in [false, true] {
            for current in [false, true] {
                for hasHeader in [false, true] {
                    let actual = AgentActivityHeaderPhase.showsStandaloneStatus(
                        isRunActive: active, isCurrentMessage: current, hasActivityHeader: hasHeader)
                    let expected = active && current && !hasHeader
                    check(actual == expected, "Standalone status must have one live owner")
                }
            }
        }
        check(ChatMotionConfiguration.forPreset(.relaxed).shimmerDuration == 1.95, "Canonical V17 default sweep")
        check(ChatMotionConfiguration.forPreset(.heightReveal).shimmerDuration == 2.2, "User-selected tempo preserved")
        check(ChatMotionConfiguration.forPreset(.quietFade).shimmerDuration == 2.6, "Quiet tempo preserved")
        check(!ChatMotionConfiguration.forPreset(.none).showsShimmer, "Motion-off stays off")
        check(!ChatMotionConfiguration.forPreset(.relaxed, reduceMotion: true).showsShimmer, "Reduce Motion stays static")
        print("PASS: \(checks) production activity lifetime and motion-policy checks")
    }
}
