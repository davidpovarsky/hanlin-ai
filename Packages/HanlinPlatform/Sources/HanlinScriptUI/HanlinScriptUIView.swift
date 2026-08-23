import HanlinPlatformContracts
import Observation
import SwiftUI

@MainActor
@Observable
public final class HanlinScriptUIModel {
    public private(set) var root: HanlinScriptUINode
    public private(set) var effects: [String: HanlinScriptUIEffect] = [:]
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
        }
    }

    fileprivate func dispatch(handlerID: String?, payload: HanlinValue = .null) {
        guard let handlerID, !handlerID.isEmpty else { return }
        eventSink(handlerID, payload)
    }
}

public struct HanlinScriptUIView: View {
    private let model: HanlinScriptUIModel

    public init(model: HanlinScriptUIModel) { self.model = model }

    public var body: some View { HanlinScriptUINodeView(node: model.root, model: model) }
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
            HStack(spacing: node.number("spacing")) { children(node) }
        case .vStack:
            VStack(spacing: node.number("spacing")) { children(node) }
        case .zStack:
            ZStack { children(node) }
        case .scrollView:
            ScrollView { children(node) }
        case .spacer:
            Spacer(minLength: node.number("minimumLength"))
        case .divider:
            Divider()
        case .progress:
            if let value = node.number("value") { ProgressView(value: value) } else { ProgressView() }
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
}
