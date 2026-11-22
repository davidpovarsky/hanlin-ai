#if canImport(SwiftUI)
import SwiftUI
import HanlinPresentationKit

/// One original Host request, in the same V17 surface as its actions. Neither
/// disclosure nor dismissal grants permission or synthesizes execution success.
public struct HanlinInlineToolApproval: View {
    public let requestID: String
    public let toolName: String
    public let reviewText: String
    public let remembersDecision: Bool
    public let displayTitle: String?
    public let systemImage: String
    public let scopeSummary: String?
    public let requiresDetailedReview: Bool
    private let answer: (Bool) -> Void
    @State private var detailsExpanded = false
    @State private var detailsReviewed = false
    @State private var decisionSubmitted = false
    @ScaledMetric(relativeTo: .footnote) private var titleSize: CGFloat = 14

    private let blue = Color(red: 0.28, green: 0.49, blue: 0.80)
    private let ink = Color(red: 0.27, green: 0.43, blue: 0.65)

    public init(requestID: String, toolName: String, reviewText: String, remembersDecision: Bool = false,
                displayTitle: String? = nil, systemImage: String = "hand.raised",
                scopeSummary: String? = nil, requiresDetailedReview: Bool = true,
                answer: @escaping (Bool) -> Void) {
        self.requestID = requestID; self.toolName = toolName
        self.reviewText = reviewText; self.answer = answer
        self.remembersDecision = remembersDecision
        self.displayTitle = displayTitle; self.systemImage = systemImage
        self.scopeSummary = scopeSummary; self.requiresDetailedReview = requiresDetailedReview
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Button {
                    detailsExpanded.toggle()
                    if detailsExpanded { detailsReviewed = true }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: systemImage)
                            .font(HanlinTypography.body.weight(.medium)).foregroundStyle(ink)
                            .frame(width: 19, height: 22).accessibilityHidden(true)
                        Text(displayTitle ?? String(localized: "Review request details"))
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
                            .fixedSize(horizontal: false, vertical: true)
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
                Text(toolName)
                    .font(HanlinTypography.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.leading, 27)
                HanlinToolDetailsText(reviewText, maximumHeight: 240,
                    accessibilityIdentifier: "hanlin-tool-consent-original-request")
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
            detailsReviewed = false
        }
    }

    private var hasReviewText: Bool {
        !reviewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var requestDescription: some View {
        VStack(alignment: .leading, spacing: 2) {
            if hasReviewText {
                if requiresDetailedReview {
                    Button {
                        detailsExpanded = true
                        detailsReviewed = true
                    } label: {
                        Text(scopeSummary ?? String(localized: "Review request details"))
                            .font(HanlinTypography.caption.weight(.medium))
                            .foregroundStyle(ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("hanlin-tool-consent-visible-request")
                } else {
                    Text(scopeSummary ?? String(localized: "Review request details"))
                        .font(HanlinTypography.caption.weight(.medium))
                        .foregroundStyle(Color.primary.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("hanlin-tool-consent-visible-request")
                }
            } else {
                Text("Request details are unavailable.")
                    .font(HanlinTypography.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(LocalizedStringKey(remembersDecision
                ? "This permission will also apply in your other conversations."
                : "Review this operation before allowing it once."))
                .font(HanlinTypography.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                Text(LocalizedStringKey(remembersDecision ? "Allow and remember" : "Allow once"))
                    .font(HanlinTypography.caption.weight(.semibold))
                    .foregroundStyle(ink)
                    .padding(.horizontal, 13).frame(minHeight: 36)
                    .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(blue.opacity(0.14), lineWidth: 0.7))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canAllow)
            .accessibilityIdentifier(remembersDecision ? "hanlin-tool-consent-allow-remember" : "hanlin-tool-consent-allow-once")
        }
        .fixedSize(horizontal: true, vertical: false)
        .disabled(decisionSubmitted)
    }

    private func submit(_ allowed: Bool) {
        guard !decisionSubmitted, !allowed || canAllow else { return }
        decisionSubmitted = true
        answer(allowed)
    }

    private var canAllow: Bool {
        hasReviewText && (!requiresDetailedReview || detailsReviewed)
    }
}

/// Technical payloads wrap inside a finite, single-axis viewport. Concrete
/// positive sizing prevents unspecified biaxial viewport measurements during
/// disclosure probes; it does not identify a particular crash's root cause.
public struct HanlinToolDetailsText: View {
    private let text: String
    private let maximumHeight: CGFloat
    private let identifier: String
    @ScaledMetric(relativeTo: .caption) private var lineHeight: CGFloat = 18

    public init(_ text: String, maximumHeight: CGFloat = 280,
                accessibilityIdentifier: String = "hanlin-tool-content-expanded-text") {
        self.text = text
        self.maximumHeight = maximumHeight.isFinite ? min(480, max(52, maximumHeight)) : 280
        self.identifier = accessibilityIdentifier
    }

    private var viewportHeight: CGFloat {
        let lineCount = text.split(separator: "\n", omittingEmptySubsequences: false).count
        let estimatedLines = max(lineCount, Int(ceil(Double(text.count) / 52)))
        let safeLineHeight = lineHeight.isFinite ? min(160, max(1, lineHeight)) : 18
        let estimatedHeight = CGFloat(estimatedLines) * safeLineHeight + 16
        return min(maximumHeight, max(52, estimatedHeight.isFinite ? estimatedHeight : maximumHeight))
    }

    public var body: some View {
        ScrollView(.vertical) {
            Text(text)
                .font(HanlinTypography.caption.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .accessibilityIdentifier(identifier)
        }
        .frame(height: viewportHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
