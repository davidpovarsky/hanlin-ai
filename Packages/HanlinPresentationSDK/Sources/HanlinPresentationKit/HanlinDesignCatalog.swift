#if canImport(SwiftUI)
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The app and embedded chat surfaces share Apple's semantic text styles.
/// Change the family here; Dynamic Type, script fallback and accessibility
/// remain owned by the system. Individual surfaces may refine weight only.
public enum HanlinTypography {
    public static let design: Font.Design = .default

    /// Preserve intentional glyph and already-scaled document sizes while
    /// sharing the family. Prefer a semantic role for application text.
    public static func fixed(size: CGFloat, weight: Font.Weight = .regular,
                             design: Font.Design? = nil) -> Font {
        .system(size: size, weight: weight, design: design ?? Self.design)
    }

    public static var largeTitle: Font { .system(.largeTitle, design: design) }
    public static var title: Font { .system(.title, design: design) }
    public static var title2: Font { .system(.title2, design: design) }
    public static var title3: Font { .system(.title3, design: design) }
    public static var headline: Font { .system(.headline, design: design) }
    public static var subheadline: Font { .system(.subheadline, design: design) }
    public static var body: Font { .system(.body, design: design) }
    public static var callout: Font { .system(.callout, design: design) }
    public static var footnote: Font { .system(.footnote, design: design) }
    public static var caption: Font { .system(.caption, design: design) }
    public static var caption2: Font { .system(.caption2, design: design) }

    #if canImport(UIKit)
    /// Use for native editors and Markdown so they follow the same family.
    @MainActor public static func uiFont(_ style: UIFont.TextStyle) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style)
        let family: UIFontDescriptor.SystemDesign
        switch design {
        case .rounded: family = .rounded
        case .serif: family = .serif
        case .monospaced: family = .monospaced
        default: family = .default
        }
        guard let descriptor = base.fontDescriptor.withDesign(family) else { return base }
        return UIFont(descriptor: descriptor, size: 0)
    }
    #endif
}

/// Shared metrics for application controls, not document or generated-content
/// geometry. Native lists, forms, menus, toggles and navigation keep their own
/// system metrics; custom layout is reserved for the approved Morph composer.
public enum HanlinControlMetrics {
    public static let minimumHitTarget: CGFloat = 44
    public static let pageInset: CGFloat = 12
    public static let sectionSpacing: CGFloat = 12
    public static let rowSpacing: CGFloat = 8
    public static let rowCornerRadius: CGFloat = 12
    public static let popoverCornerRadius: CGFloat = 22
    public static let iconSize: CGFloat = 24
    public static let badgeHorizontalInset: CGFloat = 5
    public static let badgeVerticalInset: CGFloat = 1.5
}
#endif
