import SwiftUI

public struct HanlinScriptWidgetElementView: View {
    public let element: HanlinScriptWidgetElement
    public let actionHandler: ((String, [String: Any]?) -> Void)?

    public init(
        element: HanlinScriptWidgetElement,
        actionHandler: ((String, [String: Any]?) -> Void)? = nil
    ) {
        self.element = element
        self.actionHandler = actionHandler
    }

    public var body: some View {
        Self.buildView(element: element, actionHandler: actionHandler)
    }

    public static func buildView(
        element: HanlinScriptWidgetElement,
        actionHandler: ((String, [String: Any]?) -> Void)? = nil
    ) -> AnyView {
        let tag = element.tag.lowercased()
        let baseView: AnyView

        switch tag {
        // Stacks
        case "hstack":
            let spacing = element.number("spacing").map { CGFloat($0) }
            let alignment = HanlinScriptWidgetAttributes.parseVerticalAlignment(element.string("alignment"))
            baseView = AnyView(
                HStack(alignment: alignment, spacing: spacing) {
                    ForEach(element.children) { child in
                        buildView(element: child, actionHandler: actionHandler)
                    }
                }
            )

        case "vstack":
            let spacing = element.number("spacing").map { CGFloat($0) }
            let alignment = HanlinScriptWidgetAttributes.parseHorizontalAlignment(element.string("alignment"))
            baseView = AnyView(
                VStack(alignment: alignment, spacing: spacing) {
                    ForEach(element.children) { child in
                        buildView(element: child, actionHandler: actionHandler)
                    }
                }
            )

        case "zstack":
            let alignment = HanlinScriptWidgetAttributes.parseAlignment(element.string("alignment"))
            baseView = AnyView(
                ZStack(alignment: alignment) {
                    ForEach(element.children) { child in
                        buildView(element: child, actionHandler: actionHandler)
                    }
                }
            )

        // Grids
        case "hgrid":
            baseView = HanlinScriptWidgetElements.renderGrid(isVertical: false, element: element) { child in
                buildView(element: child, actionHandler: actionHandler)
            }

        case "vgrid":
            baseView = HanlinScriptWidgetElements.renderGrid(isVertical: true, element: element) { child in
                buildView(element: child, actionHandler: actionHandler)
            }

        // Text & Content
        case "text":
            let content = element.string("text") ?? element.rawText ?? ""
            var t = Text(content).font(HanlinScriptWidgetAttributes.parseFont(element))
            if element.bool("bold") == true { t = t.bold() }
            if element.bool("italic") == true { t = t.italic() }
            baseView = AnyView(t)

        case "date":
            baseView = HanlinScriptWidgetElements.renderDate(element)

        case "image", "gif":
            if let sf = element.string("systemName") ?? element.string("name") {
                baseView = AnyView(Image(systemName: sf).font(HanlinScriptWidgetAttributes.parseFont(element)))
            } else if let src = element.string("src") ?? element.string("url"), let img = UIImage(contentsOfFile: src) {
                baseView = AnyView(Image(uiImage: img).resizable())
            } else {
                baseView = AnyView(Image(systemName: "photo"))
            }

        case "spacer":
            let minLen = element.number("minLength").map { CGFloat($0) }
            baseView = AnyView(Spacer(minLength: minLen))

        // Shapes
        case "rect", "capsule", "ellipse", "circle", "divider", "line", "roundedrect":
            baseView = HanlinScriptWidgetElements.renderShape(tag, element: element)

        // Visual Data
        case "gauge":
            baseView = HanlinScriptWidgetElements.renderGauge(element)

        case "chart":
            baseView = HanlinScriptWidgetElements.renderChart(element)

        case "ring":
            baseView = HanlinScriptWidgetElements.renderRing(element)

        case "progress":
            let val = element.number("value") ?? 0.5
            let total = element.number("total") ?? 1.0
            baseView = AnyView(ProgressView(value: val, total: total))

        // Components & Actions
        case "link":
            let title = element.string("title") ?? element.rawText ?? "Link"
            let urlStr = element.string("url") ?? ""
            if let url = URL(string: urlStr) {
                baseView = AnyView(Link(title, destination: url))
            } else {
                baseView = AnyView(Text(title))
            }

        case "icon":
            baseView = HanlinScriptWidgetElements.renderIcon(element)

        case "label":
            let title = element.string("title") ?? element.rawText ?? ""
            let icon = element.string("icon") ?? element.string("systemName") ?? "star"
            baseView = AnyView(Label(title, systemImage: icon))

        case "badge":
            baseView = HanlinScriptWidgetElements.renderBadge(element)

        case "chip":
            baseView = HanlinScriptWidgetElements.renderChip(element)

        case "stat":
            baseView = HanlinScriptWidgetElements.renderStat(element)

        case "button":
            baseView = HanlinScriptWidgetElements.renderButton(element, children: element.children, actionHandler: actionHandler)

        case "toggle":
            baseView = HanlinScriptWidgetElements.renderToggle(element)

        // Fragment & Group
        case "fragment", "group":
            baseView = AnyView(
                VStack(spacing: 0) {
                    ForEach(element.children) { child in
                        buildView(element: child, actionHandler: actionHandler)
                    }
                }
            )

        default:
            baseView = AnyView(
                Text("Unsupported: <\(tag)>")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            )
        }

        return HanlinScriptWidgetAttributes.applyModifiers(baseView, element: element)
    }
}
