//
//  HanlinCompactChatWorkspace.swift
//  AI_HLY
//
//  Source-faithful compact workspace host ported from
//  InteriorOrganizerV3_3.swiftpm/AppModule/ContentView.swift (lines 293-405).
//  Owns ONE `ZStack(alignment: .bottom)`, ONE `NavigationStack(path: $path)` with
//  `@Namespace private var libraryZoom`, and ONE persistent anchored composer dock
//  shared across the compact Home screen (`composerKey == "new"`) and any pushed
//  chat destination (`.chat(UUID)`), while hiding the dock in `.allConversations`.
//

import SwiftUI
import SwiftData

enum HanlinCompactWorkspaceRoute: Hashable, Sendable {
    case allConversations
    case chat(UUID)
}

@MainActor
struct HanlinCompactChatWorkspace: View {
    let chatRecords: [ChatRecords]
    let allModels: [AllModels]
    @Binding var path: [HanlinCompactWorkspaceRoute]
    @Binding var searchText: String
    let matchedSnippets: [UUID: (AttributedString, UUID)]
    let loadHistoryMessages: Bool
    let forceRefresh: Bool

    let onOpenSafariGuide: () -> Void
    let onOpenTranslation: () -> Void
    let onOpenPolish: () -> Void
    let onOpenSummary: () -> Void
    let onCreateAuthorizedNewChat: () -> ChatRecords?
    let onTogglePin: (ChatRecords) -> Void
    let onEditRecord: (ChatRecords) -> Void
    let onDeleteRecord: (ChatRecords) -> Void
    let onRefresh: () -> Void
    @Bindable var sessionBridge: HanlinActiveComposerSessionBridge

    @Namespace private var libraryZoom
    @State private var dockHeight: CGFloat = 176
    @State private var matchedMessageIDByChat: [UUID: UUID] = [:]
    @FocusState private var isCompactComposerInputActive: Bool

    // Dummy bindings used only when the persistent dock is bound to the Home ("new") draft
    @State private var homeShowScrollToBottom: Bool = false
    @State private var homeNeedScrollToBottom: Bool = false
    @State private var homeIsMultiSelectMode: Bool = false
    @State private var homeSelectedMessageIDs: Set<UUID> = []
    @State private var homeChatTemps: [ChatMessages] = []
    @State private var homeIsResponding: Bool = false

    // MARK: - Responsive Width Threshold & Route Helpers (§1 R1, §4.5, §7A.4)

    /// Measured container width threshold below which iPad windows (Split View / Stage Manager)
    /// switch from the wide `NavigationSplitView` to the compact workspace.
    static let compactWidthThreshold: CGFloat = 640

    static func effectiveContainerWidth(
        measuredWidth: CGFloat,
        simulatedWidthEnvironment: String? = ProcessInfo.processInfo.environment["HANLIN_SIMULATE_CONTAINER_WIDTH"]
    ) -> CGFloat {
        if let raw = simulatedWidthEnvironment,
           let parsed = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
           parsed > 0 {
            return CGFloat(parsed)
        }
        return measuredWidth
    }

    static func shouldUseCompactWorkspace(
        isPhoneIdiom: Bool,
        horizontalSizeClass: UserInterfaceSizeClass?,
        availableWidth: CGFloat
    ) -> Bool {
        if isPhoneIdiom {
            return true
        }
        if availableWidth > 0 {
            return availableWidth < compactWidthThreshold
        }
        return horizontalSizeClass == .compact
    }

    static func isComposerVisible(for path: [HanlinCompactWorkspaceRoute]) -> Bool {
        path.last != .allConversations
    }

    static func activeComposerKey(for path: [HanlinCompactWorkspaceRoute]) -> String {
        if case .chat(let id) = path.last {
            return id.uuidString
        }
        return "new"
    }

    private var composerVisible: Bool {
        Self.isComposerVisible(for: path)
    }

    private var activeComposerKey: String {
        Self.activeComposerKey(for: path)
    }

    private var activeChatID: UUID? {
        if case .chat(let id) = path.last {
            return id
        }
        return nil
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                navigationRoot(availableHeight: proxy.size.height)

                if composerVisible {
                    anchoredComposer(availableSize: proxy.size)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.36, dampingFraction: 0.88), value: composerVisible)
            .onChange(of: path) { oldPath, newPath in
                isCompactComposerInputActive = false
                sessionBridge.expectedActiveSessionID = activeChatID
                let isHidden = !newPath.isEmpty
                NotificationCenter.default.post(name: .hideTabBar, object: isHidden)

                // If leaving a pending first-turn chat before handoff completed, cancel cleanly
                if let pendingTarget = sessionBridge.pendingFirstTurn?.targetChatID,
                   sessionBridge.pendingFirstTurn?.isPendingHandoff == true,
                   !newPath.contains(.chat(pendingTarget)) {
                    sessionBridge.cancelPendingFirstTurn(reason: "Navigated away from pending chat destination.")
                }
                _ = oldPath
            }
            .onAppear {
                sessionBridge.expectedActiveSessionID = activeChatID
                if let defaultIndex = HanlinDefaultChatPolicy.defaultModelIndex(in: allModels) {
                    sessionBridge.homeSelectedModelIndex = defaultIndex
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hanlin-compact-chat-workspace")
    }

    // MARK: - Navigation Root (ContentView.swift lines 349-380)

    private func navigationRoot(availableHeight: CGFloat) -> some View {
        NavigationStack(path: $path) {
            compactHomeScreen(availableHeight: availableHeight)
                .navigationTitle("Hylic.AI")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        if loadHistoryMessages {
                            HStack(spacing: 4) {
                                ProgressView().font(.caption)
                                Text("正在加载...").font(.caption)
                            }
                        } else {
                            Button(action: onOpenSafariGuide) {
                                Label {
                                    Text("软件指南")
                                        .font(.caption)
                                } icon: {
                                    Image(systemName: "text.rectangle.page")
                                }
                            }
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            if let created = onCreateAuthorizedNewChat(),
                               let id = created.id {
                                path.append(.chat(id))
                            }
                        } label: {
                            Image(systemName: "plus.bubble")
                        }
                        .accessibilityIdentifier("hanlin-new-chat-button")
                    }
                }
                .navigationDestination(for: HanlinCompactWorkspaceRoute.self) { route in
                    destinationView(for: route)
                }
        }
    }

    @ViewBuilder
    private func destinationView(for route: HanlinCompactWorkspaceRoute) -> some View {
        switch route {
        case .allConversations:
            HanlinCompactConversationLibrary(
                chatRecords: chatRecords,
                searchText: $searchText,
                matchedSnippets: matchedSnippets,
                forceRefresh: forceRefresh,
                onSelectConversation: { record, matchedMsgID in
                    guard let id = record.id else { return }
                    if let matchedMsgID {
                        matchedMessageIDByChat[id] = matchedMsgID
                    }
                    path = [.chat(id)]
                },
                onAddNewChat: {
                    if let created = onCreateAuthorizedNewChat(),
                       let id = created.id {
                        path = [.chat(id)]
                    }
                },
                onTogglePin: onTogglePin,
                onEditRecord: onEditRecord,
                onDeleteRecord: { record in
                    let deletedID = record.id
                    onDeleteRecord(record)
                    if let deletedID {
                        sessionBridge.clearCachedDraft(for: deletedID)
                    }
                },
                onRefresh: onRefresh
            )
            .navigationTransition(.zoom(sourceID: "all-conversations", in: libraryZoom))
            .toolbarVisibility(.visible, for: .navigationBar)

        case .chat(let id):
            if let record = chatRecords.first(where: { $0.id == id }) {
                ChatViewWrapper(
                    chatRecord: record,
                    matchedMessageID: matchedMessageIDByChat[id]
                )
                .environment(\.hanlinExternalCompactComposerHost, true)
                .environment(\.hanlinExternalDockHeight, dockHeight)
                .environment(\.hanlinComposerSessionBridge, sessionBridge)
                .id(id)
            } else {
                ContentUnavailableView(
                    String(localized: "Conversation Not Found"),
                    systemImage: "bubble.left.and.exclamationmark.bubble.right"
                )
            }
        }
    }

    // MARK: - Compact Home Screen (ContentView.swift lines 413-513)

    private func compactHomeScreen(availableHeight: CGFloat) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                quickUtilitiesSection

                welcomeHeroSection

                Spacer(minLength: 16)

                HanlinCompactRecentChats(
                    chatRecords: chatRecords,
                    temporaryChatIDs: sessionBridge.temporaryChatIDs,
                    libraryZoom: libraryZoom,
                    onSelectConversation: { record in
                        guard let id = record.id else { return }
                        path.append(.chat(id))
                    },
                    onOpenLibrary: {
                        path.append(.allConversations)
                    },
                    onTogglePin: onTogglePin,
                    onEditRecord: onEditRecord,
                    onDeleteRecord: { record in
                        let deletedID = record.id
                        onDeleteRecord(record)
                        if let deletedID {
                            sessionBridge.clearCachedDraft(for: deletedID)
                        }
                    }
                )
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, max(230, dockHeight + 28))
            .frame(maxWidth: .infinity, minHeight: max(320, availableHeight - 16), alignment: .bottomLeading)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            onRefresh()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hanlin-compact-home-screen")
    }

    private var quickUtilitiesSection: some View {
        HStack(spacing: 10) {
            Button(action: onOpenTranslation) {
                HStack(spacing: 6) {
                    Image("translate")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .foregroundStyle(Color.hlBluefont)
                    Text("即时翻译")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.hlBluefont)
                        .lineLimit(1)
                }
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(Color.hlBluefont.opacity(0.16), in: Capsule())
            }
            .buttonStyle(.plain)

            Button(action: onOpenPolish) {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.sparkles.inverse")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(Color.hlGreen)
                    Text("即时润色")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.hlGreen)
                        .lineLimit(1)
                }
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(Color.hlGreen.opacity(0.16), in: Capsule())
            }
            .buttonStyle(.plain)

            Button(action: onOpenSummary) {
                HStack(spacing: 6) {
                    Image(systemName: "highlighter")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(Color.hlCyanite)
                    Text("即时摘要")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.hlCyanite)
                        .lineLimit(1)
                }
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity)
                .background(Color.hlCyanite.opacity(0.16), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var welcomeHeroSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Start a conversation or continue recent work"))
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(String(localized: "Type below to start a new chat immediately, or open the organizer dock for attachments, modes, tools, skills, and MCP."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    // MARK: - Single Persistent Anchored Composer (ContentView.swift lines 382-405)

    private var mountedEndpointForActiveRoute: HanlinActiveComposerSessionBridge.Endpoint? {
        guard let activeID = activeChatID,
              let endpoint = sessionBridge.activeEndpoint,
              endpoint.sessionID == activeID else {
            return nil
        }
        return endpoint
    }

    private func anchoredComposer(availableSize: CGSize) -> some View {
        let endpoint = mountedEndpointForActiveRoute
        return ChatViewBottom(
            chatRecord: endpoint?.chatRecord ?? sessionBridge.homePlaceholderRecord,
            modelTemp: (endpoint?.modelTemp.isEmpty == false) ? (endpoint?.modelTemp ?? allModels) : allModels,
            TemporaryRecord: endpoint?.temporaryRecord ?? false,
            respondIndex: endpoint?.respondIndex ?? 0,
            onSelectModel: { index in
                if let endpoint {
                    endpoint.onSelectModel(index)
                } else if allModels.indices.contains(index) {
                    sessionBridge.homeSelectedModelIndex = index
                }
            },
            onSendUser: {
                if let activeID = activeChatID {
                    _ = sessionBridge.performSendUser(expectedSessionID: activeID)
                } else if let targetID = sessionBridge.beginHomeFirstTurn(
                    availableModels: allModels,
                    createAuthorizedChat: onCreateAuthorizedNewChat
                ) {
                    path.append(.chat(targetID))
                }
            },
            onSendObserve: {
                if let activeID = activeChatID {
                    _ = sessionBridge.performSendObserve(expectedSessionID: activeID)
                }
            },
            onCancel: {
                if let activeID = activeChatID {
                    _ = sessionBridge.performCancel(expectedSessionID: activeID)
                }
            },
            selectedModelIndex: endpoint?.selectedModelIndex ?? $sessionBridge.homeSelectedModelIndex,
            showScrollToBottomButton: endpoint?.showScrollToBottomButton ?? $homeShowScrollToBottom,
            needScrollToBottomButton: endpoint?.needScrollToBottomButton ?? $homeNeedScrollToBottom,
            isMultiSelectMode: endpoint?.isMultiSelectMode ?? $homeIsMultiSelectMode,
            selectedMessageIDs: endpoint?.selectedMessageIDs ?? $homeSelectedMessageIDs,
            chatTemps: endpoint?.chatTemps ?? $homeChatTemps,
            showTemperatureSlider: endpoint?.showTemperatureSlider ?? $sessionBridge.homeShowTemperatureSlider,
            temperature: endpoint?.temperature ?? $sessionBridge.homeTemperature,
            showTopPSlider: endpoint?.showTopPSlider ?? $sessionBridge.homeShowTopPSlider,
            topP: endpoint?.topP ?? $sessionBridge.homeTopP,
            showMaxTokensSlider: endpoint?.showMaxTokensSlider ?? $sessionBridge.homeShowMaxTokensSlider,
            maxTokens: endpoint?.maxTokens ?? $sessionBridge.homeMaxTokens,
            showMaxMessagesNumSlider: endpoint?.showMaxMessagesNumSlider ?? $sessionBridge.homeShowMaxMessagesNumSlider,
            maxMessagesNum: endpoint?.maxMessagesNum ?? $sessionBridge.homeMaxMessagesNum,
            message: endpoint?.message ?? $sessionBridge.homeMessage,
            selectedImages: endpoint?.selectedImages ?? $sessionBridge.homeSelectedImages,
            selectedDocumentURLs: endpoint?.selectedDocumentURLs ?? $sessionBridge.homeSelectedDocumentURLs,
            selectedURLs: endpoint?.selectedURLs ?? $sessionBridge.homeSelectedURLs,
            selectedPrompts: endpoint?.selectedPrompts ?? $sessionBridge.homeSelectedPrompts,
            showPhotoSourceOptions: endpoint?.showPhotoSourceOptions ?? $sessionBridge.homeShowPhotoSourceOptions,
            showModelSuggestions: endpoint?.showModelSuggestions ?? $sessionBridge.homeShowModelSuggestions,
            filteredModels: endpoint?.filteredModels ?? $sessionBridge.homeFilteredModels,
            isResponding: endpoint?.isResponding ?? $homeIsResponding,
            isFeedBack: endpoint?.isFeedBack ?? $sessionBridge.homeIsFeedBack,
            ifKnowledge: endpoint?.ifKnowledge ?? $sessionBridge.homeIfKnowledge,
            ifSearch: endpoint?.ifSearch ?? $sessionBridge.homeIfSearch,
            ifToolUse: endpoint?.ifToolUse ?? $sessionBridge.homeIfToolUse,
            ifThink: endpoint?.ifThink ?? $sessionBridge.homeIfThink,
            ifAudio: endpoint?.ifAudio ?? $sessionBridge.homeIfAudio,
            ifPlanning: endpoint?.ifPlanning ?? $sessionBridge.homeIfPlanning,
            thinkingLength: endpoint?.thinkingLength ?? $sessionBridge.homeThinkingLength,
            showKnowledgeAlert: endpoint?.showKnowledgeAlert ?? $sessionBridge.homeShowKnowledgeAlert,
            knowledgeAlertMessage: endpoint?.knowledgeAlertMessage ?? $sessionBridge.homeKnowledgeAlertMessage,
            showSearchAlert: endpoint?.showSearchAlert ?? $sessionBridge.homeShowSearchAlert,
            selectedImageSize: endpoint?.selectedImageSize ?? $sessionBridge.homeSelectedImageSize,
            imageReversePrompt: endpoint?.imageReversePrompt ?? $sessionBridge.homeImageReversePrompt,
            isInputActive: $isCompactComposerInputActive,
            dockContextKey: activeComposerKey,
            availableWorkspaceSize: availableSize
        )
        .onGeometryChange(for: CGFloat.self) { geo in
            geo.size.height
        } action: { height in
            let clamped = max(136, height)
            if abs(dockHeight - clamped) > 1 {
                dockHeight = clamped
            }
        }
        .accessibilityIdentifier("hanlin-persistent-compact-composer")
    }
}
