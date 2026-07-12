import SwiftUI

struct NativeAppTextStudioEditorView: View {
    @ObservedObject var store: NativeAppTextStudioStore
    let platform: NativeAppPlatformServices

    private let sample = "Hanlin Native Apps share one Core between the full app and Assistant tools. Visit https://example.com or email hello@example.com to test extraction."

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $store.draft)
                .font(.body.monospaced())
                .padding(12)
                .background(Color(uiColor: .secondarySystemGroupedBackground))

            Divider()

            HStack {
                Button("Paste") {
                    store.draft = platform.pasteboard.readString() ?? store.draft
                }
                Button("Sample") {
                    store.draft = sample
                }
                Button("Clear", role: .destructive) {
                    store.draft = ""
                }
                Spacer()
                Text("\(store.draft.count) characters")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    platform.pasteboard.writeString(store.draft)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .disabled(store.draft.isEmpty)
            }
            .buttonStyle(.bordered)
            .padding()
        }
        .navigationTitle("Editor")
    }
}
