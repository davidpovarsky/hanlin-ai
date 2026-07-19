import SwiftUI

struct AgentActivitySummaryView: View {
    let run: AgentRun
    let isExpanded: Bool?
    let onActivate: () -> Void

    private var timeline: AgentDisplayTimeline { AgentActivityComposer.compose(run) }

    init(run: AgentRun, onOpenInspector: @escaping () -> Void) {
        self.run = run
        isExpanded = nil
        onActivate = onOpenInspector
    }

    init(run: AgentRun, isExpanded: Bool, onToggle: @escaping () -> Void) {
        self.run = run
        self.isExpanded = isExpanded
        onActivate = onToggle
    }

    var body: some View {
        Button(action: onActivate) {
            HStack(spacing: 7) {
                if run.status == .running || run.status == .pending {
                    ProgressView()
                        .controlSize(.mini)
                }
                Text(timeline.summaryTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Image(systemName: chevronName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(timeline.summaryTitle)
        .accessibilityHint(accessibilityHint)
    }

    private var chevronName: String {
        guard let isExpanded else { return "chevron.right" }
        return isExpanded ? "chevron.up" : "chevron.down"
    }

    private var accessibilityHint: String {
        guard let isExpanded else { return String(localized: "Open activity") }
        return isExpanded ? String(localized: "Collapse process") : String(localized: "Expand process")
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
