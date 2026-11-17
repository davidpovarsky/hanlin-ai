#if canImport(SwiftUI)
import SwiftUI

/// Presentation of the original Host's pending one-use request. The host supplies
/// safe review text and handles both buttons against the immutable request ID.
/// Dismissing a view does not create an approval or a synthetic execution result.
public struct HanlinInlineToolApproval: View {
    public let requestID: String
    public let toolName: String
    public let reviewText: String
    private let answer: (Bool) -> Void
    @State private var detailsExpanded = false

    public init(requestID: String, toolName: String, reviewText: String,
                answer: @escaping (Bool) -> Void) {
        self.requestID = requestID; self.toolName = toolName
        self.reviewText = reviewText; self.answer = answer
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Allow \(toolName)?", systemImage: "hand.raised")
                .font(.subheadline.weight(.semibold))
            Text("Review this operation before allowing it once.")
                .font(.footnote).foregroundStyle(.secondary)
            DisclosureGroup("Request", isExpanded: $detailsExpanded) {
                ScrollView(.horizontal) {
                    Text(reviewText).font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .accessibilityIdentifier("hanlin-tool-consent-original-request")
                }
            }
            .disclosureGroupStyle(HanlinMotionDisclosureStyle())
            .accessibilityIdentifier("hanlin-tool-consent-review-toggle")
            HStack(spacing: 16) {
                Button("Deny", role: .cancel) { answer(false) }
                    .accessibilityIdentifier("hanlin-tool-consent-deny")
                Button("Allow once") { answer(true) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("hanlin-tool-consent-allow-once")
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hanlin-tool-approval-\(requestID)")
    }
}
#endif
