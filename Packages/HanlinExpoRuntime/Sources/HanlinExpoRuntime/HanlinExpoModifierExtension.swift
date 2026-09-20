import ExpoModulesCore
import ExpoUI
import SwiftUI

public struct HanlinNavigationBarTitleDisplayModeModifier: ViewModifier {
    public let displayMode: NavigationBarItem.TitleDisplayMode

    public init(displayMode: NavigationBarItem.TitleDisplayMode) {
        self.displayMode = displayMode
    }

    public func body(content: Content) -> some View {
        content.navigationBarTitleDisplayMode(displayMode)
    }
}

public enum HanlinExpoModifierRegistry {
    @MainActor
    public static func registerCustomModifiers() {
        HanlinExpoSession.ensureAppDefinesLoaded()
        ViewModifierRegistry.register("navigationBarTitleDisplayMode") { params, _, _ in
            let modeString = params["displayMode"] as? String ?? "inline"
            let mode: NavigationBarItem.TitleDisplayMode = switch modeString {
            case "large": .large
            case "automatic": .automatic
            default: .inline
            }
            return HanlinNavigationBarTitleDisplayModeModifier(displayMode: mode)
        }
    }

    public static func unregisterCustomModifiers() {
        ViewModifierRegistry.unregister("navigationBarTitleDisplayMode")
    }
}
