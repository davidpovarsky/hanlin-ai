import SwiftUI

struct AgentActivitySummaryView: View {
    let run: AgentRun
    let onOpenInspector: () -> Void

    private var timeline: AgentDisplayTimeline { AgentActivityComposer.compose(run) }

    var body: some View {
        Button(action: onOpenInspector) {
            HStack(spacing: 7) {
                if run.status == .running || run.status == .pending {
                    ProgressView()
                        .controlSize(.mini)
                }
                Text(timeline.summaryTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(timeline.summaryTitle)
        .accessibilityHint(String(localized: "Open activity"))
    }
}

enum AgentActivityDurationFormatter {
    static func string(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = interval < 60 ? [.second] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: max(0, interval)) ?? "0s"
    }
}
