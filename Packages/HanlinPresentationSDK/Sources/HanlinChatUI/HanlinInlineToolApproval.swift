#if canImport(SwiftUI)
import SwiftUI
import HanlinPresentationKit

/// One original Host request, in the same V17 surface as its actions. Neither
/// disclosure nor dismissal grants permission or synthesizes execution success.
public struct HanlinInlineToolApproval: View {
    public let requestID: String
    public let toolName: String
    public let reviewText: String
    private let answer: (Bool) -> Void
    @State private var detailsExpanded = false
    @State private var decisionSubmitted = false
    @ScaledMetric(relativeTo: .footnote) private var titleSize: CGFloat = 14

    private let blue = Color(red: 0.28, green: 0.49, blue: 0.80)
    private let ink = Color(red: 0.27, green: 0.43, blue: 0.65)

    public init(requestID: String, toolName: String, reviewText: String,
                answer: @escaping (Bool) -> Void) {
        self.requestID = requestID; self.toolName = toolName
        self.reviewText = reviewText; self.answer = answer
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Button { detailsExpanded.toggle() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "hand.raised")
                            .font(HanlinTypography.body.weight(.medium)).foregroundStyle(.gray)
                            .frame(width: 19, height: 22).accessibilityHidden(true)
                        Text("Allow \(toolName)?")
                            .font(HanlinTypography.fixed(size: titleSize, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true).layoutPriority(1)
                        HanlinActivityDisclosureArrow(isExpanded: detailsExpanded)
                        Spacer(minLength: 2)
                        Image(systemName: "lock.shield")
                            .font(HanlinTypography.caption2.weight(.medium))
                            .foregroundStyle(ink.opacity(0.85)).accessibilityHidden(true)
                        Text("Awaiting approval")
                            .font(HanlinTypography.caption2.weight(.medium))
                            .foregroundStyle(ink.opacity(0.88))
                    }
                    .frame(minHeight: 26).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("hanlin-tool-consent-review-toggle")
                .accessibilityValue(detailsExpanded ? Text("Expanded") : Text("Collapsed"))

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 10) {
                        requestDescription.frame(minWidth: 180, alignment: .leading)
                        Spacer(minLength: 0)
                        actions
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        requestDescription
                        HStack { Spacer(minLength: 0); actions }
                    }
                }
                .padding(.leading, 27)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color(red: 0.952, green: 0.971, blue: 0.990)))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(blue.opacity(0.16), lineWidth: 0.8))

            HanlinAnimatedDisclosure(isExpanded: detailsExpanded, spacing: 0) {
                ScrollView([.horizontal, .vertical]) {
                    Text(reviewText).font(HanlinTypography.footnote.monospaced())
                        .textSelection(.enabled)
                        .accessibilityIdentifier("hanlin-tool-consent-original-request")
                }
                .frame(maxHeight: 240)
                .padding(.leading, 27).padding(.top, 3).padding(.bottom, 8)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color.primary.opacity(0.10))
                        .frame(width: 1).padding(.leading, 10).accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hanlin-tool-approval-\(requestID)")
        .onChange(of: requestID) { _, _ in
            decisionSubmitted = false
            detailsExpanded = false
        }
    }

    private var hasReviewText: Bool {
        !reviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var requestDescription: some View {
        VStack(alignment: .leading, spacing: 2) {
            if hasReviewText {
                // The Host currently supplies redacted arguments, not a typed
                // recipient/scope summary. Show every original field verbatim;
                // never infer a friendlier scope from arbitrary JSON keys.
                // A bounded native viewport keeps all long/unstructured input
                // scrollable without line limits, ellipsis or hidden fields.
                ScrollView(.vertical) { visibleRequestText }
                    .frame(height: 112)
            } else {
                Text("Request details are unavailable.")
                    .font(HanlinTypography.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Review this operation before allowing it once.")
                .font(HanlinTypography.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var visibleRequestText: some View {
        Text(reviewText)
            .font(HanlinTypography.caption.monospaced())
            .foregroundStyle(Color.primary.opacity(0.75))
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .accessibilityIdentifier("hanlin-tool-consent-visible-request")
    }

    private var actions: some View {
        HStack(spacing: 7) {
            Button(role: .cancel) { submit(false) } label: {
                Text("Deny").font(HanlinTypography.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9).frame(minHeight: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("hanlin-tool-consent-deny")
            Button { submit(true) } label: {
                Text("Allow once").font(HanlinTypography.caption.weight(.semibold))
                    .foregroundStyle(ink)
                    .padding(.horizontal, 13).frame(minHeight: 36)
                    .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(blue.opacity(0.14), lineWidth: 0.7))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!hasReviewText)
            .accessibilityIdentifier("hanlin-tool-consent-allow-once")
        }
        .fixedSize(horizontal: true, vertical: false)
        .disabled(decisionSubmitted)
    }

    private func submit(_ allowed: Bool) {
        guard !decisionSubmitted, !allowed || hasReviewText else { return }
        decisionSubmitted = true
        answer(allowed)
    }
}
#endif
