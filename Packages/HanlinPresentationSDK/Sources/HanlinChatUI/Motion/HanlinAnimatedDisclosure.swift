#if canImport(SwiftUI)
import SwiftUI

/// Original implementation informed by Fatbobman's height/spacing discussion:
/// https://fatbobman.com/en/posts/taming-row-height-and-spacing-jumps/
/// No Gist source is incorporated (no explicit license was found).
/// The chat's LazyVStack remains the scrolling/layout owner.
public struct HanlinAnimatedDisclosure<Content: View>: View {
    let isExpanded: Bool
    var spacing: CGFloat = 6
    @ViewBuilder let content: () -> Content

    public init(isExpanded: Bool, spacing: CGFloat = 6, @ViewBuilder content: @escaping () -> Content) {
        self.isExpanded = isExpanded; self.spacing = spacing; self.content = content
    }

    @Environment(\.chatMotion) private var motion
    @State private var mounted = false
    @State private var progress: CGFloat = 0
    @State private var revision = 0

    public var body: some View {
        ChatDisclosureLayout(progress: progress, spacing: spacing) {
            if mounted {
                VStack(alignment: .leading, spacing: 6, content: content)
                    .transition(.identity)
            }
        }
        .opacity(motion.collapsedOpacity + (1 - motion.collapsedOpacity) * Double(progress))
        .clipped()
        .contentShape(Rectangle())
        .allowsHitTesting(isExpanded)
        .accessibilityHidden(!isExpanded)
        .onAppear { settle() }
        .onChange(of: isExpanded) { _, _ in transition() }
        .onChange(of: motion.isAnimated) { _, animated in
            if !animated { settle() }
        }
    }

    private func settle() {
        revision += 1
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            mounted = isExpanded
            progress = isExpanded ? 1 : 0
        }
    }

    private func transition() {
        guard motion.isAnimated else { settle(); return }
        // Keep the animatable ChatDisclosureLayout mounted at progress == 0 so
        // first expand starts immediately without an extra child onAppear turn.
        animateToTarget()
    }

    private func animateToTarget() {
        guard motion.isAnimated else { settle(); return }
        revision += 1
        let currentRevision = revision
        let expanding = isExpanded
        withAnimation(motion.disclosureAnimation(expanding: expanding), completionCriteria: .removed) {
            if expanding { mounted = true }
            progress = expanding ? 1 : 0
        } completion: {
            guard revision == currentRevision, !isExpanded, !expanding else { return }
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { mounted = false }
        }
    }
}

/// Keep native DisclosureGroup ownership/identity, sharing only its presentation.
public struct HanlinMotionDisclosureStyle: DisclosureGroupStyle {
    public init() {}
    @Environment(\.chatMotion) private var motion

    public func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                configuration.isExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    configuration.label
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 180 : 0))
                        .animation(motion.disclosureAnimation(expanding: configuration.isExpanded), value: configuration.isExpanded)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? Text("Expanded") : Text("Collapsed"))
            HanlinAnimatedDisclosure(isExpanded: configuration.isExpanded) {
                configuration.content
            }
        }
    }
}

/// Only the reported height and the gap change. Text always receives an
/// unconstrained height proposal, including while interrupted/reversed.
private struct ChatDisclosureLayout: Layout {
    var progress: CGFloat
    let spacing: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let natural = subview.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        // Use the same width for measurement and placement. A narrower reported
        // text width can otherwise rewrap during placement and change its height.
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? natural.width
        return CGSize(width: width, height: (natural.height + spacing) * min(1, max(0, progress)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let subview = subviews.first else { return }
        let naturalProposal = ProposedViewSize(width: bounds.width, height: nil)
        subview.place(at: CGPoint(x: bounds.minX, y: bounds.minY + spacing * min(1, max(0, progress))),
            anchor: .topLeading, proposal: naturalProposal)
    }
}

#endif
