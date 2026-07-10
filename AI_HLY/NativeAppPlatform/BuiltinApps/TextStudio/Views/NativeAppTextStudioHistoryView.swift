import SwiftUI

struct NativeAppTextStudioHistoryView: View {
    @ObservedObject var store: NativeAppTextStudioStore

    var body: some View {
        List {
            if store.history.isEmpty {
                ContentUnavailableView(
                    "No History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Analyses and transformations will appear here.")
                )
            } else {
                ForEach(store.history) { item in
                    NavigationLink {
                        NativeAppTextStudioHistoryDetailView(item: item)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.operation).font(.headline)
                            Text(item.createdAt, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(item.output).font(.caption).lineLimit(2)
                        }
                    }
                }
                .onDelete(perform: store.removeHistory)
            }
        }
        .navigationTitle("History")
        .toolbar {
            if !store.history.isEmpty {
                Button("Clear", role: .destructive) { store.clearHistory() }
            }
        }
    }
}

private struct NativeAppTextStudioHistoryDetailView: View {
    let item: NativeAppTextStudioHistoryItem

    var body: some View {
        List {
            Section("Operation") {
                LabeledContent("Name", value: item.operation)
                LabeledContent("Date") { Text(item.createdAt, style: .date) }
            }
            Section("Input") {
                Text(item.input).textSelection(.enabled)
            }
            Section("Output") {
                Text(item.output).textSelection(.enabled)
            }
        }
        .navigationTitle(item.operation)
    }
}
