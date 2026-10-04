import ExpoUI

public enum HanlinExpoModifierRegistry {
    @MainActor
    public static func registerCustomModifiers() {
        HanlinExpoSession.ensureAppDefinesLoaded()
        HanlinGeneratedModifierRegistry.register()
    }

    public static func unregisterCustomModifiers() {
        HanlinGeneratedModifierRegistry.unregister()
    }
}
