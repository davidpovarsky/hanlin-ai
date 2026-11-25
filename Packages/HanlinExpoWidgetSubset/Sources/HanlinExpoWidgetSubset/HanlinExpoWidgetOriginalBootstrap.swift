// Generated from the original widget registration layout.
@MainActor
public enum HanlinExpoWidgetOriginalBootstrap {
    private static var installed = false
    public static func install() {
        guard !installed else { return }
        installed = true
        _ = ViewModifierRegistry.shared
        registerWidgetModifiers()
    }
}
