import HanlinLocalization
#if canImport(SwiftUI)
import A2UICore
import A2UISwiftUI
import BasicCatalogSwiftUI
import SwiftUI

/// The same official renderer is shared by inline, expanded and historical presentation.
@MainActor
public struct HanlinA2UIResultView: View {
    public let session: HanlinA2UISession

    public init(session: HanlinA2UISession) { self.session = session }
    @Environment(\.isEnabled) private var hostEnabled

    public var body: some View {
        Group {
            if session.unroutedFailure != nil {
                fallback
            }
            ForEach(session.surfaceIDs, id: \.self) { id in
                if session.failures[id] != nil {
                    fallback
                } else if let surface = session.surface(id) {
                    HanlinA2UISurfaceView(model: surface)
                        .environment(\.hanlinA2UIHistoryMediaEnabled,
                            session.allowsLocalHistoryMedia ? hostEnabled : nil)
                }
            }
        }
        .disabled(session.isInputSealed || session.isClosed)
        // Layout direction, locale, Dynamic Type and accessibility remain the host's environment.
        // No forced RTL, custom geometry, fixed heights, nested scrolling or automatic expansion.
    }

    private var fallback: some View {
        ContentUnavailableView(
            hanlin: "Content unavailable",
            systemImage: "rectangle.slash",
            description: Text("This content could not be displayed.", bundle: HanlinLocalization.bundle)
        )
        .accessibilityIdentifier("hanlin-a2ui-fallback")
    }
}

@MainActor
private struct HanlinA2UISurfaceView: View {
    @ObservedObject var model: SurfaceViewModel
    @Environment(\.locale) private var locale

    var body: some View {
        #if os(iOS)
        Surface(viewModel: model, catalogs: [
            HanlinMediaCatalogImplementation.basicCatalog(locale: locale),
            HanlinMediaCatalogImplementation.makeCatalog(locale: locale)
        ])
        #else
        Surface(
            viewModel: model,
            catalog: BasicCatalogImplementation.makeCatalog(version: .v10, locale: locale)
        )
        #endif
    }
}
#endif
