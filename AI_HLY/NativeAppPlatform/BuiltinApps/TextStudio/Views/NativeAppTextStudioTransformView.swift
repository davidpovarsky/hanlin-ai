import SwiftUI

struct NativeAppTextStudioTransformView: View {
    let service: NativeAppTextStudioService
    @ObservedObject var store: NativeAppTextStudioStore
    let platform: NativeAppPlatformServices
    let initialTransform: NativeAppTextStudioTransform?

    @State private var transform: NativeAppTextStudioTransform
    @State private var output = ""

    init(
        service: NativeAppTextStudioService,
        store: NativeAppTextStudioStore,
        platform: NativeAppPlatformServices,
        initialTransform: NativeAppTextStudioTransform? = nil
    ) {
        self.service = service
        self.store = store
        self.platform = platform
        self.initialTransform = initialTransform
        _transform = State(initialValue: initialTransform ?? .trimWhitespace)
    }

    var body: some View {
        List {
            Section("Transformation") {
                Picker("Operation", selection: $transform) {
                    ForEach(NativeAppTextStudioTransform.allCases) { transform in
                        Text(transform.title).tag(transform)
                    }
                }

                Button {
                    runTransform()
                } label: {
                    Label("Run Transformation", systemImage: "wand.and.stars")
                }
                .disabled(store.draft.isEmpty)
            }

            Section("Before") {
                Text(store.draft.isEmpty ? "No text in the editor." : store.draft)
                    .foregroundStyle(store.draft.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
            }

            Section("After") {
                Text(output.isEmpty ? "Run a transformation to see the result." : output)
                    .foregroundStyle(output.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)

                if !output.isEmpty {
                    Button("Replace Draft with Result") {
                        store.draft = output
                    }
                    Button("Copy Result") {
                        platform.pasteboard.writeString(output)
                    }
                }
            }
        }
        .navigationTitle("Transform")
        .onChange(of: initialTransform, initial: true) { _, newValue in
            if let newValue { transform = newValue }
        }
    }

    private func runTransform() {
        output = service.transform(store.draft, using: transform)
        store.addHistory(operation: transform.title, input: store.draft, output: output)
    }
}
