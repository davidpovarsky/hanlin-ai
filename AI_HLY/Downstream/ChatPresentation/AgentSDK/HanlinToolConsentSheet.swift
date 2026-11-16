import SwiftUI

/// The user reviews the same immutable request the original Host will validate again.
/// Dismissal, timeout, cancellation and context changes all revoke this one-use request.
struct HanlinToolConsentSheet: View {
    let request: HanlinAppToolConsent.Request
    let answer: (Bool) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Tool", value: request.tool)
                    Text("This operation uses Hanlin’s access. Review its request before allowing it once.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Request") {
                    Text(String(decoding: request.invocation.originalArgumentsJSON ?? Data(), as: UTF8.self))
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .accessibilityIdentifier("hanlin-tool-consent-original-request")
                }
            }
            .navigationTitle("Allow tool operation?")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { answer(false) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Allow once") { answer(true) }
                        .accessibilityIdentifier("hanlin-tool-consent-allow-once")
                }
            }
        }
    }
}

#if DEBUG && targetEnvironment(simulator)
struct HanlinPhase2AcceptanceStatusView: View {
    let isResponding: Bool
    let conversationID: UUID?
    @State private var requests = 0
    var body: some View {
        HStack {
            Text("\(requests)").accessibilityIdentifier("hanlin-phase2-request-count")
            Text(conversationID?.uuidString ?? "unavailable").accessibilityIdentifier("hanlin-phase2-chat-id")
        }
        .font(.caption2)
        .task {
            while !Task.isCancelled {
                let observed = AgentRuntimeUIAcceptanceURLProtocol.observedPhase2Requests
                if requests != observed { requests = observed }
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            }
        }
    }
}
#endif
