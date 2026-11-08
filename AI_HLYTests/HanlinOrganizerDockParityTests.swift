//
//  HanlinOrganizerDockParityTests.swift
//  AI_HLYTests
//
//  Comprehensive unit test suites (§7A.1 – §7A.9) verifying the source-faithful
//  InteriorOrganizer V3.3 OrganizerDock, compact recent chats, zoom transitions,
//  session bridge, pending first turn state machine, and non-regression of original chat files.
//

import CryptoKit
import Foundation
import SwiftUI
import SwiftData
import Testing
@testable import AI_Hanlin

// MARK: - 7A.1 OrganizerDockStateTests

@MainActor
@Suite("7A.1 OrganizerDockState — Source Height Formulas, Drag & Resize Thresholds", .serialized)
struct OrganizerDockStateTests {

    @Test("1.1 Default collapsed state matches InteriorOrganizerV3_3 formulas (126pt composer, 161pt panel, 140pt editorMax)")
    func defaultCollapsedStateMatchesSourceFormulas() {
        let state = HanlinOrganizerDockState()
        #expect(state.mode == .collapsed)
        #expect(state.lastExpandedMode == .general)
        #expect(!state.isExpanded)
        #expect(state.measuredInputHeight == 26)
        #expect(state.autoComposerHeight == 126) // min(226, max(126, max(26, 26) + 99))
        #expect(state.maxComposerHeight == 515)  // min(515, max(200, 780) * 0.76)
        #expect(state.composerHeight == 126)
        #expect(state.panelHeight == 161)        // composerHeight + 35
        #expect(state.editorMaxHeight == 140)    // max(140, 126 - 88)
    }

    @Test("1.2 Multiline measuredInputHeight growth (up to 226pt base) and attachment overhead (up to 310pt)")
    func multilineDraftAndAttachmentHeightFormulas() {
        let state = HanlinOrganizerDockState()
        state.measuredInputHeight = 68
        #expect(state.autoComposerHeight == 167) // 68 + 99
        #expect(state.composerHeight == 167)
        #expect(state.panelHeight == 202)        // 167 + 35

        // Large input clamps base to 226, plus attachmentOverheadHeight (62pt) -> 288pt
        state.measuredInputHeight = 180
        state.attachmentOverheadHeight = 62
        #expect(state.autoComposerHeight == 288) // min(310, 226 + 62)
        #expect(state.composerHeight == 288)
        #expect(state.panelHeight == 323)        // 288 + 35
        #expect(state.editorMaxHeight == 140)    // max(140, 288 - 88 - 62 = 138) -> 140
    }

    @Test("1.3 Expanded state sets panelHeight to min(max(composerHeight + 36, effectiveAvailable - 10), composerHeight + 321)")
    func expandedStatePanelAndComposerHeight() {
        let state = HanlinOrganizerDockState()
        state.manualComposerHeight = 320
        #expect(state.composerHeight == 320)
        #expect(state.editorMaxHeight == 232) // max(140, 320 - 88)

        state.openMode(.general)
        #expect(state.isExpanded)
        #expect(state.mode == .general)
        #expect(state.panelHeight == 641) // min(max(320 + 36, 780 - 10), 320 + 321) = 641
    }

    @Test("1.4 Drawer drag gesture threshold (< -34 expands to lastExpandedMode, > 34 collapses, -34...34 no-op)")
    func drawerDragThresholdsMatchSource() {
        let state = HanlinOrganizerDockState()
        state.lastExpandedMode = .tools

        // Within threshold (-34...34): remains collapsed
        state.handleDrawerDragEnded(translationHeight: -34)
        #expect(state.mode == .collapsed)

        // Strictly < -34: expands to lastExpandedMode (.tools)
        state.handleDrawerDragEnded(translationHeight: -35)
        #expect(state.mode == .tools)
        #expect(state.isExpanded)

        // Within threshold while expanded: remains expanded
        state.handleDrawerDragEnded(translationHeight: 34)
        #expect(state.mode == .tools)

        // Strictly > 34: collapses and preserves lastExpandedMode
        state.handleDrawerDragEnded(translationHeight: 35)
        #expect(state.mode == .collapsed)
        #expect(state.lastExpandedMode == .tools)
    }

    @Test("1.5 Composer resize handle drag and +/-72pt accessibility step with snap-to-auto (<= auto + 6pt)")
    func composerResizeDragAndAccessibilityAdjustment() {
        let state = HanlinOrganizerDockState()
        #expect(state.composerHeight == 126)

        // Drag up by 60pt -> composerHeight becomes 186pt
        state.handleComposerResizeChanged(translationHeight: -60)
        #expect(state.composerHeight == 186)
        #expect(state.editorMaxHeight == 140) // max(140, 186 - 88 = 98)

        // End gesture clears gestureStartHeight
        state.handleComposerResizeEnded()
        #expect(state.gestureStartHeight == nil)

        // Accessibility increment (+72pt)
        state.adjustComposerHeightByAccessibility(increment: true)
        #expect(state.composerHeight == 258) // 186 + 72
        #expect(state.editorMaxHeight == 170) // 258 - 88

        // Accessibility decrement (-72pt twice back to 126pt auto snap)
        state.adjustComposerHeightByAccessibility(increment: false)
        #expect(state.composerHeight == 186)
        state.adjustComposerHeightByAccessibility(increment: false)
        #expect(state.composerHeight == 126)
        #expect(state.manualComposerHeight == nil)
    }

    @Test("1.6 Input focus, empty draft, and context key change reset transient layout state")
    func focusAndLifecycleResets() {
        let state = HanlinOrganizerDockState()
        state.openMode(.general)
        state.manualComposerHeight = 220

        // Focusing input collapses drawer automatically while keeping manual height
        state.handleInputFocusChange(true)
        #expect(state.mode == .collapsed)
        #expect(state.manualComposerHeight == 220)

        // Clearing draft text resets manualComposerHeight
        state.handleDraftTextChange("")
        #expect(state.manualComposerHeight == nil)

        // Switching context key collapses drawer and resets transient measurements
        state.openMode(.tools)
        state.manualComposerHeight = 240
        state.handleContextKeyChange("chat-123")
        #expect(state.contextKey == "chat-123")
        #expect(state.mode == .collapsed)
        #expect(state.manualComposerHeight == nil)
    }

    @Test("1.7 Manual composer resize expands and shrinks effectiveEditorFrameHeight monotonically")
    func manualResizeExpandsInnerEditorFrameHeight() {
        let state = HanlinOrganizerDockState()
        #expect(state.effectiveEditorFrameHeight(intrinsicHeight: 38, minimumInteractiveHeight: 44) == 44)

        // Drag up by 60pt (composerHeight = 186pt) -> inner editor frame expands to 98pt
        state.handleComposerResizeChanged(translationHeight: -60)
        state.handleComposerResizeEnded()
        #expect(state.composerHeight == 186)
        #expect(state.effectiveEditorFrameHeight(intrinsicHeight: 38, minimumInteractiveHeight: 44) == 98)

        // Drag up further by 72pt (composerHeight = 258pt) -> inner editor frame expands to 170pt
        state.adjustComposerHeightByAccessibility(increment: true)
        #expect(state.composerHeight == 258)
        #expect(state.effectiveEditorFrameHeight(intrinsicHeight: 38, minimumInteractiveHeight: 44) == 170)

        // Step back down to auto height -> inner editor frame returns to 44pt
        state.adjustComposerHeightByAccessibility(increment: false)
        state.adjustComposerHeightByAccessibility(increment: false)
        #expect(state.manualComposerHeight == nil)
        #expect(state.effectiveEditorFrameHeight(intrinsicHeight: 38, minimumInteractiveHeight: 44) == 44)
    }

    @Test("1.8 Keyboard overlap updates keyboardHeight without double-subtracting when container already shrunk")
    func keyboardOverlapAvoidsDoubleSubtraction() {
        let state = HanlinOrganizerDockState()
        state.availableHeight = 780

        // Container not shrunk by safe area -> full 300pt keyboard overlap applied
        state.updateKeyboardOverlap(300, baselineContainerHeight: 780)
        #expect(state.keyboardHeight == 300)

        // Container already shrunk by 300pt safe area (780 -> 480) -> keyboardHeight is 0 (no double-subtraction)
        state.availableHeight = 480
        state.updateKeyboardOverlap(300, baselineContainerHeight: 780)
        #expect(state.keyboardHeight == 0)

        // Keyboard hidden -> resets to 0
        state.availableHeight = 780
        state.updateKeyboardOverlap(0, baselineContainerHeight: 780)
        #expect(state.keyboardHeight == 0)
    }
}

// MARK: - 7A.2 HanlinComposerDrawerRouteTests

@MainActor
@Suite("7A.2 HanlinComposerDrawerRouteTests — Unified Drawer Modes & Direct Tools Shortcut", .serialized)
struct HanlinComposerDrawerRouteTests {

    @Test("2.1 Tapping `+` and `Tools` swaps drawer modes in-place within the single dock without closing/reopening")
    func switchingPlusAndToolsSwapsModeInSameDock() {
        let coordinator = HanlinComposerPopupCoordinator()
        #expect(coordinator.activePopup == nil)
        #expect(coordinator.dockState.mode == .collapsed)

        // 1 tap on `+` opens .general in the dock
        coordinator.toggle(.general)
        #expect(coordinator.activePopup == .general)
        #expect(coordinator.dockState.mode == .general)
        #expect(coordinator.dockState.isExpanded)

        // Push a subroute inside General, then tap Tools -> swaps directly to .tools and clears generalNavigationPath
        coordinator.pushGeneralSubroute(.prompts, reduceMotion: true)
        #expect(coordinator.generalNavigationPath == [.prompts])

        coordinator.toggle(.tools)
        #expect(coordinator.activePopup == .tools)
        #expect(coordinator.dockState.mode == .tools)
        #expect(coordinator.dockState.isExpanded)
        #expect(coordinator.generalNavigationPath.isEmpty)
        #expect(coordinator.toolsNavigationPath.isEmpty)

        // Push a subroute inside Tools, then tap `+` -> swaps directly to .general and clears toolsNavigationPath
        coordinator.pushToolsSubroute(.skillsCenter, reduceMotion: true)
        #expect(coordinator.toolsNavigationPath == [.skillsCenter])

        coordinator.toggle(.general)
        #expect(coordinator.activePopup == .general)
        #expect(coordinator.dockState.mode == .general)
        #expect(coordinator.dockState.isExpanded)
        #expect(coordinator.toolsNavigationPath.isEmpty)

        // Tapping `+` again while .general is open collapses the dock
        coordinator.toggle(.general)
        #expect(coordinator.activePopup == nil)
        #expect(coordinator.dockState.mode == .collapsed)
        #expect(!coordinator.dockState.isExpanded)
        #expect(coordinator.dockState.lastExpandedMode == .general)
    }

    @Test("2.2 Direct 1-tap Tools button opens Tools root immediately from collapsed state")
    func directOneTapToolsOpensToolsRootImmediately() {
        let coordinator = HanlinComposerPopupCoordinator()
        coordinator.presentDirectTools()
        #expect(coordinator.activePopup == .tools)
        #expect(coordinator.dockState.mode == .tools)
        #expect(coordinator.dockState.lastExpandedMode == .tools)
        #expect(coordinator.toolsNavigationPath.isEmpty)

        // Tapping Tools again collapses and remembers .tools as lastExpandedMode for drawer handle tap
        coordinator.toggle(.tools)
        #expect(coordinator.dockState.mode == .collapsed)
        #expect(coordinator.dockState.lastExpandedMode == .tools)

        coordinator.dockState.handleDrawerHandleTap()
        #expect(coordinator.dockState.mode == .tools)
    }

    @Test("2.3 Opening Model Picker collapses any open dock drawer so only one surface is active")
    func modelPickerCollapsesDrawer() {
        let coordinator = HanlinComposerPopupCoordinator()
        coordinator.presentDirectTools()
        #expect(coordinator.dockState.mode == .tools)

        coordinator.toggle(.model)
        #expect(coordinator.activePopup == .model)
        #expect(coordinator.dockState.mode == .collapsed)
        #expect(!coordinator.dockState.isExpanded)
    }
}

// MARK: - 7A.3 CompactRecentConversationsTests

@MainActor
@Suite("7A.3 CompactRecentConversationsTests — Strictly 3 Most Recently Edited Saved Chats", .serialized)
struct CompactRecentConversationsTests {

    @Test("3.1 Selects at most 3 persisted chat records sorted strictly by lastEdited descending, ignoring isPinned")
    func selectsTopThreeByLastEditedIgnoringPinnedAndTemp() {
        let now = Date()
        let chatNewest = ChatRecords(
            id: UUID(),
            name: "Newest Unpinned",
            type: "chat",
            lastEdited: now,
            isPinned: false
        )
        let chatSecond = ChatRecords(
            id: UUID(),
            name: "Second Recent",
            type: "chat",
            lastEdited: now.addingTimeInterval(-60),
            isPinned: false
        )
        let chatThird = ChatRecords(
            id: UUID(),
            name: "Third Recent",
            type: "chat",
            lastEdited: now.addingTimeInterval(-120),
            isPinned: false
        )
        let chatOldPinned = ChatRecords(
            id: UUID(),
            name: "Old Pinned Thread",
            type: "chat",
            lastEdited: now.addingTimeInterval(-3600),
            isPinned: true
        )
        let tempID = UUID()
        let tempChat = ChatRecords(
            id: tempID,
            name: "Unsaved Temporary Chat",
            type: "chat",
            lastEdited: now.addingTimeInterval(60),
            isPinned: false
        )
        let nonChat = ChatRecords(
            id: UUID(),
            name: "Welcome Banner",
            type: "welcome",
            lastEdited: now.addingTimeInterval(120),
            isPinned: true
        )

        let recent = HanlinCompactRecentChats.recentConversations(
            from: [chatOldPinned, chatThird, tempChat, nonChat, chatNewest, chatSecond],
            temporaryChatIDs: [tempID]
        )

        #expect(recent.count == 3)
        #expect(recent.map { $0.name ?? "" } == [
            "Newest Unpinned",
            "Second Recent",
            "Third Recent"
        ])
    }
}

// MARK: - 7A.4 CompactChatRouteTests

@MainActor
@Suite("7A.4 CompactChatRouteTests — Width Threshold (< 640pt) & Workspace Route Identity", .serialized)
struct CompactChatRouteTests {

    @Test("4.1 Compact workspace activates on iPhone and narrow iPad (< 640pt), preserving SplitView on wide iPad (>= 640pt)")
    func compactWorkspaceThresholdMatchesSpec() {
        // iPhone always uses compact workspace
        #expect(HanlinCompactChatWorkspace.shouldUseCompactWorkspace(
            isPhoneIdiom: true,
            horizontalSizeClass: .compact,
            availableWidth: 393
        ))
        #expect(HanlinCompactChatWorkspace.shouldUseCompactWorkspace(
            isPhoneIdiom: true,
            horizontalSizeClass: .regular,
            availableWidth: 852
        ))

        // Narrow iPad (Slide Over / 1/3 Split View / narrow Stage Manager < 640pt) uses compact workspace
        #expect(HanlinCompactChatWorkspace.shouldUseCompactWorkspace(
            isPhoneIdiom: false,
            horizontalSizeClass: .compact,
            availableWidth: 320
        ))
        #expect(HanlinCompactChatWorkspace.shouldUseCompactWorkspace(
            isPhoneIdiom: false,
            horizontalSizeClass: .regular,
            availableWidth: 639.5
        ))

        // Wide iPad (>= 640pt with regular horizontalSizeClass) keeps NavigationSplitView
        #expect(!HanlinCompactChatWorkspace.shouldUseCompactWorkspace(
            isPhoneIdiom: false,
            horizontalSizeClass: .regular,
            availableWidth: 640
        ))
        #expect(!HanlinCompactChatWorkspace.shouldUseCompactWorkspace(
            isPhoneIdiom: false,
            horizontalSizeClass: .regular,
            availableWidth: 1024
        ))
    }

    @Test("4.2 Workspace route distinguishes .allConversations library (composer hidden) from .chat(UUID) (composer visible)")
    func workspaceRouteIdentity() {
        let idA = UUID()
        let idB = UUID()
        let routeLibrary = HanlinCompactWorkspaceRoute.allConversations
        let routeChatA = HanlinCompactWorkspaceRoute.chat(idA)
        let routeChatB = HanlinCompactWorkspaceRoute.chat(idB)

        #expect(routeLibrary != routeChatA)
        #expect(routeChatA != routeChatB)
        #expect(routeChatA == .chat(idA))

        #expect(HanlinCompactChatWorkspace.isComposerVisible(for: []))
        #expect(HanlinCompactChatWorkspace.isComposerVisible(for: [routeChatA]))
        #expect(!HanlinCompactChatWorkspace.isComposerVisible(for: [routeLibrary]))
        #expect(HanlinCompactChatWorkspace.isComposerVisible(for: [routeLibrary, routeChatA]))

        #expect(HanlinCompactChatWorkspace.activeComposerKey(for: []) == "new")
        #expect(HanlinCompactChatWorkspace.activeComposerKey(for: [routeChatA]) == idA.uuidString)
    }
}

// MARK: - 7A.5 ChatComposerSessionBridgeTests

@MainActor
@Suite("7A.5 ChatComposerSessionBridgeTests — Live Endpoint Registration, Stale Unregister Guard & Per-Chat Drafts", .serialized)
struct ChatComposerSessionBridgeTests {

    private static func makeTestEndpoint(
        sessionID: UUID,
        token: UUID = UUID(),
        isReadyToSend: Bool = true,
        message: Binding<String>,
        selectedImages: Binding<[UIImage]> = .constant([]),
        selectedDocumentURLs: Binding<[URL]> = .constant([]),
        ifSearch: Binding<Bool> = .constant(false),
        ifKnowledge: Binding<Bool> = .constant(false),
        ifThink: Binding<Bool> = .constant(false),
        thinkingLength: Binding<Int> = .constant(0),
        ifPlanning: Binding<Bool> = .constant(false),
        ifAudio: Binding<Bool> = .constant(false),
        ifToolUse: Binding<Bool> = .constant(false),
        onSendUser: @escaping () -> Void = {},
        onSendObserve: @escaping () -> Void = {},
        onCancel: @escaping () -> Void = {}
    ) -> HanlinActiveComposerSessionBridge.Endpoint {
        let record = ChatRecords(id: sessionID, name: "Test Chat", type: "chat", lastEdited: Date())
        let model = AllModels(name: "gpt-4o-mini", displayName: "GPT-4o Mini", position: 0, company: "OPENAI")
        return HanlinActiveComposerSessionBridge.Endpoint(
            sessionID: sessionID,
            registrationToken: token,
            isReadyToSend: isReadyToSend,
            chatRecord: record,
            modelTemp: [model],
            temporaryRecord: false,
            respondIndex: 0,
            selectedModelIndex: .constant(0),
            showScrollToBottomButton: .constant(false),
            needScrollToBottomButton: .constant(false),
            isMultiSelectMode: .constant(false),
            selectedMessageIDs: .constant([]),
            chatTemps: .constant([]),
            showTemperatureSlider: .constant(false),
            temperature: .constant(0.7),
            showTopPSlider: .constant(false),
            topP: .constant(0.95),
            showMaxTokensSlider: .constant(false),
            maxTokens: .constant(2048),
            showMaxMessagesNumSlider: .constant(false),
            maxMessagesNum: .constant(12),
            message: message,
            selectedImages: selectedImages,
            selectedDocumentURLs: selectedDocumentURLs,
            selectedURLs: .constant([]),
            selectedPrompts: .constant([]),
            showPhotoSourceOptions: .constant(false),
            showModelSuggestions: .constant(false),
            filteredModels: .constant([]),
            isResponding: .constant(false),
            isFeedBack: .constant(false),
            ifKnowledge: ifKnowledge,
            ifSearch: ifSearch,
            ifToolUse: ifToolUse,
            ifThink: ifThink,
            ifAudio: ifAudio,
            ifPlanning: ifPlanning,
            thinkingLength: thinkingLength,
            showKnowledgeAlert: .constant(false),
            knowledgeAlertMessage: .constant(""),
            showSearchAlert: .constant(false),
            selectedImageSize: .constant("1024x1024"),
            imageReversePrompt: .constant(""),
            onSelectModel: { _ in },
            onSendUser: onSendUser,
            onSendObserve: onSendObserve,
            onCancel: onCancel
        )
    }

    @Test("5.1 Registers, dispatches send/observe/cancel, and guards against stale unregister from previous ChatView")
    func endpointRegistrationAndStaleUnregisterGuard() {
        let bridge = HanlinActiveComposerSessionBridge()
        let chatA = UUID()
        let tokenA = UUID()
        let chatB = UUID()
        let tokenB = UUID()

        var sentUserA = 0
        var sentObserveA = 0
        var cancelledA = 0
        var textA = "Draft A"

        let endpointA = Self.makeTestEndpoint(
            sessionID: chatA,
            token: tokenA,
            message: Binding(get: { textA }, set: { textA = $0 }),
            onSendUser: { sentUserA += 1 },
            onSendObserve: { sentObserveA += 1 },
            onCancel: { cancelledA += 1 }
        )

        bridge.register(endpoint: endpointA)
        #expect(bridge.activeEndpoint?.sessionID == chatA)

        #expect(bridge.performSendUser(expectedSessionID: chatA))
        #expect(bridge.performSendObserve(expectedSessionID: chatA))
        #expect(bridge.performCancel(expectedSessionID: chatA))
        #expect(sentUserA == 1)
        #expect(sentObserveA == 1)
        #expect(cancelledA == 1)

        // Register chatB BEFORE chatA's onDisappear runs -> unregister(chatA) must NOT clear chatB
        var textB = "Draft B"
        let endpointB = Self.makeTestEndpoint(
            sessionID: chatB,
            token: tokenB,
            message: Binding(get: { textB }, set: { textB = $0 })
        )
        bridge.register(endpoint: endpointB)
        #expect(bridge.activeEndpoint?.sessionID == chatB)

        bridge.unregister(sessionID: chatA, token: tokenA)
        #expect(bridge.activeEndpoint?.sessionID == chatB)

        bridge.unregister(sessionID: chatB, token: tokenB)
        #expect(bridge.activeEndpoint == nil)
    }

    @Test("5.2 Per-chat draft snapshots isolate text, attachments, and toggles across Chat A and Chat B")
    func perChatDraftSnapshotsIsolateState() {
        let bridge = HanlinActiveComposerSessionBridge()
        let chatA = UUID()
        let chatB = UUID()
        let docURL = URL(fileURLWithPath: "/tmp/docA.txt")

        var textA = "Draft in A"
        var docsA = [docURL]
        var searchA = true
        let endpointA = Self.makeTestEndpoint(
            sessionID: chatA,
            message: Binding(get: { textA }, set: { textA = $0 }),
            selectedDocumentURLs: Binding(get: { docsA }, set: { docsA = $0 }),
            ifSearch: Binding(get: { searchA }, set: { searchA = $0 })
        )
        bridge.snapshotDraft(from: endpointA)

        var textB = "Draft in B"
        var knowledgeB = true
        let endpointB = Self.makeTestEndpoint(
            sessionID: chatB,
            message: Binding(get: { textB }, set: { textB = $0 }),
            ifKnowledge: Binding(get: { knowledgeB }, set: { knowledgeB = $0 })
        )
        bridge.snapshotDraft(from: endpointB)

        #expect(bridge.perChatDrafts[chatA]?.message == "Draft in A")
        #expect(bridge.perChatDrafts[chatA]?.selectedDocumentURLs == [docURL])
        #expect(bridge.perChatDrafts[chatA]?.ifSearch == true)

        #expect(bridge.perChatDrafts[chatB]?.message == "Draft in B")
        #expect(bridge.perChatDrafts[chatB]?.selectedDocumentURLs.isEmpty == true)
        #expect(bridge.perChatDrafts[chatB]?.ifKnowledge == true)

        // Restoring into a fresh Chat A endpoint restores Chat A's snapshot
        var restoredTextA = ""
        var restoredDocsA: [URL] = []
        var restoredSearchA = false
        let freshEndpointA = Self.makeTestEndpoint(
            sessionID: chatA,
            message: Binding(get: { restoredTextA }, set: { restoredTextA = $0 }),
            selectedDocumentURLs: Binding(get: { restoredDocsA }, set: { restoredDocsA = $0 }),
            ifSearch: Binding(get: { restoredSearchA }, set: { restoredSearchA = $0 })
        )
        bridge.register(endpoint: freshEndpointA)
        #expect(restoredTextA == "Draft in A")
        #expect(restoredDocsA == [docURL])
        #expect(restoredSearchA == true)
    }

    @Test("5.3 Out-of-order stale endpoint registration is rejected when expectedActiveSessionID does not match")
    func outOfOrderStaleRegistrationRejected() {
        let bridge = HanlinActiveComposerSessionBridge()
        let chatA = UUID()
        let chatB = UUID()
        bridge.expectedActiveSessionID = chatB

        var textA = "Stale A"
        let endpointA = Self.makeTestEndpoint(
            sessionID: chatA,
            message: Binding(get: { textA }, set: { textA = $0 })
        )
        bridge.register(endpoint: endpointA)
        #expect(bridge.activeEndpoint == nil)

        var textB = "Active B"
        let endpointB = Self.makeTestEndpoint(
            sessionID: chatB,
            message: Binding(get: { textB }, set: { textB = $0 })
        )
        bridge.register(endpoint: endpointB)
        #expect(bridge.activeEndpoint?.sessionID == chatB)
    }

    @Test("5.4 Layout mode transition guard preserves temporary chat state across width transitions")
    func layoutModeTransitionPreservesTemporaryChat() {
        let bridge = HanlinActiveComposerSessionBridge()
        let tempChatID = UUID()

        bridge.setTemporaryChat(true, for: tempChatID)
        #expect(bridge.isTemporaryChat(tempChatID))
        #expect(bridge.temporaryChatIDs.contains(tempChatID))

        bridge.beginLayoutModeTransition()
        #expect(bridge.isTransitioningLayoutMode == true)
        #expect(bridge.isTemporaryChat(tempChatID))

        bridge.endLayoutModeTransition()
        #expect(bridge.isTransitioningLayoutMode == false)
        #expect(bridge.isTemporaryChat(tempChatID))

        bridge.clearCachedDraft(for: tempChatID)
        #expect(!bridge.isTemporaryChat(tempChatID))
    }
}

// MARK: - 7A.6 PendingFirstTurnTests

@MainActor
@Suite("7A.6 PendingFirstTurnTests — Home First-Send State Machine & Cancellation", .serialized)
struct PendingFirstTurnTests {

    @Test("6.1 Sending from Home creates chat, transitions to .awaitingEndpoint, and dispatches once ChatView registers")
    func homeFirstTurnDispatchesOnEndpointRegistration() {
        let bridge = HanlinActiveComposerSessionBridge()
        bridge.homeMessage = "Hello from compact Home"
        let createdChatID = UUID()
        let model = AllModels(name: "gpt-4o-mini", displayName: "GPT-4o Mini", position: 0, company: "OPENAI")

        let returnedID = bridge.beginHomeFirstTurn(availableModels: [model]) {
            ChatRecords(id: createdChatID, name: "New Chat", type: "chat", lastEdited: Date())
        }
        #expect(returnedID == createdChatID)
        #expect(bridge.homeMessage.isEmpty)
        #expect(bridge.pendingFirstTurn?.targetChatID == createdChatID)
        #expect(bridge.pendingFirstTurn?.status == .awaitingEndpoint(targetChatID: createdChatID))
        #expect(bridge.pendingFirstTurn?.isPendingHandoff == true)

        var transferredText = ""
        var userSendDispatched = 0
        let record = ChatRecords(id: createdChatID, name: "New Chat", type: "chat", lastEdited: Date())
        let endpoint = HanlinActiveComposerSessionBridge.Endpoint(
            sessionID: createdChatID,
            registrationToken: UUID(),
            isReadyToSend: true,
            chatRecord: record,
            modelTemp: [model],
            temporaryRecord: false,
            respondIndex: 0,
            selectedModelIndex: .constant(0),
            showScrollToBottomButton: .constant(false),
            needScrollToBottomButton: .constant(false),
            isMultiSelectMode: .constant(false),
            selectedMessageIDs: .constant([]),
            chatTemps: .constant([]),
            showTemperatureSlider: .constant(false),
            temperature: .constant(0.7),
            showTopPSlider: .constant(false),
            topP: .constant(0.95),
            showMaxTokensSlider: .constant(false),
            maxTokens: .constant(2048),
            showMaxMessagesNumSlider: .constant(false),
            maxMessagesNum: .constant(12),
            message: Binding(get: { transferredText }, set: { transferredText = $0 }),
            selectedImages: .constant([]),
            selectedDocumentURLs: .constant([]),
            selectedURLs: .constant([]),
            selectedPrompts: .constant([]),
            showPhotoSourceOptions: .constant(false),
            showModelSuggestions: .constant(false),
            filteredModels: .constant([]),
            isResponding: .constant(false),
            isFeedBack: .constant(false),
            ifKnowledge: .constant(false),
            ifSearch: .constant(false),
            ifToolUse: .constant(false),
            ifThink: .constant(false),
            ifAudio: .constant(false),
            ifPlanning: .constant(false),
            thinkingLength: .constant(0),
            showKnowledgeAlert: .constant(false),
            knowledgeAlertMessage: .constant(""),
            showSearchAlert: .constant(false),
            selectedImageSize: .constant("1024x1024"),
            imageReversePrompt: .constant(""),
            onSelectModel: { _ in },
            onSendUser: { userSendDispatched += 1 },
            onSendObserve: {},
            onCancel: {}
        )

        bridge.register(endpoint: endpoint)
        #expect(transferredText == "Hello from compact Home")
        #expect(userSendDispatched == 1)
        #expect(bridge.pendingFirstTurn?.status == .dispatched(targetChatID: createdChatID))
        #expect(bridge.pendingFirstTurn?.isPendingHandoff == false)
    }

    @Test("6.2 Cancelling pending first turn before endpoint registration prevents late execution")
    func cancellingPendingFirstTurnPreventsExecution() {
        let bridge = HanlinActiveComposerSessionBridge()
        bridge.homeMessage = "Cancel before mount"
        let createdChatID = UUID()
        let model = AllModels(name: "gpt-4o-mini", displayName: "GPT-4o Mini", position: 0, company: "OPENAI")

        _ = bridge.beginHomeFirstTurn(availableModels: [model]) {
            ChatRecords(id: createdChatID, name: "New Chat", type: "chat", lastEdited: Date())
        }
        #expect(bridge.pendingFirstTurn?.isPendingHandoff == true)

        bridge.cancelPendingFirstTurn()
        #expect(bridge.pendingFirstTurn?.status == .cancelled(reason: "Cancelled by navigation"))
        #expect(bridge.pendingFirstTurn?.isPendingHandoff == false)
        #expect(bridge.homeMessage == "Cancel before mount")
    }

    @Test("6.3 Rejected send rolls back to .failed and restores all Home draft fields including URLs and mode flags")
    func rejectedSendRollsBackAndRestoresHomeDraft() {
        let bridge = HanlinActiveComposerSessionBridge()
        bridge.homeMessage = "Recoverable Home Turn"
        bridge.homeSelectedURLs = ["https://example.com/spec"]
        bridge.homeSelectedDocumentURLs = [URL(fileURLWithPath: "/tmp/spec.pdf")]
        bridge.homeIfSearch = true
        bridge.homeIfThink = true
        let createdChatID = UUID()
        let model = AllModels(name: "gpt-4o-mini", displayName: "GPT-4o Mini", position: 0, company: "OPENAI")

        let returnedID = bridge.beginHomeFirstTurn(availableModels: [model]) {
            ChatRecords(id: createdChatID, name: "New Chat", type: "chat", lastEdited: Date())
        }
        #expect(returnedID == createdChatID)
        #expect(bridge.homeMessage.isEmpty)
        #expect(bridge.homeSelectedURLs.isEmpty)

        var transferredText = ""
        let record = ChatRecords(id: createdChatID, name: "New Chat", type: "chat", lastEdited: Date())
        let rejectingEndpoint = HanlinActiveComposerSessionBridge.Endpoint(
            sessionID: createdChatID,
            registrationToken: UUID(),
            isReadyToSend: true,
            chatRecord: record,
            modelTemp: [model],
            temporaryRecord: false,
            respondIndex: 0,
            selectedModelIndex: .constant(0),
            showScrollToBottomButton: .constant(false),
            needScrollToBottomButton: .constant(false),
            isMultiSelectMode: .constant(false),
            selectedMessageIDs: .constant([]),
            chatTemps: .constant([]),
            showTemperatureSlider: .constant(false),
            temperature: .constant(0.7),
            showTopPSlider: .constant(false),
            topP: .constant(0.95),
            showMaxTokensSlider: .constant(false),
            maxTokens: .constant(2048),
            showMaxMessagesNumSlider: .constant(false),
            maxMessagesNum: .constant(12),
            message: Binding(get: { transferredText }, set: { transferredText = $0 }),
            selectedImages: .constant([]),
            selectedDocumentURLs: .constant([]),
            selectedURLs: .constant([]),
            selectedPrompts: .constant([]),
            showPhotoSourceOptions: .constant(false),
            showModelSuggestions: .constant(false),
            filteredModels: .constant([]),
            isResponding: .constant(false),
            isFeedBack: .constant(false),
            ifKnowledge: .constant(false),
            ifSearch: .constant(false),
            ifToolUse: .constant(false),
            ifThink: .constant(false),
            ifAudio: .constant(false),
            ifPlanning: .constant(false),
            thinkingLength: .constant(0),
            showKnowledgeAlert: .constant(false),
            knowledgeAlertMessage: .constant(""),
            showSearchAlert: .constant(false),
            selectedImageSize: .constant("1024x1024"),
            imageReversePrompt: .constant(""),
            onSelectModel: { _ in },
            onSendUser: {},
            onSendObserve: {},
            onCancel: {},
            validateSendAcceptance: { false }
        )

        bridge.register(endpoint: rejectingEndpoint)
        #expect(bridge.pendingFirstTurn?.status == .failed(reason: "Target ChatView rejected first-turn send."))
        #expect(bridge.pendingFirstTurn?.isAccepted == false)
        #expect(bridge.homeMessage == "Recoverable Home Turn")
        #expect(bridge.homeSelectedURLs == ["https://example.com/spec"])
        #expect(bridge.homeSelectedDocumentURLs == [URL(fileURLWithPath: "/tmp/spec.pdf")])
        #expect(bridge.homeIfSearch == true)
        #expect(bridge.homeIfThink == true)
    }

    @Test("6.4 Invalid or hidden homeSelectedModelIndex is strictly refused without silent fallback")
    func invalidHomeSelectedModelIndexRefused() {
        let bridge = HanlinActiveComposerSessionBridge()
        bridge.homeMessage = "Should not silently switch model"
        bridge.homeSelectedModelIndex = 5 // Out of bounds
        let model = AllModels(name: "gpt-4o-mini", displayName: "GPT-4o Mini", position: 0, company: "OPENAI")

        let returnedID = bridge.beginHomeFirstTurn(availableModels: [model]) {
            ChatRecords(id: UUID(), name: "New Chat", type: "chat", lastEdited: Date())
        }
        #expect(returnedID == nil)
        #expect(bridge.homeMessage == "Should not silently switch model")
        #expect(bridge.pendingFirstTurn == nil)
    }
}

// MARK: - 7A.7 ModelPopoverZoomOrderTests

@MainActor
@Suite("7A.7 ModelPopoverZoomOrderTests — Expand First, Push All Models Only On Completion", .serialized)
struct ModelPopoverZoomOrderTests {

    @Test("A dismissed presentation cannot alter a reopened popover's pending expansion")
    func staleCompletionCannotEndNewExpansion() {
        let coordinator = HanlinComposerPopupCoordinator()
        coordinator.deferAnimationCompletionsForTesting = true
        coordinator.toggle(.model)
        coordinator.pushModelSubroute()
        coordinator.closeAll()
        coordinator.toggle(.model)
        coordinator.pushModelSubroute()

        coordinator.flushPendingAnimationCompletions(firstOnly: true)
        #expect(coordinator.isModelAnimatingExpand)
        #expect(coordinator.modelNavigationPath.isEmpty)
        coordinator.flushPendingAnimationCompletions()
        #expect(!coordinator.isModelAnimatingExpand)
        #expect(coordinator.modelNavigationPath == [.allModels])
    }

    @Test("Popover dimensions remain inside narrow and short measured containers")
    func popoverFitsSmallContainer() {
        let coordinator = HanlinComposerPopupCoordinator()
        let target = CGSize(width: 344, height: 472)
        #expect(coordinator.responsiveSize(target: target,
            availableContainerSize: CGSize(width: 220, height: 220)) == CGSize(width: 200, height: 192))
        #expect(coordinator.responsiveSize(target: target,
            availableContainerSize: CGSize(width: 500, height: 400)) == CGSize(width: 344, height: 372))
        #expect(coordinator.responsiveSize(target: target,
            availableContainerSize: CGSize(width: 1024, height: 768)) == target)
    }

    @Test("7.1 pushModelSubroute(.allModels) expands popover FIRST and appends .allModels ONLY in completion handler")
    func expandFirstThenPushAllModelsInCompletion() {
        let coordinator = HanlinComposerPopupCoordinator()
        coordinator.deferAnimationCompletionsForTesting = true

        coordinator.toggle(.model)
        #expect(coordinator.activePopup == .model)
        #expect(!coordinator.modelFrameExpanded)
        #expect(coordinator.modelNavigationPath.isEmpty)

        // Trigger All Models transition with reduceMotion = false
        coordinator.pushModelSubroute(.allModels, reduceMotion: false)

        // Immediately after call: popover MUST be expanded, but .allModels MUST NOT be in modelNavigationPath yet!
        #expect(coordinator.modelFrameExpanded == true)
        #expect(coordinator.modelNavigationPath.isEmpty)

        // Once the expansion animation completion fires, .allModels is appended so matched zoom runs in expanded bounds
        coordinator.flushPendingAnimationCompletions()
        #expect(coordinator.modelNavigationPath == [.allModels])
    }

    @Test("7.2 Generation token cancels stale completion if popover is dismissed or popped mid-animation")
    func generationTokenCancelsStaleCompletion() {
        let coordinator = HanlinComposerPopupCoordinator()
        coordinator.deferAnimationCompletionsForTesting = true

        coordinator.toggle(.model)
        coordinator.pushModelSubroute(.allModels, reduceMotion: false)
        #expect(coordinator.modelFrameExpanded)
        #expect(coordinator.modelNavigationPath.isEmpty)

        // Dismiss before completion fires
        coordinator.closeAll()
        coordinator.flushPendingAnimationCompletions()

        // Stale completion must NOT append .allModels
        #expect(coordinator.modelNavigationPath.isEmpty)
        #expect(!coordinator.modelFrameExpanded)
    }

    @Test("7.3 With Reduce Motion enabled, expansion and .allModels navigation happen immediately")
    func reduceMotionNavigatesImmediately() {
        let coordinator = HanlinComposerPopupCoordinator()
        coordinator.toggle(.model)
        coordinator.pushModelSubroute(.allModels, reduceMotion: true)
        #expect(coordinator.modelFrameExpanded)
        #expect(coordinator.modelNavigationPath == [.allModels])

        coordinator.popModelToRoot()
        coordinator.markModelDestinationDisappeared(reduceMotion: true)
        #expect(!coordinator.modelFrameExpanded)
        #expect(coordinator.modelNavigationPath.isEmpty)
    }
}

// MARK: - 7A.8 ComposerActionsParityTests

@MainActor
@Suite("7A.8 ComposerActionsParityTests — Capability Truth Table & Classic Badge/Chip Parity", .serialized)
struct ComposerActionsParityTests {

    @Test("8.1 Capability snapshot and active mode chips use classic hammer.fill and truthful counts")
    func capabilityAndChipsUseClassicVocabulary() {
        let model = AllModels(
            name: "gpt-4o-mini",
            displayName: "GPT-4o Mini",
            position: 0,
            company: "OPENAI",
            supportsSearch: true,
            supportsTextGen: true,
            supportsMultimodal: true,
            supportsReasoning: true,
            supportReasoningChange: true,
            supportsToolUse: true
        )
        let cap = HanlinComposerActionBridge.capabilitySnapshot(for: model)
        #expect(cap.hasModel)
        #expect(cap.supportsSearch)
        #expect(cap.supportsToolUse)
        #expect(cap.supportsThinkingLengthMenu)

        let chips = HanlinComposerActionBridge.activeModeChips(
            capability: cap,
            ifSearch: true,
            ifKnowledge: false,
            ifThink: true,
            thinkingLength: 2,
            ifPlanning: false,
            ifAudio: false,
            ifToolUse: true,
            activeMCPServerCount: 2,
            selectedImageSize: "1024x1024"
        )
        let toolsChip = chips.first { $0.kind == .tools }
        #expect(toolsChip != nil)
        #expect(toolsChip?.systemImage == "hammer.fill")

        let shortcutCount = HanlinComposerActionBridge.activeToolsShortcutCount(
            capability: cap,
            ifToolUse: true,
            activeMCPServerCount: 2
        )
        #expect(shortcutCount == 3)
    }
}

// MARK: - 7A.9 OriginalSourceNonRegressionTests

@MainActor
@Suite("7A.9 OriginalSourceNonRegressionTests — Untouched Classic Chat Bubbles & Components", .serialized)
struct OriginalSourceNonRegressionTests {

    @Test("9.1 ChatViewComponents.swift and ChatandFile.swift retain all original bubble identifiers")
    func chatViewComponentsAndChatAndFileRetainOriginalIdentifiers() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let componentsURL = repoRoot.appendingPathComponent("AI_HLY/Views/Components/ChatViewComponents.swift")
        let chatAndFileURL = repoRoot.appendingPathComponent("AI_HLY/Views/Components/ChatandFile.swift")

        let componentsSource = try String(contentsOf: componentsURL, encoding: .utf8)
        let chatAndFileSource = try String(contentsOf: chatAndFileURL, encoding: .utf8)

        #expect(componentsSource.contains("hanlin-user-bubble"))
        #expect(componentsSource.contains("hanlin-assistant-bubble"))
        #expect(componentsSource.contains("hanlin-search-bubble"))
        #expect(componentsSource.contains("hanlin-info-bubble"))
        #expect(componentsSource.contains("hanlin-action-buttons-row"))
        #expect(componentsSource.contains("hanlin-code-block-row"))
        #expect(componentsSource.contains("hanlin-html-web-bubble"))
        #expect(!chatAndFileSource.isEmpty)
    }

    @Test("9.2 Protected chat files and authoritative V3.3 reference metadata remain cryptographically intact")
    func protectedFilesAndReferenceMetadataRemainIntact() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        func normalizedSHA256AndLength(relativePath: String) throws -> (String, Int) {
            let url = repoRoot.appendingPathComponent(relativePath)
            let raw = try Data(contentsOf: url)
            let normalized = String(decoding: raw, as: UTF8.self)
                .replacingOccurrences(of: "\r\n", with: "\n")
            let data = Data(normalized.utf8)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return (digest, data.count)
        }

        let (componentsSHA, componentsBytes) = try normalizedSHA256AndLength(
            relativePath: "AI_HLY/Views/Components/ChatViewComponents.swift"
        )
        let (chatAndFileSHA, chatAndFileBytes) = try normalizedSHA256AndLength(
            relativePath: "AI_HLY/Views/Components/ChatandFile.swift"
        )
        let (apiManagerSHA, apiManagerBytes) = try normalizedSHA256AndLength(
            relativePath: "AI_HLY/Services/ChatServices/APIManager.swift"
        )

        #expect(componentsBytes == 245684)
        #expect(componentsSHA == "cbcbdffd5a05abe6889b9eafe83a5266661f61c6440c6e12ac74be4565ba1901")
        #expect(chatAndFileBytes == 1966)
        #expect(chatAndFileSHA == "3260125c5dece237c8775806b21c470275c9cb5a88328fa6fba2f283c8f3e26d")
        #expect(apiManagerBytes == 197303)
        #expect(apiManagerSHA == "ec09f12217985b6f37e9f88ea6653eff2823a31f96a9eb0ad6fe1062ea204df4")

        let sourceRefURL = repoRoot.appendingPathComponent("docs/hanlin-dock-v33-source-parity/SOURCE_REFERENCE_AND_SHA.md")
        let sourceRefText = try String(contentsOf: sourceRefURL, encoding: .utf8)
        #expect(sourceRefText.contains("8611c6f7f537296f6ddc365b349f4bf773c2de70728183a94c75ea5731705723"))
        #expect(sourceRefText.contains("9d9ebe09a5f2ec6c590b7ad52cc15db6c967951acca6be42e9044623c642a716"))
        #expect(sourceRefText.contains("1,810") || sourceRefText.contains("1810"))
    }
}
