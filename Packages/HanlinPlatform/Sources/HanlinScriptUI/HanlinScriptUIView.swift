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
        case let .render(node): root = node
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
                set: { if !$0 { model.activePresentation = nil } }
            )
        ) {
            Button("OK") { model.activePresentation = nil }
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
            set: { model.activePresentation = $0 }
        )) { presentation in
            if let content = presentation.content {
                HanlinScriptUINodeView(node: content, model: model)
            }
        }
    }

    private var fullScreenPresentation: Binding<HanlinScriptUIPresentation?> {
        Binding(
            get: { model.activePresentation?.style == .fullScreen ? model.activePresentation : nil },
            set: { model.activePresentation = $0 }
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
                .accessibilityLabel(node.string("accessibilityLabel") ?? node.string("text") ?? "")
        case .image:
            Image(systemName: node.string("systemName") ?? "photo")
                .accessibilityLabel(node.string("accessibilityLabel") ?? "Image")
        case .button:
            Button { model.dispatch(handlerID: node.string("onPress")) } label: {
                if node.children.isEmpty { Text(node.string("title") ?? "") } else { children(node) }
            }
            .accessibilityHint(node.string("accessibilityHint") ?? "")
        case .textField:
            TextField(node.string("placeholder") ?? "", text: Binding(
                get: { node.string("value") ?? "" },
                set: { model.dispatch(handlerID: node.string("onChange"), payload: .string($0)) }
            ))
            .textFieldStyle(.roundedBorder)
        case .hStack:
            HStack(spacing: node.dimension("spacing")) { children(node) }
        case .vStack:
            VStack(spacing: node.dimension("spacing")) { children(node) }
        case .zStack:
            ZStack { children(node) }
        case .scrollView:
            ScrollView { children(node) }
        case .spacer:
            Spacer(minLength: node.dimension("minimumLength"))
        case .divider:
            Divider()
        case .progress:
            if let value = node.number("value") { ProgressView(value: value) } else { ProgressView() }
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
                set: { model.selectedTab = $0 }
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

    func dimension(_ name: String) -> CGFloat? {
        number(name).map(CGFloat.init)
    }
}
