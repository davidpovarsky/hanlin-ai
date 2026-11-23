#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit

/// Deliver touch-down immediately to controls inside a single containing
/// transcript `UIScrollView` without changing `canCancelContentTouches`,
/// scroll enablement, pan recognition, or global `UIAppearance`.
@MainActor
public struct ChatScrollImmediateContentTouches: UIViewRepresentable {
    public var onScrollViewChanged: @MainActor (UIScrollView?) -> Void = { _ in }

    public init(onScrollViewChanged: @escaping @MainActor (UIScrollView?) -> Void = { _ in }) {
        self.onScrollViewChanged = onScrollViewChanged
    }

    public func makeUIView(context: Context) -> ConfigurationView {
        let view = ConfigurationView()
        view.onScrollViewChanged = onScrollViewChanged
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.backgroundColor = .clear
        return view
    }

    public func updateUIView(_ uiView: ConfigurationView, context: Context) {
        uiView.onScrollViewChanged = onScrollViewChanged
        uiView.applyIfNeeded()
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: ConfigurationView, context: Context) -> CGSize? {
        .zero
    }

    public static func dismantleUIView(_ uiView: ConfigurationView, coordinator: ()) {
        uiView.restoreOriginalValue()
        uiView.onScrollViewChanged = { _ in }
    }

    public final class ConfigurationView: UIView {
        var onScrollViewChanged: @MainActor (UIScrollView?) -> Void = { _ in }
        private weak var observedScrollView: UIScrollView?
        private var originalDelaysContentTouches: Bool?

        public override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                restoreOriginalValue()
            } else {
                applyIfNeeded()
            }
        }

        public override func didMoveToSuperview() {
            super.didMoveToSuperview()
            applyIfNeeded()
        }

        public override func layoutSubviews() {
            super.layoutSubviews()
            applyIfNeeded()
        }

        func restoreOriginalValue() {
            if let scrollView = observedScrollView, let original = originalDelaysContentTouches {
                scrollView.delaysContentTouches = original
            }
            observedScrollView = nil
            originalDelaysContentTouches = nil
            onScrollViewChanged(nil)
        }

        func applyIfNeeded() {
            guard let window else {
                restoreOriginalValue()
                return
            }
            if let scrollView = observedScrollView,
               scrollView.window === window,
               isDescendant(of: scrollView) {
                if scrollView.delaysContentTouches {
                    scrollView.delaysContentTouches = false
                }
                onScrollViewChanged(scrollView)
                return
            }
            var ancestor = superview
            var containingScrollView: UIScrollView?
            while let view = ancestor {
                if let scrollView = view as? UIScrollView, !(scrollView is UITextView) {
                    containingScrollView = scrollView
                    break
                }
                ancestor = view.superview
            }
            guard let scrollView = containingScrollView else {
                restoreOriginalValue()
                return
            }
            if observedScrollView !== scrollView {
                restoreOriginalValue()
                observedScrollView = scrollView
                originalDelaysContentTouches = scrollView.delaysContentTouches
            }
            if scrollView.delaysContentTouches {
                scrollView.delaysContentTouches = false
            }
            onScrollViewChanged(scrollView)
        }
    }
}

public extension View {
    @MainActor
    func chatScrollImmediateContentTouches(
        onScrollViewChanged: @escaping @MainActor (UIScrollView?) -> Void = { _ in }
    ) -> some View {
        background(alignment: .topLeading) {
            ChatScrollImmediateContentTouches(onScrollViewChanged: onScrollViewChanged)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }
}
#endif
