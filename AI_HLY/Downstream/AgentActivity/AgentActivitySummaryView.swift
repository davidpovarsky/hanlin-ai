import SwiftUI

struct AgentActivitySummaryView: View {
    let run: AgentRun
    var onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?

    @State private var isExpanded = false
    @State private var showsInspector = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var timeline: AgentDisplayTimeline { AgentActivityComposer.compose(run) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Button {
                    withAnimation(reduceMotion ? nil : .smooth) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 7) {
                        if run.status == .running || run.status == .pending {
                            ProgressView().controlSize(.mini)
                        }
                        Text(timeline.summaryTitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 6)

                Button {
                    showsInspector = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Open activity"))
            }

            if isExpanded {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(timeline.activities.enumerated()), id: \.element.id) { index, activity in
                        AgentActivityStepView(
                            activity: activity,
                            isLast: index == timeline.activities.count - 1,
                            onLaunchRequest: onLaunchRequest
                        )
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else if run.status == .running,
                      let current = timeline.activities.last(where: { $0.status == .running }) {
                Text(current.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .sheet(isPresented: $showsInspector) {
            AgentActivityInspectorView(run: run, onLaunchRequest: onLaunchRequest)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .animation(reduceMotion ? nil : .smooth, value: run.status)
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
