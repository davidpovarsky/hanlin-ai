import SwiftData
import SwiftUI

/// A transient navigation request; the original SwiftData record remains the owner.
struct HanlinConversationSelection: Identifiable {
    let id = UUID()
    let conversationID: UUID
    var source: ChatSourceDestination?
    var messageID: UUID?
}

struct HanlinWorkspaceActions: ToolbarContent {
    let onOpenProfile: () -> Void
    let onOpenMiniApps: () -> Void
    let onOpenVision: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button(action: onOpenMiniApps) {
                    Label("Open MiniApps", systemImage: "square.grid.2x2")
                }
                .accessibilityIdentifier("hanlin-open-miniapps")
                Button(action: onOpenVision) {
                    Label(String(localized: "视觉"), systemImage: "eye")
                }
                .accessibilityIdentifier("hanlin-vision-tab")
            } label: {
                Label("More", systemImage: "ellipsis")
            }
            .accessibilityIdentifier("hanlin-workspace-actions")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: onOpenProfile) {
                Label("Profile", systemImage: "person.crop.circle")
            }
            .accessibilityIdentifier("hanlin-settings-tab")
        }
    }
}

struct HanlinPersonalLibraryView: View {
    let onOpenProfile: () -> Void
    let onOpenMiniApps: () -> Void
    let onOpenVision: () -> Void
    let onOpenConversation: (HanlinConversationSelection) -> Void
    @State private var sheet: LibrarySheet?

    private enum LibrarySheet: String, Identifiable {
        case knowledge, saved
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Personal library") {
                    Button { sheet = .knowledge } label: {
                        Label("Knowledge", systemImage: "books.vertical")
                    }
                    .accessibilityIdentifier("hanlin-library-knowledge")
                    NavigationLink { MemoryArchiveView() } label: {
                        Label("Memory", systemImage: "archivebox")
                    }
                    .accessibilityIdentifier("hanlin-library-memory")
                    NavigationLink { PromptRepoView() } label: {
                        Label("Prompts", systemImage: "text.bubble")
                    }
                    .accessibilityIdentifier("hanlin-library-prompts")
                    NavigationLink {
                        HanlinCanvasLibraryView(onOpenConversation: onOpenConversation)
                    } label: {
                        Label("Canvas", systemImage: "doc.richtext")
                    }
                    .accessibilityIdentifier("hanlin-library-canvas")
                    Button { sheet = .saved } label: {
                        Label("Saved messages", systemImage: "bookmark")
                    }
                    .accessibilityIdentifier("hanlin-library-saved")
                }
            }
            .navigationTitle("Library")
            .accessibilityIdentifier("hanlin-personal-library")
            .toolbar {
                HanlinWorkspaceActions(onOpenProfile: onOpenProfile,
                    onOpenMiniApps: onOpenMiniApps, onOpenVision: onOpenVision)
            }
        }
        .sheet(item: $sheet) { destination in
            switch destination {
            case .knowledge:
                KnowledgeListView(isPresentedInSheet: true)
            case .saved:
                ChatSavedExcerptsView()
                    .environment(\.chatOpenSavedSource, { record, source in
                        guard let id = record.id else { return }
                        onOpenConversation(.init(conversationID: id, source: source, messageID: source.messageID))
                    })
            }
        }
    }
}

private struct HanlinCanvasLibraryView: View {
    @Query(sort: \ChatRecords.lastEdited, order: .reverse) private var conversations: [ChatRecords]
    let onOpenConversation: (HanlinConversationSelection) -> Void
    @State private var query = ""

    private var records: [ChatRecords] {
        conversations.filter { record in
            guard record.id != nil, let canvas = record.canvas, !canvas.content.isEmpty else { return false }
            return query.isEmpty || canvas.title.localizedStandardContains(query)
                || canvas.content.localizedStandardContains(query)
                || (record.name ?? "").localizedStandardContains(query)
        }
    }

    var body: some View {
        List(records, id: \.id) { record in
            Button {
                guard let id = record.id else { return }
                let message = record.messages?.filter { $0.showCanvas == true }
                    .max(by: { $0.timestamp < $1.timestamp })
                onOpenConversation(.init(conversationID: id, messageID: message?.id))
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text((record.canvas?.title.isEmpty == false ? record.canvas?.title : nil) ?? String(localized: "Canvas"))
                    Text(record.name ?? String(localized: "Chat"))
                        .font(HanlinTypography.caption).foregroundStyle(.secondary)
                    Text("Open in conversation").font(HanlinTypography.caption2).foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("hanlin-library-canvas-\(record.id?.uuidString ?? "unavailable")")
        }
        .navigationTitle("Canvas")
        .accessibilityIdentifier("hanlin-canvas-library")
        .searchable(text: $query)
        .overlay {
            if records.isEmpty {
                ContentUnavailableView("No canvases", systemImage: "doc.richtext",
                    description: Text("Canvases remain in their original conversations."))
            }
        }
    }
}
