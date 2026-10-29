import SwiftUI

public struct HanlinScriptWidgetAttributes {
    public static func parseColor(_ val: Any?) -> Color? {
        guard let val else { return nil }
        if let s = val as? String {
            if s.hasPrefix("#") {
                var hex = String(s.dropFirst())
                if hex.count == 3 {
                    hex = hex.map { "\($0)\($0)" }.joined()
                }
                if hex.count == 6 { hex += "FF" }
                if let num = UInt64(hex, radix: 16) {
                    let r = Double((num >> 24) & 0xFF) / 255.0
                    let g = Double((num >> 16) & 0xFF) / 255.0
                    let b = Double((num >> 8) & 0xFF) / 255.0
                    let a = Double(num & 0xFF) / 255.0
                    return Color(red: r, green: g, blue: b, opacity: a)
                }
            }
            switch s.lowercased() {
            case "red": return .red
            case "blue": return .blue
            case "green": return .green
            case "yellow": return .yellow
            case "orange": return .orange
            case "purple": return .purple
            case "pink": return .pink
            case "gray": return .gray
            case "white": return .white
            case "black": return .black
            case "clear": return .clear
            case "primary": return .primary
            case "secondary": return .secondary
            default: return nil
            }
        }
        return nil
    }

    public static func parseFont(_ element: HanlinScriptWidgetElement) -> Font {
        if let size = element.number("size") ?? element.number("fontSize") {
            var f = Font.system(size: CGFloat(size))
            if let weightStr = element.string("weight") {
                f = f.weight(parseWeight(weightStr))
            }
            return f
        }
        if let styleStr = element.string("font") ?? element.string("style") {
            switch styleStr.lowercased() {
            case "largetitle": return .largeTitle
            case "title": return .title
            case "title2": return .title2
            case "title3": return .title3
            case "headline": return .headline
            case "subheadline": return .subheadline
            case "body": return .body
            case "callout": return .callout
            case "footnote": return .footnote
            case "caption": return .caption
            case "caption2": return .caption2
            default: break
            }
        }
        return .body
    }

    public static func parseWeight(_ s: String) -> Font.Weight {
        switch s.lowercased() {
        case "bold": return .bold
        case "semibold": return .semibold
        case "medium": return .medium
        case "regular": return .regular
        case "light": return .light
        case "thin": return .thin
        case "heavy": return .heavy
        case "black": return .black
        default: return .regular
        }
    }

    public static func parseAlignment(_ s: String?) -> Alignment {
        switch s?.lowercased() {
        case "top": return .top
        case "bottom": return .bottom
        case "leading", "left": return .leading
        case "trailing", "right": return .trailing
        case "topleading": return .topLeading
        case "toptrailing": return .topTrailing
        case "bottomleading": return .bottomLeading
        case "bottomtrailing": return .bottomTrailing
        default: return .center
        }
    }

    public static func parseVerticalAlignment(_ s: String?) -> VerticalAlignment {
        switch s?.lowercased() {
        case "top": return .top
        case "bottom": return .bottom
        default: return .center
        }
    }

    public static func parseHorizontalAlignment(_ s: String?) -> HorizontalAlignment {
        switch s?.lowercased() {
        case "leading", "left": return .leading
        case "trailing", "right": return .trailing
        default: return .center
        }
    }

    public static func applyModifiers<V: View>(_ view: V, element: HanlinScriptWidgetElement) -> AnyView {
        var result = AnyView(view)

        // Padding
        if let pad = element.number("padding") {
            result = AnyView(result.padding(CGFloat(pad)))
        }

        // Frame
        let w = element.number("width").map { CGFloat($0) }
        let h = element.number("height").map { CGFloat($0) }
        if w != nil || h != nil {
            result = AnyView(result.frame(width: w, height: h))
        }

        // Foreground color
        if let fg = parseColor(element.props["color"] ?? element.props["foregroundColor"]) {
            result = AnyView(result.foregroundColor(fg))
        }

        // Background
        if let bg = parseColor(element.props["background"] ?? element.props["backgroundColor"]) {
            result = AnyView(result.background(bg))
        }

        // Corner Radius
        if let radius = element.number("radius") ?? element.number("cornerRadius") {
            result = AnyView(result.cornerRadius(CGFloat(radius)))
        }

        // Opacity
        if let op = element.number("opacity") {
            result = AnyView(result.opacity(op))
        }

        return result
    }
}
