//
//  HanlinCompactRecentChats.swift
//  AI_HLY
//
//  Source-faithful "Recent Conversations" section for the compact Home screen,
//  ported from InteriorOrganizerV3_3.swiftpm/AppModule/ContentView.swift (lines 469-578).
//  Displays the 3 most recently edited persisted ChatRecords (by `lastEdited` descending)
//  and hosts the `View All` matchedTransitionSource(id: "all-conversations", in: libraryZoom).
//

import SwiftUI
import SwiftData

@MainActor
struct HanlinCompactRecentChats: View {
    let chatRecords: [ChatRecords]
    let temporaryChatIDs: Set<UUID>
    let libraryZoom: Namespace.ID
    let onSelectConversation: (ChatRecords) -> Void
    let onOpenLibrary: () -> Void
    let onTogglePin: (ChatRecords) -> Void
    let onEditRecord: (ChatRecords) -> Void
    let onDeleteRecord: (ChatRecords) -> Void

    /// Returns up to 3 genuinely recent persisted chat records sorted strictly by `lastEdited` descending (§4.5 & §7A.3).
    /// Excludes non-chat records and temporary/unsaved records.
    static func recentConversations(
        from records: [ChatRecords],
        temporaryChatIDs: Set<UUID> = []
    ) -> [ChatRecords] {
        let validChats = records.filter { record in
            guard let id = record.id else { return false }
            guard !temporaryChatIDs.contains(id) else { return false }
            let kind = (record.type ?? "chat").lowercased()
            return kind == "chat"
        }
        let sortedByRecency = validChats.sorted { lhs, rhs in
            if lhs.lastEdited != rhs.lastEdited {
                return lhs.lastEdited > rhs.lastEdited
            }
            return (lhs.id?.uuidString ?? "") < (rhs.id?.uuidString ?? "")
        }
        return Array(sortedByRecency.prefix(3))
    }

    private var recentItems: [ChatRecords] {
        Self.recentConversations(from: chatRecords, temporaryChatIDs: temporaryChatIDs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            recentHeader
            recentRowsList
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hanlin-compact-recent-section")
    }

    // MARK: - Recent Header + View All Zoom Source (ContentView.swift lines 479-495)

    private var recentHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(String(localized: "Recent Conversations"))
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("hanlin-compact-recent-header")

            Spacer()

            Button(action: onOpenLibrary) {
                HStack(spacing: 4) {
                    Text(String(localized: "View All"))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.hlBluefont)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .matchedTransitionSource(id: "all-conversations", in: libraryZoom)
            .accessibilityIdentifier("hanlin-compact-view-all-button")
        }
    }

    // MARK: - 3 Recent Rows (ContentView.swift lines 496-513)

    @ViewBuilder
    private var recentRowsList: some View {
        if recentItems.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.subheadline)
                    .foregroundStyle(Color.hlBluefont)
                Text(String(localized: "No recent conversations yet. Type a message below to start."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("hanlin-compact-recent-empty")
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(recentItems.enumerated()), id: \.element.id) { index, record in
                    Button {
                        onSelectConversation(record)
                    } label: {
                        HanlinRecentConversationRow(record: record)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("hanlin-compact-recent-row-\(index)")
                    .contextMenu {
                        Button {
                            onEditRecord(record)
                        } label: {
                            Label("编辑图标", systemImage: "paintbrush")
                        }

                        Button {
                            onTogglePin(record)
                        } label: {
                            Label(
                                record.isPinned ? "取消置顶" : "置顶消息",
                                systemImage: record.isPinned ? "pin.slash" : "pin"
                            )
                        }

                        Button(role: .destructive) {
                            onDeleteRecord(record)
                        } label: {
                            Label("删除消息", systemImage: "trash")
                        }
                    }

                    if index < recentItems.count - 1 {
                        Rectangle()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 0.6)
                    }
                }
            }
        }
    }
}

// MARK: - Single-Line Fading Row (ContentView.swift lines 543-578)

struct HanlinRecentConversationRow: View {
    let record: ChatRecords

    private var titleText: String {
        let raw = (record.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? String(localized: "Untitled Chat") : raw
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: record.icon ?? "bubble.left.circle.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.from(name: record.color ?? ".hlBlue"))
                .frame(width: 24, height: 24)

            Text(titleText)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.82),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            if record.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.hlBluefont.opacity(0.75))
            }
        }
        .frame(height: 54)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(titleText)
        .accessibilityIdentifier("hanlin-chat-row-\(record.name ?? "")")
    }
}
