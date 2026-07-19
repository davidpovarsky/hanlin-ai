import SwiftUI

struct AgentInlineProcessView: View {
    let run: AgentRun
    let timeline: AgentDisplayTimeline
    let onSelectActivity: (String) -> Void

    private var items: [AgentTranscriptItem] {
        run.transcriptItems
            .filter(AgentInlineProcessPolicy.includes)
            .sorted { $0.sequence < $1.sequence }
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(items) { item in
                AgentInlineProcessItemView(
                    item: item,
                    activity: AgentTranscriptPresentation.activity(for: item, in: timeline),
                    onSelectActivity: onSelectActivity
                )
            }
        }
        .padding(.leading, 10)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(.quaternary)
                .frame(width: 1)
        }
    }
}

enum AgentInlineProcessPolicy {
    static func includes(_ item: AgentTranscriptItem) -> Bool {
        guard item.visibilityAfterCompletion == .collapseIntoThinking else { return false }
        if item.kind == .progress,
           AgentActivityCompositionPolicy.isInternalTransportText(item.text ?? "") {
            return false
        }
        switch item.kind {
        case .reasoning, .progress, .toolActivity, .assistantText, .error:
            return item.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        case .userVisibleToolResult:
            return false
        }
    }
}
