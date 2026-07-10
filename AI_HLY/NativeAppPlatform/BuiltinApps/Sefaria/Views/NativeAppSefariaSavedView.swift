import SwiftUI

struct NativeAppSefariaSavedView: View {
    let sourceService: NativeAppSefariaSourceService
    @ObservedObject var store: NativeAppSefariaStore

    var body: some View {
        List {
            if store.savedSources.isEmpty {
                ContentUnavailableView(
                    "No Saved Sources",
                    systemImage: "bookmark",
                    description: Text("Open a source and tap Bookmark.")
                )
            } else {
                ForEach(store.savedSources) { source in
                    NavigationLink {
                        NativeAppSefariaSourceDetailView(source: source, store: store)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.ref).font(.headline)
                            Text(source.combinedText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets.sorted(by: >) {
                        let source = store.savedSources[index]
                        store.toggleSaved(source)
                    }
                }
            }
        }
        .navigationTitle("Saved")
    }
}
