import SwiftUI

struct MCPInstallProgressView: View {
    let state: MCPInstallState

    var body: some View {
        switch state {
        case .idle:
            EmptyView()
        case .previewing:
            ProgressView(MCPL10n.string("Reading package metadata"))
        case .installing(_, let phase, let fraction):
            VStack(alignment: .leading, spacing: 8) {
                if let fraction { ProgressView(value: fraction) } else { ProgressView() }
                Text(title(for: phase)).font(.caption)
            }
            .accessibilityElement(children: .combine)
        case .completed:
            Label(MCPL10n.string("Installation completed"), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(_, let message, let rollbackMessage):
            VStack(alignment: .leading, spacing: 6) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                if let rollbackMessage {
                    Text(rollbackMessage).font(.caption).textSelection(.enabled)
                }
            }
            .foregroundStyle(.red)
        case .cancelled:
            Label(MCPL10n.string("Installation cancelled"), systemImage: "xmark.circle")
        }
    }

    private func title(for phase: MCPInstallPhase) -> String {
        switch phase {
        case .resolving: MCPL10n.string("Resolving")
        case .downloading: MCPL10n.string("Downloading")
        case .verifying: MCPL10n.string("Verifying")
        case .extracting: MCPL10n.string("Extracting")
        case .installingDependencies: MCPL10n.string("Installing dependencies")
        case .checkingCompatibility: MCPL10n.string("Checking compatibility")
        case .registering: MCPL10n.string("Registering")
        case .starting: MCPL10n.string("Starting")
        case .completed: MCPL10n.string("Completed")
        }
    }
}
