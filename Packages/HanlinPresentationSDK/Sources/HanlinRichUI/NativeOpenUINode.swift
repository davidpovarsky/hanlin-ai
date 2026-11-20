#if canImport(SwiftUI) && canImport(UIKit) && canImport(Charts)
import SwiftUI
import Charts
import HanlinPresentationKit

/// Rendering only: all expressions, $bindings and action plans come from the
/// original lang-core evaluator. The catalog prompt lists these actual mappings.
struct NativeOpenUINode: View {
    let value: PresentationValue
    let runtime: OpenUIBridgeModel
    let configuration: OpenUIRendererConfiguration
    @State private var selectedTab = ""
    private var node: [String: PresentationValue] { value.object ?? [:] }
    private var props: [String: PresentationValue] { node["props"]?.object ?? [:] }
    private var type: String { node["typeName"]?.string ?? "" }
    private var id: String { node["id"]?.string ?? "" }
    private var enabled: Bool { node["enabled"] == .bool(true) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
        Group {
            if let custom = configuration.nativeComponent?(
                .init(id: id, typeName: type, properties: props, isEnabled: enabled),
                .init(write: { runtime.field(id, value: $0) }, trigger: { runtime.action(id) })) {
                custom
            } else {
            switch type {
            case "Stack", "Card", "Form", "FormControl", "Buttons", "FollowUps", "Tabs", "Accordion", "Carousel":
                layout.accessibilityElement(children: .contain)
            case "Input", "TextArea", "Select", "DatePicker", "Slider", "CheckBoxGroup", "RadioGroup", "SwitchGroup", "Button":
                control
            case "BarChart", "LineChart", "AreaChart", "HorizontalBarChart", "PieChart", "ScatterChart":
                chart
            case "Table", "EntityList", "ListBlock", "Steps", "ImageGallery", "Comparison", "Sources":
                collection.accessibilityElement(children: .contain)
            default:
                textOrMedia
            }
            }
        }
        .accessibilityIdentifier("openui-native-\(type)-\(text("name", fallback: id))")
        if !text("validationError").isEmpty {
            Text(text("validationError")).font(.caption).foregroundStyle(.red)
                .accessibilityLabel(text("validationError"))
        }
        }
    }

    @ViewBuilder private var layout: some View {
        switch type {
        case "Stack", "Card":
            Group {
                if text("direction") == "row" {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: gap) { children(props["children"]) }
                        VStack(alignment: .leading, spacing: gap) { children(props["children"]) }
                    }
                } else { VStack(alignment: .leading, spacing: gap) { children(props["children"]) } }
            }
            .padding(type == "Card" && text("variant") != "clear" ? 12 : 0)
            .background(type == "Card" && text("variant") != "clear" ? Color.secondary.opacity(0.08) : .clear,
                        in: RoundedRectangle(cornerRadius: 14))
        case "Form":
            VStack(alignment: .leading, spacing: 14) { children(props["fields"]); children(props["buttons"]) }
        case "FormControl":
            VStack(alignment: .leading, spacing: 6) {
                Text(text("label")).font(.subheadline.weight(.medium))
                children(props["input"])
                if !text("hint").isEmpty { Text(text("hint")).font(.caption).foregroundStyle(.secondary) }
            }
        case "Buttons":
            if text("direction") == "column" { VStack(alignment: .leading) { children(props["buttons"]) } }
            else { ViewThatFits { HStack { children(props["buttons"]) }; VStack(alignment: .leading) { children(props["buttons"]) } } }
        case "FollowUps": VStack(alignment: .leading, spacing: 8) { children(props["items"]) }
        case "Tabs":
            let items = array("items")
            let chosen = selectedTab.isEmpty ? (items.first?.object?["props"]?.object?["value"]?.string ?? "") : selectedTab
            VStack(alignment: .leading) {
                Picker("Section", selection: Binding(get: { chosen }, set: { selectedTab = $0 })) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        let p = item.object?["props"]?.object ?? [:]
                        Text(p["trigger"]?.string ?? "").tag(p["value"]?.string ?? "")
                    }
                }.pickerStyle(.segmented)
                if let item = items.first(where: { $0.object?["props"]?.object?["value"]?.string == chosen }) {
                    children(item.object?["props"]?.object?["content"])
                }
            }
        case "Accordion":
            VStack(alignment: .leading) {
                ForEach(Array(array("items").enumerated()), id: \.offset) { _, item in
                    let p = item.object?["props"]?.object ?? [:]
                    DisclosureGroup(p["trigger"]?.string ?? "Details") { children(p["content"]) }
                }
            }
        case "Carousel":
            ScrollView(.horizontal) { HStack(alignment: .top, spacing: 12) {
                ForEach(Array(array("children").enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading) { children(item) }.containerRelativeFrame(.horizontal)
                }
            }.scrollTargetLayout() }.scrollTargetBehavior(.viewAligned)
        default: EmptyView()
        }
    }

    @ViewBuilder private var control: some View {
        switch type {
        case "Input":
            if text("type") == "password" { SecureField(text("placeholder"), text: stringBinding).textFieldStyle(.roundedBorder).disabled(!enabled) }
            else { TextField(text("placeholder"), text: stringBinding).textFieldStyle(.roundedBorder)
                .keyboardType(text("type") == "number" ? .decimalPad : text("type") == "email" ? .emailAddress : .default).disabled(!enabled) }
        case "TextArea": TextField(text("placeholder"), text: stringBinding, axis: .vertical).lineLimit(3...8).textFieldStyle(.roundedBorder).disabled(!enabled)
        case "Select", "RadioGroup":
            Picker(text("name"), selection: stringBinding) {
                ForEach(Array(array("items").enumerated()), id: \.offset) { _, item in
                    let p = item.object?["props"]?.object ?? [:]
                    Text(p["label"]?.string ?? "").tag(p["value"]?.string ?? "")
                }
            }.pickerStyle(.menu).disabled(!enabled)
        case "DatePicker":
            if text("mode") == "range" {
                VStack(alignment: .leading) {
                    DatePicker("Start date", selection: dateBinding(key: "from"), displayedComponents: [.date])
                    DatePicker("End date", selection: dateBinding(key: "to"),
                        in: (date(props["currentValue"]?.object?["from"]) ?? .distantPast)..., displayedComponents: [.date])
                }.disabled(!enabled)
            } else {
                DatePicker(text("name"), selection: dateBinding(), displayedComponents: [.date]).disabled(!enabled)
            }
        case "Slider":
            let minimum = number("min", fallback: 0)
            let maximum = max(minimum + 0.0001, number("max", fallback: 100))
            VStack(alignment: .leading) {
                if !text("label").isEmpty { Text(text("label")) }
                Slider(value: sliderBinding(index: 0, minimum: minimum, maximum: maximum),
                    in: minimum...maximum, step: max(0.0001, number("step", fallback: 1)))
                    .accessibilityLabel(text("label", fallback: text("name"))).disabled(!enabled)
                if (props["currentValue"]?.array?.count ?? 0) > 1 {
                    Slider(value: sliderBinding(index: 1, minimum: minimum, maximum: maximum),
                        in: minimum...maximum, step: max(0.0001, number("step", fallback: 1)))
                        .accessibilityLabel("\(text("label", fallback: text("name"))) upper value").disabled(!enabled)
                }
            }
        case "CheckBoxGroup", "SwitchGroup":
            VStack(alignment: .leading) {
                ForEach(Array(array("items").enumerated()), id: \.offset) { _, item in
                    let p = item.object?["props"]?.object ?? [:]
                    let name = p["name"]?.string ?? ""
                    Toggle(p["label"]?.string ?? name, isOn: Binding(get: {
                        (props["currentValue"]?.object?[name] ?? p["defaultChecked"]) == .bool(true)
                    }, set: { next in
                        var values = props["currentValue"]?.object ?? [:]
                        values[name] = .bool(next); runtime.field(id, value: .object(values))
                    })).disabled(!enabled)
                }
            }
        case "Button":
            Button(text("label"), role: text("type") == "destructive" ? .destructive : nil) { runtime.action(id) }
                .buttonStyle(.bordered).disabled(!enabled)
        default: EmptyView()
        }
    }

    @ViewBuilder private var textOrMedia: some View {
        switch type {
        case "CardHeader", "InlineHeader":
            VStack(alignment: .leading, spacing: 4) {
                Text(text("title", fallback: text("heading"))).font(.headline)
                let detail = text("subtitle", fallback: text("description"))
                if !detail.isEmpty { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
            }
        case "Title": Text(text("text")).font(.title2.weight(.semibold)).textSelection(.enabled)
        case "Conclusion": Text(.init(text("text"))).font(.body.weight(.medium)).textSelection(.enabled)
        case "TextContent", "MarkDownRenderer", "Paragraph": Text(.init(text("text", fallback: text("textMarkdown")))).textSelection(.enabled)
        case "Text", "BoldText":
            VStack(alignment: .leading) {
                Text(text("value")).fontWeight(type == "BoldText" ? .semibold : .regular)
                if !text("subtext").isEmpty { Text(text("subtext")).font(.caption).foregroundStyle(.secondary) }
            }.textSelection(.enabled)
        case "Label": Text(text("text")).font(.subheadline)
        case "CodeBlock": ScrollView(.horizontal) { Text(text("codeString")).font(.system(.callout, design: .monospaced)).textSelection(.enabled) }
        case "Separator": Divider()
        case "Image", "ImageBlock": image(url: text("src"), alt: text("alt"))
        case "Tag": Text(text("text")).font(.caption).padding(.horizontal, 8).padding(.vertical, 4).background(.quaternary, in: Capsule())
        case "TagBlock":
            ScrollView(.horizontal) { HStack { ForEach(Array(array("tags").enumerated()), id: \.offset) { _, tag in
                Text(tag.string ?? "").font(.caption).padding(6).background(.quaternary, in: Capsule())
            } } }
        case "TextCallout", "Callout":
            VStack(alignment: .leading) { Text(text("title")).font(.headline); Text(text("description")) }
                .padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        case "SourceQuote":
            VStack(alignment: .leading, spacing: 6) {
                Text(.init(text("text"))).textSelection(.enabled)
                if props["hasAction"] == .bool(true) {
                    Button(text("reference")) { runtime.action(id) }.font(.caption).disabled(!enabled)
                } else { Text(text("reference")).font(.caption) }
            }.padding(.leading, 10).overlay(alignment: .leading) { Rectangle().fill(.secondary.opacity(0.4)).frame(width: 2) }
        default: EmptyView()
        }
    }

    @ViewBuilder private var collection: some View {
        switch type {
        case "Table":
            let columns = array("columns").compactMap { $0.object?["props"]?.object }
            let count = columns.map { $0["data"]?.array?.count ?? 0 }.max() ?? 0
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
                    GridRow { ForEach(Array(columns.enumerated()), id: \.offset) { _, column in Text(column["label"]?.string ?? "").fontWeight(.semibold) } }
                    Divider()
                    ForEach(0..<count, id: \.self) { row in GridRow {
                        ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                            let data = column["data"]?.array ?? []
                            if data.indices.contains(row) { children(data[row]) } else { Text("") }
                        }
                    } }
                }.textSelection(.enabled)
            }
        case "ImageGallery":
            ScrollView(.horizontal) { HStack(alignment: .top) {
                ForEach(Array(array("images").enumerated()), id: \.offset) { _, item in
                    image(url: item.object?["src"]?.string ?? "", alt: item.object?["alt"]?.string ?? "").frame(width: 220)
                }
            } }
        case "EntityList":
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(array("rows").enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top) { Text(item.object?["left"]?.displayText ?? ""); Spacer(); Text(item.object?["right"]?.displayText ?? "") }
                }
            }
        case "ListBlock", "Steps":
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(array("items").enumerated()), id: \.offset) { index, item in
                    let p = item.object?["props"]?.object ?? [:]
                    if p["hasAction"] == .bool(true), let itemID = item.object?["id"]?.string {
                        Button { runtime.action(itemID) } label: { listRow(p, index: index) }
                            .buttonStyle(.plain).disabled(!enabled)
                    } else { listRow(p, index: index) }
                }
            }
        case "Comparison":
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top) { comparisonPositions }
                VStack(alignment: .leading) { comparisonPositions }
            }
        case "Sources":
            VStack(alignment: .leading) { ForEach(Array(array("references").enumerated()), id: \.offset) { _, ref in Text(ref.displayText).font(.caption) } }
        default: EmptyView()
        }
    }

    @ViewBuilder private var comparisonPositions: some View {
        ForEach(Array(array("positions").enumerated()), id: \.offset) { _, position in
            VStack(alignment: .leading) { Text(position.object?["title"]?.string ?? "").font(.headline); Text(position.object?["text"]?.string ?? "") }.padding(8)
        }
    }

    @ViewBuilder private var chart: some View {
        if type == "PieChart" {
            let labels = array("labels")
            let values = array("values")
            Chart(Array(values.enumerated()), id: \.offset) { index, value in
                SectorMark(angle: .value("Value", value.number ?? 0), innerRadius: .ratio(text("variant") == "donut" ? 0.6 : 0))
                    .foregroundStyle(by: .value("Label", labels.indices.contains(index) ? labels[index].displayText : String(index + 1)))
            }.frame(height: number("height", fallback: 220))
        } else if type == "ScatterChart" {
            Chart(scatterPoints) { point in
                PointMark(x: .value("X", point.x), y: .value("Y", point.y)).foregroundStyle(by: .value("Series", point.series))
            }.frame(height: number("height", fallback: 220))
        } else {
            Chart(seriesPoints) { point in
                if type == "HorizontalBarChart" {
                    BarMark(x: .value("Value", point.value), y: .value("Category", point.label)).foregroundStyle(by: .value("Series", point.series))
                } else if type == "LineChart" {
                    LineMark(x: .value("Category", point.label), y: .value("Value", point.value)).foregroundStyle(by: .value("Series", point.series))
                } else if type == "AreaChart" {
                    AreaMark(x: .value("Category", point.label), y: .value("Value", point.value)).foregroundStyle(by: .value("Series", point.series))
                } else {
                    BarMark(x: .value("Category", point.label), y: .value("Value", point.value)).foregroundStyle(by: .value("Series", point.series))
                }
            }.frame(height: number("height", fallback: 220))
        }
    }

    private struct SeriesPoint: Identifiable { let id: String; let label: String; let value: Double; let series: String }
    private var seriesPoints: [SeriesPoint] {
        let labels = array("labels")
        return array("series").enumerated().flatMap { seriesIndex, item -> [SeriesPoint] in
            let p = item.object?["props"]?.object ?? [:]
            return (p["values"]?.array ?? []).enumerated().map { index, value in
                .init(id: "\(seriesIndex)/\(index)", label: labels.indices.contains(index) ? labels[index].displayText : String(index + 1),
                      value: value.number ?? 0, series: p["category"]?.string ?? "")
            }
        }
    }
    private struct ScatterPoint: Identifiable { let id: String; let x: Double; let y: Double; let series: String }
    private var scatterPoints: [ScatterPoint] {
        array("datasets").enumerated().flatMap { seriesIndex, item -> [ScatterPoint] in
            let p = item.object?["props"]?.object ?? [:]
            return (p["points"]?.array ?? []).enumerated().map { index, item in
                let point = item.object?["props"]?.object ?? [:]
                return .init(id: "\(seriesIndex)/\(index)", x: point["x"]?.number ?? 0, y: point["y"]?.number ?? 0, series: p["name"]?.string ?? "")
            }
        }
    }

    private func text(_ key: String, fallback: String = "") -> String { props[key]?.string ?? fallback }
    private func number(_ key: String, fallback: Double) -> Double { props[key]?.number ?? fallback }
    private func array(_ key: String) -> [PresentationValue] { props[key]?.array ?? [] }
    private var gap: CGFloat { ["none": 0, "xs": 4, "s": 8, "m": 12, "l": 16, "xl": 24, "2xl": 32][text("gap")] ?? 12 }
    private var stringBinding: Binding<String> {
        Binding(get: { text("currentValue", fallback: text("defaultValue")) }, set: { runtime.field(id, value: .string($0)) })
    }
    private func date(_ value: PresentationValue?) -> Date? {
        guard let raw = value?.object?["__hanlinOpenUIDate"]?.string ?? value?.string else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = formatter.date(from: raw) { return value }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }
    private func dateValue(_ value: Date) -> PresentationValue {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return .object(["__hanlinOpenUIDate": .string(formatter.string(from: value))])
    }
    private func dateBinding(key: String? = nil) -> Binding<Date> {
        Binding(get: {
            date(key.map { props["currentValue"]?.object?[$0] } ?? props["currentValue"]) ?? .now
        }, set: { next in
            if let key {
                var range = props["currentValue"]?.object ?? [:]
                range[key] = dateValue(next)
                if key == "from", let end = date(range["to"]), end < next { range["to"] = dateValue(next) }
                runtime.field(id, value: .object(range))
            } else { runtime.field(id, value: dateValue(next)) }
        })
    }
    private func sliderBinding(index: Int, minimum: Double, maximum: Double) -> Binding<Double> {
        Binding(get: {
            let values = props["currentValue"]?.array ?? []
            return min(maximum, max(minimum, values.indices.contains(index) ? values[index].number ?? minimum : minimum))
        }, set: { next in
            var values = props["currentValue"]?.array ?? [.number(minimum)]
            guard values.indices.contains(index) else { return }
            let lower = index > 0 ? values[index - 1].number ?? minimum : minimum
            let upper = index + 1 < values.count ? values[index + 1].number ?? maximum : maximum
            values[index] = .number(min(upper, max(lower, next)))
            runtime.field(id, value: .array(values))
        })
    }
    private func listRow(_ props: [String: PresentationValue], index: Int) -> some View {
        HStack(alignment: .top) {
            if text("variant") == "image", let item = props["image"]?.object {
                image(url: item["src"]?.string ?? "", alt: item["alt"]?.string ?? "").frame(width: 44)
            } else { Text("\(index + 1).").foregroundStyle(.secondary) }
            VStack(alignment: .leading) {
                Text(props["title"]?.string ?? "").fontWeight(.medium)
                children(props["subtitle"] ?? props["details"])
                if let label = props["actionLabel"]?.string { Text(label).font(.caption).foregroundStyle(.tint) }
            }
        }
    }
    @ViewBuilder private func children(_ value: PresentationValue?) -> some View {
        if let values = value?.array {
            ForEach(Array(values.enumerated()), id: \.offset) { _, child in
                if child.object?["typeName"] != nil {
                    AnyView(NativeOpenUINode(value: child, runtime: runtime, configuration: configuration))
                } else if child != .null { Text(child.displayText).textSelection(.enabled) }
            }
        } else if let value, value.object?["typeName"] != nil { AnyView(NativeOpenUINode(value: value, runtime: runtime, configuration: configuration)) }
        else if let value, value != .null { Text(value.displayText).textSelection(.enabled) }
    }
    private func image(url: String, alt: String) -> some View {
        AsyncImage(url: URL(string: url)) { phase in
            if let image = phase.image { image.resizable().scaledToFit() }
            else { Text(alt).foregroundStyle(.secondary) }
        }.accessibilityLabel(alt)
    }
}
#endif
