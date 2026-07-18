import SwiftUI

struct AgentActivityInspectorSelection: Identifiable {
    let id = UUID()
    var selectedActivityID: String?
}

struct AgentRunTranscriptView: View {
    let run: AgentRun
    let isResponding: Bool
    let temporaryRecord: Bool
    let usesMathRenderer: Bool
    let rendersFinalAnswer: Bool
    let onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?

    @State private var inspectorSelection: AgentActivityInspectorSelection?

    private var timeline: AgentDisplayTimeline { AgentActivityComposer.compose(run) }
    private var orderedItems: [AgentTranscriptItem] {
        run.transcriptItems
    }
    private var isFinished: Bool {
        run.status != .running && run.status != .pending
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isFinished {
                if run.hasMeaningfulThinkingActivity {
                    AgentActivitySummaryView(run: run) {
                        inspectorSelection = AgentActivityInspectorSelection(selectedActivityID: nil)
                    }
                }
                ForEach(orderedItems.filter { $0.visibilityAfterCompletion == .remainInChat }) { item in
                    transcriptItem(item, isLive: false)
                }
            } else {
                ForEach(orderedItems) { item in
                    transcriptItem(item, isLive: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $inspectorSelection) { selection in
            AgentActivityInspectorView(
                run: run,
                selectedActivityID: selection.selectedActivityID
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private func transcriptItem(_ item: AgentTranscriptItem, isLive: Bool) -> some View {
        switch item.kind {
        case .reasoning, .toolActivity:
            if isLive {
                AgentTranscriptActivityRow(
                    item: item,
                    activity: AgentTranscriptPresentation.activity(for: item, in: timeline)
                ) { selectedID in
                    inspectorSelection = AgentActivityInspectorSelection(selectedActivityID: selectedID)
                }
            }

        case .progress:
            if isLive, let text = nonempty(item.text) {
                Button {
                    AgentActivityTrace.selected(item: item)
                    inspectorSelection = AgentActivityInspectorSelection(
                        selectedActivityID: item.externalID ?? item.id.uuidString
                    )
                } label: {
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(String(localized: "Open activity"))
            }

        case .assistantText:
            if let text = nonempty(item.text), isLive || (rendersFinalAnswer && item.textRole == .final) {
                AgentTranscriptTextView(text: text, usesMathRenderer: usesMathRenderer)
            }

        case .userVisibleToolResult:
            AgentTranscriptToolResultView(
                item: item,
                temporaryRecord: temporaryRecord,
                onLaunchRequest: onLaunchRequest
            )

        case .error:
            if let text = nonempty(item.text) {
                Label(text, systemImage: "exclamationmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

enum AgentTranscriptPresentation {
    static func activity(
        for item: AgentTranscriptItem,
        in timeline: AgentDisplayTimeline
    ) -> AgentDisplayActivity? {
        if let stepID = item.activityStepID,
           let match = timeline.activities.first(where: { $0.sourceStepIDs.contains(stepID) }) {
            return match
        }
        if let callID = item.callID,
           let match = timeline.activities.first(where: { $0.id == callID }) {
            return match
        }
        guard let externalID = item.externalID else { return nil }
        let normalized = externalID
            .replacingOccurrences(of: "tool:", with: "")
            .replacingOccurrences(of: "call:", with: "")
            .replacingOccurrences(of: "execution:", with: "")
            .replacingOccurrences(of: ":execution", with: "")
        return timeline.activities.first { $0.id == externalID || $0.id == normalized }
    }
}
