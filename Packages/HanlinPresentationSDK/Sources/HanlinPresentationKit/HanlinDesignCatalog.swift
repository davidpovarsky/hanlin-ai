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

/// The approved Morph experiment's material and geometry, shared by the
/// production shell and its live capability cards. Native search, menus and
/// forms keep system styling; these values preserve the original glass design.
public enum HanlinMorphStyle {
    public static let blue = Color(red: 58.0 / 255, green: 124.0 / 255, blue: 180.0 / 255)
    public static let azure = Color(red: 2.0 / 255, green: 136.0 / 255, blue: 209.0 / 255)
    public static let glassMergeDistance: CGFloat = 32
    public static let panelInputSpacing: CGFloat = 13
    public static let launcherInputSpacing: CGFloat = 10
    public static let launcherSize: CGFloat = 52
    public static let inputCornerRadius: CGFloat = 27
    public static let panelCornerRadius: CGFloat = 29
    public static let panelInset: CGFloat = 16
    public static let panelContentSpacing: CGFloat = 14
    public static let minimumPageHeight: CGFloat = 80
    public static let horizontalInset: CGFloat = 18
    public static let topInset: CGFloat = 12
    public static let bottomInset: CGFloat = 14
    public static let hostSpacing: CGFloat = 6
    public static let sendButtonSize: CGFloat = 34
    public static let sendButtonInset: CGFloat = 9
    public static let cardCornerRadius: CGFloat = 17
    public static let cardMinimumHeight: CGFloat = 94
    public static let cardHorizontalInset: CGFloat = 13
    public static let cardVerticalInset: CGFloat = 7
    public static let cardSpacing: CGFloat = 10
    public static let cardMinimumWidth: CGFloat = 128
    public static let cardMaximumWidth: CGFloat = 230
    public static let attachmentMinimumHeight: CGFloat = 62
}
#endif
