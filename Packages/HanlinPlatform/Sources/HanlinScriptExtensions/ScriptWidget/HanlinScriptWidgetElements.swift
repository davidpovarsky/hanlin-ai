import SwiftUI
#if canImport(Charts)
import Charts
#endif
import AppIntents

public struct HanlinScriptWidgetElements {
    // 1. Text & Date
    public static func renderDate(_ element: HanlinScriptWidgetElement) -> AnyView {
        let dateVal: Date
        if let ts = element.number("date") ?? element.number("timestamp") {
            dateVal = Date(timeIntervalSince1970: ts > 10_000_000_000 ? ts / 1000.0 : ts)
        } else {
            dateVal = Date()
        }

        let styleStr = element.string("style")?.lowercased() ?? "date"
        let v: Text
        switch styleStr {
        case "time": v = Text(dateVal, style: .time)
        case "relative": v = Text(dateVal, style: .relative)
        case "offset": v = Text(dateVal, style: .offset)
        case "timer": v = Text(dateVal, style: .timer)
        default: v = Text(dateVal, style: .date)
        }
        return AnyView(v.font(HanlinScriptWidgetAttributes.parseFont(element)))
    }

    // 2. Chart
    public static func renderChart(_ element: HanlinScriptWidgetElement) -> AnyView {
        #if canImport(Charts)
        if #available(iOS 16.0, *) {
            let data = element.array("data")?.compactMap { $0 as? [String: Any] } ?? []
            let chartType = element.string("type")?.lowercased() ?? "bar"

            return AnyView(
                Chart {
                    ForEach(0..<data.count, id: \.self) { idx in
                        let item = data[idx]
                        let x = (item["x"] as? String) ?? "\(idx)"
                        let y = (item["y"] as? NSNumber)?.doubleValue ?? 0.0

                        if chartType == "line" {
                            LineMark(x: .value("X", x), y: .value("Y", y))
                        } else if chartType == "point" {
                            PointMark(x: .value("X", x), y: .value("Y", y))
                        } else {
                            BarMark(x: .value("X", x), y: .value("Y", y))
                        }
                    }
                }
            )
        }
        #endif
        return AnyView(Text("Chart"))
    }

    // 3. Gauge
    public static func renderGauge(_ element: HanlinScriptWidgetElement) -> AnyView {
        let val = element.number("value") ?? 0.0
        let min = element.number("min") ?? 0.0
        let max = element.number("max") ?? 100.0
        let title = element.string("title") ?? element.string("label") ?? ""

        if #available(iOS 16.0, *) {
            return AnyView(
                Gauge(value: val, in: min...max) {
                    Text(title)
                }
            )
        } else {
            return AnyView(ProgressView(value: val, total: max))
        }
    }

    // 4. Ring (Circular Progress)
    public static func renderRing(_ element: HanlinScriptWidgetElement) -> AnyView {
        let val = (element.number("value") ?? 0.5)
        let strokeWidth = CGFloat(element.number("lineWidth") ?? 8.0)
        let color = HanlinScriptWidgetAttributes.parseColor(element.props["color"]) ?? .blue

        return AnyView(
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: strokeWidth)
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(val, 0), 1)))
                    .stroke(color, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        )
    }

    // 5. Extras: Badge, Chip, Stat, Icon
    public static func renderBadge(_ element: HanlinScriptWidgetElement) -> AnyView {
        let text = element.string("text") ?? element.rawText ?? ""
        let color = HanlinScriptWidgetAttributes.parseColor(element.props["color"]) ?? .blue

        return AnyView(
            Text(text)
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.2))
                .foregroundColor(color)
                .clipShape(Capsule())
        )
    }

    public static func renderChip(_ element: HanlinScriptWidgetElement) -> AnyView {
        let text = element.string("text") ?? element.rawText ?? ""
        let icon = element.string("icon")

        return AnyView(
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon).font(.caption)
                }
                Text(text).font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.15))
            .clipShape(Capsule())
        )
    }

    public static func renderStat(_ element: HanlinScriptWidgetElement) -> AnyView {
        let title = element.string("title") ?? ""
        let value = element.string("value") ?? ""
        let trend = element.string("trend")

        return AnyView(
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption2).foregroundColor(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value).font(.title3.bold())
                    if let trend {
                        Text(trend).font(.caption2).foregroundColor(trend.hasPrefix("+") ? .green : .red)
                    }
                }
            }
        )
    }

    public static func renderIcon(_ element: HanlinScriptWidgetElement) -> AnyView {
        let name = element.string("name") ?? element.string("systemName") ?? "star"
        let color = HanlinScriptWidgetAttributes.parseColor(element.props["color"]) ?? .primary
        return AnyView(
            Image(systemName: name)
                .font(HanlinScriptWidgetAttributes.parseFont(element))
                .foregroundColor(color)
        )
    }

    // 6. Button & Toggle
    public static func renderButton(
        _ element: HanlinScriptWidgetElement,
        children: [HanlinScriptWidgetElement],
        actionHandler: ((String, [String: Any]?) -> Void)? = nil
    ) -> AnyView {
        let label = element.string("title") ?? element.string("label") ?? element.rawText ?? "Action"
        let action = element.string("action") ?? element.string("target") ?? ""

        if #available(iOS 17.0, *) {
            let intent = HanlinGenericWidgetActionIntent(
                packageID: "",
                entrypointID: "",
                target: action,
                environment: "{}"
            )
            return AnyView(
                SwiftUI.Button(intent: intent) {
                    Text(label)
                }
            )
        } else {
            return AnyView(
                SwiftUI.Button(action: {
                    actionHandler?(action, element.props)
                }) {
                    Text(label)
                }
            )
        }
    }

    public static func renderToggle(_ element: HanlinScriptWidgetElement) -> AnyView {
        let label = element.string("label") ?? element.string("title") ?? ""
        let isOn = element.bool("isOn") ?? element.bool("value") ?? false

        if #available(iOS 17.0, *) {
            let intent = HanlinGenericWidgetActionIntent(
                packageID: "",
                entrypointID: "",
                target: "toggle",
                environment: "{}"
            )
            return AnyView(
                SwiftUI.Toggle(isOn: intent) {
                    Text(label)
                }
            )
        } else {
            return AnyView(
                SwiftUI.Toggle(isOn: .constant(isOn)) {
                    Text(label)
                }
            )
        }
    }

    // 7. Shapes
    public static func renderShape(_ tag: String, element: HanlinScriptWidgetElement) -> AnyView {
        let fill = HanlinScriptWidgetAttributes.parseColor(element.props["color"] ?? element.props["fill"]) ?? .primary

        switch tag {
        case "rect":
            return AnyView(Rectangle().fill(fill))
        case "roundedrect":
            let r = CGFloat(element.number("radius") ?? 8.0)
            return AnyView(RoundedRectangle(cornerRadius: r).fill(fill))
        case "capsule":
            return AnyView(Capsule().fill(fill))
        case "circle":
            return AnyView(Circle().fill(fill))
        case "ellipse":
            return AnyView(Ellipse().fill(fill))
        case "divider":
            return AnyView(Divider())
        case "line":
            return AnyView(Rectangle().frame(height: 1).foregroundColor(fill))
        default:
            return AnyView(Rectangle().fill(fill))
        }
    }

    // 8. Grid (HGrid, VGrid)
    public static func renderGrid(
        isVertical: Bool,
        element: HanlinScriptWidgetElement,
        renderChild: (HanlinScriptWidgetElement) -> AnyView
    ) -> AnyView {
        let columnsCount = Int(element.number("columns") ?? element.number("rows") ?? 2)
        let spacing = CGFloat(element.number("spacing") ?? 8.0)
        let items = Array(repeating: GridItem(.flexible(), spacing: spacing), count: max(1, columnsCount))

        if isVertical {
            return AnyView(
                LazyVGrid(columns: items, spacing: spacing) {
                    ForEach(element.children) { child in
                        renderChild(child)
                    }
                }
            )
        } else {
            return AnyView(
                LazyHGrid(rows: items, spacing: spacing) {
                    ForEach(element.children) { child in
                        renderChild(child)
                    }
                }
            )
        }
    }
}
