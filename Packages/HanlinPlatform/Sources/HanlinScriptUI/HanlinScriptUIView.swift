import Charts
import Foundation
import HanlinPlatformContracts
import Observation
import SwiftUI

@MainActor
@Observable
public final class HanlinScriptUIModel {
    public private(set) var root: HanlinScriptUINode
    public private(set) var effects: [String: HanlinScriptUIEffect] = [:]
    public var navigationPath: [HanlinScriptUIRoute] = []
    public var selectedTab: String?
    public var activePresentation: HanlinScriptUIPresentation?
    public private(set) var scenePhase: HanlinScriptUIScenePhase = .inactive
    public private(set) var lastResumePayload: HanlinScriptResumePayload?
    private var routeDestinations: [String: HanlinScriptUINode] = [:]
    private var navigationPathChangeHandlerID: String?
    private let eventSink: @MainActor (String, HanlinValue) -> Void

    public init(
        root: HanlinScriptUINode,
        eventSink: @escaping @MainActor (String, HanlinValue) -> Void
    ) {
        self.root = root
        self.eventSink = eventSink
    }

    public func apply(_ command: HanlinScriptUICommand) throws {
        switch command {
        case let .render(node):
            root = node
            routeDestinations = node.navigationDestinations()
            if let stack = node.firstNavigationStack() {
                navigationPathChangeHandlerID = stack.string("onPathChange")
                let routeIDs = stack.stringArray("path") ?? []
                navigationPath = routeIDs.compactMap { id in
                    routeDestinations[id] == nil ? nil : HanlinScriptUIRoute(id: id, payload: .string(id))
                }
            } else {
                navigationPathChangeHandlerID = nil
                navigationPath = []
            }
            if let selection = node.initialTabSelection() { selectedTab = selection }
            activePresentation = node.presentation()
        case let .patches(patches): root = try HanlinScriptUIReconciler.apply(patches, to: root)
        case let .event(handlerID, payload): eventSink(handlerID, payload)
        case .state: break
        case let .registerEffect(effect): effects[effect.id] = effect
        case let .releaseEffect(id): effects.removeValue(forKey: id)
        case let .registerRoute(route, destination): routeDestinations[route.id] = destination
        case let .navigate(route):
            guard routeDestinations[route.id] != nil else { throw HanlinScriptUIError.unknownRoute(route.id) }
            navigationPath.append(route)
        case let .pop(count):
            guard count >= 0, count <= navigationPath.count else { throw HanlinScriptUIError.invalidPopCount(count) }
            navigationPath.removeLast(count)
        case let .selectTab(id): selectedTab = id
        case let .present(presentation): activePresentation = presentation
        case let .dismissPresentation(id):
            if activePresentation?.id == id { activePresentation = nil }
        case let .scenePhase(value): scenePhase = value
        case let .resume(payload):
            lastResumePayload = payload
            let queryParameters = try HanlinObject(uniqueMembers: payload.queryParameters.map {
                (key: $0.key, value: $0.value)
            })
            eventSink("Script.onResume", .object([
                "source": .string(payload.source),
                "queryParameters": .object(queryParameters)
            ]))
        }
    }

    fileprivate func dispatch(handlerID: String?, payload: HanlinValue = .null) {
        guard let handlerID, !handlerID.isEmpty else { return }
        eventSink(handlerID, payload)
    }

    fileprivate func destination(for route: HanlinScriptUIRoute) -> HanlinScriptUINode? {
        routeDestinations[route.id]
    }

    fileprivate func route(id: String?) -> HanlinScriptUIRoute? {
        guard let id, routeDestinations[id] != nil else { return nil }
        return .init(id: id)
    }

    fileprivate func dismissActivePresentation() {
        let handlerID = activePresentation?.dismissHandlerID
        activePresentation = nil
        dispatch(handlerID: handlerID, payload: .bool(false))
    }

    func updateNavigationPath(_ path: [HanlinScriptUIRoute]) {
        navigationPath = path
        dispatch(
            handlerID: navigationPathChangeHandlerID,
            payload: .array(path.map { .string($0.id) })
        )
    }
}

public struct HanlinScriptUIView: View {
    private let model: HanlinScriptUIModel

    public init(model: HanlinScriptUIModel) { self.model = model }

    public var body: some View {
        presentationView
        .alert(
            model.activePresentation?.style == .dialog ? model.activePresentation?.title ?? "" : "",
            isPresented: Binding(
                get: { model.activePresentation?.style == .dialog },
                set: { if !$0 { model.dismissActivePresentation() } }
            )
        ) {
            if let content = model.activePresentation?.content {
                HanlinScriptUINodeView(node: content, model: model)
            } else {
                Button("OK") { model.dismissActivePresentation() }
            }
        } message: {
            Text(model.activePresentation?.message ?? "")
        }
    }

    @ViewBuilder
    private var presentationView: some View {
#if os(iOS)
        sheetView
            .fullScreenCover(item: fullScreenPresentation) { presentation in
                if let content = presentation.content {
                    HanlinScriptUINodeView(node: content, model: model)
                }
            }
#else
        sheetView
            .sheet(item: fullScreenPresentation) { presentation in
                if let content = presentation.content {
                    HanlinScriptUINodeView(node: content, model: model)
                }
            }
#endif
    }

    private var sheetView: some View {
        NavigationStack(path: Binding(
            get: { model.navigationPath },
            set: { model.updateNavigationPath($0) }
        )) {
            HanlinScriptUINodeView(node: model.root, model: model)
                .navigationDestination(for: HanlinScriptUIRoute.self) { route in
                    if let destination = model.destination(for: route) {
                        HanlinScriptUINodeView(node: destination, model: model)
                    } else {
                        ContentUnavailableView("Unavailable Route", systemImage: "exclamationmark.triangle")
                    }
                }
        }
        .sheet(item: Binding(
            get: { model.activePresentation?.style == .sheet ? model.activePresentation : nil },
            set: { if $0 == nil { model.dismissActivePresentation() } }
        )) { presentation in
            if let content = presentation.content {
                HanlinScriptUINodeView(node: content, model: model)
            }
        }
    }

    private var fullScreenPresentation: Binding<HanlinScriptUIPresentation?> {
        Binding(
            get: { model.activePresentation?.style == .fullScreen ? model.activePresentation : nil },
            set: { if $0 == nil { model.dismissActivePresentation() } }
        )
    }
}

private struct HanlinScriptUINodeView: View {
    let node: HanlinScriptUINode
    let model: HanlinScriptUIModel

    @ViewBuilder
    var body: some View {
        Group {
            switch node.kind {
        case .fragment, .group:
            Group { children(node) }
        case .text:
            Text(node.string("text") ?? "")
                .font(node.dimension("font").map { .system(size: $0) })
                .fontWeight(node.fontWeight())
                .foregroundStyle(node.color("foregroundStyle") ?? .primary)
                .accessibilityLabel(node.string("accessibilityLabel") ?? node.string("text") ?? "")
        case .image:
            Image(systemName: node.string("systemName") ?? "photo")
                .font(node.dimension("font").map { .system(size: $0) })
                .foregroundStyle(node.color("foregroundStyle") ?? .primary)
                .accessibilityLabel(node.string("accessibilityLabel") ?? "Image")
        case .button:
            Button { model.dispatch(handlerID: node.string("onPress")) } label: {
                if node.children.isEmpty { Text(node.string("title") ?? "") } else { children(node) }
            }
            .accessibilityHint(node.string("accessibilityHint") ?? "")
        case .link:
            if let value = node.string("url"), let url = URL(string: value) {
                Link(destination: url) {
                    if node.children.isEmpty { Text(value) } else { children(node) }
                }
            }
        case .menu:
            Menu {
                children(node)
            } label: {
                Label(node.string("title") ?? "Menu", systemImage: node.string("systemImage") ?? "ellipsis.circle")
            }
        case .toggle:
            Toggle(node.string("title") ?? "", isOn: Binding(
                get: { node.bool("value") ?? false },
                set: { model.dispatch(handlerID: node.string("onChange"), payload: .bool($0)) }
            ))
        case .textField:
            TextField(node.string("placeholder") ?? "", text: Binding(
                get: { node.string("value") ?? "" },
                set: { model.dispatch(handlerID: node.string("onChange"), payload: .string($0)) }
            ))
            .textFieldStyle(.roundedBorder)
        case .hStack:
            HStack(spacing: node.dimension("spacing")) { children(node) }
                .padding(node.edgeInsets())
        case .vStack:
            VStack(spacing: node.dimension("spacing")) { children(node) }
                .padding(node.edgeInsets())
        case .zStack:
            ZStack { children(node) }
                .padding(node.edgeInsets())
        case .scrollView:
            ScrollView { LazyVStack(alignment: .leading) { children(node) } }
                .navigationTitle(node.string("navigationTitle") ?? "")
        case .form:
            Form { children(node) }
                .navigationTitle(node.string("navigationTitle") ?? "")
        case .label:
            Label(
                node.string("title") ?? "",
                systemImage: node.string("systemImage") ?? "circle"
            )
        case .controlGroup:
            ControlGroup { children(node) }
        case .groupBox:
            GroupBox {
                childRange(node, from: node.integer("labelCount"))
            } label: {
                if node.integer("labelCount") > 0 {
                    childRange(node, from: 0, count: node.integer("labelCount"))
                } else if let title = node.string("title") {
                    Text(title)
                }
            }
        case .picker:
            Picker(node.string("title") ?? "", selection: Binding(
                get: { node.string("value") ?? "" },
                set: { model.dispatch(handlerID: node.string("onChange"), payload: .string($0)) }
            )) {
                ForEach(node.children.indices, id: \.self) { index in
                    let child = node.children[index]
                    HanlinScriptUINodeView(node: child, model: model)
                        .tag(child.string("tag") ?? child.string("text") ?? String(index))
                }
            }
        case .contentUnavailableView:
            ContentUnavailableView {
                if node.integer("labelCount") > 0 {
                    childRange(node, from: 0, count: node.integer("labelCount"))
                } else {
                    Label(node.string("title") ?? "", systemImage: node.string("systemImage") ?? "tray")
                }
            } description: {
                if node.integer("descriptionCount") > 0 {
                    childRange(
                        node,
                        from: node.integer("labelCount"),
                        count: node.integer("descriptionCount")
                    )
                } else if let description = node.string("description") {
                    Text(description)
                }
            } actions: {
                childRange(
                    node,
                    from: node.integer("labelCount") + node.integer("descriptionCount"),
                    count: node.integer("actionCount")
                )
            }
        case .disclosureGroup:
            DisclosureGroup(isExpanded: Binding(
                get: { node.bool("isExpanded") ?? false },
                set: { model.dispatch(handlerID: node.string("onChange"), payload: .bool($0)) }
            )) {
                childRange(node, from: node.integer("labelCount"))
            } label: {
                if node.integer("labelCount") > 0 {
                    childRange(node, from: 0, count: node.integer("labelCount"))
                } else {
                    Text(node.string("title") ?? "")
                }
            }
        case .slider:
            Slider(
                value: Binding(
                    get: { node.number("value") ?? node.number("min") ?? 0 },
                    set: { model.dispatch(handlerID: node.string("onChange"), payload: .number($0)) }
                ),
                in: (node.number("min") ?? 0)...(node.number("max") ?? 1),
                step: max(node.number("step") ?? 1, .leastNonzeroMagnitude),
                onEditingChanged: {
                    model.dispatch(handlerID: node.string("onEditingChange"), payload: .bool($0))
                }
            ) {
                if node.integer("labelCount") > 0 {
                    childRange(node, from: 0, count: node.integer("labelCount"))
                } else {
                    Text(node.string("title") ?? "Value")
                }
            }
        case .lazyVGrid:
            LazyVGrid(
                columns: node.gridColumns(),
                alignment: .leading,
                spacing: node.dimension("spacing")
            ) { children(node) }
            .padding(node.edgeInsets())
        case .navigationSplitView:
            if node.integer("contentCount") > 0 {
                NavigationSplitView(
                    columnVisibility: splitVisibilityBinding,
                    preferredCompactColumn: preferredCompactColumnBinding
                ) {
                    childRange(node, from: 0, count: node.integer("sidebarCount"))
                } content: {
                    childRange(
                        node,
                        from: node.integer("sidebarCount"),
                        count: node.integer("contentCount")
                    )
                } detail: {
                    childRange(
                        node,
                        from: node.integer("sidebarCount") + node.integer("contentCount")
                    )
                }
            } else {
                NavigationSplitView(
                    columnVisibility: splitVisibilityBinding,
                    preferredCompactColumn: preferredCompactColumnBinding
                ) {
                    childRange(node, from: 0, count: node.integer("sidebarCount"))
                } detail: {
                    childRange(node, from: node.integer("sidebarCount"))
                }
            }
        case .scrollViewReader:
            ScrollViewReader { proxy in
                children(node)
                    .onChange(of: node.integer("scrollRevision"), initial: true) { _, _ in
                        guard let target = node.string("scrollTarget") else { return }
                        proxy.scrollTo(target, anchor: node.scrollAnchor())
                    }
            }
        case .markdown:
            Text(node.markdown())
                .textSelection(.enabled)
        case .svg:
            HanlinSVGView(code: node.string("code") ?? "")
                .frame(
                    width: node.nestedDimension("frame", "width"),
                    height: node.nestedDimension("frame", "height")
                )
        case .spacer:
            Spacer(minLength: node.dimension("minimumLength"))
        case .divider:
            Divider()
        case .progress:
            if let value = node.number("value") { ProgressView(value: value) } else { ProgressView() }
        case .chart:
            children(node)
                .frame(height: node.nestedDimension("frame", "height"))
        case .barChart:
            Chart(node.chartMarks()) { mark in
                if node.bool("labelOnYAxis") == true {
                    BarMark(
                        x: .value("Value", mark.value),
                        y: .value("Label", mark.label)
                    )
                } else {
                    BarMark(
                        x: .value("Label", mark.label),
                        y: .value("Value", mark.value)
                    )
                }
            }
            .frame(height: node.nestedDimension("frame", "height"))
        case .circle:
            Circle().fill(node.color("fill") ?? node.color("foregroundStyle") ?? .secondary)
                .frame(
                    width: node.nestedDimension("frame", "width"),
                    height: node.nestedDimension("frame", "height")
                )
        case .capsule:
            Capsule().fill(node.color("fill") ?? node.color("foregroundStyle") ?? .secondary)
                .frame(
                    width: node.nestedDimension("frame", "width"),
                    height: node.nestedDimension("frame", "height")
                )
        case .rectangle:
            Rectangle().fill(node.color("fill") ?? node.color("foregroundStyle") ?? .secondary)
                .frame(
                    width: node.nestedDimension("frame", "width"),
                    height: node.nestedDimension("frame", "height")
                )
        case .roundedRectangle:
            RoundedRectangle(cornerRadius: node.dimension("cornerRadius") ?? 12)
                .fill(node.color("fill") ?? node.color("foregroundStyle") ?? .secondary)
                .frame(
                    width: node.nestedDimension("frame", "width"),
                    height: node.nestedDimension("frame", "height")
                )
        case .presentation, .navigationDestination:
            EmptyView()
        case .navigationStack:
            children(node)
        case .navigationLink:
            if let route = model.route(id: node.string("route")) {
                NavigationLink(value: route) {
                    if node.children.isEmpty { Text(node.string("title") ?? route.id) } else { children(node) }
                }
            }
        case .tabView:
            TabView(selection: Binding(
                get: { model.selectedTab },
                set: {
                    model.selectedTab = $0
                    if let value = $0 {
                        model.dispatch(handlerID: node.string("onChange"), payload: .string(value))
                    }
                }
            )) { children(node) }
        case .tab:
            children(node)
                .tabItem { Label(node.string("title") ?? "", systemImage: node.string("systemName") ?? "circle") }
                .tag(node.string("id"))
            }
        }
        .hanlinID(node.string("id") ?? node.key)
    }

    private var splitVisibilityBinding: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { node.splitVisibility() },
            set: {
                model.dispatch(
                    handlerID: node.string("onColumnVisibilityChange"),
                    payload: .string($0.hanlinName)
                )
            }
        )
    }

    private var preferredCompactColumnBinding: Binding<NavigationSplitViewColumn> {
        Binding(
            get: { node.preferredCompactColumn() },
            set: {
                model.dispatch(
                    handlerID: node.string("onPreferredCompactColumnChange"),
                    payload: .string($0.hanlinName)
                )
            }
        )
    }

    @ViewBuilder
    private func children(_ node: HanlinScriptUINode) -> some View {
        ForEach(node.children.indices, id: \.self) { index in
            HanlinScriptUINodeView(node: node.children[index], model: model)
        }
    }

    @ViewBuilder
    private func childRange(_ node: HanlinScriptUINode, from start: Int, count: Int? = nil) -> some View {
        let lowerBound = min(max(start, 0), node.children.count)
        let upperBound = min(lowerBound + max(count ?? (node.children.count - lowerBound), 0), node.children.count)
        ForEach(Array(node.children[lowerBound..<upperBound]).indices, id: \.self) { index in
            HanlinScriptUINodeView(node: node.children[lowerBound + index], model: model)
        }
    }
}

private extension HanlinScriptUINode {
    func string(_ name: String) -> String? {
        guard case let .string(value)? = properties[name] else { return nil }
        return value
    }

    func stringArray(_ name: String) -> [String]? {
        guard case let .array(values)? = properties[name] else { return nil }
        return values.compactMap { value in
            guard case let .string(text) = value else { return nil }
            return text
        }
    }

    func navigationDestinations() -> [String: HanlinScriptUINode] {
        var destinations: [String: HanlinScriptUINode] = [:]
        if kind == .navigationDestination,
           let route = string("route"),
           let destination = children.first {
            destinations[route] = destination
        }
        for child in children {
            destinations.merge(child.navigationDestinations()) { _, latest in latest }
        }
        return destinations
    }

    func firstNavigationStack() -> HanlinScriptUINode? {
        if kind == .navigationStack { return self }
        return children.lazy.compactMap { $0.firstNavigationStack() }.first
    }

    func number(_ name: String) -> Double? {
        switch properties[name] {
        case let .integer(value): Double(value)
        case let .number(value): value
        default: nil
        }
    }

    func integer(_ name: String) -> Int {
        switch properties[name] {
        case let .integer(value): Int(value)
        case let .number(value): Int(value)
        default: 0
        }
    }

    func gridColumns() -> [GridItem] {
        guard case let .array(values)? = properties["columns"] else {
            return [.init(.flexible())]
        }
        let columns = values.compactMap { value -> GridItem? in
            guard case let .object(column) = value,
                  case let .object(size)? = column["size"] else { return nil }
            func number(_ object: HanlinObject<HanlinValue>, _ key: String) -> CGFloat? {
                switch object[key] {
                case let .integer(value): CGFloat(value)
                case let .number(value): CGFloat(value)
                default: nil
                }
            }
            let type: String? = if case let .string(value)? = size["type"] { value } else { nil }
            let minimum = number(size, "minimum") ?? 10
            let maximum = number(size, "maximum") ?? .infinity
            let gridSize: GridItem.Size = switch type {
            case "fixed": .fixed(number(size, "value") ?? minimum)
            case "adaptive": .adaptive(minimum: minimum, maximum: maximum)
            default: .flexible(minimum: minimum, maximum: maximum)
            }
            return .init(gridSize, spacing: number(column, "spacing"))
        }
        return columns.isEmpty ? [.init(.flexible())] : columns
    }

    func splitVisibility() -> NavigationSplitViewVisibility {
        switch string("columnVisibility") {
        case "all": .all
        case "doubleColumn": .doubleColumn
        case "detailOnly": .detailOnly
        default: .automatic
        }
    }

    func preferredCompactColumn() -> NavigationSplitViewColumn {
        switch string("preferredCompactColumn") {
        case "sidebar": .sidebar
        case "content": .content
        default: .detail
        }
    }

    func scrollAnchor() -> UnitPoint? {
        switch string("scrollAnchor") {
        case "top": .top
        case "bottom": .bottom
        case "leading": .leading
        case "trailing": .trailing
        case "center": .center
        default: nil
        }
    }

    func markdown() -> AttributedString {
        let source = string("content") ?? string("text") ?? ""
        return (try? AttributedString(markdown: source)) ?? AttributedString(source)
    }

    func bool(_ name: String) -> Bool? {
        guard case let .bool(value)? = properties[name] else { return nil }
        return value
    }

    func color(_ name: String) -> Color? {
        guard let value = string(name) else { return nil }
        return switch value {
        case "systemRed", "red": .red
        case "systemOrange", "orange": .orange
        case "systemYellow", "yellow": .yellow
        case "systemGreen", "green": .green
        case "systemMint", "mint": .mint
        case "systemTeal", "teal": .teal
        case "systemCyan", "cyan": .cyan
        case "systemBlue", "blue": .blue
        case "systemIndigo", "indigo": .indigo
        case "systemPurple", "purple": .purple
        case "systemPink", "pink": .pink
        case "white": .white
        case "black": .black
        case "clear": .clear
        default: nil
        }
    }

    func chartMarks() -> [HanlinScriptUIChartMark] {
        guard case let .array(values)? = properties["marks"] else { return [] }
        return values.enumerated().compactMap { index, value in
            guard case let .object(mark) = value else { return nil }
            let label: String
            switch mark["label"] {
            case let .string(value): label = value
            case let .integer(value): label = String(value)
            case let .number(value): label = String(value)
            default: return nil
            }
            let number: Double
            switch mark["value"] {
            case let .integer(value): number = Double(value)
            case let .number(value): number = value
            default: return nil
            }
            return .init(id: index, label: label, value: number)
        }
    }

    func dimension(_ name: String) -> CGFloat? {
        number(name).map { CGFloat($0) }
    }

    func nestedDimension(_ objectName: String, _ memberName: String) -> CGFloat? {
        guard case let .object(object)? = properties[objectName] else { return nil }
        switch object[memberName] {
        case let .integer(value): return CGFloat(value)
        case let .number(value): return CGFloat(value)
        default: return nil
        }
    }

    func edgeInsets() -> EdgeInsets {
        if let value = dimension("padding") {
            return .init(top: value, leading: value, bottom: value, trailing: value)
        }
        guard case let .object(padding)? = properties["padding"] else { return .init() }
        func value(_ key: String) -> CGFloat {
            switch padding[key] {
            case let .integer(value): return CGFloat(value)
            case let .number(value): return CGFloat(value)
            default: return 0
            }
        }
        let horizontal = value("horizontal")
        let vertical = value("vertical")
        return .init(
            top: value("top") == 0 ? vertical : value("top"),
            leading: value("leading") == 0 ? horizontal : value("leading"),
            bottom: value("bottom") == 0 ? vertical : value("bottom"),
            trailing: value("trailing") == 0 ? horizontal : value("trailing")
        )
    }

    func fontWeight() -> Font.Weight? {
        switch string("fontWeight") {
        case "ultraLight": .ultraLight
        case "thin": .thin
        case "light": .light
        case "regular": .regular
        case "medium": .medium
        case "semibold": .semibold
        case "bold": .bold
        case "heavy": .heavy
        case "black": .black
        default: nil
        }
    }

    func initialTabSelection() -> String? {
        if kind == .tabView {
            switch properties["selection"] {
            case let .string(value): return value
            case let .integer(value): return String(value)
            case let .number(value): return String(value)
            default: break
            }
        }
        return children.lazy.compactMap { $0.initialTabSelection() }.first
    }

    func presentation() -> HanlinScriptUIPresentation? {
        if kind == .presentation,
           let id = string("id"),
           let styleName = string("style"),
           let style = HanlinScriptUIPresentationStyle(rawValue: styleName) {
            let content: HanlinScriptUINode? = if children.count == 1 {
                children[0]
            } else if children.isEmpty {
                nil
            } else {
                .init(kind: .fragment, children: children)
            }
            return .init(
                id: id,
                style: style,
                title: string("title"),
                message: string("message"),
                content: content,
                dismissHandlerID: string("onDismiss")
            )
        }
        return children.lazy.compactMap { $0.presentation() }.first
    }
}

private struct HanlinScriptUIChartMark: Identifiable {
    let id: Int
    let label: String
    let value: Double
}

private extension View {
    @ViewBuilder
    func hanlinID(_ value: String?) -> some View {
        if let value { id(value) } else { self }
    }
}

private extension NavigationSplitViewVisibility {
    var hanlinName: String {
        if self == .all { "all" }
        else if self == .doubleColumn { "doubleColumn" }
        else if self == .detailOnly { "detailOnly" }
        else { "automatic" }
    }
}

private extension NavigationSplitViewColumn {
    var hanlinName: String {
        if self == .sidebar { "sidebar" }
        else if self == .content { "content" }
        else { "detail" }
    }
}
