import Charts
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
            set: { model.navigationPath = $0 }
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
        case .presentation:
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

    @ViewBuilder
    private func children(_ node: HanlinScriptUINode) -> some View {
        ForEach(node.children.indices, id: \.self) { index in
            HanlinScriptUINodeView(node: node.children[index], model: model)
        }
    }
}

private extension HanlinScriptUINode {
    func string(_ name: String) -> String? {
        guard case let .string(value)? = properties[name] else { return nil }
        return value
    }

    func number(_ name: String) -> Double? {
        switch properties[name] {
        case let .integer(value): Double(value)
        case let .number(value): value
        default: nil
        }
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
