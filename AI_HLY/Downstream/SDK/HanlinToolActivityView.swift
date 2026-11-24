import Foundation
import SwiftUI

/// The exact activity subtree rendered in Hanlin's original message bubble.
/// It retains the original thinking/round/tool hierarchy, animation ownership,
/// expandable output and verified consent actions.
@MainActor
public struct HanlinToolActivityView: View {
    private let message: HanlinConversationMessageSnapshot
    private let controller: HanlinConversationController?
    private let isActive: Bool
    private let hasAnswerText: Bool
    private let externalExpansion: Binding<Bool>?
    @State private var expanded = false

    public init(message: HanlinConversationMessageSnapshot,
                controller: HanlinConversationController? = nil,
                isActive: Bool = false, hasAnswerText: Bool? = nil,
                isExpanded: Binding<Bool>? = nil) {
        self.message = message
        self.controller = controller
        self.isActive = isActive
        self.hasAnswerText = hasAnswerText ?? !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        self.externalExpansion = isExpanded
    }

    public var body: some View {
        let expansion = externalExpansion ?? $expanded
        ChatBubbleView.AgentActivityContentView(
            run: ChatBubbleView.AgentActivityContentView.presentationRun(originalRun),
            reasoning: message.reasoning, reasoningTime: message.reasoningTime,
            legacyToolContent: message.toolContent ?? "",
            disclosureExpanded: expansion.wrappedValue, isExpanded: expansion,
            isActive: isActive, hasAnswerText: hasAnswerText, toolApproval: approval)
            .equatable()
    }

    private var originalRun: AgentRun? {
        message.agentRunJSON.flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONDecoder().decode(AgentRun.self, from: $0) }
    }

    private var approval: ChatToolApprovalPresentation? {
        guard let controller, controller.isRunning,
              controller.projection?.groupBeginMessage.id == message.id,
              controller.sessionOwner.pendingApprovalRowID == message.id,
              let pending = controller.sessionOwner.consent.pending else { return nil }
        return .original(pending) { allowed in
            try? controller.answerApproval(id: pending.id, allowed: allowed)
        }
    }
}
