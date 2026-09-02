import Foundation
import HanlinNativeScriptRuntime

/// Keeps Hanlin's pre-embedded NativeScript providers reachable from the
/// production app binary without starting a NativeScript session.
enum HanlinNativeScriptProductionBootstrap {
    @MainActor
    private static var embeddedSwiftUIProvider: HanlinNativeScriptSwiftUIFixtureProvider?

    @MainActor
    static func prepareEmbeddedProviders() {
        if embeddedSwiftUIProvider == nil {
            embeddedSwiftUIProvider = HanlinNativeScriptSwiftUIFixtureProvider()
        }

        guard let provider = embeddedSwiftUIProvider else {
            return
        }

        let providerClass: AnyClass = type(of: provider)
        if NSClassFromString("HanlinNativeScriptSwiftUIFixtureProvider") !== providerClass {
            print("HANLIN_NS_SWIFTUI_PROVIDER_LINK_MISMATCH")
        }
    }
}
