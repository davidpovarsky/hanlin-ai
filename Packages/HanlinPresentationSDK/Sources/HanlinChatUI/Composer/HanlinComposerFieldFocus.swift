import SwiftUI

/// Reports focus from text inputs inside the existing composer panel. Hosts can
/// include these controls in their existing keyboard owner without installing a
/// second keyboard observer or inspecting a private native view hierarchy.
public struct HanlinComposerFieldFocusPreferenceKey: PreferenceKey {
    public static let defaultValue = false

    public static func reduce(value: inout Bool, nextValue: () -> Bool) {
        let next = nextValue()
        value = value || next
    }
}

extension View {
    /// Custom capability panels can publish their native input's FocusState
    /// through the same route used by the shared search and configuration fields.
    public func hanlinComposerFieldFocus(_ isFocused: Bool) -> some View {
        preference(key: HanlinComposerFieldFocusPreferenceKey.self, value: isFocused)
    }
}
