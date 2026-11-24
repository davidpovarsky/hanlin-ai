import HanlinLocalization
import HanlinPresentationKit
import SwiftUI
import UIKit

extension EnvironmentValues {
    @Entry var chatMessageLongPressPreview: (@MainActor (UIView, CGPoint) -> Void)? = nil
}

/// Nonselectable model headers keep message actions available for rich-only replies.
/// This anchor owns no recognizer and never intercepts a native selection surface.
@MainActor
private final class ChatMessagePreviewAnchorReference {
    weak var view: UIView?
}

private struct ChatMessagePreviewAnchor: UIViewRepresentable {
    let reference: ChatMessagePreviewAnchorReference
    func makeCoordinator() -> ChatMessagePreviewAnchorReference { reference }
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        reference.view = view
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) { reference.view = uiView }
    static func dismantleUIView(_ uiView: UIView, coordinator: ChatMessagePreviewAnchorReference) {
        if coordinator.view === uiView { coordinator.view = nil }
    }
}

private struct ChatMessagePreviewSource: ViewModifier {
    @State private var anchor = ChatMessagePreviewAnchorReference()
    let action: @MainActor (UIView, CGPoint) -> Void

    func body(content: Content) -> some View {
        content
            .background { ChatMessagePreviewAnchor(reference: anchor) }
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 1.0, maximumDistance: 10) { present() }
            .accessibilityAction(named: Text("Message actions", bundle: HanlinLocalization.bundle)) { present() }
    }

    private func present() {
        guard let view = anchor.view, view.window != nil else { return }
        action(view, CGPoint(x: view.bounds.midX, y: view.bounds.midY))
    }
}

extension View {
    /// Apply only to a nonselectable header; text uses UITextView's own routing.
    func chatMessagePreviewSource(_ action: @escaping @MainActor (UIView, CGPoint) -> Void) -> some View {
        modifier(ChatMessagePreviewSource(action: action))
    }
}

/// A deliberate long hold has its own public gesture. The selection surface
/// remains owned by UITextView, and no SwiftUI context menu competes with it.
@MainActor
enum ChatMessagePreviewPresenter {
    struct Style {
        let locale: Locale
        let layoutDirection: LayoutDirection
        let colorScheme: ColorScheme
        let dynamicTypeSize: DynamicTypeSize
    }
    struct Action: Identifiable {
        let id: String
        let title: String
        let symbol: String
        var role: ButtonRole? = nil
        let perform: @MainActor () -> Void
    }

    static func present(from source: UIView, at point: CGPoint, preferredWidth: CGFloat,
                        text: String, citations: HanlinMessageCitations?, style: Style, actions: [Action]) {
        guard let window = source.window, source.bounds.width.isFinite, source.bounds.height.isFinite,
              source.bounds.width > 0, source.bounds.height > 0, point.x.isFinite, point.y.isFinite,
              let metrics = ChatMessagePreviewMetrics.fitting(preferredWidth: Double(preferredWidth),
                windowWidth: Double(window.bounds.width), windowHeight: Double(window.bounds.height)) else { return }
        var responder: UIResponder? = source
        while responder != nil, !(responder is UIViewController) { responder = responder?.next }
        guard var presenter = responder as? UIViewController else { return }
        while let presented = presenter.presentedViewController, !presented.isBeingDismissed { presenter = presented }
        guard !presenter.isBeingDismissed, presenter.viewIfLoaded?.window === window else { return }

        let size = CGSize(width: metrics.width, height: metrics.height)
        let controller = UIHostingController(rootView: ChatMessagePreview(text: text, citations: citations, style: style, actions: actions))
        controller.rootView = ChatMessagePreview(text: text, citations: citations, style: style, actions: actions) { [weak controller] action in
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

private struct ChatMessagePreview: View {
    let text: String
    let citations: HanlinMessageCitations?
    let style: ChatMessagePreviewPresenter.Style
    let actions: [ChatMessagePreviewPresenter.Action]
    var select: ((ChatMessagePreviewPresenter.Action) -> Void)? = nil

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ScrollView {
                    ChatMarkdownView(text: text)
                        .environment(\.hanlinMessageCitations, citations)
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
