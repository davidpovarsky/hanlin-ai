import SwiftUI

struct AgentTranscriptActivityRow: View {
    let item: AgentTranscriptItem
    let activity: AgentDisplayActivity?
    let onSelectActivity: (String) -> Void

    var body: some View {
        let family = ChatPresentationBridge.executionFamily(
            for: activity?.kind,
            toolName: item.toolName
        )
        let title = activity?.narrativeText ?? activity?.title ?? item.text ?? String(localized: "Thinking")
        let queries = activity?.queries ?? []

        ChatExecutionTimelineItemView(
            familyID: family,
            title: title,
            subtitle: activity?.subtitle,
            status: activity?.status ?? item.status,
            queries: queries,
            inputPreview: activity?.inputPreview,
            outputPreview: activity?.outputPreview,
            errorDescription: activity?.errorDescription,
            onOpenDetails: {
                AgentActivityTrace.selected(item: item)
                onSelectActivity(selectionID)
            }
        )
        .accessibilityLabel(title)
        .accessibilityValue(statusLabel)
        .accessibilityHint(String(localized: "Open activity"))
    }

    var selectionID: String {
        item.externalID ?? item.id.uuidString
    }

    private var iconName: String {
        if let systemImage = activity?.systemImage { return systemImage }
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
        log("agent_inspector_closed", runID: runID, selectedActivityID: nil)
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
