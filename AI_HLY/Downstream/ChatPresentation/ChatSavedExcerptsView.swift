import SwiftData
import SwiftUI

struct ChatSavedExcerptsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ChatSavedExcerpt.createdAt, order: .reverse) private var excerpts: [ChatSavedExcerpt]
    @Query private var chats: [ChatRecords]
    @State private var query = ""
    @State private var error: String?

    private var filtered: [ChatSavedExcerpt] {
        excerpts.filter { query.isEmpty || $0.quote.localizedStandardContains(query) || $0.sourceTitle.localizedStandardContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { excerpt in
                    NavigationLink {
                        savedDetail(excerpt)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(excerpt.quote).lineLimit(4)
                            Text(excerpt.sourceTitle).font(.caption).foregroundStyle(.secondary)
                            Text(excerpt.createdAt, style: .date).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .contextMenu {
                        Button { UIPasteboard.general.string = excerpt.quote } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        Button(role: .destructive) { delete(excerpt) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions { Button("Delete", role: .destructive) { delete(excerpt) } }
                }
            }
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView(query.isEmpty ? "No saved messages" : "No results", systemImage: "bookmark")
                }
            }
            .navigationTitle("Saved messages")
            .searchable(text: $query)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert("Could not update saved messages", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private func delete(_ excerpt: ChatSavedExcerpt) {
        context.delete(excerpt)
        do { try context.save() } catch { self.error = error.localizedDescription }
    }

    @ViewBuilder
    private func savedDetail(_ excerpt: ChatSavedExcerpt) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ChatMarkdownView(text: excerpt.quote)
                if let chat = chats.first(where: { $0.id == excerpt.chatRecordID }),
                   let messageID = excerpt.messageID,
                   chat.messages?.contains(where: { $0.id == messageID }) == true {
                    NavigationLink {
                        ChatView(chatRecord: chat, matchedMessageID: messageID)
                            .environment(\.chatHighlightedQuote, excerpt.quote)
                    } label: {
                        Label("Open in conversation", systemImage: "bubble.left.and.text.bubble.right")
                    }
                } else {
                    Label("The original message is no longer available. Your saved text is kept.", systemImage: "bubble.left.and.exclamationmark.bubble.right")
                        .foregroundStyle(.secondary)
                }
            }.padding()
        }
        .navigationTitle(excerpt.sourceTitle)
        .toolbar { ShareLink(item: excerpt.quote) }
    }
}
