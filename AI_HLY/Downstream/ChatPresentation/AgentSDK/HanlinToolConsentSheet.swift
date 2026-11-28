import HanlinLocalization
import SwiftUI

/// The user reviews the same immutable request the original Host will validate again.
/// Dismissal, timeout, cancellation and context changes reject the pending request.
struct HanlinToolConsentSheet: View {
    let request: HanlinAppToolConsent.Request
    let answer: (Bool) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(hanlin: "Tool", value: request.tool)
                    Text(request.remembersDecision
                        ? String(localized: "This permission will also apply in your other conversations.", bundle: HanlinLocalization.bundle)
                        : String(localized: "This operation uses Hanlin’s access. Review its request before allowing it once.", bundle: HanlinLocalization.bundle))
                        .font(HanlinTypography.footnote).foregroundStyle(.secondary)
                }
                Section(hanlin: "Request") {
                    Text(String(decoding: request.originalArgumentsJSON ?? Data(), as: UTF8.self))
                        .font(HanlinTypography.footnote.monospaced())
                        .textSelection(.enabled)
                        .accessibilityIdentifier("hanlin-tool-consent-original-request")
                }
            }
            .navigationTitle(Text("Allow tool operation?", bundle: HanlinLocalization.bundle))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(hanlin: "Cancel", role: .cancel) { answer(false) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(request.remembersDecision ? String(localized: "Allow and remember", bundle: HanlinLocalization.bundle) : String(localized: "Allow once", bundle: HanlinLocalization.bundle)) { answer(true) }
                        .accessibilityIdentifier("hanlin-tool-consent-allow-once")
                }
            }
        }
    }
}

#if (DEBUG || HANLIN_TESTING) && targetEnvironment(simulator)
struct HanlinPhase2AcceptanceStatusView: View {
    let isResponding: Bool
    let conversationID: UUID?
    @State private var requests = 0
    var body: some View {
        HStack {
            Text("\(requests)", bundle: HanlinLocalization.bundle).accessibilityIdentifier("hanlin-phase2-request-count")
            Text(conversationID?.uuidString ?? "unavailable").accessibilityIdentifier("hanlin-phase2-chat-id")
        }
        .font(HanlinTypography.caption2)
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
