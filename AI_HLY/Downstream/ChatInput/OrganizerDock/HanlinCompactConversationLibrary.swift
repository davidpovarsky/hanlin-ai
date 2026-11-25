import HanlinLocalization
//
//  HanlinCompactConversationLibrary.swift
//  AI_HLY
//
//  Searchable full conversation library destination for the compact workspace,
//  ported from InteriorOrganizerV3_3.swiftpm/AppModule/ContentView.swift (lines 1382-1467).
//  Reuses Hanlin's existing ListView.filterAndSortChatRecords, ChatRowView, and
//  pin/edit/delete actions while preserving `.toolbarVisibility(.visible, for: .navigationBar)`
//  across native matched zoom transitions and cancelled interactive back gestures.
//

import SwiftUI
import SwiftData

@MainActor
struct HanlinCompactConversationLibrary: View {
    @State private var showsSavedMessages = false
    @FocusState private var searchFocused: Bool
    @State private var searchPresented = false
    let chatRecords: [ChatRecords]
    @Binding var searchText: String
    let matchedSnippets: [UUID: (AttributedString, UUID)]
    let forceRefresh: Bool
    let onSelectConversation: (ChatRecords, UUID?) -> Void
    let onAddNewChat: () -> Void
    let onTogglePin: (ChatRecords) -> Void
    let onEditRecord: (ChatRecords) -> Void
    let onDeleteRecord: (ChatRecords) -> Void
    let onRefresh: () -> Void
    var isPresented: Bool = true
    var keyboardOwner: HanlinCompactKeyboardOwner? = nil

    private var filteredRecords: [ChatRecords] {
        ListView.filterAndSortChatRecords(chatRecords, searchText: searchText)
    }

    var body: some View {
        List {
            if filteredRecords.isEmpty {
                ContentUnavailableView(
                    searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? String(localized: "No Conversations", bundle: HanlinLocalization.bundle)
                        : String(localized: "No Matching Conversations", bundle: HanlinLocalization.bundle),
                    systemImage: "magnifyingglass",
                    description: Text(
                        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? String(localized: "Start a new chat from the home screen.", bundle: HanlinLocalization.bundle)
                            : String(localized: "Try a different keyword.", bundle: HanlinLocalization.bundle)
                    )
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .padding(.top, 28)
            } else {
                Section {
                    ForEach(filteredRecords, id: \.id) { record in
                        libraryRow(for: record)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(String(localized: "All Conversations", bundle: HanlinLocalization.bundle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.visible, for: .navigationBar)
        .searchable(
            text: $searchText,
            isPresented: $searchPresented,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text("搜索聊天与消息内容", bundle: HanlinLocalization.bundle)
        )
        .searchFocused($searchFocused)
        .onChange(of: isPresented) { _, presented in
            if !presented { endSearch() }
        }
        .onDisappear(perform: endSearch)
        .background {
            if let keyboardOwner {
                HanlinCompactSearchFocusRegistration(
                    owner: keyboardOwner, isFocused: searchFocused && isPresented)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .refreshable {
            onRefresh()
        }
        .toolbar {
            if isPresented {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsSavedMessages = true } label: {
                        Label(hanlin: "Saved messages", systemImage: "bookmark")
                    }
                    .accessibilityIdentifier("hanlin-saved-messages-open")
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        endSearch()
                        onAddNewChat()
                    } label: {
                        Label(hanlin: "New chat", systemImage: "plus.bubble")
                    }
                    .accessibilityIdentifier("hanlin-new-chat-button")
                }
            }
        }
        .sheet(isPresented: $showsSavedMessages) { ChatSavedExcerptsView() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hanlin-compact-conversation-library")
        .accessibilityHidden(true, isEnabled: !isPresented)
    }

    private func endSearch() {
        // Focus and search presentation are distinct native states. End both
        // before routing away from this retained searchable navigation stack.
        searchFocused = false
        searchPresented = false
    }

    @ViewBuilder
    private func libraryRow(for record: ChatRecords) -> some View {
        let snippetPair = matchedSnippets[record.id ?? UUID()]
        let snippet = snippetPair?.0
        let messageID = snippetPair?.1

        Button {
            #if DEBUG || HANLIN_TESTING
            keyboardOwner?.traceNavigation("row-before-end-search", requestedHistory: isPresented)
            #endif
            endSearch()
            onSelectConversation(record, messageID)
        } label: {
            ChatRowView(
                record: record,
                searchText: searchText,
                matchedSnippet: snippet
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onEditRecord(record)
            } label: {
                Label(hanlin: "编辑图标", systemImage: "paintbrush")
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
                Label(hanlin: "删除消息", systemImage: "trash")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 5)
        .listRowInsets(EdgeInsets())
        .listRowBackground(pinnedBackground(for: record))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDeleteRecord(record)
            } label: {
                Label(hanlin: "删除消息", systemImage: "trash")
            }
            .tint(Color(.hanlinHLRed))
            .accessibilityIdentifier("hanlin-history-delete-action")
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                onTogglePin(record)
            } label: {
                Label(
                    record.isPinned ? "取消置顶" : "置顶消息",
                    systemImage: record.isPinned ? "pin.slash" : "pin"
                )
            }
            .tint(Color(.hanlinHLBlue))

            Button {
                onEditRecord(record)
            } label: {
                Label(hanlin: "编辑图标", systemImage: "paintbrush")
            }
            .tint(.hanlinHLGreen)
        }
        .id((record.id?.uuidString ?? "") + String(forceRefresh))
        .accessibilityIdentifier("hanlin-chat-row-\(record.name ?? "")")
    }

    @ViewBuilder
    private func pinnedBackground(for record: ChatRecords) -> some View {
        if record.isPinned {
            BlurView(style: .systemUltraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: Color.from(name: record.color ?? "hlBlue"), radius: 1)
                .padding(3)
        } else {
            Color.clear
        }
    }
}
