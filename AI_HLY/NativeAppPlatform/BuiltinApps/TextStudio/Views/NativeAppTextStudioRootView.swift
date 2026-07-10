import SwiftUI

struct NativeAppTextStudioRootView: View {
    let service: NativeAppTextStudioService
    let context: NativeAppContext

    @StateObject private var store = NativeAppTextStudioStore()

    var body: some View {
        TabView {
            NativeAppTextStudioEditorView(store: store)
                .tabItem { Label("Editor", systemImage: "square.and.pencil") }

            NativeAppTextStudioAnalysisView(service: service, store: store)
                .tabItem { Label("Analyze", systemImage: "chart.bar.doc.horizontal") }

            NativeAppTextStudioTransformView(service: service, store: store)
                .tabItem { Label("Transform", systemImage: "wand.and.stars") }

            NativeAppTextStudioHistoryView(store: store)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
        }
        .navigationTitle("Text Studio")
        .navigationBarTitleDisplayMode(.inline)
    }
}
