import AppIntents
import HanlinPlatformContracts
import HanlinScriptUI
import SwiftUI

public struct HanlinExtensionNodeView: View {
    private let node: HanlinScriptUINode
    private let identity: HanlinScriptExtensionIdentity?

    public init(node: HanlinScriptUINode, identity: HanlinScriptExtensionIdentity? = nil) {
        self.node = node
        self.identity = identity
    }

    @ViewBuilder
    public var body: some View {
        primitive
            .modifier(HanlinExtensionNodeStyleModifier(style: .init(node: node)))
    }

    @ViewBuilder
    private var primitive: some View {
        switch node.kind {
        case .text:
            Text(text("text") ?? "")
        case .image:
            Image(systemName: text("systemName") ?? "photo")
        case .hStack:
            HStack(alignment: verticalAlignment, spacing: number("spacing").map(CGFloat.init)) { children }
        case .vStack:
            VStack(alignment: horizontalAlignment, spacing: number("spacing").map(CGFloat.init)) { children }
        case .fragment, .group, .groupBox, .form, .lazyVGrid, .scrollViewReader:
            VStack(spacing: number("spacing").map(CGFloat.init)) { children }
        case .zStack:
            ZStack(alignment: stackAlignment) { children }
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
        case .button:
            if let intent = scriptActionIntent {
                Button(intent: intent) { children }
            } else {
                VStack { children }
            }
        case .link, .menu, .toggle, .textField, .scrollView, .navigationStack, .navigationSplitView,
             .navigationLink, .navigationDestination, .picker, .svg, .tabView, .tab:
            Label("Open Hanlin", systemImage: "arrow.up.forward.app")
        case .chart, .barChart:
            VStack { children }
        case .circle:
            Circle()
                .fill(color("fill") ?? .clear)
                .overlay(Circle().stroke(.secondary.opacity(node.properties["fill"] == nil ? 1 : 0)))
        case .capsule:
            Capsule().fill(color("fill") ?? .secondary)
        case .rectangle:
            Rectangle().fill(color("fill") ?? .secondary)
        case .roundedRectangle:
            RoundedRectangle(cornerRadius: CGFloat(number("cornerRadius") ?? 12))
                .fill(color("fill") ?? .secondary)
        case .liveActivityUI, .liveActivityContent, .liveActivityCompactLeading,
             .liveActivityCompactTrailing, .liveActivityMinimal, .liveActivityExpandedLeading,
             .liveActivityExpandedTrailing, .liveActivityExpandedCenter, .liveActivityExpandedBottom:
            Group { children }
        case .presentation:
            EmptyView()
        }
    }

    @ViewBuilder
    private var children: some View {
        ForEach(Array(node.children.enumerated()), id: \.offset) { _, child in
            HanlinExtensionNodeView(node: child, identity: identity)
        }
    }

    private var scriptActionIntent: HanlinInvokeScriptActionIntent? {
        guard let identity,
              case let .object(descriptor)? = node.properties["intent"],
              descriptor["__hanlinAppIntent"] == .bool(true),
              case let .string(name)? = descriptor["name"] else { return nil }
        let parameters = descriptor["parameters"] ?? .object([:])
        guard let data = try? parameters
            .jsonValue(destination: .javaScriptBinary64)
            .canonicalJSONData(),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return .init(identity: identity, actionName: name, parametersJSON: json)
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

    private func color(_ key: String) -> Color? {
        guard let value = text(key) else { return nil }
        return HanlinExtensionColor.color(value)
    }

    private var horizontalAlignment: HorizontalAlignment {
        switch text("alignment") {
        case "leading": .leading
        case "trailing": .trailing
        default: .center
        }
    }

    private var verticalAlignment: VerticalAlignment {
        switch text("alignment") {
        case "top": .top
        case "bottom": .bottom
        case "firstTextBaseline": .firstTextBaseline
        case "lastTextBaseline": .lastTextBaseline
        default: .center
        }
    }

    private var stackAlignment: Alignment {
        switch text("alignment") {
        case "topLeading": .topLeading
        case "top": .top
        case "topTrailing": .topTrailing
        case "leading": .leading
        case "trailing": .trailing
        case "bottomLeading": .bottomLeading
        case "bottom": .bottom
        case "bottomTrailing": .bottomTrailing
        default: .center
        }
    }
}

struct HanlinExtensionNodeStyle: Equatable {
    let fontSize: Double?
    let fontWeight: String?
    let foregroundStyle: String?
    let padding: Double?
    let frameWidth: Double?
    let frameHeight: Double?
    let opacity: Double
    let lineLimit: Int?
    let minimumScaleFactor: Double
    let strikethrough: Bool

    init(node: HanlinScriptUINode) {
        func number(_ value: HanlinValue?) -> Double? {
            switch value {
            case let .integer(value): Double(value)
            case let .number(value): value
            default: nil
            }
        }
        func string(_ value: HanlinValue?) -> String? {
            guard case let .string(value)? = value else { return nil }
            return value
        }
        fontSize = number(node.properties["font"])
        fontWeight = string(node.properties["fontWeight"])
        foregroundStyle = string(node.properties["foregroundStyle"])
        padding = number(node.properties["padding"])
        if case let .object(frame)? = node.properties["frame"] {
            frameWidth = number(frame["width"])
            frameHeight = number(frame["height"])
        } else {
            frameWidth = nil
            frameHeight = nil
        }
        opacity = min(max(number(node.properties["opacity"]) ?? 1, 0), 1)
        lineLimit = number(node.properties["lineLimit"]).map { max(0, Int($0)) }
        minimumScaleFactor = min(max(number(node.properties["minimumScaleFactor"]) ?? 1, 0.01), 1)
        strikethrough = node.properties["strikethrough"] != nil
            && node.properties["strikethrough"] != .null
            && node.properties["strikethrough"] != .bool(false)
    }
}

private struct HanlinExtensionNodeStyleModifier: ViewModifier {
    let style: HanlinExtensionNodeStyle

    func body(content: Content) -> some View {
        content
            .font(style.fontSize.map { .system(size: CGFloat($0)) })
            .fontWeight(weight)
            .lineLimit(style.lineLimit)
            .minimumScaleFactor(style.minimumScaleFactor)
            .opacity(style.opacity)
            .strikethrough(style.strikethrough)
            .modifier(HanlinExtensionForegroundModifier(value: style.foregroundStyle))
            .modifier(HanlinExtensionPaddingModifier(value: style.padding))
            .modifier(HanlinExtensionFrameModifier(width: style.frameWidth, height: style.frameHeight))
    }

    private var weight: Font.Weight? {
        switch style.fontWeight {
        case "ultraLight": .ultraLight
        case "thin": .thin
        case "light": .light
        case "medium": .medium
        case "semibold": .semibold
        case "bold": .bold
        case "heavy": .heavy
        case "black": .black
        default: nil
        }
    }
}

private struct HanlinExtensionForegroundModifier: ViewModifier {
    let value: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let value, let color = HanlinExtensionColor.color(value) {
            content.foregroundStyle(color)
        } else {
            content
        }
    }
}

private struct HanlinExtensionPaddingModifier: ViewModifier {
    let value: Double?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let value { content.padding(CGFloat(value)) } else { content }
    }
}

private struct HanlinExtensionFrameModifier: ViewModifier {
    let width: Double?
    let height: Double?

    @ViewBuilder
    func body(content: Content) -> some View {
        if width != nil || height != nil {
            content.frame(width: width.map(CGFloat.init), height: height.map(CGFloat.init))
        } else {
            content
        }
    }
}

private enum HanlinExtensionColor {
    static func color(_ value: String) -> Color? {
        switch value {
        case "label", "primary": .primary
        case "secondaryLabel", "secondary": .secondary
        case "systemRed", "red": .red
        case "systemGreen", "green": .green
        case "systemBlue", "blue": .blue
        case "systemOrange", "orange": .orange
        case "systemYellow", "yellow": .yellow
        case "systemPink", "pink": .pink
        case "systemPurple", "purple": .purple
        case "systemTeal", "teal": .teal
        case "systemIndigo", "indigo": .indigo
        case "systemBrown", "brown": .brown
        case "systemCyan", "cyan": .cyan
        case "white": .white
        case "black": .black
        case "clear": .clear
        default: hex(value)
        }
    }

    private static func hex(_ value: String) -> Color? {
        let digits = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard digits.count == 6 || digits.count == 8,
              let raw = UInt64(digits, radix: 16) else { return nil }
        let red = Double((raw >> (digits.count == 8 ? 24 : 16)) & 0xFF) / 255
        let green = Double((raw >> (digits.count == 8 ? 16 : 8)) & 0xFF) / 255
        let blue = Double((raw >> (digits.count == 8 ? 8 : 0)) & 0xFF) / 255
        let alpha = digits.count == 8 ? Double(raw & 0xFF) / 255 : 1
        return Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}
