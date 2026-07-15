//
//  AgentActivitySummaryView.swift
//  AI_HLY
//

import SwiftUI

struct AgentActivitySummaryView: View {
    let run: AgentRun
    var onLaunchRequest: ((NativeAppLaunchRequest) -> Void)?

    @State private var showsInspector = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var visibleSteps: [AgentActivityStep] {
        Array(run.steps.filter { $0.kind != .result }.suffix(4))
    }

    var body: some View {
        Button {
            showsInspector = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if run.status == .running {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: statusImage)
                    }
                    Text(statusText)
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }

                ForEach(visibleSteps) { step in
                    AgentActivityCompactStepRow(step: step)
                }

                if run.steps.count > visibleSteps.count {
                    Text(String(localized: "More steps"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
        .accessibilityLabel(String(localized: "Open activity"))
        .accessibilityValue(statusText)
        .sheet(isPresented: $showsInspector) {
            AgentActivityInspectorView(run: run, onLaunchRequest: onLaunchRequest)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .animation(reduceMotion ? nil : .smooth, value: run.status)
    }

    private var statusText: String {
        let duration = AgentActivityDurationFormatter.string(run.elapsedTime)
        switch run.status {
        case .pending, .running:
            return String(localized: "Working…")
        case .completed:
            return String(format: String(localized: "Worked for %@"), duration)
        case .failed:
            return String(format: String(localized: "Stopped after %@"), duration)
        case .cancelled:
            return String(format: String(localized: "Cancelled after %@"), duration)
        }
    }

    private var statusImage: String {
        switch run.status {
        case .pending, .running: return "circle.dotted"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .cancelled: return "stop.circle.fill"
        }
    }
}

private struct AgentActivityCompactStepRow: View {
    let step: AgentActivityStep

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: step.status == .running ? "circle.fill" : statusImage)
                .font(.caption2)
                .foregroundStyle(step.status == .failed ? .red : .secondary)
            Text(step.userFacingSummary ?? step.title)
                .font(.caption)
                .foregroundStyle(step.status == .running ? .primary : .secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusImage: String {
        switch step.status {
        case .pending: return "circle"
        case .running: return "circle.fill"
        case .completed: return "checkmark.circle"
        case .failed: return "exclamationmark.circle"
        case .cancelled: return "stop.circle"
        }
    }
}

enum AgentActivityDurationFormatter {
    static func string(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = interval < 60 ? [.second] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter.string(from: max(0, interval)) ?? "0"
    }
}
