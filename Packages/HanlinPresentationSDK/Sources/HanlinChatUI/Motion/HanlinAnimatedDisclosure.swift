import HanlinLocalization
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
#if canImport(UIKit)
import UIKit
#endif

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
    @State private var nativeContentHidden = true
    @State private var transitionGeneration: UInt = 0

    public var body: some View {
        ChatDisclosureLayout(progress: progress, spacing: spacing) {
            if mounted {
                retainedContent
                    .transition(.identity)
            }
        }
        .opacity(motion.collapsedOpacity + (1 - motion.collapsedOpacity) * Double(progress))
        .clipped()
        .contentShape(Rectangle())
        .allowsHitTesting(isExpanded)
        .onAppear { settle() }
        .onChange(of: isExpanded) { _, _ in transition() }
        .onChange(of: motion.isAnimated) { _, animated in
            if !animated { settle() }
        }
    }

    private var disclosureContent: some View {
        VStack(alignment: .leading, spacing: 6, content: content)
            // A zero-height clip alone leaves retained selectable text in AX.
            // Keep the existing measured subtree, hiding its render endpoint.
            .modifier(ChatDisclosureContentVisibility(progress: progress))
            // Suppress retained descendants at their own AX boundary.
            // Hiding the container alone leaves native-backed children exposed.
            .accessibilityElement(children: isExpanded ? .contain : .ignore)
            // Do not override a nested disclosure's hidden state on expand.
            .accessibilityHidden(true, isEnabled: !isExpanded)
    }

    @ViewBuilder
    private var retainedContent: some View {
        #if canImport(UIKit)
        ChatDisclosureAccessibilityScope(isHidden: !isExpanded,
            isPhysicallyHidden: nativeContentHidden, content: disclosureContent)
        #else
        disclosureContent
        #endif
    }

    private func settle() {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            transitionGeneration &+= 1
            nativeContentHidden = !isExpanded
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
        let expanding = isExpanded
        transitionGeneration &+= 1
        let generation = transitionGeneration
        // Restore the same native subtree before its opening animation begins.
        if expanding { nativeContentHidden = false }
        // Reuse the measured content across animated collapse and reversal.
        // Recreating complex descendants here can delay the next visible frame
        // past rapid input. The native visibility gate closes only after the
        // original reveal animation finishes, without unmounting that content.
        withAnimation(motion.disclosureAnimation(expanding: expanding), completionCriteria: .removed) {
            if expanding { mounted = true }
            progress = expanding ? 1 : 0
        } completion: {
            // A reversal or an immediate settle invalidates an older completion.
            guard !expanding, transitionGeneration == generation else { return }
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { nativeContentHidden = true }
        }
    }
}

/// Keep the retained subtree render-hidden at the fully collapsed endpoint.
/// Interpolated progress preserves the preset's opacity for every visible frame;
/// using the target state here would change the entire collapse's fade curve.
private nonisolated struct ChatDisclosureContentVisibility: ViewModifier, Animatable {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.opacity(ChatDisclosureGeometry.fraction(Double(progress)) > 0 ? 1 : 0)
    }
}

#if canImport(UIKit)
/// Own the native semantic boundary for the retained content. On iOS, the
/// transparent SwiftUI clip can still expose native-backed accessibility nodes.
/// This root is created once while mounted. Completed collapse detaches the
/// owned child controller/view; reopening reattaches that same hosting graph.
@MainActor
private struct ChatDisclosureAccessibilityScope<Content: View>: UIViewControllerRepresentable {
    let isHidden: Bool
    let isPhysicallyHidden: Bool
    let content: Content

    struct Root: View {
        let content: Content
        let environment: EnvironmentValues
        let isHidden: Bool

        var body: some View {
            // Forward the complete environment, including custom chat values.
            // Virtual SwiftUI children belong to this hosting graph, so its
            // semantic visibility must receive the same logical disclosure state.
            content.environment(\.self, environment)
                .accessibilityHidden(true, isEnabled: isHidden)
        }
    }

    // Keep the same hosting graph alive while its native presentation leaves the
    // container. isHidden alone leaves SwiftUI automation children discoverable.
    final class ContainerController: UIViewController {
        let hostingController: UIHostingController<Root>

        init(rootView: Root) {
            hostingController = UIHostingController(rootView: rootView)
            super.init(nibName: nil, bundle: nil)
            hostingController.safeAreaRegions = []
            hostingController.sizingOptions = [.intrinsicContentSize]
            hostingController.view.backgroundColor = .clear
            hostingController.view.isAccessibilityElement = false
            hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        }

        required init?(coder: NSCoder) { return nil }

        override func loadView() {
            let container = ContainerView(frame: .zero)
            container.hostedView = hostingController.view
            container.backgroundColor = .clear
            container.isAccessibilityElement = false
            view = container
        }

        func updateVisibility(isHidden: Bool, isPhysicallyHidden: Bool) {
            hostingController.view.isHidden = isPhysicallyHidden
            hostingController.view.accessibilityElementsHidden = isHidden
            view.accessibilityElementsHidden = isHidden
            if isPhysicallyHidden {
                if hostingController.parent === self {
                    hostingController.willMove(toParent: nil)
                    hostingController.view.removeFromSuperview()
                    hostingController.removeFromParent()
                }
            } else if hostingController.parent == nil {
                addChild(hostingController)
                hostingController.view.frame = view.bounds
                view.addSubview(hostingController.view)
                hostingController.didMove(toParent: self)
            }
            view.invalidateIntrinsicContentSize()
        }
    }

    // Preserve the hosting view's intrinsic fallback for unspecified proposals,
    // including while its view is detached but its measured content is retained.
    private final class ContainerView: UIView {
        weak var hostedView: UIView?

        override var intrinsicContentSize: CGSize {
            hostedView?.intrinsicContentSize ?? super.intrinsicContentSize
        }

        override func sizeThatFits(_ size: CGSize) -> CGSize {
            hostedView?.sizeThatFits(size) ?? super.sizeThatFits(size)
        }
    }

    func makeUIViewController(context: Context) -> ContainerController {
        let controller = ContainerController(rootView: Root(content: content, environment: context.environment, isHidden: isHidden))
        controller.updateVisibility(isHidden: isHidden, isPhysicallyHidden: isPhysicallyHidden)
        return controller
    }

    func updateUIViewController(_ controller: ContainerController, context: Context) {
        withTransaction(context.transaction) {
            controller.hostingController.rootView = Root(content: content, environment: context.environment, isHidden: isHidden)
        }
        controller.updateVisibility(isHidden: isHidden, isPhysicallyHidden: isPhysicallyHidden)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiViewController controller: ContainerController,
                      context: Context) -> CGSize? {
        // Unspecified width uses the hosting view's native intrinsic sizing.
        // Height is always natural, never the collapsing viewport's height.
        guard let width = proposal.width, width.isFinite else { return nil }
        let natural = controller.hostingController.sizeThatFits(in: CGSize(width: max(0, width), height: .greatestFiniteMagnitude))
        return CGSize(width: ChatDisclosureGeometry.extent(Double(natural.width)),
            height: ChatDisclosureGeometry.extent(Double(natural.height)))
    }
}
#endif

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
            .accessibilityValue(configuration.isExpanded ? Text("Expanded", bundle: HanlinLocalization.bundle) : Text("Collapsed", bundle: HanlinLocalization.bundle))
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
