import Foundation

public enum HanlinChatPresentationMode: String, CaseIterable, Hashable, Sendable {
    case sheet, inspector
}

public enum HanlinLauncherStyle: String, CaseIterable, Hashable, Sendable {
    case toolbarCapsule, floatingCapsule, quickComposer
}

/// A host can allow Sheet only, Inspector only, or both. Empty policies
/// normalize to Sheet; a disallowed initial mode resolves deterministically.
public struct HanlinChatPresentationPolicy: Equatable, Sendable {
    public let modes: Set<HanlinChatPresentationMode>
    public let initialMode: HanlinChatPresentationMode

    public init(modes: Set<HanlinChatPresentationMode> = [.sheet, .inspector],
                initialMode: HanlinChatPresentationMode = .sheet) {
        let allowed: Set<HanlinChatPresentationMode> = modes.isEmpty ? [.sheet] : modes
        self.modes = allowed
        self.initialMode = allowed.contains(initialMode) ? initialMode : (allowed.contains(.sheet) ? .sheet : .inspector)
    }

    public func alternative(to mode: HanlinChatPresentationMode) -> HanlinChatPresentationMode? {
        HanlinChatPresentationMode.allCases.first { $0 != mode && modes.contains($0) }
    }
}

/// Presentation ownership is independent of any host conversation/session.
public struct HanlinChatPresentationState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case closed
        case presented(HanlinChatPresentationMode)
        case dismissing(HanlinChatPresentationMode, next: HanlinChatPresentationMode?)
    }

    public private(set) var phase: Phase = .closed
    public private(set) var policy: HanlinChatPresentationPolicy

    public init(policy: HanlinChatPresentationPolicy = .init()) { self.policy = policy }

    public var mode: HanlinChatPresentationMode? {
        if case let .presented(mode) = phase { return mode }
        return nil
    }
    public var isTransitioning: Bool {
        if case .dismissing = phase { return true }; return false
    }
    public func isShowing(_ mode: HanlinChatPresentationMode) -> Bool {
        phase == .presented(mode)
    }

    @discardableResult
    public mutating func configure(_ policy: HanlinChatPresentationPolicy) -> Bool {
        guard phase == .closed else { return false }
        self.policy = policy
        return true
    }

    public mutating func open(_ mode: HanlinChatPresentationMode? = nil) {
        guard phase == .closed else { return }
        let target = mode ?? policy.initialMode
        guard policy.modes.contains(target) else { return }
        phase = .presented(target)
    }

    public mutating func request(_ target: HanlinChatPresentationMode) {
        guard policy.modes.contains(target) else { return }
        switch phase {
        case .closed: open(target)
        case let .presented(current) where current != target:
            phase = .dismissing(current, next: target)
        default: break
        }
    }

    public mutating func close() {
        switch phase {
        case let .presented(mode), let .dismissing(mode, _):
            phase = .dismissing(mode, next: nil)
        case .closed: break
        }
    }

    public mutating func systemDismissed(_ mode: HanlinChatPresentationMode) {
        if phase == .presented(mode) { close() }
    }

    public mutating func finishDismissal(_ mode: HanlinChatPresentationMode) {
        guard case let .dismissing(outgoing, next) = phase, outgoing == mode else { return }
        phase = next.map(Phase.presented) ?? .closed
    }
}

