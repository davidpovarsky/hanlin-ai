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

struct ChatAutoFollowLayout: Equatable {
    let contentHeight: Double
    let viewportHeight: Double
    let bottomInset: Double
}

@MainActor
@Observable
final class ChatAutoFollowController {
    private(set) var state = ChatAutoFollowState()
    private let waitBeforeScroll: @MainActor () async throws -> Void
    @ObservationIgnored private var pendingScroll: Task<Void, Never>?
    @ObservationIgnored private var pendingID: UUID?
    @ObservationIgnored private var pendingAnimated = false
    @ObservationIgnored private var pendingForced = false
    @ObservationIgnored private var pendingAction: (@MainActor (Bool) -> Void)?
    @ObservationIgnored private var requested = 0
    @ObservationIgnored private var performed = 0
    @ObservationIgnored private var coalesced = 0

    init(waitBeforeScroll: @escaping @MainActor () async throws -> Void = {
        try await Task.sleep(for: .milliseconds(80))
    }) {
        self.waitBeforeScroll = waitBeforeScroll
    }

    var mode: ChatAutoFollowMode { state.mode }

    func beginRun() {
        cancelPendingScroll()
        state.mode = .following
        state.isUserInteracting = false
        trace("autoFollowEnabled")
    }

    func updateNearBottom(_ isNearBottom: Bool) {
        state.isNearBottom = isNearBottom
    }

    func userInteractionBegan() {
        cancelPendingScroll()
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

    func pauseFollowing(reason: String) {
        cancelPendingScroll()
        state.mode = .pausedByUser
        state.isUserInteracting = false
        trace("autoFollowPausedByUser", fields: ["reason": reason])
    }

    func resumeFollowing(reason: String = "bottomButton") {
        let wasPaused = state.mode == .pausedByUser
        state.mode = .following
        state.isUserInteracting = false
        if wasPaused { trace("autoFollowResumed", fields: ["reason": reason]) }
    }

    func shouldRequestScrollForVisualUpdate() -> Bool {
        guard state.mode == .following, !state.isUserInteracting else { return false }
        return true
    }

    /// A fixed coalescing window, not a trailing debounce. Continuous streaming
    /// cannot postpone scrolling indefinitely by restarting the timer.
    func scheduleScroll(animated: Bool, force: Bool = false, action: @escaping @MainActor (Bool) -> Void) {
        guard force || shouldRequestScrollForVisualUpdate() else { return }
        requested += 1
        pendingAnimated = pendingAnimated || animated
        pendingForced = pendingForced || force
        pendingAction = action
        guard pendingScroll == nil else { coalesced += 1; return }
        let id = UUID()
        pendingID = id
        pendingScroll = Task { [weak self, waitBeforeScroll] in
            do { try await waitBeforeScroll() } catch {
                if self?.pendingID == id { self?.clearPendingScroll() }
                return
            }
            guard let self, !Task.isCancelled, self.pendingID == id else { return }
            let animated = self.pendingAnimated, force = self.pendingForced, action = self.pendingAction
            self.clearPendingScroll()
            guard force || self.shouldRequestScrollForVisualUpdate() else { return }
            self.performed += 1
            self.trace("autoFollowScrollPerformed", fields: ["requested": self.requested,
                "performed": self.performed, "coalesced": self.coalesced, "forced": force])
            action?(animated)
        }
    }

    func cancelPendingScroll() {
        pendingScroll?.cancel()
        clearPendingScroll()
    }

    private func clearPendingScroll() {
        pendingScroll = nil
        pendingID = nil
        pendingAnimated = false
        pendingForced = false
        pendingAction = nil
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
