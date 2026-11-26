#if canImport(UIKit)
import HanlinLocalization
import HanlinPresentationKit
import SwiftUI
import UIKit

public extension EnvironmentValues {
    @Entry var chatMessageLongPressPreview: (@MainActor (UIView, CGPoint) -> Void)? = nil
}

/// Nonselectable model headers keep message actions available for rich-only replies.
/// This anchor owns no recognizer and never intercepts a native selection surface.
@MainActor
private final class HanlinMessagePreviewAnchorReference {
    weak var view: UIView?
}

private struct HanlinMessagePreviewAnchor: UIViewRepresentable {
    let reference: HanlinMessagePreviewAnchorReference
    func makeCoordinator() -> HanlinMessagePreviewAnchorReference { reference }
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        reference.view = view
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) { reference.view = uiView }
    static func dismantleUIView(_ uiView: UIView, coordinator: HanlinMessagePreviewAnchorReference) {
        if coordinator.view === uiView { coordinator.view = nil }
    }
}

private struct HanlinMessagePreviewSource: ViewModifier {
    @State private var anchor = HanlinMessagePreviewAnchorReference()
    let action: @MainActor (UIView, CGPoint) -> Void

    func body(content: Content) -> some View {
        content
            .background { HanlinMessagePreviewAnchor(reference: anchor) }
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 1.0, maximumDistance: 10) { present() }
            .accessibilityAction(named: Text("Message actions", bundle: HanlinLocalization.bundle)) { present() }
    }

    private func present() {
        guard let view = anchor.view, view.window != nil else { return }
        action(view, CGPoint(x: view.bounds.midX, y: view.bounds.midY))
    }
}

public extension View {
    /// Apply only to a nonselectable header; text uses UITextView's own routing.
    func chatMessagePreviewSource(_ action: @escaping @MainActor (UIView, CGPoint) -> Void) -> some View {
        modifier(HanlinMessagePreviewSource(action: action))
    }
}

/// A deliberate long hold has its own public gesture. The selection surface
/// remains owned by UITextView, and no SwiftUI context menu competes with it.
@MainActor
public enum HanlinMessagePreviewPresenter {
    public struct Style {
        public let locale: Locale
        public let layoutDirection: LayoutDirection
        public let colorScheme: ColorScheme
        public let dynamicTypeSize: DynamicTypeSize

        public init(locale: Locale, layoutDirection: LayoutDirection,
                    colorScheme: ColorScheme, dynamicTypeSize: DynamicTypeSize) {
            self.locale = locale; self.layoutDirection = layoutDirection
            self.colorScheme = colorScheme; self.dynamicTypeSize = dynamicTypeSize
        }
    }
    public typealias Action = HanlinMessageAction

    public static func present<Content: View>(
        from source: UIView, at point: CGPoint, preferredWidth: CGFloat,
        style: Style, actions: [Action], @ViewBuilder content: () -> Content
    ) {
        guard let window = source.window, source.bounds.width.isFinite, source.bounds.height.isFinite,
              source.bounds.width > 0, source.bounds.height > 0, point.x.isFinite, point.y.isFinite,
              let metrics = HanlinMessagePreviewMetrics.fitting(preferredWidth: Double(preferredWidth),
                windowWidth: Double(window.bounds.width), windowHeight: Double(window.bounds.height)) else { return }
        var responder: UIResponder? = source
        while responder != nil, !(responder is UIViewController) { responder = responder?.next }
        guard var presenter = responder as? UIViewController else { return }
        while let presented = presenter.presentedViewController, !presented.isBeingDismissed { presenter = presented }
        guard !presenter.isBeingDismissed, presenter.viewIfLoaded?.window === window else { return }

        let size = CGSize(width: metrics.width, height: metrics.height)
        let previewContent = content()
        let controller = UIHostingController(rootView: HanlinMessagePreview(content: previewContent, style: style, actions: actions))
        controller.rootView = HanlinMessagePreview(content: previewContent, style: style, actions: actions) { [weak controller] action in
            controller?.dismiss(animated: true) { action.perform() }
        }
        controller.modalPresentationStyle = .popover
        controller.preferredContentSize = size
        if let popover = controller.popoverPresentationController {
            // Anchor to the live controller, not a recyclable Markdown paragraph.
            let anchor = source.convert(point, to: presenter.view)
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: min(max(0, anchor.x), presenter.view.bounds.width),
                                       y: min(max(0, anchor.y), presenter.view.bounds.height), width: 1, height: 1)
        }
        presenter.present(controller, animated: true)
    }
}

private struct HanlinMessagePreview<Content: View>: View {
    let content: Content
    let style: HanlinMessagePreviewPresenter.Style
    let actions: [HanlinMessagePreviewPresenter.Action]
    var select: ((HanlinMessagePreviewPresenter.Action) -> Void)? = nil

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ScrollView {
                    content
                        .environment(\.chatMessageLongPressPreview, nil)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: min(300, max(0, geometry.size.height * 0.46)))
                .accessibilityIdentifier("hanlin-message-preview-content")
                Divider()
                List(actions) { action in
                    Button(role: action.role) { select?(action) } label: {
                        Label(action.title, systemImage: action.symbol)
                            .font(HanlinTypography.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .disabled(!action.isEnabled)
                    .accessibilityIdentifier("hanlin-message-menu-" + action.id)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // UIKit owns the actual viewport, including keyboard/split-view clamping.
        // preferredContentSize is only a request; the content always fits it.
        .environment(\.locale, style.locale)
        .environment(\.layoutDirection, style.layoutDirection)
        .environment(\.colorScheme, style.colorScheme)
        .environment(\.dynamicTypeSize, style.dynamicTypeSize)
        .background(.background)
        .accessibilityIdentifier("hanlin-message-preview")
    }
}
#endif
