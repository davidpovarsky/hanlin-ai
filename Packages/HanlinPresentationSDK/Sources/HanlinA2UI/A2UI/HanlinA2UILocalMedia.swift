#if canImport(SwiftUI)
import SwiftUI

/// Captured outside the history-only Surface disable. nil leaves ordinary inherited
/// enablement intact. This value grants no Session, binding, form or RPC authority.
public extension EnvironmentValues {
    @Entry var hanlinA2UIHistoryMediaEnabled: Bool? = nil
}

/// Only existing catalog media builders use this boundary. Form controls retain the
/// Surface's disabled environment; a host-disabled or closed history never overrides it.
@MainActor
public struct HanlinA2UILocalMedia<Content: View>: View {
    @Environment(\.hanlinA2UIHistoryMediaEnabled) private var historyHostEnabled
    @Environment(\.isEnabled) private var inheritedEnabled
    @Environment(\.scenePhase) private var scenePhase
    private let content: Content

    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        content.environment(\.isEnabled,
            (historyHostEnabled ?? inheritedEnabled) && scenePhase == .active)
    }
}
#endif
