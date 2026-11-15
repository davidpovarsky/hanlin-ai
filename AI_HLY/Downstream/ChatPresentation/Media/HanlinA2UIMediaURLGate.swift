#if HANLIN_A2UI_POC
import A2UICore
import A2UISwiftUI
import SwiftUI

/// Preserve the original official component builder and model; reject invalid sources before
/// it constructs an AsyncImage or player. Removing a player runs upstream disappearance cleanup.
@MainActor
struct HanlinA2UIMediaURLGate: View {
    let node: Node
    let isPlayer: Bool
    let builder: ComponentViewBuilder
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        if permitted, !isPlayer || isEnabled {
            builder(node)
        } else {
            ContentUnavailableView("Media unavailable", systemImage: "rectangle.slash",
                description: Text("This media source could not be displayed."))
        }
    }

    private var permitted: Bool {
        guard let value = node.string(for: "url"), HanlinRemoteMediaURL(value) != nil else { return false }
        if let poster = node.string(for: "posterUrl"), !poster.isEmpty {
            return HanlinRemoteMediaURL(poster) != nil
        }
        return true
    }
}
#endif
