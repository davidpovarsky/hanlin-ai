import SwiftUI
import HanlinChatUI

extension View {
    func hanlinFeedback<Trigger: Equatable>(_ feedback: HanlinFeedback,
                                            trigger: Trigger) -> some View {
        modifier(HanlinFeedbackModifier(feedback, trigger: trigger))
    }
}
