#if HANLIN_A2UI_POC && (DEBUG || HANLIN_TESTING) && targetEnvironment(simulator)
import SwiftUI

/// Only the isolated native HTTP fixture exposes this observation. Values come from the
/// actual transport snapshot, including rejected attempts; this view cannot send a request.
struct HanlinA2UIAcceptanceStatusView: View {
    let isResponding: Bool
    let conversationID: UUID?
    @State private var requestCount = 0
    @State private var failure = "none"

    var body: some View {
        HStack {
            Text("\(requestCount)").accessibilityIdentifier("hanlin-native-a2ui-request-count")
            Text(failure).accessibilityIdentifier("hanlin-native-a2ui-request-failure")
            Text(isResponding ? "running" : "idle").accessibilityIdentifier("hanlin-native-a2ui-state")
            Text(conversationID?.uuidString ?? "unavailable").accessibilityIdentifier("hanlin-native-a2ui-chat-id")
        }
        .font(HanlinTypography.caption2)
        .onChange(of: isResponding, initial: true) { _, _ in
            requestCount = HanlinNativeA2UIAcceptanceProvider.observedRequestCount
            failure = HanlinNativeA2UIAcceptanceProvider.lastRequestFailure ?? "none"
        }
    }
}
#endif
