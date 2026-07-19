import Foundation
import Observation

enum ChatAutoFollowMode: String, Hashable, Sendable {
    case following
    case pausedByUser
}

struct ChatAutoFollowState: Equatable, Sendable {
    var mode: ChatAutoFollowMode = .following
    var isNearBottom = true
    var isUserInteracting = false
}

@MainActor
@Observable
final class ChatAutoFollowController {
    private(set) var state = ChatAutoFollowState()

    var mode: ChatAutoFollowMode { state.mode }

    func beginRun() {
        state.mode = .following
        state.isUserInteracting = false
        trace("autoFollowEnabled")
    }

    func updateNearBottom(_ isNearBottom: Bool) {
        state.isNearBottom = isNearBottom
    }

    func userInteractionBegan() {
        state.isUserInteracting = true
    }

    func userInteractionEnded() {
        guard state.isUserInteracting else { return }
        state.isUserInteracting = false
        if state.isNearBottom {
            resumeFollowing(reason: "manualBottom")
        } else if state.mode != .pausedByUser {
            state.mode = .pausedByUser
            trace("autoFollowPausedByUser")
        }
    }

    func resumeFollowing(reason: String = "bottomButton") {
        let wasPaused = state.mode == .pausedByUser
        state.mode = .following
        state.isUserInteracting = false
        if wasPaused { trace("autoFollowResumed", fields: ["reason": reason]) }
    }

    func shouldRequestScrollForVisualUpdate() -> Bool {
        guard state.mode == .following, !state.isUserInteracting else { return false }
        trace("autoFollowScrollRequested")
        return true
    }

    func runEnded() {
        state.isUserInteracting = false
    }

    private func trace(_ event: String, fields: [String: Any] = [:]) {
        guard AgentDiagnosticsConfiguration.level != .off else { return }
        var metadata = fields
        metadata["autoFollowMode"] = state.mode.rawValue
        metadata["isNearBottom"] = state.isNearBottom
        NativeToolTraceLogger.shared.log(event, metadata)
    }
}
