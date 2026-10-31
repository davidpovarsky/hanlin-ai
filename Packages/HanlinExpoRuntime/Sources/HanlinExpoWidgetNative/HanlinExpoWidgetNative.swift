import Foundation
@_exported import HanlinExpoWidgetSubset
import SwiftUI

enum NativeWidgetError: Error { case missingTarget }

// Adapted from pinned expo-widgets/ios/Widgets/Buttons.swift. Keep the original
// ExpoUI props, Children and UIBaseView modifier path. The intent itself belongs
// to HanlinScriptExtensions, injected to keep the package graph acyclic.
final class ButtonProps: HanlinExpoWidgetSubset.ButtonProps {
    @Field var target: String?
    var nativeButton: AnyView?
}

struct WidgetButtonView: ExpoSwiftUI.View {
    @ObservedObject var props: ButtonProps
    var body: some View {
        if let button = props.nativeButton { button }
        else { Text("Missing widget action") }
    }
}

struct WidgetButtonLabel: ExpoSwiftUI.View {
    @ObservedObject var props: ButtonProps
    var body: some View {
        if let label = props.label {
            if let systemImage = props.systemImage {
                Label(title: { Text(label) }, icon: { Image(systemName: systemImage) })
            } else { Text(label) }
        } else { Children() }
    }
}

@MainActor
public enum HanlinExpoWidgetNative {
    public static func render(
        node: [String: Any],
        resources: [String: URL] = [:],
        buttonBuilder: @escaping (String, SwiftUI.ButtonRole?, AnyView) -> AnyView
    ) -> any ExpoSwiftUI.AnyChild {
        WidgetsViewRenderer(name: "Hanlin", buttonBuilder: buttonBuilder, node: node, context: AppContext(resources: resources)).render()
    }
}
