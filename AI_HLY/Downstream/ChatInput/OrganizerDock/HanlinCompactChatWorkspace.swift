import HanlinLocalization
//
//  HanlinCompactChatWorkspace.swift
//  AI_HLY
//
//  Source-faithful compact workspace host ported from
//  InteriorOrganizerV3_3.swiftpm/AppModule/ContentView.swift (lines 293-405).
//  Owns one keyboard-resizing vertical stack around the original NavigationStack,
//  `@Namespace private var libraryZoom`, and one persistent anchored composer dock
//  shared across the compact Home screen (`composerKey == "new"`) and any pushed
//  chat destination (`.chat(UUID)`), while hiding the dock in `.allConversations`.
//

import SwiftUI
import SwiftData
import UIKit

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
    let onCreateAuthorizedNewChat: () -> ChatRecords?
    let onTogglePin: (ChatRecords) -> Void
    let onEditRecord: (ChatRecords) -> Void
    let onDeleteRecord: (ChatRecords) -> Void
    let onRefresh: () -> Void
    @Bindable var sessionBridge: HanlinActiveComposerSessionBridge
    let onOpenProfile: () -> Void
    let onOpenMiniApps: () -> Void
    let onOpenVision: () -> Void
    @State private var showsHistory = false
    @Query private var apiKeys: [APIKeys]

    @Namespace private var libraryZoom
    @State private var dockHeight: CGFloat = 176
    @State private var workspaceSize: CGSize = .zero
    @State private var keyboardOwner = HanlinCompactKeyboardOwner()
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
        // NavigationStack receives keyboard insets in its own UIKit content
        // host. The persistent sibling dock needs the same visible viewport;
        // the outer workspace owns keyboard avoidance for both children.
        HanlinSidebarReveal(isPresented: $showsHistory, reservesBackGesture: !path.isEmpty) {
            historySidebar
        } content: {
            workspaceSurface
        }
        .modifier(HanlinCompactKeyboardAvoidance(owner: keyboardOwner))
        .onChange(of: showsHistory) { _, presented in
            keyboardOwner.setHistoryPresented(presented)
            if presented {
                isCompactComposerInputActive = false
                keyboardOwner.editor?.resignFirstResponder()
            }
        }
        .onChange(of: path) { oldPath, newPath in
            #if DEBUG || HANLIN_TESTING
            keyboardOwner.traceNavigation(
                "path-change", path: newPath, previousPath: oldPath,
                requestedHistory: showsHistory, readAfterYield: true)
            #endif
            showsHistory = false
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
            if let defaultIndex = HanlinDefaultChatPolicy.creationModelIndex(in: allModels, providers: apiKeys) {
                sessionBridge.homeSelectedModelIndex = defaultIndex
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hanlin-compact-chat-workspace")
        .onDisappear {
            keyboardOwner.setHistoryPresented(false)
            showsHistory = false
        }
    }

    private var workspaceSurface: some View {
        VStack(spacing: 0) {
            navigationRoot(availableHeight: max(0, workspaceSize.height - (composerVisible ? dockHeight : 0)))
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            if composerVisible {
                anchoredComposer(availableSize: workspaceSize)
                    .compactWorkspaceGeometryProbe("composer")
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        // Both flexible slots accept the same keyboard-time proposal. The
        // outer effect keeps this exact subtree mounted while revealing History.
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newSize in
            workspaceSize = newSize
        }
        .compactWorkspaceGeometryProbe("workspace")
        .animation(.spring(response: 0.36, dampingFraction: 0.88), value: composerVisible)
    }

    private var historySidebar: some View {
        NavigationStack {
            conversationLibrary(isPresented: showsHistory)
                .navigationTitle(Text("History", bundle: HanlinLocalization.bundle))
                .toolbar {
                    if showsHistory {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(hanlin: "Done") { showsHistory = false }
                                .accessibilityIdentifier("hanlin-history-done")
                        }
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    // The original contextual Profile route; no demo settings
                    // or replacement product menu is introduced by the effect.
                    Button(action: onOpenProfile) {
                        Label(hanlin: "Profile", systemImage: "person.crop.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .accessibilityIdentifier("hanlin-settings-tab")
                    .background(.bar)
                    .accessibilityHidden(true, isEnabled: !showsHistory)
                }
        }
    }

    private var historyButton: some View {
        Button { showsHistory = true } label: {
            Label(hanlin: "History", systemImage: "sidebar.left")
        }
        .accessibilityIdentifier("hanlin-history-open")
    }

    // MARK: - Navigation Root (ContentView.swift lines 349-380)

    private func navigationRoot(availableHeight: CGFloat) -> some View {
        NavigationStack(path: $path) {
            compactHomeScreen(availableHeight: availableHeight)
                .compactWorkspaceGeometryProbe("home-navigation-content")
                .navigationTitle(Text("Hanlin", bundle: HanlinLocalization.bundle))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    HanlinWorkspaceActions(onOpenProfile: onOpenProfile,
                        onOpenMiniApps: onOpenMiniApps, onOpenVision: onOpenVision)
                    ToolbarItem(placement: .topBarLeading) {
                        historyButton
                    }
                    ToolbarItem(placement: .navigationBarLeading) {
                        if loadHistoryMessages {
                            HStack(spacing: 4) {
                                ProgressView().font(HanlinTypography.caption)
                                Text("正在加载...", bundle: HanlinLocalization.bundle).font(HanlinTypography.caption)
                            }
                        } else {
                            Button(action: onOpenSafariGuide) {
                                Label {
                                    Text("软件指南", bundle: HanlinLocalization.bundle)
                                        .font(HanlinTypography.caption)
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
                            Label(hanlin: "New chat", systemImage: "plus.bubble")
                        }
                        .accessibilityIdentifier("hanlin-new-chat-button")
                    }
                }
                .navigationDestination(for: HanlinCompactWorkspaceRoute.self) { route in
                    destinationView(for: route)
                        .compactWorkspaceGeometryProbe("chat-navigation-content")
                }
        }
    }

    @ViewBuilder
    private func destinationView(for route: HanlinCompactWorkspaceRoute) -> some View {
        switch route {
        case .allConversations:
            conversationLibrary(isPresented: true)
                .navigationTransition(.zoom(sourceID: "all-conversations", in: libraryZoom))
                .toolbarVisibility(.visible, for: .navigationBar)

        case .chat(let id):
            if let record = chatRecords.first(where: { $0.id == id }) {
                ChatViewWrapper(
                    chatRecord: record,
                    matchedMessageID: matchedMessageIDByChat[id]
                )
                .environment(\.hanlinExternalCompactComposerHost, true)
                .environment(\.hanlinExternalDockHeight, 0)
                .environment(\.hanlinComposerSessionBridge, sessionBridge)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { historyButton }
                }
                .id(id)
            } else {
                ContentUnavailableView(
                    String(localized: "Conversation Not Found", bundle: HanlinLocalization.bundle),
                    systemImage: "bubble.left.and.exclamationmark.bubble.right"
                )
            }
        }
    }

    private func conversationLibrary(isPresented: Bool) -> some View {
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
                showsHistory = false
                #if DEBUG || HANLIN_TESTING
                keyboardOwner.traceNavigation(
                    "callback-before-path", path: path,
                    requestedHistory: showsHistory)
                #endif
                path = [.chat(id)]
            },
            onAddNewChat: {
                if let created = onCreateAuthorizedNewChat(),
                   let id = created.id {
                    showsHistory = false
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
            onRefresh: onRefresh,
            isPresented: isPresented,
            keyboardOwner: keyboardOwner
        )
    }

    // MARK: - Compact Home Screen (ContentView.swift lines 413-513)

    private func compactHomeScreen(availableHeight: CGFloat) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
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
                        showsHistory = true
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
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, minHeight: max(320, availableHeight - 16), alignment: .bottomLeading)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            onRefresh()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("hanlin-compact-home-screen")
    }

    private var welcomeHeroSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Start a conversation or continue recent work", bundle: HanlinLocalization.bundle))
                .font(HanlinTypography.fixed(size: 24, weight: .semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(String(localized: "Type below to start a new chat immediately, or open the organizer dock for attachments, modes, tools, skills, and MCP.", bundle: HanlinLocalization.bundle))
                .font(HanlinTypography.subheadline)
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
            availableWorkspaceSize: availableSize,
            onNativeEditorLifecycle: { editor, event in
                keyboardOwner.observe(editor, event: event)
            },
            onModelPopoverPresentationChange: { id, presented in
                keyboardOwner.modelPopoverPresentationChanged(id, presented: presented)
            },
            readCurrentMessageState: {
                if let endpoint { return endpoint.readCurrentMessageState?() }
                return sessionBridge.homeDraft.snapshot
            }
        )
        .onGeometryChange(for: CGFloat.self) { geo in
            geo.size.height
        } action: { height in
            let clamped = max(136, height)
            if abs(dockHeight - clamped) > 1 {
                dockHeight = clamped
            }
        }
    }
}

// The probe measures the unpadded workspace, so applying its inset does not
// move its own reference bounds. There is one overlap writer for navigation
// and the existing persistent composer; editor identity and bindings stay intact.
@MainActor
private struct HanlinCompactKeyboardAvoidance: ViewModifier {
    let owner: HanlinCompactKeyboardOwner
    @State private var keyboardOverlap: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .padding(.bottom, keyboardOverlap)
            .background {
                HanlinCompactKeyboardFrameProbe(owner: owner) { overlap in
                    guard keyboardOverlap != overlap else { return }
                    keyboardOverlap = overlap
                }
                .accessibilityHidden(true)
                .allowsHitTesting(false)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

// Ownership comes from this workspace's actual editor or registered history
// search subtree. Settings/sheet inputs and other panes are not owners.
// Weak view registrations need no walk through private hosting hierarchies.
@MainActor
final class HanlinCompactKeyboardOwner {
    private(set) weak var editor: UITextView?
    fileprivate weak var observer: HanlinCompactKeyboardFrameView?
    private var modelPopoverIDs: Set<UUID> = []
    private var historyPresented = false
    private var editorAccessibilityBeforeHistory: (isElement: Bool, elementsHidden: Bool)?
    #if DEBUG || HANLIN_TESTING
    private var accessibilityTraceSequence = 0
    private var accessibilityTraceGeneration: UInt = 0
    private var accessibilityTraceTask: Task<Void, Never>?
    private var navigationTraceSequence = 0
    private var navigationTraceGeneration: UInt = 0
    private var navigationTraceTask: Task<Void, Never>?
    #endif
    private struct SearchFocus {
        weak var anchor: UIView?
        weak var window: UIWindow?
    }
    private var searchFocus: [UUID: SearchFocus] = [:]

    /// Each actual searchable subtree registers its own view/window and focus.
    /// A hidden or removed library can revoke only its own registration.
    func setSearchFocus(_ id: UUID, anchor: UIView, focused: Bool) {
        guard focused, let window = anchor.window else {
            removeSearchFocus(id)
            return
        }
        guard searchFocus[id]?.anchor !== anchor || searchFocus[id]?.window !== window else { return }
        searchFocus[id] = SearchFocus(anchor: anchor, window: window)
        observer?.ownershipDidChange("history-search-focused")
    }

    func removeSearchFocus(_ id: UUID) {
        guard searchFocus.removeValue(forKey: id) != nil else { return }
        observer?.ownershipDidChange("history-search-unfocused")
    }

    /// The model picker is part of this composer's keyboard context. Its native
    /// search may take focus without moving the source below the keyboard.
    /// Tokens prevent a late dismissal from clearing a newer presentation.
    func modelPopoverPresentationChanged(_ id: UUID, presented: Bool) {
        let changed = presented ? modelPopoverIDs.insert(id).inserted : modelPopoverIDs.remove(id) != nil
        guard changed else { return }
        observer?.ownershipDidChange(presented ? "model-presented" : "model-dismissed")
    }

    func ownsKeyboardFocus(in window: UIWindow) -> Bool {
        let ownsComposer = editor?.window === window
            && (editor?.isFirstResponder == true || !modelPopoverIDs.isEmpty)
        let ownsSearch = searchFocus.values.contains {
            $0.window === window && $0.anchor?.window === window
        }
        return ownsComposer || ownsSearch
    }

    /// The mounted editor belongs to this workspace. History temporarily owns
    /// accessibility without replacing the editor or changing its text/focus.
    func setHistoryPresented(_ presented: Bool) {
        historyPresented = presented
        applyEditorAccessibilityOwnership()
        #if DEBUG || HANLIN_TESTING
        traceEditorAccessibility("history-set-immediate")
        scheduleAccessibilityReadback()
        #endif
    }

    #if DEBUG || HANLIN_TESTING
    /// Observational only: read the existing owned editor, without traversing
    /// ancestors, changing accessibility, or recording draft/selection content.
    private func traceEditorAccessibility(_ phase: String) {
        guard ProcessInfo.processInfo.environment["HANLIN_COMPOSER_EDIT_DIAGNOSTICS"] == "1",
              accessibilityTraceSequence < 96 else { return }
        accessibilityTraceSequence += 1
        var record: [String: Any] = [
            "epoch": Date().timeIntervalSince1970,
            "pid": ProcessInfo.processInfo.processIdentifier,
            "phase": phase,
            "sequence": accessibilityTraceSequence,
            "owner": String(describing: ObjectIdentifier(self)),
            "historyPresented": historyPresented,
            "editorPresent": editor != nil
        ]
        if let editor {
            record["editor"] = String(describing: ObjectIdentifier(editor))
            record["nativeClass"] = String(reflecting: type(of: editor))
            record["identifier"] = editor.accessibilityIdentifier ?? ""
            record["isAccessibilityElement"] = editor.isAccessibilityElement
            record["accessibilityElementsHidden"] = editor.accessibilityElementsHidden
            // Keep diagnostics independent of optional getter implementations;
            // this editor rejected a block getter during native startup.
            record["blockGetterInspection"] = "not-read"
            record["containerGetterInspection"] = "not-read"
            record["isUserInteractionEnabled"] = editor.isUserInteractionEnabled
            record["isHidden"] = editor.isHidden
            record["alpha"] = editor.alpha
            record["isFirstResponder"] = editor.isFirstResponder
            record["traits"] = editor.accessibilityTraits.rawValue
            record["notEnabledTrait"] = editor.accessibilityTraits.contains(.notEnabled)
            record["layoutDirection"] = editor.effectiveUserInterfaceLayoutDirection == .rightToLeft ? "rtl" : "ltr"
            record["bounds"] = String(describing: editor.bounds)
            if let window = editor.window {
                record["window"] = String(describing: ObjectIdentifier(window))
                record["windowFrame"] = String(describing: editor.convert(editor.bounds, to: window))
            }
        }
        if let original = editorAccessibilityBeforeHistory {
            record["savedOriginalIsElement"] = original.isElement
            record["savedOriginalElementsHidden"] = original.elementsHidden
        }
        guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
              let message = String(data: data, encoding: .utf8) else { return }
        NSLog("%@", "[HANLIN_SIDEBAR_EDITOR_AX] " + message as NSString)
    }

    /// One yielded readback per visibility change or new editor attachment.
    /// This is not a timing gate and never alters the original test or UI state.
    private func scheduleAccessibilityReadback() {
        guard ProcessInfo.processInfo.environment["HANLIN_COMPOSER_EDIT_DIAGNOSTICS"] == "1",
              accessibilityTraceSequence < 96, let editor else { return }
        accessibilityTraceGeneration &+= 1
        let generation = accessibilityTraceGeneration
        accessibilityTraceTask?.cancel()
        accessibilityTraceTask = Task { @MainActor [weak self, weak editor] in
            await Task.yield()
            guard !Task.isCancelled, let self, let editor, self.editor === editor,
                  self.accessibilityTraceGeneration == generation else { return }
            self.traceEditorAccessibility("deferred-yield-readback")
            self.accessibilityTraceTask = nil
        }
    }
    #endif

    #if DEBUG || HANLIN_TESTING
    /// Observe only the controllers in this editor's actual window. No view is
    /// loaded, no delegate is replaced, and no navigation or focus is changed.
    func traceNavigation(
        _ phase: String,
        path: [HanlinCompactWorkspaceRoute]? = nil,
        previousPath: [HanlinCompactWorkspaceRoute]? = nil,
        requestedHistory: Bool? = nil,
        readAfterYield: Bool = false
    ) {
        guard ProcessInfo.processInfo.environment["HANLIN_COMPOSER_EDIT_DIAGNOSTICS"] == "1",
              navigationTraceSequence < 24 else { return }
        navigationTraceSequence += 1
        let capture = navigationTraceSequence
        func identity(_ object: AnyObject?) -> String {
            guard let object else { return "nil" }
            return "0x" + String(UInt(bitPattern: ObjectIdentifier(object)), radix: 16)
        }
        func kinds(_ routes: [HanlinCompactWorkspaceRoute]?) -> [String] {
            (routes ?? []).prefix(8).map { route in
                switch route {
                case .allConversations: return "allConversations"
                case .chat(_): return "chat"
                }
            }
        }
        func emit(_ fields: [String: Any]) {
            var record = fields
            record["epoch"] = Date().timeIntervalSince1970
            record["pid"] = ProcessInfo.processInfo.processIdentifier
            record["capture"] = capture
            record["phase"] = phase
            record["owner"] = identity(self)
            guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
                  let message = String(data: data, encoding: .utf8) else { return }
            NSLog("%@", ("[HANLIN_SIDEBAR_NAVIGATION] " + message) as NSString)
        }
        let window = editor?.window
        let root = window?.rootViewController
        emit([
            "kind": "begin", "window": identity(window), "root": identity(root),
            "ownerHistoryNow": historyPresented,
            "requestedHistoryAtEvent": requestedHistory.map { $0 as Any } ?? NSNull(),
            "pathSnapshotSupplied": path != nil, "pathSnapshotKinds": kinds(path),
            "pathSnapshotCount": path?.count ?? 0,
            "previousPathSnapshotKinds": kinds(previousPath),
            "previousPathSnapshotCount": previousPath?.count ?? 0,
            "nodeLimit": 32, "depthLimit": 8, "captureLimit": 24
        ])
        if let root {
            // Strong references keep each public controller identity stable for
            // this synchronous capture; cycles never create a second node.
            var nodes: [(controller: UIViewController, depth: Int)] = [(root, 0)]
            var seen: Set<ObjectIdentifier> = [ObjectIdentifier(root)]
            var reachedLimit = false
            var index = 0
            func enqueue(_ controller: UIViewController, depth: Int) {
                let id = ObjectIdentifier(controller)
                guard !seen.contains(id) else { return }
                guard depth <= 8, nodes.count < 32 else {
                    reachedLimit = true
                    return
                }
                seen.insert(id)
                nodes.append((controller, depth))
            }
            while index < nodes.count {
                let (controller, depth) = nodes[index]
                index += 1
                let id = identity(controller)
                let children = controller.children
                let presented = controller.presentedViewController
                emit([
                    "kind": "controller", "id": id, "depth": depth,
                    "type": String(String(reflecting: type(of: controller)).prefix(120)),
                    "beingPresented": controller.isBeingPresented,
                    "beingDismissed": controller.isBeingDismissed,
                    "presented": identity(presented), "childrenCount": children.count
                ])
                // Small records keep the retained diagnostic stream bounded and
                // avoid truncating a controller with many public children.
                let childIDs = children.prefix(32).map { identity($0) }
                for start in stride(from: 0, to: childIDs.count, by: 8) {
                    emit(["kind": "children", "id": id, "offset": start,
                          "ids": Array(childIDs[start..<min(start + 8, childIDs.count)])])
                }
                if children.count > 32 { reachedLimit = true }
                if let navigation = controller as? UINavigationController {
                    let stack = navigation.viewControllers
                    emit([
                        "kind": "navigation", "id": id,
                        "top": identity(navigation.topViewController),
                        "visible": identity(navigation.visibleViewController),
                        "stackCount": stack.count,
                        "stackIDs": stack.prefix(8).map { identity($0) },
                        "stackIDsTruncated": stack.count > 8
                    ])
                }
                if let transition = controller.transitionCoordinator {
                    emit([
                        "kind": "transition", "controller": id,
                        "id": identity(transition as AnyObject),
                        "duration": transition.transitionDuration,
                        "animated": transition.isAnimated,
                        "interactive": transition.isInteractive,
                        "cancelled": transition.isCancelled,
                        "from": identity(transition.viewController(forKey: .from)),
                        "to": identity(transition.viewController(forKey: .to))
                    ])
                }
                for child in children.prefix(32) { enqueue(child, depth: depth + 1) }
                if let presented { enqueue(presented, depth: depth + 1) }
            }
            emit(["kind": "end", "nodes": nodes.count, "limitReached": reachedLimit])
        } else {
            emit(["kind": "end", "nodes": 0, "limitReached": false, "rootUnavailable": true])
        }
        if readAfterYield, let window {
            navigationTraceGeneration &+= 1
            let generation = navigationTraceGeneration
            navigationTraceTask?.cancel()
            navigationTraceTask = Task { @MainActor [weak self, weak window] in
                // This is an observation, never a readiness or routing gate.
                await Task.yield()
                guard !Task.isCancelled, let self, let window,
                      self.editor?.window === window,
                      self.navigationTraceGeneration == generation else { return }
                self.traceNavigation(
                    "path-change-yield", path: path, previousPath: previousPath)
                self.navigationTraceTask = nil
            }
        }
    }
    #endif

    private func applyEditorAccessibilityOwnership() {
        guard let editor else {
            editorAccessibilityBeforeHistory = nil
            return
        }
        if historyPresented {
            if editorAccessibilityBeforeHistory == nil {
                editorAccessibilityBeforeHistory = (
                    editor.isAccessibilityElement, editor.accessibilityElementsHidden)
            }
            editor.isAccessibilityElement = false
            editor.accessibilityElementsHidden = true
        } else {
            restoreEditorAccessibility()
        }
    }

    private func restoreEditorAccessibility() {
        guard let original = editorAccessibilityBeforeHistory else { return }
        editor?.isAccessibilityElement = original.isElement
        editor?.accessibilityElementsHidden = original.elementsHidden
        editorAccessibilityBeforeHistory = nil
    }

    func observe(_ editor: UITextView, event: NativeMultilineTextEditor.LifecycleEvent) {
        switch event {
        case .attached:
            let changed = self.editor !== editor
            if changed {
                restoreEditorAccessibility()
                self.editor = editor
            }
            // Every native update reports attachment, including active IME
            // composition. Reassert ownership before the same-editor fast path.
            applyEditorAccessibilityOwnership()
            #if DEBUG || HANLIN_TESTING
            traceEditorAccessibility("attached-immediate")
            if changed { scheduleAccessibilityReadback() }
            #endif
            guard changed else { return }
            observer?.ownershipDidChange("editor-attached")
        case .focusChanged(let focused):
            guard self.editor === editor else { return }
            observer?.ownershipDidChange(focused ? "editor-focused" : "editor-unfocused")
        case .detached:
            // A late teardown from a replaced editor cannot unregister its successor.
            guard self.editor === editor else { return }
            restoreEditorAccessibility()
            self.editor = nil
            observer?.ownershipDidChange("editor-detached")
        }
    }
}

/// A noninteractive anchor for this searchable library's native window. It
/// contributes focus ownership only; the existing workspace probe remains the
/// sole keyboard frame observer and overlap writer.
@MainActor
struct HanlinCompactSearchFocusRegistration: UIViewRepresentable {
    let owner: HanlinCompactKeyboardOwner
    let isFocused: Bool

    func makeUIView(context: Context) -> Anchor {
        Anchor(owner: owner, focused: isFocused)
    }

    func updateUIView(_ view: Anchor, context: Context) {
        view.update(owner: owner, focused: isFocused)
    }

    static func dismantleUIView(_ view: Anchor, coordinator: Void) {
        view.disconnect()
    }

    final class Anchor: UIView {
        private let token = UUID()
        private weak var owner: HanlinCompactKeyboardOwner?
        private var searchIsFocused: Bool

        init(owner: HanlinCompactKeyboardOwner, focused: Bool) {
            self.owner = owner
            self.searchIsFocused = focused
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            publishFocus()
        }

        func update(owner: HanlinCompactKeyboardOwner, focused: Bool) {
            if self.owner !== owner {
                self.owner?.removeSearchFocus(token)
                self.owner = owner
            }
            self.searchIsFocused = focused
            publishFocus()
        }

        func disconnect() {
            owner?.removeSearchFocus(token)
            owner = nil
        }

        private func publishFocus() {
            owner?.setSearchFocus(token, anchor: self, focused: searchIsFocused)
        }
    }
}

@MainActor
private struct HanlinCompactKeyboardFrameProbe: UIViewRepresentable {
    let owner: HanlinCompactKeyboardOwner
    var onOverlapChanged: (CGFloat) -> Void

    func makeUIView(context: Context) -> HanlinCompactKeyboardFrameView {
        let view = HanlinCompactKeyboardFrameView(owner: owner)
        view.onOverlapChanged = onOverlapChanged
        return view
    }

    func updateUIView(_ uiView: HanlinCompactKeyboardFrameView, context: Context) {
        uiView.onOverlapChanged = onOverlapChanged
        uiView.setNeedsLayout()
    }

    static func dismantleUIView(_ uiView: HanlinCompactKeyboardFrameView, coordinator: Void) {
        uiView.disconnect()
    }
}

@MainActor
fileprivate final class HanlinCompactKeyboardFrameView: UIView {
    var onOverlapChanged: ((CGFloat) -> Void)?
    private let owner: HanlinCompactKeyboardOwner
    private weak var observedWindow: UIWindow?
    private weak var keyboardScreen: UIScreen?
    private var keyboardFrame: CGRect?
    private var keyboardScreenBounds: CGRect?
    private var observations: [NotificationCenter.ObservationToken] = []
    private var deliveredOverlap: CGFloat?
    private var deliveryScheduled = false
    #if DEBUG || HANLIN_TESTING
    private var lastLayoutWitness: String?
    #endif

    init(owner: HanlinCompactKeyboardOwner) {
        self.owner = owner
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        owner.observer = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window !== observedWindow {
            // Releasing typed tokens stops observation of the previous window.
            observations.removeAll()
            observedWindow = window
            clearKeyboardFrame()
            if window != nil { observeKeyboard() }
        }
        queueOverlapUpdate(reason: "window-changed")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        queueOverlapUpdate(reason: "layout")
    }

    func ownershipDidChange(_ reason: String) {
        queueOverlapUpdate(reason: reason)
    }

    func disconnect() {
        observations.removeAll()
        clearKeyboardFrame()
        observedWindow = nil
        if owner.observer === self { owner.observer = nil }
        onOverlapChanged = nil
    }

    private func observeKeyboard() {
        let center = NotificationCenter.default
        observations = [
            center.addObserver(of: nil, for: UIResponder.KeyboardWillChangeFrameMessage.self) { [weak self] message in
                self?.receiveFrame(message.endFrame, screen: message.screen, isLocal: message.isLocal, reason: "will-change-frame")
            },
            center.addObserver(of: nil, for: UIResponder.KeyboardDidChangeFrameMessage.self) { [weak self] message in
                self?.receiveFrame(message.endFrame, screen: message.screen, isLocal: message.isLocal, reason: "did-change-frame")
            },
            center.addObserver(of: nil, for: UIResponder.KeyboardWillHideMessage.self) { [weak self] message in
                self?.receiveHide(on: message.screen, reason: "will-hide")
            },
            center.addObserver(of: nil, for: UIResponder.KeyboardDidHideMessage.self) { [weak self] message in
                self?.receiveHide(on: message.screen, reason: "did-hide")
            },
            center.addObserver(of: nil, for: UIWindow.DidResignKeyMessage.self) { [weak self] message in
                guard let self, self.observedWindow === message.window else { return }
                self.clearKeyboardFrame()
                self.queueOverlapUpdate(reason: "window-resigned-key")
            },
            center.addObserver(of: nil, for: UIScene.WillDeactivateMessage.self) { [weak self] message in
                guard let self, self.observedWindow?.windowScene === message.scene else { return }
                self.clearKeyboardFrame()
                self.queueOverlapUpdate(reason: "scene-deactivated")
            }
        ]
    }

    private func receiveFrame(_ frame: CGRect, screen: UIScreen, isLocal: Bool, reason: String) {
        guard let window, window === observedWindow, window.windowScene?.screen === screen else { return }
        if isLocal {
            keyboardScreen = screen
            keyboardScreenBounds = screen.bounds
            keyboardFrame = frame
        } else {
            clearKeyboardFrame()
        }
        queueOverlapUpdate(reason: isLocal ? reason : "nonlocal-frame")
    }

    private func receiveHide(on screen: UIScreen, reason: String) {
        guard observedWindow?.windowScene?.screen === screen else { return }
        // Clearing does not require first responder: UIKit may already have resigned it.
        clearKeyboardFrame()
        queueOverlapUpdate(reason: reason)
    }

    private func clearKeyboardFrame() {
        keyboardFrame = nil
        keyboardScreen = nil
        keyboardScreenBounds = nil
    }

    private var ownsKeyboardContext: Bool {
        guard owner.observer === self,
              let window, window === observedWindow, window.isKeyWindow,
              window.windowScene?.activationState == .foregroundActive else { return false }
        return owner.ownsKeyboardFocus(in: window)
    }

    private func currentOverlap() -> CGFloat {
        guard ownsKeyboardContext,
              let window, let screen = keyboardScreen,
              window.windowScene?.screen === screen,
              let frame = keyboardFrame, keyboardScreenBounds == screen.bounds else { return 0 }
        // Keyboard endFrame is in this message's screen coordinate space.
        // Convert through the actual window, including Split View/Stage Manager offsets.
        let frameInWindow = screen.coordinateSpace.convert(frame, to: window)
        let frameInView = convert(frameInWindow, from: window)
        return HanlinCompactKeyboardGeometry.dockedOverlap(
            bounds: bounds, keyboardFrameInView: frameInView,
            keyboardFrameInScreen: frame, screenBounds: screen.bounds, displayScale: screen.scale)
    }

    private func queueOverlapUpdate(reason: String) {
        witness(reason: reason)
        guard !deliveryScheduled else { return }
        deliveryScheduled = true
        // Publish after SwiftUI's current update/layout. Re-read all ownership and
        // geometry at delivery, so a queued frame cannot outlive hide/focus/window loss.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.deliveryScheduled = false
            guard self.owner.observer === self else { return }
            let overlap = self.currentOverlap()
            guard self.deliveredOverlap != overlap else { return }
            self.deliveredOverlap = overlap
            self.witness(reason: "publish")
            self.onOverlapChanged?(overlap)
        }
    }

    private func witness(reason: String) {
        #if DEBUG || HANLIN_TESTING
        guard ProcessInfo.processInfo.environment["HANLIN_COMPACT_KEYBOARD_WITNESS"] == "1" else { return }
        let localFrame: CGRect? = {
            guard let window, let screen = keyboardScreen, let keyboardFrame else { return nil }
            return convert(screen.coordinateSpace.convert(keyboardFrame, to: window), from: window)
        }()
        let facts = "bounds=\(bounds) screenFrame=\(String(describing: keyboardFrame)) localFrame=\(String(describing: localFrame)) registered=\(owner.editor != nil) firstResponder=\(owner.editor?.isFirstResponder == true) sameWindow=\(owner.editor?.window != nil && owner.editor?.window === window) keyWindow=\(window?.isKeyWindow == true) activeScene=\(window?.windowScene?.activationState == .foregroundActive) owns=\(ownsKeyboardContext) overlap=\(currentOverlap())"
        if reason == "layout" {
            guard facts != lastLayoutWitness else { return }
            lastLayoutWitness = facts
        }
        print("[HANLIN_COMPACT_KEYBOARD] event=\(reason) \(facts)")
        #endif
    }
}

// Pure intersection policy. Only a keyboard docked across its actual screen's
// bottom can resize the workspace; floating/undocked keyboards remain overlays.
enum HanlinCompactKeyboardGeometry {
    static func dockedOverlap(
        bounds: CGRect, keyboardFrameInView: CGRect, keyboardFrameInScreen: CGRect,
        screenBounds: CGRect, displayScale: CGFloat
    ) -> CGFloat {
        let rectangles = [bounds, keyboardFrameInView, keyboardFrameInScreen, screenBounds]
        guard displayScale.isFinite, displayScale > 0,
              rectangles.allSatisfy({ rect in
                  [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height].allSatisfy(\.isFinite)
                      && rect.width > 0 && rect.height > 0
              }) else { return 0 }
        let tolerance = 1 / displayScale
        guard keyboardFrameInScreen.minX <= screenBounds.minX + tolerance,
              keyboardFrameInScreen.maxX >= screenBounds.maxX - tolerance,
              keyboardFrameInScreen.minY < screenBounds.maxY,
              keyboardFrameInScreen.maxY >= screenBounds.maxY - tolerance else { return 0 }
        let intersection = bounds.intersection(keyboardFrameInView)
        guard !intersection.isNull, !intersection.isEmpty,
              intersection.maxY >= bounds.maxY - tolerance else { return 0 }
        return min(bounds.height, max(0, bounds.maxY - intersection.minY))
    }
}

// Observation only: keep the real keyboard/layout path unchanged during acceptance.
private extension View {
    @ViewBuilder
    func compactWorkspaceGeometryProbe(_ location: String) -> some View {
        #if DEBUG || HANLIN_TESTING
        if ProcessInfo.processInfo.environment["HANLIN_DOCK_ACCEPTANCE_FIXTURES"] == "1" {
            self.onGeometryChange(for: String.self) { proxy in
                let frame = proxy.frame(in: .global)
                let insets = proxy.safeAreaInsets
                let measurements = [
                    proxy.size.width, proxy.size.height,
                    frame.minX, frame.minY, frame.width, frame.height,
                    insets.top, insets.leading, insets.bottom, insets.trailing
                ]
                return measurements.map { String(Int($0.rounded())) }.joined(separator: ",")
            } action: { measurements in
                print("[HANLIN_COMPACT_GEOMETRY] \(location) size,frame,insets=\(measurements)")
            }
        } else {
            self
        }
        #else
        self
        #endif
    }
}
