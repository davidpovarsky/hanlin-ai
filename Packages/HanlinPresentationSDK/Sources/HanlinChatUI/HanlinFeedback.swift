#if canImport(UIKit)
import SwiftUI
import UIKit

public enum HanlinFeedback: Sendable {
    case impact, selection, increase, success, warning, error
}

/// UIKit generates the event synchronously, without retaining a SwiftUI graph
/// location after a transient row/popover is removed. This avoids the exact
/// LocationBasedFeedbackAdaptor path in the owner's iPad crash report.
@MainActor
private final class HanlinFeedbackPlayer {
    static let shared = HanlinFeedbackPlayer()
    private let impact = UIImpactFeedbackGenerator(style: .medium)
    private let selection = UISelectionFeedbackGenerator()
    private let notification = UINotificationFeedbackGenerator()
    private var lastFeedback: ContinuousClock.Instant?

    func play(_ feedback: HanlinFeedback) {
        let now = ContinuousClock.now
        // Several controls can observe the same action. Generate one event.
        if let lastFeedback, now - lastFeedback < .milliseconds(75) { return }
        lastFeedback = now
        switch feedback {
        case .impact: impact.impactOccurred()
        case .selection, .increase: selection.selectionChanged()
        case .success: notification.notificationOccurred(.success)
        case .warning: notification.notificationOccurred(.warning)
        case .error: notification.notificationOccurred(.error)
        }
    }
}

public struct HanlinFeedbackModifier<Trigger: Equatable>: ViewModifier {
    let feedback: HanlinFeedback
    let trigger: Trigger

    public init(_ feedback: HanlinFeedback, trigger: Trigger) {
        self.feedback = feedback
        self.trigger = trigger
    }

    public func body(content: Content) -> some View {
        content.onChange(of: trigger) { _, _ in
            HanlinFeedbackPlayer.shared.play(feedback)
        }
    }
}
#endif
