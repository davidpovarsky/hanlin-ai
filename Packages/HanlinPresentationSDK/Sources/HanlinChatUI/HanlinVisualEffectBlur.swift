#if canImport(UIKit)
import SwiftUI
import UIKit

/// Original native material, shared by Hanlin screens and message selection.
public struct HanlinVisualEffectBlur: UIViewRepresentable {
    public let style: UIBlurEffect.Style
    public init(style: UIBlurEffect.Style) { self.style = style }
    public func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
    public func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}
#endif
