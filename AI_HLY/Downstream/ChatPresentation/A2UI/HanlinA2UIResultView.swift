#if HANLIN_A2UI_POC
import A2UICore
import A2UISwiftUI
import BasicCatalogSwiftUI
import SwiftUI

/// An isolated native renderer, ready for a later integration proposal. No chat-shell wiring.
@MainActor
struct HanlinA2UIResultView: View {
    let session: HanlinA2UISession

    var body: some View {
        Group {
            if session.unroutedFailure != nil {
                fallback
            }
            ForEach(session.surfaceIDs, id: \.self) { id in
                if session.failures[id] != nil {
                    fallback
                } else if let surface = session.surface(id) {
                    HanlinA2UISurfaceView(model: surface)
                }
            }
        }
        // Layout direction, locale, Dynamic Type and accessibility remain the host's environment.
        // No forced RTL, custom geometry, fixed heights, nested scrolling or automatic expansion.
    }

    private var fallback: some View {
        ContentUnavailableView(
            "Content unavailable",
            systemImage: "rectangle.slash",
            description: Text("This content could not be displayed.")
        )
        .accessibilityIdentifier("hanlin-a2ui-fallback")
    }
}

@MainActor
private struct HanlinA2UISurfaceView: View {
    @ObservedObject var model: SurfaceViewModel
    @Environment(\.locale) private var locale

    var body: some View {
        Surface(
            viewModel: model,
            catalog: BasicCatalogImplementation.makeCatalog(version: .v10, locale: locale)
        )
    }
}
#endif
