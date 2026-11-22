import Foundation

/// Finite geometry shared by disclosure measurement and placement. Layout may
/// probe zero/unspecified sizes while attaching scroll-backed descendants.
/// In particular, infinity * 0 must never escape as a NaN layer bound.
public enum ChatDisclosureGeometry {
    public static func extent(_ value: Double) -> Double {
        value.isFinite ? max(0, value) : 0
    }

    public static func fraction(_ progress: Double) -> Double {
        progress.isFinite ? min(1, max(0, progress)) : 0
    }

    public static func revealedHeight(naturalHeight: Double, spacing: Double, progress: Double) -> Double {
        let fullHeight = extent(naturalHeight) + extent(spacing)
        guard fullHeight.isFinite else { return 0 }
        return fullHeight * fraction(progress)
    }
}

#if canImport(SwiftUI)
import SwiftUI
import HanlinPresentationKit

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
        .onDisappear { revision += 1 }
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
                        .font(HanlinTypography.caption.weight(.semibold))
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

/// Only the reported height and the gap change. Measure unconstrained natural
/// height, then place the child at that full height during collapse/reversal.
private struct ChatDisclosureLayout: Layout {
    var progress: CGFloat
    let spacing: CGFloat
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let proposedWidth = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil }
        let natural = subview.sizeThatFits(ProposedViewSize(width: proposedWidth, height: nil))
        let width = proposedWidth ?? CGFloat(ChatDisclosureGeometry.extent(Double(natural.width)))
        let height = ChatDisclosureGeometry.revealedHeight(naturalHeight: Double(natural.height),
            spacing: Double(spacing), progress: Double(progress))
        return CGSize(width: width, height: CGFloat(height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let subview = subviews.first else { return }
        let width = CGFloat(ChatDisclosureGeometry.extent(Double(bounds.width)))
        let natural = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
        let naturalHeight = CGFloat(ChatDisclosureGeometry.extent(Double(natural.height)))
        let gap = CGFloat(ChatDisclosureGeometry.extent(Double(spacing))
            * ChatDisclosureGeometry.fraction(Double(progress)))
        let originX = bounds.minX.isFinite ? bounds.minX : 0
        let originY = bounds.minY.isFinite ? bounds.minY : 0
        // Preserve V17's full natural child height throughout the reveal. The
        // enclosing clip changes; nested ScrollViews never receive the shrinking
        // mask's zero/unspecified height as their attachment viewport.
        subview.place(at: CGPoint(x: originX, y: originY + gap), anchor: .topLeading,
            proposal: ProposedViewSize(width: width, height: naturalHeight))
    }

}

#endif
