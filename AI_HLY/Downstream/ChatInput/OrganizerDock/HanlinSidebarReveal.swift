import SwiftUI
import UIKit

/// The approved sidebar reference contributes motion only. The caller keeps
/// ownership of Hanlin's real history, navigation stack, and persistent composer.
@MainActor
struct HanlinSidebarReveal<Sidebar: View, Content: View>: View {
    @Binding var isPresented: Bool
    let reservesBackGesture: Bool
    let sidebar: Sidebar
    let content: Content

    init(isPresented: Binding<Bool>, reservesBackGesture: Bool,
         @ViewBuilder sidebar: () -> Sidebar, @ViewBuilder content: () -> Content) {
        _isPresented = isPresented
        self.reservesBackGesture = reservesBackGesture
        self.sidebar = sidebar()
        self.content = content()
    }

    @Environment(\.layoutDirection) private var contentDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var translation: CGFloat = 0

    private var settlingAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.88)
    }

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            let sidebarWidth = min(310, width * 0.78)
            let progress = HanlinSidebarDragPolicy.progress(
                isPresented: isPresented, translation: translation, width: sidebarWidth)

            ZStack(alignment: .leading) {
                sidebar
                    .environment(\.layoutDirection, contentDirection)
                    .frame(width: sidebarWidth, height: geometry.size.height)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .accessibilityElement(children: .contain)
                    .contentShape(Rectangle())
                    .scaleEffect(reduceMotion ? 1 : 0.86 + 0.14 * progress,
                                 anchor: UnitPoint(x: 1, y: 0.5))
                    .offset(x: reduceMotion ? 0 : 22 * (1 - progress))
                    .opacity(reduceMotion ? 1 : 0.72 + 0.28 * progress)
                    .allowsHitTesting(isPresented)
                    .accessibilityHidden(!isPresented)

                ZStack {
                    content
                        .environment(\.layoutDirection, contentDirection)
                        // Keep the original subtree mounted while preventing a
                        // tap on the exposed strip from sending or editing a chat.
                        .allowsHitTesting(!isPresented)
                        .accessibilityHidden(isPresented)
                    if isPresented {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { settle(presented: false) }
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: width, height: geometry.size.height)
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: reduceMotion ? 0 : 20 * progress))
                .shadow(color: .black.opacity(reduceMotion ? 0 : 0.13 * progress),
                        radius: 18, x: -4)
                .offset(x: sidebarWidth * progress)
            }
            .frame(width: width, height: geometry.size.height, alignment: .leading)
            .contentShape(Rectangle())
            .clipped()
            // Only physical layer placement is LTR. Each product subtree above
            // retains the app's actual language, including native RTL toolbars.
            .environment(\.layoutDirection, .leftToRight)
            .gesture(HanlinSidebarPan(
                configuration: .init(
                    isEnabled: scenePhase == .active,
                    isPresented: isPresented,
                    reservesBackGesture: reservesBackGesture,
                    contentDirection: contentDirection,
                    size: CGSize(width: width, height: geometry.size.height),
                    sidebarWidth: sidebarWidth),
                onChanged: { delta in
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { translation = delta }
                },
                onEnded: { delta, velocity, cancelled in
                    settle(presented: HanlinSidebarDragPolicy.destination(
                        isPresented: isPresented, translation: delta,
                        velocity: velocity, width: sidebarWidth, cancelled: cancelled))
                }))
            .animation(settlingAnimation, value: isPresented)
            .onChange(of: geometry.size.width) { _, _ in resetTranslation() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { resetTranslation() }
            }
            .onChange(of: isPresented) { _, _ in translation = 0 }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hanlin-sidebar-reveal")
    }

    private func settle(presented: Bool) {
        withAnimation(settlingAnimation) {
            translation = 0
            isPresented = presented
        }
    }

    private func resetTranslation() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { translation = 0 }
    }
}

enum HanlinSidebarDragPolicy {
    static func progress(isPresented: Bool, translation: CGFloat, width: CGFloat) -> CGFloat {
        guard width.isFinite, width > 0, translation.isFinite else { return isPresented ? 1 : 0 }
        return min(1, max(0, (isPresented ? 1 : 0) + translation / width))
    }

    static func destination(isPresented: Bool, translation: CGFloat, velocity: CGFloat,
                            width: CGFloat, cancelled: Bool) -> Bool {
        guard !cancelled, width.isFinite, width > 0,
              translation.isFinite, velocity.isFinite else { return isPresented }
        let projected = (isPresented ? width : 0) + translation + velocity * 0.15
        return projected > width * 0.5
    }
}

/// UIKit performs axis arbitration before recognition, while SwiftUI owns the
/// recognizer's lifetime and view scope. Nothing is installed on a shared window.
@MainActor
struct HanlinSidebarPan: UIGestureRecognizerRepresentable {
    @MainActor
    struct Configuration {
        var isEnabled: Bool
        var isPresented: Bool
        var reservesBackGesture: Bool
        var contentDirection: LayoutDirection
        var size: CGSize
        var sidebarWidth: CGFloat

        func acceptsStart(at point: CGPoint, velocity: CGPoint) -> Bool {
            guard isEnabled, CGRect(origin: .zero, size: size).contains(point),
                  abs(velocity.x) > abs(velocity.y) * 1.3,
                  isPresented ? velocity.x < 0 : velocity.x > 0 else { return false }
            if !isPresented && reservesBackGesture {
                let distanceFromBackEdge = contentDirection == .leftToRight
                    ? point.x : size.width - point.x
                if distanceFromBackEdge < 32 { return false }
            }
            return true
        }
    }

    let configuration: Configuration
    let onChanged: @MainActor (CGFloat) -> Void
    let onEnded: @MainActor (CGFloat, CGFloat, Bool) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(configuration: configuration, converter: converter)
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.maximumNumberOfTouches = 1
        recognizer.cancelsTouchesInView = true
        recognizer.delegate = context.coordinator
        recognizer.isEnabled = configuration.isEnabled
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.configuration = configuration
        // Refresh on every update, including reactivation in the same window.
        recognizer.isEnabled = configuration.isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let delta = context.converter.localTranslation?.x ?? 0
        switch recognizer.state {
        case .began, .changed:
            onChanged(delta)
        case .ended:
            onEnded(delta, context.converter.localVelocity?.x ?? 0, false)
        case .cancelled, .failed:
            onEnded(0, 0, true)
        default:
            break
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var configuration: Configuration
        private let converter: CoordinateSpaceConverter
        private var startPoint: CGPoint = .zero

        init(configuration: Configuration, converter: CoordinateSpaceConverter) {
            self.configuration = configuration
            self.converter = converter
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            startPoint = converter.convert(globalPoint: touch.location(in: nil), to: .local)
            let inSidebar = configuration.isPresented && startPoint.x < configuration.sidebarWidth
            return configuration.isEnabled
                && !Self.preservesNativeInteraction(startingAt: touch.view, inSidebar: inSidebar)
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            configuration.acceptsStart(at: startPoint, velocity: converter.localVelocity ?? .zero)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // Native back navigation owns its screen edge. Do not initiate a
            // reveal and subsequently cancel the navigation controller's gesture.
            otherGestureRecognizer is UIScreenEdgePanGestureRecognizer
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let scroll = otherGestureRecognizer.view as? UIScrollView,
                  otherGestureRecognizer === scroll.panGestureRecognizer else { return false }
            // A strictly horizontal reveal may coexist with vertical scrolling;
            // horizontal carousels, native row actions and text selection keep
            // their own recognizers and are excluded before recognition.
            return !Self.scrollsHorizontally(scroll)
        }

        static func preservesNativeInteraction(startingAt view: UIView?, inSidebar: Bool) -> Bool {
            var candidate = view
            while let current = candidate {
                if current is UIControl || current is UITextView { return true }
                if inSidebar && (current is UITableViewCell || current is UICollectionViewCell) {
                    return true
                }
                if let scroll = current as? UIScrollView, scrollsHorizontally(scroll) { return true }
                candidate = current.superview
            }
            return false
        }

        private static func scrollsHorizontally(_ scroll: UIScrollView) -> Bool {
            scroll.alwaysBounceHorizontal
                || scroll.contentSize.width + scroll.adjustedContentInset.left
                    + scroll.adjustedContentInset.right > scroll.bounds.width + 1
        }
    }
}
