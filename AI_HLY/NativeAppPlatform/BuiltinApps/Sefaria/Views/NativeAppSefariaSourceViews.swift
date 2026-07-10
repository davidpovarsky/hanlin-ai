import SwiftUI
import UIKit

struct NativeAppSefariaSourceLoaderView: View {
    let ref: String
    let sourceService: NativeAppSefariaSourceService
    @ObservedObject var store: NativeAppSefariaStore

    @State private var source: NativeAppSefariaSource?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let source {
                NativeAppSefariaSourceDetailView(source: source, store: store)
            } else if let errorMessage {
                ContentUnavailableView(
                    "Unable to Load Source",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else {
                ProgressView("Loading \(ref)…")
            }
        }
        .navigationTitle(ref)
        .task {
            do { source = try await sourceService.source(ref: ref) }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

struct NativeAppSefariaSourceDetailView: View {
    let source: NativeAppSefariaSource
    @ObservedObject var store: NativeAppSefariaStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                NativeAppSefariaSourceCard(
                    source: source,
                    language: store.preferredLanguage,
                    mode: .fullApp
                )

                HStack {
                    Button {
                        store.toggleSaved(source)
                    } label: {
                        Label(
                            store.isSaved(source) ? "Remove Bookmark" : "Bookmark",
                            systemImage: store.isSaved(source) ? "bookmark.fill" : "bookmark"
                        )
                    }

                    Button {
                        UIPasteboard.general.string = source.combinedText
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }

                    ShareLink(item: source.combinedText) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
                .buttonStyle(.bordered)

                if let url = source.url {
                    Link(destination: url) {
                        Label("Open on Sefaria.org", systemImage: "safari")
                    }
                }
            }
            .padding()
        }
        .navigationTitle(source.ref)
        .navigationBarTitleDisplayMode(.inline)
    }
}
