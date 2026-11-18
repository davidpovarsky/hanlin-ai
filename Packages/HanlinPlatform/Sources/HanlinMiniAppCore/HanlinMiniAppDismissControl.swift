#if canImport(SwiftUI)
import SwiftUI

private struct HanlinMiniAppShowsDismissControlKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// Enable only when the Host presents a compiled app without its own close control.
    var hanlinMiniAppShowsDismissControl: Bool {
        get { self[HanlinMiniAppShowsDismissControlKey.self] }
        set { self[HanlinMiniAppShowsDismissControlKey.self] = newValue }
    }
}

public extension View {
    /// Attach to the root content inside the provider's existing NavigationStack.
    /// A toolbar outside that stack does not reach its native navigation bar.
    @MainActor
    func hanlinMiniAppDismissControl() -> some View {
        modifier(HanlinMiniAppDismissControl())
    }
}

@MainActor
private struct HanlinMiniAppDismissControl: ViewModifier {
    @Environment(\.hanlinMiniAppShowsDismissControl) private var showsControl
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content.toolbar {
            if showsControl {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("hanlin-miniapps-app-close")
                }
            }
        }
    }
}
#endif
