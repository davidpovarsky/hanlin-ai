import SwiftUI

struct MCPRuntimeStatusView: View {
    let snapshot: MCPRuntimeSnapshot

    var body: some View {
        LabeledContent {
            HStack {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                Text(statusTitle)
            }
            .accessibilityElement(children: .combine)
        } label: {
            Text(MCPL10n.string("Node runtime"))
        }
        if let version = snapshot.nodeVersion {
            LabeledContent(MCPL10n.string("Node version"), value: version)
        }
        LabeledContent(MCPL10n.string("Active workers"), value: "\(snapshot.activeWorkerCount)")
        if let message = snapshot.message {
            Text(message).font(.caption).foregroundStyle(.red)
        }
    }

    private var statusTitle: String {
        switch snapshot.state {
        case .stopped: MCPL10n.string("Stopped")
        case .starting: MCPL10n.string("Starting")
        case .running: MCPL10n.string("Running")
        case .failed: MCPL10n.string("Failed")
        }
    }

    private var statusIcon: String {
        switch snapshot.state {
        case .running: "checkmark.circle.fill"
        case .starting: "clock.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .stopped: "stop.circle"
        }
    }

    private var statusColor: Color {
        switch snapshot.state {
        case .running: .green
        case .starting: .orange
        case .failed: .red
        case .stopped: .secondary
        }
    }
}
