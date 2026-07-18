import SwiftUI

struct AgentTranscriptActivityRow: View {
    let item: AgentTranscriptItem
    let activity: AgentDisplayActivity?
    let onSelectActivity: (String) -> Void

    @ViewBuilder
    var body: some View {
        if let activity {
            AgentActivityStepView(activity: activity, isLast: true) { _ in
                AgentActivityTrace.selected(item: item)
                onSelectActivity(selectionID)
            }
        } else {
            Button {
                AgentActivityTrace.selected(item: item)
                onSelectActivity(selectionID)
            } label: {
                HStack(spacing: 8) {
                    if item.status == .running || item.status == .pending {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: iconName)
                            .font(.caption)
                            .foregroundStyle(item.status == .failed ? .red : .secondary)
                    }
                    Text(item.text ?? String(localized: "Thinking"))
                        .font(.subheadline)
                        .foregroundStyle(item.status == .failed ? .red : .secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.text ?? String(localized: "Thinking"))
            .accessibilityValue(statusLabel)
            .accessibilityHint(String(localized: "Open activity"))
        }
    }

    var selectionID: String {
        item.externalID ?? item.id.uuidString
    }

    private var iconName: String {
        switch activity?.kind {
        case .reasoning: return "bubble.left.and.text.bubble.right"
        case .search: return "magnifyingglass"
        case .source, .document: return "doc.text"
        case .code: return "terminal"
        case .map: return "map"
        case .calendar: return "calendar"
        case .health: return "heart.text.square"
        case .error: return "exclamationmark.circle"
        case .narrative: return "circle.fill"
        case .tool, .result, .none: return "sparkles"
        }
    }

    private var statusLabel: String {
        switch item.status {
        case .pending, .running: return String(localized: "Working…")
        case .completed: return String(localized: "Completed")
        case .failed: return String(localized: "Failed")
        case .cancelled: return String(localized: "Cancelled")
        }
    }
}

enum AgentActivityTrace {
    static func selected(item: AgentTranscriptItem) {
        log("agent_activity_selected", item: item)
    }

    static func inspectorOpened(runID: UUID, selectedActivityID: String?) {
        log("agent_inspector_opened", runID: runID, selectedActivityID: selectedActivityID)
    }

    static func inspectorScrolled(runID: UUID, selectedActivityID: String) {
        log("agent_inspector_scrolled_to_activity", runID: runID, selectedActivityID: selectedActivityID)
    }

    static func inspectorClosed(runID: UUID) {
        log("agent_inspector_closed", runID: runID)
    }

    private static func log(_ event: String, item: AgentTranscriptItem) {
        log(event, runID: nil, selectedActivityID: item.externalID ?? item.id.uuidString)
    }

    private static func log(_ event: String, runID: UUID?, selectedActivityID: String?) {
        guard AgentDiagnosticsConfiguration.level == .fullLocalDebug else { return }
        NativeToolTraceLogger.shared.log(
            event,
            [
                "runID": runID?.uuidString ?? "",
                "selectedActivityID": selectedActivityID ?? ""
            ]
        )
    }
}
