//
//  HanlinOrganizerDockParityTests.swift
//  AI_HLYTests
//
//  Comprehensive unit test suites (§7A.1 – §7A.9) verifying the source-faithful
//  InteriorOrganizer V3.3 OrganizerDock, compact recent chats, zoom transitions,
//  session bridge, pending first turn state machine, and non-regression of original chat files.
//

import Foundation
import SwiftUI
import SwiftData
import Testing
@testable import AI_Hanlin

// MARK: - 7A.1 OrganizerDockStateTests

@MainActor
@Suite("7A.1 OrganizerDockState — Source Height Formulas, Drag & Resize Thresholds", .serialized)
struct OrganizerDockStateTests {

    @Test("1.1 Default collapsed state matches InteriorOrganizerV3_3 formulas (92pt composer, 132pt panel, 120pt editorMax)")
    func defaultCollapsedStateMatchesSourceFormulas() {
        let state = HanlinOrganizerDockState()
        #expect(state.mode == .collapsed)
        #expect(state.lastExpandedMode == .general)
        #expect(!state.isExpanded)
        #expect(state.draftLineCount == 1)
        #expect(state.autoComposerHeight == 92)
        #expect(state.maxComposerHeight == 334)
        #expect(state.composerHeight == 92)
        #expect(state.panelHeight == 132) // 92 + 40
        #expect(state.editorMaxHeight == 120) // max(120, 92 - 40)
    }

    @Test("1.2 Multiline draft growth (up to 4 lines at +20pt/line) and attachment strip offset (+44pt)")
    func multilineDraftAndAttachmentHeightFormulas() {
        let state = HanlinOrganizerDockState()
        state.updateDraftMetrics(text: "Line 1\nLine 2\nLine 3", hasAttachments: false)
        #expect(state.draftLineCount == 3)
        #expect(state.autoComposerHeight == 132) // 92 + 2 * 20
        #expect(state.composerHeight == 132)
        #expect(state.panelHeight == 172) // 132 + 40

        // 6 lines clamps to max 4 lines in autoComposerHeight
        state.updateDraftMetrics(text: "1\n2\n3\n4\n5\n6", hasAttachments: true)
        #expect(state.draftLineCount == 6)
        #expect(state.autoComposerHeight == 196) // 92 + 3 * 20 + 44
        #expect(state.composerHeight == 196)
        #expect(state.panelHeight == 236) // 196 + 40
        #expect(state.editorMaxHeight == 120) // max(120, 196 - 84 = 112) -> 120
    }

    @Test("1.3 Expanded state clamps maxComposerHeight to 244 and sets panelHeight to composerHeight + 356")
    func expandedStatePanelAndMaxComposerHeight() {
        let state = HanlinOrganizerDockState()
        state.manualComposerHeight = 320
        #expect(state.composerHeight == 320)
        #expect(state.editorMaxHeight == 280) // max(120, 320 - 40)

        state.setMode(.general)
        #expect(state.isExpanded)
        #expect(state.maxComposerHeight == 244)
        #expect(state.composerHeight == 244) // clamped from 320 to 244 while expanded
        #expect(state.panelHeight == 600) // 244 + 356
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

    @Test("1.5 Composer resize handle drag and +/-72pt accessibility step with snap-to-auto (< 8pt)")
    func composerResizeDragAndAccessibilityAdjustment() {
        let state = HanlinOrganizerDockState()
        #expect(state.composerHeight == 92)

        // Drag up by 60pt -> composerHeight becomes 152pt
        state.handleComposerResizeChanged(translationHeight: -60)
        #expect(state.composerHeight == 152)
        #expect(state.editorMaxHeight == 120) // max(120, 152 - 40 = 112)

        // Drag up by 120pt from base 152 after end
        state.handleComposerResizeEnded()
        #expect(state.composerResizeDragBase == 0)

        // Accessibility increment (+72pt)
        state.adjustComposerHeightByAccessibility(increment: true)
        #expect(state.composerHeight == 224) // 152 + 72
        #expect(state.editorMaxHeight == 184) // 224 - 40

        // Accessibility decrement (-72pt twice back toward 92pt)
        state.adjustComposerHeightByAccessibility(increment: false)
        #expect(state.composerHeight == 152)
        state.adjustComposerHeightByAccessibility(increment: false)
        #expect(state.composerHeight == 92)
        #expect(state.manualComposerHeight == 0)
    }

    @Test("1.6 Input focus and draft sent / context change reset drawer and manual heights")
    func focusAndLifecycleResets() {
        let state = HanlinOrganizerDockState()
        state.setMode(.general)
        state.manualComposerHeight = 220

        // Focusing input collapses drawer automatically
        state.handleInputFocusChanged(true)
        #expect(state.mode == .collapsed)
        #expect(state.manualComposerHeight == 220)

        // Sending draft resets manual height and collapses drawer
        state.setMode(.tools)
        state.resetForDraftSent()
        #expect(state.mode == .collapsed)
        #expect(state.manualComposerHeight == 0)
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
        coordinator.toggleGeneralMenu()
        #expect(coordinator.activePopup == .general)
        #expect(coordinator.dockState.mode == .general)
        #expect(coordinator.dockState.isExpanded)

        // Push a subroute inside General, then tap Tools -> swaps directly to .tools and clears generalPath
        coordinator.pushGeneralSubroute(.prompts)
        #expect(coordinator.generalPath == [.prompts])

        coordinator.toggleToolsMenu()
        #expect(coordinator.activePopup == .tools)
        #expect(coordinator.dockState.mode == .tools)
        #expect(coordinator.dockState.isExpanded)
        #expect(coordinator.generalPath.isEmpty)
        #expect(coordinator.toolsPath.isEmpty)

        // Push a subroute inside Tools, then tap `+` -> swaps directly to .general and clears toolsPath
        coordinator.pushToolsSubroute(.skills)
        #expect(coordinator.toolsPath == [.skills])

        coordinator.toggleGeneralMenu()
        #expect(coordinator.activePopup == .general)
        #expect(coordinator.dockState.mode == .general)
        #expect(coordinator.dockState.isExpanded)
        #expect(coordinator.toolsPath.isEmpty)

        // Tapping `+` again while .general is open collapses the dock
        coordinator.toggleGeneralMenu()
        #expect(coordinator.activePopup == nil)
        #expect(coordinator.dockState.mode == .collapsed)
        #expect(!coordinator.dockState.isExpanded)
        #expect(coordinator.dockState.lastExpandedMode == .general)
    }

    @Test("2.2 Direct 1-tap Tools button opens Tools root immediately from collapsed state")
    func directOneTapToolsOpensToolsRootImmediately() {
        let coordinator = HanlinComposerPopupCoordinator()
        coordinator.toggleToolsMenu()
        #expect(coordinator.activePopup == .tools)
        #expect(coordinator.dockState.mode == .tools)
        #expect(coordinator.dockState.lastExpandedMode == .tools)
        #expect(coordinator.toolsPath.isEmpty)

        // Tapping Tools again collapses and remembers .tools as lastExpandedMode for drawer handle tap
        coordinator.toggleToolsMenu()
        #expect(coordinator.dockState.mode == .collapsed)
        #expect(coordinator.dockState.lastExpandedMode == .tools)

        coordinator.dockState.handleDrawerHandleTap()
        #expect(coordinator.dockState.mode == .tools)
    }

    @Test("2.3 Opening Model Picker collapses any open dock drawer so only one surface is active")
    func modelPickerCollapsesDrawer() {
        let coordinator = HanlinComposerPopupCoordinator()
        coordinator.toggleToolsMenu()
        #expect(coordinator.dockState.mode == .tools)

        coordinator.toggleModelPicker()
        #expect(coordinator.activePopup == .modelPicker)
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
        #expect(HanlinCompactChatWorkspace.shouldUseCompactWorkspace(availableWidth: 393, isPad: false))
        #expect(HanlinCompactChatWorkspace.shouldUseCompactWorkspace(availableWidth: 852, isPad: false))

        // Narrow iPad (Slide Over / 1/3 Split View / narrow Stage Manager < 640pt) uses compact workspace
        #expect(HanlinCompactChatWorkspace.shouldUseCompactWorkspace(availableWidth: 320, isPad: true))
        #expect(HanlinCompactChatWorkspace.shouldUseCompactWorkspace(availableWidth: 639.5, isPad: true))

        // Wide iPad (>= 640pt) keeps NavigationSplitView
        #expect(!HanlinCompactChatWorkspace.shouldUseCompactWorkspace(availableWidth: 640, isPad: true))
        #expect(!HanlinCompactChatWorkspace.shouldUseCompactWorkspace(availableWidth: 1024, isPad: true))
    }

    @Test("4.2 Workspace route distinguishes .allConversations library from .chat(UUID)")
    func workspaceRouteIdentity() {
        let idA = UUID()
        let idB = UUID()
        let routeLibrary = HanlinCompactWorkspaceRoute.allConversations
        let routeChatA = HanlinCompactWorkspaceRoute.chat(idA)
        let routeChatB = HanlinCompactWorkspaceRoute.chat(idB)

        #expect(routeLibrary != routeChatA)
        #expect(routeChatA != routeChatB)
        #expect(routeChatA == .chat(idA))
    }
}

// MARK: - 7A.5 ChatComposerSessionBridgeTests

@MainActor
@Suite("7A.5 ChatComposerSessionBridgeTests — Live Endpoint Registration, Stale Unregister Guard & Per-Chat Drafts", .serialized)
struct ChatComposerSessionBridgeTests {

    @Test("5.1 Registers, dispatches send/observe/cancel, and guards against stale unregister from previous ChatView")
    func endpointRegistrationAndStaleUnregisterGuard() {
        let bridge = HanlinActiveComposerSessionBridge()
        let chatA = UUID()
        let chatB = UUID()

        var sentUserA = 0
        var sentObserveA = 0
        var cancelledA = 0
        var textA = "Draft A"
        var imagesA: [UIImage] = []
        var docsA: [URL] = []
        var boolState = false
        var intState = 0
        var optIntState: Int? = nil
        var strState = "1024x1024"
        var modelA: AllModels? = nil

        let makeEndpoint = { (id: UUID, onUser: @escaping () -> Void, onObserve: @escaping () -> Void, onCancel: @escaping () -> Void) -> HanlinActiveComposerSessionBridge.Endpoint in
            HanlinActiveComposerSessionBridge.Endpoint(
                chatID: id,
                inputText: Binding(get: { textA }, set: { textA = $0 }),
                selectedImages: Binding(get: { imagesA }, set: { imagesA = $0 }),
                selectedDocumentURLs: Binding(get: { docsA }, set: { docsA = $0 }),
                ifSearch: Binding(get: { boolState }, set: { boolState = $0 }),
                ifKnowledge: Binding(get: { boolState }, set: { boolState = $0 }),
                ifThink: Binding(get: { boolState }, set: { boolState = $0 }),
                thinkingLength: Binding(get: { intState }, set: { intState = $0 }),
                ifPlanning: Binding(get: { boolState }, set: { boolState = $0 }),
                ifAudio: Binding(get: { boolState }, set: { boolState = $0 }),
                ifToolUse: Binding(get: { boolState }, set: { boolState = $0 }),
                temporaryRecord: Binding(get: { boolState }, set: { boolState = $0 }),
                isResponding: Binding(get: { boolState }, set: { boolState = $0 }),
                currentModel: Binding(get: { modelA }, set: { modelA = $0 }),
                selectedImageSize: Binding(get: { strState }, set: { strState = $0 }),
                currentAspectRatioIndex: Binding(get: { intState }, set: { intState = $0 }),
                locationText: Binding(get: { nil }, set: { _ in }),
                chooseModelSheet: Binding(get: { boolState }, set: { boolState = $0 }),
                showKnowledgeAlert: Binding(get: { boolState }, set: { boolState = $0 }),
                showSearchAlert: Binding(get: { boolState }, set: { boolState = $0 }),
                showReasoningAlert: Binding(get: { boolState }, set: { boolState = $0 }),
                showLanAlert: Binding(get: { boolState }, set: { boolState = $0 }),
                showModelPicker: Binding(get: { boolState }, set: { boolState = $0 }),
                showPromptSelector: Binding(get: { boolState }, set: { boolState = $0 }),
                showPhotoPicker: Binding(get: { boolState }, set: { boolState = $0 }),
                showCameraSheet: Binding(get: { boolState }, set: { boolState = $0 }),
                showDocumentPicker: Binding(get: { boolState }, set: { boolState = $0 }),
                selectedQuickIndex: Binding(get: { optIntState }, set: { optIntState = $0 }),
                onSelectModel: { _ in },
                checkSearchAvailability: { true },
                checkEmbeddingAvailability: { true },
                onClearChat: {},
                onResetContext: {},
                onPolishInput: {},
                onSummarizeChat: {},
                onExportConversationText: {},
                onOpenEmbeddingSettings: {},
                onOpenMCPSettings: {},
                onOpenSkillsSettings: {},
                onOpenSystemPromptEditor: {},
                onOpenCanvas: {},
                sendUser: onUser,
                sendObserve: onObserve,
                cancelRun: onCancel
            )
        }

        bridge.register(makeEndpoint(chatA, { sentUserA += 1 }, { sentObserveA += 1 }, { cancelledA += 1 }))
        #expect(bridge.activeChatID == chatA)

        bridge.performSendUser(createChatFromHome: { nil })
        bridge.performSendObserve(createChatFromHome: { nil })
        bridge.performCancel()
        #expect(sentUserA == 1)
        #expect(sentObserveA == 1)
        #expect(cancelledA == 1)

        // Register chatB BEFORE chatA's onDisappear runs -> unregister(chatA) must NOT clear chatB
        bridge.register(makeEndpoint(chatB, {}, {}, {}))
        #expect(bridge.activeChatID == chatB)
        bridge.unregister(chatID: chatA)
        #expect(bridge.activeChatID == chatB)
        bridge.unregister(chatID: chatB)
        #expect(bridge.activeChatID == nil)
    }

    @Test("5.2 Per-chat draft snapshots isolate text, attachments, and toggles across Chat A and Chat B")
    func perChatDraftSnapshotsIsolateState() {
        let bridge = HanlinActiveComposerSessionBridge()
        let chatA = UUID()
        let chatB = UUID()
        let docURL = URL(fileURLWithPath: "/tmp/docA.txt")

        bridge.saveDraftSnapshot(
            HanlinChatDraftSnapshot(
                inputText: "Draft in A",
                selectedImages: [],
                selectedDocumentURLs: [docURL],
                ifSearch: true,
                ifKnowledge: false,
                ifThink: true,
                thinkingLength: 2,
                ifPlanning: false,
                ifAudio: false,
                ifToolUse: true,
                selectedImageSize: "1024x1024",
                currentAspectRatioIndex: 0,
                selectedModelID: "gpt-4o"
            ),
            for: chatA
        )
        bridge.saveDraftSnapshot(
            HanlinChatDraftSnapshot(
                inputText: "Draft in B",
                selectedImages: [],
                selectedDocumentURLs: [],
                ifSearch: false,
                ifKnowledge: true,
                ifThink: false,
                thinkingLength: 0,
                ifPlanning: true,
                ifAudio: false,
                ifToolUse: false,
                selectedImageSize: "1024x1024",
                currentAspectRatioIndex: 0,
                selectedModelID: "claude-sonnet"
            ),
            for: chatB
        )

        let restoredA = bridge.restoreDraftSnapshot(for: chatA)
        let restoredB = bridge.restoreDraftSnapshot(for: chatB)
        #expect(restoredA?.inputText == "Draft in A")
        #expect(restoredA?.selectedDocumentURLs == [docURL])
        #expect(restoredA?.ifSearch == true)
        #expect(restoredA?.selectedModelID == "gpt-4o")

        #expect(restoredB?.inputText == "Draft in B")
        #expect(restoredB?.selectedDocumentURLs.isEmpty == true)
        #expect(restoredB?.ifKnowledge == true)
        #expect(restoredB?.selectedModelID == "claude-sonnet")
    }
}

// MARK: - 7A.6 PendingFirstTurnTests

@MainActor
@Suite("7A.6 PendingFirstTurnTests — Home First-Send State Machine & Cancellation", .serialized)
struct PendingFirstTurnTests {

    @Test("6.1 Sending from Home creates chat, transitions to .awaitingEndpoint, and dispatches once ChatView registers")
    func homeFirstTurnDispatchesOnEndpointRegistration() {
        let bridge = HanlinActiveComposerSessionBridge()
        bridge.homeInputText = "Hello from compact Home"
        let createdChatID = UUID()

        let returnedID = bridge.beginHomeFirstTurn(mode: .userMessage) {
            createdChatID
        }
        #expect(returnedID == createdChatID)
        #expect(bridge.homeInputText.isEmpty)
        #expect(bridge.pendingFirstTurn?.chatID == createdChatID)
        #expect(bridge.pendingFirstTurn?.state == .awaitingEndpoint)

        var transferredText = ""
        var userSendDispatched = 0
        var boolState = false
        var intState = 0
        var optIntState: Int? = nil
        var strState = "1024x1024"
        var imgs: [UIImage] = []
        var docs: [URL] = []
        var model: AllModels? = nil

        let endpoint = HanlinActiveComposerSessionBridge.Endpoint(
            chatID: createdChatID,
            inputText: Binding(get: { transferredText }, set: { transferredText = $0 }),
            selectedImages: Binding(get: { imgs }, set: { imgs = $0 }),
            selectedDocumentURLs: Binding(get: { docs }, set: { docs = $0 }),
            ifSearch: Binding(get: { boolState }, set: { boolState = $0 }),
            ifKnowledge: Binding(get: { boolState }, set: { boolState = $0 }),
            ifThink: Binding(get: { boolState }, set: { boolState = $0 }),
            thinkingLength: Binding(get: { intState }, set: { intState = $0 }),
            ifPlanning: Binding(get: { boolState }, set: { boolState = $0 }),
            ifAudio: Binding(get: { boolState }, set: { boolState = $0 }),
            ifToolUse: Binding(get: { boolState }, set: { boolState = $0 }),
            temporaryRecord: Binding(get: { boolState }, set: { boolState = $0 }),
            isResponding: Binding(get: { boolState }, set: { boolState = $0 }),
            currentModel: Binding(get: { model }, set: { model = $0 }),
            selectedImageSize: Binding(get: { strState }, set: { strState = $0 }),
            currentAspectRatioIndex: Binding(get: { intState }, set: { intState = $0 }),
            locationText: Binding(get: { nil }, set: { _ in }),
            chooseModelSheet: Binding(get: { boolState }, set: { boolState = $0 }),
            showKnowledgeAlert: Binding(get: { boolState }, set: { boolState = $0 }),
            showSearchAlert: Binding(get: { boolState }, set: { boolState = $0 }),
            showReasoningAlert: Binding(get: { boolState }, set: { boolState = $0 }),
            showLanAlert: Binding(get: { boolState }, set: { boolState = $0 }),
            showModelPicker: Binding(get: { boolState }, set: { boolState = $0 }),
            showPromptSelector: Binding(get: { boolState }, set: { boolState = $0 }),
            showPhotoPicker: Binding(get: { boolState }, set: { boolState = $0 }),
            showCameraSheet: Binding(get: { boolState }, set: { boolState = $0 }),
            showDocumentPicker: Binding(get: { boolState }, set: { boolState = $0 }),
            selectedQuickIndex: Binding(get: { optIntState }, set: { optIntState = $0 }),
            onSelectModel: { _ in },
            checkSearchAvailability: { true },
            checkEmbeddingAvailability: { true },
            onClearChat: {},
            onResetContext: {},
            onPolishInput: {},
            onSummarizeChat: {},
            onExportConversationText: {},
            onOpenEmbeddingSettings: {},
            onOpenMCPSettings: {},
            onOpenSkillsSettings: {},
            onOpenSystemPromptEditor: {},
            onOpenCanvas: {},
            sendUser: { userSendDispatched += 1 },
            sendObserve: {},
            cancelRun: {}
        )

        bridge.register(endpoint)
        #expect(transferredText == "Hello from compact Home")
        #expect(userSendDispatched == 1)
        #expect(bridge.pendingFirstTurn == nil)
    }

    @Test("6.2 Cancelling pending first turn before endpoint registration prevents late execution")
    func cancellingPendingFirstTurnPreventsExecution() {
        let bridge = HanlinActiveComposerSessionBridge()
        bridge.homeInputText = "Cancel before mount"
        let createdChatID = UUID()

        _ = bridge.beginHomeFirstTurn(mode: .userMessage) { createdChatID }
        #expect(bridge.isAwaitingPendingFirstTurn)

        bridge.cancelPendingFirstTurn()
        #expect(!bridge.isAwaitingPendingFirstTurn)
        #expect(bridge.pendingFirstTurn == nil)
    }
}

// MARK: - 7A.7 ModelPopoverZoomOrderTests

@MainActor
@Suite("7A.7 ModelPopoverZoomOrderTests — Expand First, Push All Models Only On Completion", .serialized)
struct ModelPopoverZoomOrderTests {

    @Test("7.1 pushModelSubroute(.allModels) expands popover FIRST and appends .allModels ONLY in completion handler")
    func expandFirstThenPushAllModelsInCompletion() {
        let coordinator = HanlinComposerPopupCoordinator()
        coordinator.deferAnimationCompletionsForTesting = true

        coordinator.toggleModelPicker()
        #expect(coordinator.activePopup == .modelPicker)
        #expect(!coordinator.isModelPopoverExpanded)
        #expect(coordinator.modelPath.isEmpty)

        // Trigger All Models transition with reduceMotion = false
        coordinator.pushModelSubroute(.allModels, reduceMotion: false)

        // Immediately after call: popover MUST be expanded, but .allModels MUST NOT be in modelPath yet!
        #expect(coordinator.isModelPopoverExpanded == true)
        #expect(coordinator.modelPath.isEmpty)

        // Once the expansion animation completion fires, .allModels is appended so matched zoom runs in expanded bounds
        coordinator.flushPendingAnimationCompletions()
        #expect(coordinator.modelPath == [.allModels])
    }

    @Test("7.2 Generation token cancels stale completion if popover is dismissed or popped mid-animation")
    func generationTokenCancelsStaleCompletion() {
        let coordinator = HanlinComposerPopupCoordinator()
        coordinator.deferAnimationCompletionsForTesting = true

        coordinator.toggleModelPicker()
        coordinator.pushModelSubroute(.allModels, reduceMotion: false)
        #expect(coordinator.isModelPopoverExpanded)
        #expect(coordinator.modelPath.isEmpty)

        // Dismiss before completion fires
        coordinator.closeAll()
        coordinator.flushPendingAnimationCompletions()

        // Stale completion must NOT append .allModels
        #expect(coordinator.modelPath.isEmpty)
        #expect(!coordinator.isModelPopoverExpanded)
    }

    @Test("7.3 With Reduce Motion enabled, expansion and .allModels navigation happen immediately")
    func reduceMotionNavigatesImmediately() {
        let coordinator = HanlinComposerPopupCoordinator()
        coordinator.toggleModelPicker()
        coordinator.pushModelSubroute(.allModels, reduceMotion: true)
        #expect(coordinator.isModelPopoverExpanded)
        #expect(coordinator.modelPath == [.allModels])

        coordinator.popModelSubroute()
        #expect(!coordinator.isModelPopoverExpanded)
        #expect(coordinator.modelPath.isEmpty)
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
}
