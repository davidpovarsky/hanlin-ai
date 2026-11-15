import SwiftUI

/// Original implementation informed by Fatbobman's height/spacing discussion:
/// https://fatbobman.com/en/posts/taming-row-height-and-spacing-jumps/
/// No Gist source is incorporated (no explicit license was found).
/// The chat's LazyVStack remains the scrolling/layout owner.
struct HanlinAnimatedDisclosure<Content: View>: View {
    let isExpanded: Bool
    var spacing: CGFloat = 6
    @ViewBuilder let content: () -> Content

    @Environment(\.chatMotion) private var motion
    @State private var mounted = false
    @State private var progress: CGFloat = 0
    @State private var revision = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if mounted {
                ChatDisclosureLayout(progress: progress, spacing: spacing) {
                    VStack(alignment: .leading, spacing: 6, content: content)
                        .opacity(motion.collapsedOpacity + (1 - motion.collapsedOpacity) * Double(progress))
                        .scaleEffect(x: 1, y: motion.collapsedScale + (1 - motion.collapsedScale) * Double(progress), anchor: .top)
                }
                .clipped()
                .contentShape(Rectangle())
                .allowsHitTesting(isExpanded)
                .accessibilityHidden(!isExpanded)
                .onAppear {
                    if isExpanded && progress == 0 { animateToTarget() }
                }
            }
        }
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
        // Mount at zero without inheriting a caller's animation. No timers or
        // measured-height state; natural size is read during each layout pass.
        if isExpanded && !mounted {
            revision += 1
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { mounted = true; progress = 0 }
            return // The mounted child's onAppear starts from its rendered zero height.
        }
        animateToTarget()
    }

    private func animateToTarget() {
        guard motion.isAnimated else { settle(); return }
        revision += 1
        let currentRevision = revision
        let expanding = isExpanded
        withAnimation(motion.disclosureAnimation(expanding: expanding), completionCriteria: .removed) {
            progress = expanding ? 1 : 0
        } completion: {
            guard revision == currentRevision, !isExpanded, !expanding else { return }
            mounted = false
        }
    }
}

/// Keep native DisclosureGroup ownership/identity, sharing only its presentation.
struct HanlinMotionDisclosureStyle: DisclosureGroupStyle {
    @Environment(\.chatMotion) private var motion

    func makeBody(configuration: Configuration) -> some View {
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
        let natural = subviews.first?.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)) ?? .zero
        // Use the same width for measurement and placement. A narrower reported
        // text width can otherwise rewrap during placement and change its height.
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? natural.width
        return CGSize(width: width, height: (natural.height + spacing) * min(1, max(0, progress)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let naturalProposal = ProposedViewSize(width: bounds.width, height: nil)
        subviews.first?.place(at: CGPoint(x: bounds.minX, y: bounds.minY + spacing * min(1, max(0, progress))),
            anchor: .topLeading, proposal: naturalProposal)
    }
}
