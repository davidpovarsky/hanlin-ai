import SwiftUI

struct NativeAppTextStudioRootView: View {
    private enum Tab: Hashable { case editor, analyze, transform, history }

    let service: NativeAppTextStudioService
    let context: NativeAppContext

    @StateObject private var store: NativeAppTextStudioStore
    @State private var selectedTab: Tab = .editor
    @State private var initialTransform: NativeAppTextStudioTransform?
    @State private var didApplyInitialRoute = false

    init(service: NativeAppTextStudioService, context: NativeAppContext) {
        self.service = service
        self.context = context
        _store = StateObject(wrappedValue: NativeAppTextStudioStore(storage: context.platform.storage))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NativeAppTextStudioEditorView(store: store, platform: context.platform)
                .tabItem { Label("Editor", systemImage: "square.and.pencil") }
                .tag(Tab.editor)

            NativeAppTextStudioAnalysisView(service: service, store: store)
                .tabItem { Label("Analyze", systemImage: "chart.bar.doc.horizontal") }
                .tag(Tab.analyze)

            NativeAppTextStudioTransformView(
                service: service,
                store: store,
                platform: context.platform,
                initialTransform: initialTransform
            )
                .tabItem { Label("Transform", systemImage: "wand.and.stars") }
                .tag(Tab.transform)

            NativeAppTextStudioHistoryView(store: store)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(Tab.history)
        }
        .navigationTitle("Text Studio")
        .navigationBarTitleDisplayMode(.inline)
        .task { applyInitialRouteIfNeeded() }
    }

    private func applyInitialRouteIfNeeded() {
        guard !didApplyInitialRoute else { return }
        didApplyInitialRoute = true
        guard let route = context.initialRoute, route.appID == NativeAppTextStudioIndex.id else { return }
        if let text = route.payload.string("text") { store.draft = text }
        switch route.screen {
        case "editor":
            selectedTab = .editor
        case "transform":
            initialTransform = route.payload.string("transform").flatMap(NativeAppTextStudioTransform.init(rawValue:))
            selectedTab = .transform
        default:
            break
        }
    }
}
