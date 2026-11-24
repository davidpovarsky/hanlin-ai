import ExpoUI

@MainActor
public enum HanlinExpoModifierRegistry {
    private static let ownership = HanlinExpoModifierOwnership()
    private static let legacyOwner = "hanlin.expo.modifiers.legacy"

    public static func registerCustomModifiers(sessionID: String) {
        guard ownership.acquire(sessionID: sessionID) else { return }
        HanlinExpoSession.ensureAppDefinesLoaded()
        HanlinGeneratedModifierRegistry.register()
    }

    public static func unregisterCustomModifiers(sessionID: String) {
        guard ownership.release(sessionID: sessionID) else { return }
        HanlinGeneratedModifierRegistry.unregister()
    }

    // Preserve callers outside the scene lifecycle without letting them release
    // modifier registration owned by any live Expo session.
    public static func registerCustomModifiers() {
        registerCustomModifiers(sessionID: legacyOwner)
    }

    public static func unregisterCustomModifiers() {
        unregisterCustomModifiers(sessionID: legacyOwner)
    }
}
