import SwiftUI
#if canImport(Charts)
import Charts
#endif
#if canImport(UIKit)
import UIKit
#endif
import AppIntents

public struct HanlinExpoWidgetsViewRenderer {
    public static func renderNode(_ node: [String: Any], actionContext: HanlinExpoActionContext? = nil) -> AnyView {
        guard let type = node["type"] as? String else {
            return AnyView(EmptyView())
        }

        let props = node["props"] as? [String: Any] ?? [:]
        let rawChildren = props["children"]
        let childrenNodes = extractChildren(rawChildren)

        let baseView: AnyView
        switch type {
        case "TextView", "Text":
            baseView = renderText(props)

        case "HStackView", "HStack":
            let spacing = (props["spacing"] as? NSNumber)?.doubleValue.map { CGFloat($0) }
            let alignment = parseVerticalAlignment(props["alignment"] as? String)
            baseView = AnyView(
                HStack(alignment: alignment, spacing: spacing) {
                    ForEach(0..<childrenNodes.count, id: \.self) { idx in
                        renderNode(childrenNodes[idx], actionContext: actionContext)
                    }
                }
            )

        case "VStackView", "VStack":
            let spacing = (props["spacing"] as? NSNumber)?.doubleValue.map { CGFloat($0) }
            let alignment = parseHorizontalAlignment(props["alignment"] as? String)
            baseView = AnyView(
                VStack(alignment: alignment, spacing: spacing) {
                    ForEach(0..<childrenNodes.count, id: \.self) { idx in
                        renderNode(childrenNodes[idx], actionContext: actionContext)
                    }
                }
            )

        case "ZStackView", "ZStack":
            let alignment = parseAlignment(props["alignment"] as? String)
            baseView = AnyView(
                ZStack(alignment: alignment) {
                    ForEach(0..<childrenNodes.count, id: \.self) { idx in
                        renderNode(childrenNodes[idx], actionContext: actionContext)
                    }
                }
            )

        case "RectangleView", "Rectangle":
            baseView = AnyView(Rectangle().fill(parseColor(props["fill"] ?? props["color"]) ?? Color.primary))

        case "RoundedRectangleView", "RoundedRectangle":
            let radius = CGFloat((props["cornerRadius"] as? NSNumber)?.doubleValue ?? 8.0)
            baseView = AnyView(RoundedRectangle(cornerRadius: radius).fill(parseColor(props["fill"] ?? props["color"]) ?? Color.primary))

        case "CapsuleView", "Capsule":
            baseView = AnyView(Capsule().fill(parseColor(props["fill"] ?? props["color"]) ?? Color.primary))

        case "CircleView", "Circle":
            baseView = AnyView(Circle().fill(parseColor(props["fill"] ?? props["color"]) ?? Color.primary))

        case "EllipseView", "Ellipse":
            baseView = AnyView(Ellipse().fill(parseColor(props["fill"] ?? props["color"]) ?? Color.primary))

        case "SpacerView", "Spacer":
            let minLength = (props["minLength"] as? NSNumber)?.doubleValue.map { CGFloat($0) }
            baseView = AnyView(Spacer(minLength: minLength))

        case "DividerView", "Divider":
            baseView = AnyView(Divider())

        case "ImageView", "Image":
            baseView = renderImage(props)

        case "ProgressView":
            baseView = renderProgress(props)

        case "GaugeView", "Gauge":
            baseView = renderGauge(props)

        case "ChartView", "Chart":
            baseView = renderChart(props)

        case "Button", "WidgetButtonView":
            baseView = renderButton(props, children: childrenNodes, actionContext: actionContext)

        case "LinkView", "Link":
            let title = (props["title"] as? String) ?? (props["text"] as? String) ?? "Link"
            let urlStr = props["url"] as? String ?? ""
            if let url = URL(string: urlStr) {
                baseView = AnyView(Link(title, destination: url))
            } else {
                baseView = AnyView(Text(title))
            }

        case "AccessoryWidgetBackgroundView":
            if #available(iOS 16.0, *) {
                baseView = AnyView(AccessoryWidgetBackground())
            } else {
                baseView = AnyView(Color.clear)
            }

        case "ScriptWidgetSubtree":
            // Mixed-tree bridge: embed ScriptWidget Element/JSX inside Expo layout!
            baseView = renderScriptWidgetSubtree(props)

        case "react.fragment", "SlotView", "OverlayView", "BackgroundView", "MaskView":
            baseView = AnyView(
                VStack(spacing: 0) {
                    ForEach(0..<childrenNodes.count, id: \.self) { idx in
                        renderNode(childrenNodes[idx], actionContext: actionContext)
                    }
                }
            )

        default:
            baseView = AnyView(EmptyView())
        }

        return applyModifiers(baseView, props: props)
    }

    private static func renderText(_ props: [String: Any]) -> AnyView {
        let content = (props["text"] as? String) ?? (props["content"] as? String) ?? ""
        var t = Text(content)

        if let fontName = props["font"] as? String {
            switch fontName.lowercased() {
            case "largetitle": t = t.font(.largeTitle)
            case "title": t = t.font(.title)
            case "title2": t = t.font(.title2)
            case "title3": t = t.font(.title3)
            case "headline": t = t.font(.headline)
            case "subheadline": t = t.font(.subheadline)
            case "body": t = t.font(.body)
            case "callout": t = t.font(.callout)
            case "footnote": t = t.font(.footnote)
            case "caption": t = t.font(.caption)
            case "caption2": t = t.font(.caption2)
            default: break
            }
        }
        if let size = (props["fontSize"] as? NSNumber)?.doubleValue {
            t = t.font(.system(size: CGFloat(size)))
        }
        if let weight = props["fontWeight"] as? String {
            switch weight.lowercased() {
            case "bold": t = t.fontWeight(.bold)
            case "semibold": t = t.fontWeight(.semibold)
            case "medium": t = t.fontWeight(.medium)
            case "light": t = t.fontWeight(.light)
            case "heavy": t = t.fontWeight(.heavy)
            default: break
            }
        }
        if let color = parseColor(props["color"] ?? props["foregroundColor"]) {
            t = t.foregroundColor(color)
        }
        return AnyView(t)
    }

    private static func renderImage(_ props: [String: Any]) -> AnyView {
        if let systemName = (props["systemName"] as? String) ?? (props["systemImage"] as? String) {
            return AnyView(Image(systemName: systemName))
        }
        if let source = props["source"] as? [String: Any], let uri = source["uri"] as? String {
            if uri.hasPrefix("system:") {
                let name = String(uri.dropFirst("system:".count))
                return AnyView(Image(systemName: name))
            }
            #if canImport(UIKit)
            if let img = UIImage(contentsOfFile: uri) {
                return AnyView(Image(uiImage: img).resizable())
            }
            #endif
        }
        return AnyView(Image(systemName: "photo"))
    }

    private static func renderProgress(_ props: [String: Any]) -> AnyView {
        let value = (props["value"] as? NSNumber)?.doubleValue
        let total = (props["total"] as? NSNumber)?.doubleValue ?? 1.0
        if let v = value {
            return AnyView(ProgressView(value: v, total: total))
        } else {
            return AnyView(ProgressView())
        }
    }

    private static func renderGauge(_ props: [String: Any]) -> AnyView {
        if #available(iOS 16.0, *) {
            let value = (props["value"] as? NSNumber)?.doubleValue ?? 0.0
            let min = (props["min"] as? NSNumber)?.doubleValue ?? 0.0
            let max = (props["max"] as? NSNumber)?.doubleValue ?? 100.0
            let label = (props["label"] as? String) ?? ""
            return AnyView(
                Gauge(value: value, in: min...max) {
                    Text(label)
                }
            )
        } else {
            return AnyView(ProgressView(value: (props["value"] as? NSNumber)?.doubleValue ?? 0.0, total: 100.0))
        }
    }

    private static func renderChart(_ props: [String: Any]) -> AnyView {
        #if canImport(Charts)
        if #available(iOS 16.0, *) {
            let data = props["data"] as? [[String: Any]] ?? []
            let chartType = (props["chartType"] as? String)?.lowercased() ?? "bar"

            return AnyView(
                Chart {
                    ForEach(0..<data.count, id: \.self) { i in
                        let item = data[i]
                        let xVal = (item["x"] as? String) ?? "\(i)"
                        let yVal = (item["y"] as? NSNumber)?.doubleValue ?? 0.0

                        if chartType == "line" {
                            LineMark(x: .value("X", xVal), y: .value("Y", yVal))
                        } else if chartType == "point" {
                            PointMark(x: .value("X", xVal), y: .value("Y", yVal))
                        } else {
                            BarMark(x: .value("X", xVal), y: .value("Y", yVal))
                        }
                    }
                }
            )
        }
        #endif
        return AnyView(Text("Chart"))
    }

    private static func renderButton(
        _ props: [String: Any],
        children: [[String: Any]],
        actionContext: HanlinExpoActionContext?
    ) -> AnyView {
        let label = (props["label"] as? String) ?? (props["title"] as? String)
        let systemImage = props["systemImage"] as? String
        let target = props["target"] as? String

        if #available(iOS 17.0, *) {
            let intent = HanlinGenericWidgetActionIntent(
                packageID: actionContext?.packageID ?? "",
                entrypointID: actionContext?.entrypointID ?? "",
                target: target ?? "",
                environment: actionContext?.environmentJSON ?? "{}"
            )

            return AnyView(
                SwiftUI.Button(intent: intent) {
                    if let label {
                        if let systemImage {
                            Label(label, systemImage: systemImage)
                        } else {
                            Text(label)
                        }
                    } else if !children.isEmpty {
                        ForEach(0..<children.count, id: \.self) { idx in
                            renderNode(children[idx], actionContext: actionContext)
                        }
                    } else {
                        Text("Action")
                    }
                }
            )
        } else {
            return AnyView(
                SwiftUI.Button(action: {}) {
                    if let label { Text(label) } else { Text("Action") }
                }
            )
        }
    }

    private static func renderScriptWidgetSubtree(_ props: [String: Any]) -> AnyView {
        if let script = props["script"] as? String {
            let res = HanlinScriptWidgetRuntime.shared.execute(script: script, environment: [:])
            switch res {
            case let .success(elem):
                return AnyView(HanlinScriptWidgetElementView(element: elem))
            case let .failure(err):
                return AnyView(Text("ScriptWidget Error: \(err.localizedDescription)").foregroundColor(.red).font(.caption))
            }
        } else if let elemDict = props["element"] as? [String: Any] {
            let elem = HanlinScriptWidgetElement(dictionary: elemDict)
            return AnyView(HanlinScriptWidgetElementView(element: elem))
        }
        return AnyView(EmptyView())
    }

    private static func applyModifiers(_ view: AnyView, props: [String: Any]) -> AnyView {
        var v = view

        if let padding = (props["padding"] as? NSNumber)?.doubleValue {
            v = AnyView(v.padding(CGFloat(padding)))
        }

        let width = (props["width"] as? NSNumber)?.doubleValue.map { CGFloat($0) }
        let height = (props["height"] as? NSNumber)?.doubleValue.map { CGFloat($0) }
        if width != nil || height != nil {
            v = AnyView(v.frame(width: width, height: height))
        }

        if let bg = parseColor(props["background"] ?? props["backgroundColor"]) {
            v = AnyView(v.background(bg))
        }

        if let cornerRadius = (props["cornerRadius"] as? NSNumber)?.doubleValue {
            v = AnyView(v.cornerRadius(CGFloat(cornerRadius)))
        }

        if let opacity = (props["opacity"] as? NSNumber)?.doubleValue {
            v = AnyView(v.opacity(opacity))
        }

        return v
    }

    private static func extractChildren(_ raw: Any?) -> [[String: Any]] {
        if let dict = raw as? [String: Any] {
            return [dict]
        }
        if let arr = raw as? [Any] {
            return arr.compactMap { $0 as? [String: Any] }
        }
        return []
    }

    public static func parseColor(_ val: Any?) -> Color? {
        guard let s = val as? String else { return nil }
        if s.hasPrefix("#") {
            var hex = String(s.dropFirst())
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
        case "gray": return .gray
        case "white": return .white
        case "black": return .black
        case "clear": return .clear
        case "primary": return .primary
        case "secondary": return .secondary
        default: return nil
        }
    }

    private static func parseVerticalAlignment(_ s: String?) -> VerticalAlignment {
        switch s?.lowercased() {
        case "top": return .top
        case "bottom": return .bottom
        default: return .center
        }
    }

    private static func parseHorizontalAlignment(_ s: String?) -> HorizontalAlignment {
        switch s?.lowercased() {
        case "leading", "left": return .leading
        case "trailing", "right": return .trailing
        default: return .center
        }
    }

    private static func parseAlignment(_ s: String?) -> Alignment {
        switch s?.lowercased() {
        case "top": return .top
        case "bottom": return .bottom
        case "leading", "left": return .leading
        case "trailing", "right": return .trailing
        case "topLeading": return .topLeading
        case "topTrailing": return .topTrailing
        case "bottomLeading": return .bottomLeading
        case "bottomTrailing": return .bottomTrailing
        default: return .center
        }
    }
}

public struct HanlinExpoActionContext: Sendable {
    public let packageID: String
    public let entrypointID: String
    public let environmentJSON: String

    public init(packageID: String, entrypointID: String, environmentJSON: String = "{}") {
        self.packageID = packageID
        self.entrypointID = entrypointID
        self.environmentJSON = environmentJSON
    }
}
