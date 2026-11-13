import HanlinScriptStore
import QuickLook
import SwiftUI

struct ChavrusaShareInboxView: View {
    @State private var batches: [HanlinShareBatch] = []
    @State private var legacyItems: [ChavrusaSharedItem] = []
    @State private var hasUnreadableItems = false
    @State private var loadFailed = false
    @State private var previewFile: URL?

    var body: some View {
        List {
            Section {
                Text("These items are saved on this device. No MiniApp action has run.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if loadFailed || hasUnreadableItems {
                Section {
                    Label("Some shared items couldn’t be read. Their original files were kept.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            ForEach(batches) { batch in
                Section {
                    ForEach(batch.items) { item in
                        switch item.content {
                        case .text, .url:
                            Text(item.text ?? "").textSelection(.enabled)
                        case .file:
                            Button {
                                Task {
                                    do { previewFile = try await ChavrusaShareInbox.shared.ownedFile(batchID: batch.id, itemID: item.id) }
                                    catch { loadFailed = true }
                                }
                            } label: {
                                Label(item.name ?? String(localized: "Shared file"), systemImage: "doc")
                            }
                            .accessibilityIdentifier("hanlin-share-file-\(item.id.uuidString.lowercased())")
                        case .rejected:
                            Label("This item could not be loaded from the source app.", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: { Text(batch.createdAt, style: .date) }
            }
            if !legacyItems.isEmpty {
                Section("Earlier Shared Items") {
                    ForEach(legacyItems) { item in
                        if let text = item.text { Text(text).textSelection(.enabled) }
                        else if let url = item.url, !url.isFileURL { Text(url.absoluteString).textSelection(.enabled) }
                        else { Text("An earlier file link may no longer be available. The original record was kept.") }
                    }
                }
            }
        }
        .navigationTitle("Shared Items")
        .accessibilityIdentifier("hanlin-share-inbox")
        .task { await reload() }
        .refreshable { await reload() }
        .quickLookPreview($previewFile)
    }

    private func reload() async {
        do {
            let scan = try await ChavrusaShareInbox.shared.pendingBatches()
            batches = scan.batches
            hasUnreadableItems = !scan.rejected.isEmpty
            legacyItems = try await ChavrusaShareInbox.shared.pendingItems()
            loadFailed = false
        } catch { loadFailed = true }
    }
}
