import Foundation
import HanlinNativeScriptRuntime

/// Keeps Hanlin's pre-embedded NativeScript providers reachable from the
/// production app binary without starting a NativeScript session.
enum HanlinNativeScriptProductionBootstrap {
    @MainActor
    static func prepareEmbeddedProviders() {
        let providerClass: AnyClass = HanlinNativeScriptSwiftUIFixtureProvider.self
        if NSClassFromString("HanlinNativeScriptSwiftUIFixtureProvider") !== providerClass {
            print("HANLIN_NS_SWIFTUI_PROVIDER_LINK_MISMATCH")
        }
    }
}
