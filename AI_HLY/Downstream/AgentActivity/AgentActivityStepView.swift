import SwiftUI

struct AgentActivityStepView: View {
    let activity: AgentDisplayActivity
    let isLast: Bool
    let onSelectActivity: (String) -> Void

    var body: some View {
        Button {
            onSelectActivity(activity.id)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(spacing: 0) {
                    Image(systemName: iconName)
                        .font(.caption)
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
                        .font(.subheadline.weight(activity.status == .running ? .medium : .regular))
                        .foregroundStyle(activity.status == .failed ? .red : .secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
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
        .accessibilityHint(String(localized: "Open activity"))
    }

    private var iconName: String {
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
        case .pending, .running: return String(localized: "Working…")
        case .completed: return String(localized: "Completed")
        case .failed: return String(localized: "Failed")
        case .cancelled: return String(localized: "Cancelled")
        }
    }
}
