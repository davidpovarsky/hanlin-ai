import HanlinAgentActivityCore
import HanlinPresentationKit
import HanlinLocalization
import SwiftUI

public struct AgentActivityStepView: View {
    public let activity: AgentDisplayActivity
    public let isLast: Bool
    public let onSelectActivity: (String) -> Void

    public var body: some View {
        Button {
            onSelectActivity(activity.id)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 0) {
                    Image(systemName: iconName)
                        .font(HanlinTypography.caption)
                        .foregroundStyle(iconColor)
                        .frame(width: 18, height: 18)
                    if !isLast {
                        Rectangle()
                            .fill(.quaternary)
                            .frame(width: 1)
                            .frame(minHeight: 26)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(activity.narrativeText ?? activity.title)
                        .font(HanlinTypography.subheadline.weight(activity.status == .running ? .medium : .regular))
                        .foregroundStyle(activity.status == .failed ? .red : .secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(HanlinTypography.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.bottom, 12)
            }
            .frame(minHeight: 44, alignment: .top)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(activity.title)
        .accessibilityValue(statusLabel)
        .accessibilityHint(String(localized: "Open activity", bundle: HanlinLocalization.bundle))
    }

    private var iconName: String {
        if let systemImage = activity.systemImage { return systemImage }
        switch activity.kind {
        case .reasoning: return "bubble.left.and.text.bubble.right"
        case .narrative: return "circle.fill"
        case .search: return "magnifyingglass"
        case .source, .document: return "doc.text"
        case .code: return "terminal"
        case .map: return "map"
        case .calendar: return "calendar"
        case .health: return "heart.text.square"
        case .tool: return "sparkles"
        case .result: return "checkmark.circle"
        case .error: return "exclamationmark.circle"
        }
    }

    private var iconColor: Color {
        activity.status == .failed ? .red : .secondary
    }

    private var statusLabel: String {
        switch activity.status {
        case .pending, .running: return String(localized: "Working…", bundle: HanlinLocalization.bundle)
        case .completed: return String(localized: "Completed", bundle: HanlinLocalization.bundle)
        case .failed: return String(localized: "Failed", bundle: HanlinLocalization.bundle)
        case .cancelled: return String(localized: "Cancelled", bundle: HanlinLocalization.bundle)
        }
    }

    public init(
        activity: AgentDisplayActivity,
        isLast: Bool,
        onSelectActivity: @escaping (String) -> Void
    ) {
        self.activity = activity
        self.isLast = isLast
        self.onSelectActivity = onSelectActivity
    }
}
