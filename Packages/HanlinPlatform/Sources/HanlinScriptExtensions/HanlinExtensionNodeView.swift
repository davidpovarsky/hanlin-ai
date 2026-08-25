import HanlinPlatformContracts
import HanlinScriptUI
import SwiftUI

public struct HanlinExtensionNodeView: View {
    private let node: HanlinScriptUINode

    public init(node: HanlinScriptUINode) {
        self.node = node
    }

    @ViewBuilder
    public var body: some View {
        switch node.kind {
        case .text:
            Text(text("text") ?? "")
        case .image:
            Image(systemName: text("systemName") ?? "photo")
        case .hStack:
            HStack { children }
        case .vStack, .fragment, .group, .groupBox, .form, .lazyVGrid, .scrollViewReader:
            VStack { children }
        case .zStack:
            ZStack { children }
        case .spacer:
            Spacer()
        case .divider:
            Divider()
        case .progress:
            ProgressView()
        case .label:
            Label(text("title") ?? "", systemImage: text("systemImage") ?? "circle")
        case .markdown:
            Text(text("content") ?? text("text") ?? "")
        case .contentUnavailableView:
            ContentUnavailableView(text("title") ?? "Unavailable", systemImage: text("systemImage") ?? "tray")
        case .disclosureGroup, .controlGroup:
            VStack { children }
        case .slider:
            ProgressView(value: number("value"), total: number("max") ?? 1)
        case .button, .link, .menu, .toggle, .textField, .scrollView, .navigationStack, .navigationSplitView,
             .navigationLink, .navigationDestination, .picker, .svg, .tabView, .tab:
            Label("Open Hanlin", systemImage: "arrow.up.forward.app")
        case .chart, .barChart:
            VStack { children }
        case .circle:
            Circle().fill(.secondary)
        case .capsule:
            Capsule().fill(.secondary)
        case .rectangle:
            Rectangle().fill(.secondary)
        case .roundedRectangle:
            RoundedRectangle(cornerRadius: 12).fill(.secondary)
        case .presentation:
            EmptyView()
        }
    }

    @ViewBuilder
    private var children: some View {
        ForEach(Array(node.children.enumerated()), id: \.offset) { _, child in
            HanlinExtensionNodeView(node: child)
        }
    }

    private func text(_ key: String) -> String? {
        guard case let .string(value)? = node.properties[key] else { return nil }
        return value
    }

    private func number(_ key: String) -> Double? {
        switch node.properties[key] {
        case let .integer(value): Double(value)
        case let .number(value): value
        default: nil
        }
    }
}
