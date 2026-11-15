#if HANLIN_A2UI_POC
import SwiftUI

/// Captured outside the history-only Surface disable. nil leaves ordinary inherited
/// enablement intact. This value grants no Session, binding, form or RPC authority.
extension EnvironmentValues {
    @Entry var hanlinA2UIHistoryMediaEnabled: Bool? = nil
}

/// Only existing catalog media builders use this boundary. Form controls retain the
/// Surface's disabled environment; a host-disabled or closed history never overrides it.
@MainActor
struct HanlinA2UILocalMedia<Content: View>: View {
    @Environment(\.hanlinA2UIHistoryMediaEnabled) private var historyHostEnabled
    @Environment(\.isEnabled) private var inheritedEnabled
    @Environment(\.scenePhase) private var scenePhase
    private let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content.environment(\.isEnabled,
            (historyHostEnabled ?? inheritedEnabled) && scenePhase == .active)
    }
}
#endif
