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
import UIKit
#if canImport(HanlinAgentCore)
import HanlinAgentCore
#endif
@testable import AI_Hanlin

@Suite("Composer live refresh identity")
struct ComposerRefreshIdentityTests {
    @Test("Old chats, temporary sessions, revisions, configuration and cancellations cannot publish")
    func staleRequestsAreRejected() {
        let chat = UUID()
        let request = HanlinComposerRefreshContext(chatID: chat, temporary: false, selectionRevision: 7, globallyEnabled: true, serverStates: ["server:true"])
        #expect(request.canPublish(current: request, currentSelectionRevision: 7, isCancelled: false))
        #expect(!request.canPublish(current: request, currentSelectionRevision: 7, isCancelled: true))
        #expect(!request.canPublish(current: request, currentSelectionRevision: 8, isCancelled: false))
        #expect(!request.canPublish(current: nil, currentSelectionRevision: 7, isCancelled: false))
        let otherChat = HanlinComposerRefreshContext(chatID: UUID(), temporary: false, selectionRevision: 7, globallyEnabled: true, serverStates: ["server:true"])
        let temporary = HanlinComposerRefreshContext(chatID: chat, temporary: true, selectionRevision: 7, globallyEnabled: true, serverStates: ["server:true"])
        let disabled = HanlinComposerRefreshContext(chatID: chat, temporary: false, selectionRevision: 7, globallyEnabled: false, serverStates: ["server:true"])
        #expect(!request.canPublish(current: otherChat, currentSelectionRevision: 7, isCancelled: false))
        #expect(!request.canPublish(current: temporary, currentSelectionRevision: 7, isCancelled: false))
        #expect(!request.canPublish(current: disabled, currentSelectionRevision: 7, isCancelled: false))
    }
}

@MainActor
@Suite("Composer asynchronous selection publication")
struct ComposerSelectionRefreshTests {
    private enum ReadError: Error { case failed }
    private final class DelayedRead {
        var continuation: CheckedContinuation<Set<UUID>, Error>?
        func read() async throws -> Set<UUID> {
            try await withCheckedThrowingContinuation { continuation = $0 }
        }
    }

    private final class IntentDelay {
        var continuation: CheckedContinuation<Void, Never>?
        func wait() async { await withCheckedContinuation { continuation = $0 } }
    }

    @Test("Rapid UI server intents retain both selections after a delayed first action")
    func delayedUIToggleIntentsPreserveBothSelections() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hanlin-ui-intents-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let runtimeLayout = RuntimeFileLayout(root: root)
        let environment = RuntimeEnvironmentStore(fileLayout: runtimeLayout)
        let runtime = NodeRuntimeService(fileLayout: runtimeLayout, environment: environment)
        let layout = MCPFileLayout(root: root, legacyMigrationSource: nil)
        let store = MCPChatSelectionStore(fileLayout: layout)
        let provider = MCPRuntimeProvider(runtime: runtime, fileLayout: layout, runtimeEnvironment: environment, selectionStore: store)
        await provider.loadIfNeeded(startHost: false)
        let chatID = UUID(), firstID = UUID(), secondID = UUID()
        let delay = IntentDelay()
        let first = Task { @MainActor in
            await delay.wait()
            return try await HanlinComposerToolsRootView.applyServerSelection(provider: provider, serverID: firstID, isSelected: true, chatID: chatID, temporary: true)
        }
        while delay.continuation == nil { await Task.yield() }
        let second = Task { @MainActor in
            try await HanlinComposerToolsRootView.applyServerSelection(provider: provider, serverID: secondID, isSelected: true, chatID: chatID, temporary: true)
        }
        let secondResult = await second.result
        delay.continuation?.resume()
        let firstResult = await first.result
        _ = try secondResult.get()
        _ = try firstResult.get()
        #expect(try await provider.readSelection(chatID: chatID, temporary: true) == [firstID, secondID])
        #expect(try await store.selection(chatID: chatID, temporary: true) == [firstID, secondID])
    }

    @Test("A failed server intent remains visible after another server succeeds")
    func delayedFailureSurvivesOtherServerCommit() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("hanlin-ui-errors-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let runtimeLayout = RuntimeFileLayout(root: root)
        let environment = RuntimeEnvironmentStore(fileLayout: runtimeLayout)
        let runtime = NodeRuntimeService(fileLayout: runtimeLayout, environment: environment)
        let layout = MCPFileLayout(root: root, legacyMigrationSource: nil)
        let store = MCPChatSelectionStore(fileLayout: layout)
        let provider = MCPRuntimeProvider(runtime: runtime, fileLayout: layout, runtimeEnvironment: environment, selectionStore: store)
        await provider.loadIfNeeded(startHost: false)
        let scope = MCPChatSelectionScope(chatID: UUID(), temporary: true)
        let firstID = UUID(), secondID = UUID()
        let feedback = HanlinMCPIntentFeedback()
        var currentScope: MCPChatSelectionScope? = scope
        var displayed: Set<UUID> = []
        let delay = IntentDelay()
        let firstRequest = feedback.begin(serverID: firstID, scope: scope)
        let first = Task { @MainActor in
            await HanlinComposerToolsRootView.performServerSelection(
                serverID: firstID, isSelected: true, scope: scope, requestID: firstRequest,
                feedback: feedback, isCurrentScope: { currentScope == scope },
                apply: { await delay.wait(); throw ReadError.failed },
                read: { try await provider.readSelection(chatID: scope.chatID, temporary: scope.temporary) },
                revision: { provider.selectionRevision(chatID: scope.chatID, temporary: scope.temporary) },
                publish: { displayed = $0 })
        }
        while delay.continuation == nil { await Task.yield() }
        let secondRequest = feedback.begin(serverID: secondID, scope: scope)
        await HanlinComposerToolsRootView.performServerSelection(
            serverID: secondID, isSelected: true, scope: scope, requestID: secondRequest,
            feedback: feedback, isCurrentScope: { currentScope == scope },
            apply: { try await HanlinComposerToolsRootView.applyServerSelection(provider: provider, serverID: secondID, isSelected: true, chatID: scope.chatID, temporary: scope.temporary) },
            read: { try await provider.readSelection(chatID: scope.chatID, temporary: scope.temporary) },
            revision: { provider.selectionRevision(chatID: scope.chatID, temporary: scope.temporary) },
            publish: { displayed = $0 })
        delay.continuation?.resume()
        await first.value
        #expect(try await provider.readSelection(chatID: scope.chatID, temporary: scope.temporary) == [secondID])
        #expect(displayed == [secondID])
        #expect(feedback.message(for: firstID) != nil)
        #expect(feedback.message(for: secondID) == nil)

        let refreshed = HanlinComposerRefreshContext(chatID: scope.chatID, temporary: scope.temporary, selectionRevision: provider.selectionRevision(chatID: scope.chatID, temporary: scope.temporary), globallyEnabled: false, serverStates: [])
        await HanlinComposerSelectionRefresh.perform(request: refreshed, current: { refreshed },
            revision: { provider.selectionRevision(chatID: scope.chatID, temporary: scope.temporary) },
            read: { try await provider.readSelection(chatID: scope.chatID, temporary: scope.temporary) },
            publish: { if case .success(let value) = $0 { displayed = value } })
        #expect(feedback.message(for: firstID) != nil)

        let supersededDelay = IntentDelay()
        let older = feedback.begin(serverID: firstID, scope: scope)
        let oldTask = Task { @MainActor in
            await HanlinComposerToolsRootView.performServerSelection(
                serverID: firstID, isSelected: true, scope: scope, requestID: older,
                feedback: feedback, isCurrentScope: { currentScope == scope },
                apply: { await supersededDelay.wait(); throw ReadError.failed },
                read: { try await provider.readSelection(chatID: scope.chatID, temporary: scope.temporary) },
                revision: { provider.selectionRevision(chatID: scope.chatID, temporary: scope.temporary) },
                publish: { displayed = $0 })
        }
        while supersededDelay.continuation == nil { await Task.yield() }
        let newer = feedback.begin(serverID: firstID, scope: scope)
        await HanlinComposerToolsRootView.performServerSelection(
            serverID: firstID, isSelected: true, scope: scope, requestID: newer,
            feedback: feedback, isCurrentScope: { currentScope == scope },
            apply: { try await HanlinComposerToolsRootView.applyServerSelection(provider: provider, serverID: firstID, isSelected: true, chatID: scope.chatID, temporary: scope.temporary) },
            read: { try await provider.readSelection(chatID: scope.chatID, temporary: scope.temporary) },
            revision: { provider.selectionRevision(chatID: scope.chatID, temporary: scope.temporary) },
            publish: { displayed = $0 })
        supersededDelay.continuation?.resume()
        await oldTask.value
        #expect(feedback.message(for: firstID) == nil)
        #expect(try await provider.readSelection(chatID: scope.chatID, temporary: scope.temporary) == [firstID, secondID])
        let switched = feedback.begin(serverID: firstID, scope: scope)
        currentScope = MCPChatSelectionScope(chatID: UUID(), temporary: true)
        feedback.setScope(currentScope)
        feedback.finish(serverID: firstID, scope: scope, requestID: switched, error: "wrong chat")
        #expect(feedback.message(for: firstID) == nil)
    }

    @Test("A delayed old-chat result and error are discarded, while a current failure is published")
    func delayedChatSwitchAndReadFailure() async {
        let first = HanlinComposerRefreshContext(chatID: UUID(), temporary: false, selectionRevision: 1, globallyEnabled: true, serverStates: [])
        let second = HanlinComposerRefreshContext(chatID: UUID(), temporary: true, selectionRevision: 0, globallyEnabled: true, serverStates: [])
        for shouldFail in [false, true] {
            let gate = DelayedRead()
            var current: HanlinComposerRefreshContext? = first
            var publications = 0
            let task = Task {
                await HanlinComposerSelectionRefresh.perform(request: first, current: { current }, revision: { 1 }, read: { try await gate.read() }, publish: { _ in publications += 1 })
            }
            while gate.continuation == nil { await Task.yield() }
            current = second
            if shouldFail { gate.continuation?.resume(throwing: ReadError.failed) }
            else { gate.continuation?.resume(returning: [UUID()]) }
            await task.value
            #expect(publications == 0)
        }
        let gate = DelayedRead()
        var didPublishFailure = false
        let task = Task {
            await HanlinComposerSelectionRefresh.perform(request: first, current: { first }, revision: { 1 }, read: { try await gate.read() }, publish: { result in
                if case .failure = result { didPublishFailure = true }
            })
        }
        while gate.continuation == nil { await Task.yield() }
        gate.continuation?.resume(throwing: ReadError.failed)
        await task.value
        #expect(didPublishFailure)
    }

    @Test("Cancellation discards a delayed read without canceling the service")
    func canceledReadDoesNotPublish() async {
        let request = HanlinComposerRefreshContext(chatID: UUID(), temporary: false, selectionRevision: 1, globallyEnabled: true, serverStates: [])
        let gate = DelayedRead()
        var publications = 0
        let task = Task {
            await HanlinComposerSelectionRefresh.perform(request: request, current: { request }, revision: { 1 }, read: { try await gate.read() }, publish: { _ in publications += 1 })
        }
        while gate.continuation == nil { await Task.yield() }
        task.cancel()
        gate.continuation?.resume(returning: [])
        await task.value
        #expect(publications == 0)
    }
}

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

    @Test("1.6 Focus and draft changes preserve manual size; a context change resets it")
    func focusAndLifecycleResets() {
        let state = HanlinOrganizerDockState()
        state.openMode(.general)
        state.manualComposerHeight = 220

        // Focusing input collapses drawer automatically while keeping manual height
        state.handleInputFocusChange(true)
        #expect(state.mode == .collapsed)
        #expect(state.manualComposerHeight == 220)

        // Clearing the draft preserves the deliberate manual size.
        state.handleDraftTextChange("")
        #expect(state.manualComposerHeight == 220)
        state.handleDraftTextChange("new draft")
        #expect(state.manualComposerHeight == 220)

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
        #expect(state.effectiveEditorFrameHeight(intrinsicHeight: 240, minimumInteractiveHeight: 44) == 240)

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

    @Test("History search does not reuse indices after Unicode case folding changes byte length")
    func historySnippetKeepsOriginalStringIndices() {
        let message = "İ" + String(repeating: "x", count: 60) + "END"
        #expect(message.utf8.count != message.lowercased().utf8.count)
        #expect(ListView.messageSearchSnippet(in: message, searchText: "end")
                == String(repeating: "x", count: 40) + "END")
    }

    @Test("History snippet retains complete emoji graphemes and pointed Hebrew at both context boundaries")
    func historySnippetPreservesUnicodeContext() {
        let before = "👩🏽‍💻"
        let after = "🧑‍🚀"
        let match = "שלוֹם"
        let message = String(repeating: before, count: 60) + match + String(repeating: after, count: 60)
        #expect(ListView.messageSearchSnippet(in: message, searchText: match)
                == String(repeating: before, count: 40) + match + String(repeating: after, count: 40))
    }

    @Test("History snippet returns original short text and rejects absent or empty queries")
    func historySnippetHandlesShortAndAbsentMatches() {
        #expect(ListView.messageSearchSnippet(in: "Before HeLLo אחרי", searchText: "hello") == "Before HeLLo אחרי")
        #expect(ListView.messageSearchSnippet(in: "שלום", searchText: "absent") == nil)
        #expect(ListView.messageSearchSnippet(in: "שלום", searchText: "") == nil)
    }

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

    @Test("Turning off the current chat's tool-use binding preserves another chat's setting")
    func toolUseBindingRemainsScopedToItsChat() {
        let bridge = HanlinActiveComposerSessionBridge()
        let chatA = UUID(), chatB = UUID()
        var textA = "A", textB = "B"
        var toolsA = true, toolsB = true
        let endpointA = Self.makeTestEndpoint(
            sessionID: chatA, message: Binding(get: { textA }, set: { textA = $0 }),
            ifToolUse: Binding(get: { toolsA }, set: { toolsA = $0 })
        )
        let endpointB = Self.makeTestEndpoint(
            sessionID: chatB, message: Binding(get: { textB }, set: { textB = $0 }),
            ifToolUse: Binding(get: { toolsB }, set: { toolsB = $0 })
        )
        bridge.snapshotDraft(from: endpointB)
        endpointA.ifToolUse.wrappedValue = false
        bridge.snapshotDraft(from: endpointA)
        #expect(!toolsA)
        #expect(toolsB)
        #expect(bridge.perChatDrafts[chatA]?.ifToolUse == false)
        #expect(bridge.perChatDrafts[chatB]?.ifToolUse == true)
    }

    @Test("Clearing one temporary chat's MCP selection leaves the other chat intact")
    func temporaryMCPSelectionClearDoesNotCrossChats() async throws {
        let store = MCPChatSelectionStore()
        let chatA = UUID(), chatB = UUID(), serverA = UUID(), serverB = UUID()
        try await store.setSelection([serverA], chatID: chatA, temporary: true)
        try await store.setSelection([serverB], chatID: chatB, temporary: true)
        try await store.setSelection([], chatID: chatA, temporary: true)
        let a = try await store.selection(chatID: chatA, temporary: true)
        let b = try await store.selection(chatID: chatB, temporary: true)
        #expect(a == [])
        #expect(b == [serverB])
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
    @Test("The real native catalog registration feeds the existing picker without index drift")
    func nativeCatalogRegistrationFeedsExistingPickerWithoutIndexDrift() throws {
        #if canImport(HanlinAgentCore)
        let container = try ModelContainer(for: AllModels.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let first = AllModels(name: "first", displayName: "First", position: 3, company: "OPENAI")
        let hidden = AllModels(name: "hidden", displayName: "Hidden", position: 5, company: "CUSTOM", isHidden: true)
        let selected = AllModels(name: "selected", displayName: "Selected", position: 8, company: "CUSTOM")
        context.insert(first)
        context.insert(hidden)
        context.insert(selected)
        try context.save()
        let descriptor = FetchDescriptor<AllModels>(sortBy: [SortDescriptor(\.position)])
        let original = try context.fetch(descriptor)
        let selectedIndex = try #require(original.firstIndex(where: { $0.id == selected.id }))

        let native = try HanlinAppleModelCatalogAdapter.register(in: context)
        let repeated = try HanlinAppleModelCatalogAdapter.register(in: context)
        let models = try context.fetch(descriptor)
        let nativeIndex = try #require(models.firstIndex(where: { $0.id == native.id }))
        #expect(native.id == HanlinAppleModelCatalogAdapter.catalogID)
        #expect(native.id == repeated.id)
        #expect(native.name == HanlinAppleOnDeviceProvider.modelID)
        #expect(models.count == original.count + 1)
        #expect(Array(models.prefix(original.count)).map(\.id) == original.map(\.id))
        #expect(models[selectedIndex].id == selected.id)
        #expect(nativeIndex == original.count)

        let available = HanlinAppleOnDeviceProvider.availability == .available
        let actual = HanlinModelPickerPopover.visibleModelIndices(models,
            nativeID: HanlinAppleModelCatalogAdapter.catalogID, nativeAvailable: available)
        #expect(actual.contains(nativeIndex) == available)
        #expect(actual.contains(selectedIndex))
        #expect(!actual.contains(1)) // Hidden row retains its original array slot.
        #expect(HanlinModelPickerPopover.visibleModelIndices(models,
            nativeID: HanlinAppleModelCatalogAdapter.catalogID, nativeAvailable: false) == [0, 2])
        #expect(HanlinModelPickerPopover.visibleModelIndices(models,
            nativeID: HanlinAppleModelCatalogAdapter.catalogID, nativeAvailable: true) == [0, 2, 3])
        #expect(models[nativeIndex].id == native.id) // Unavailable does not rewrite a saved selection.
        #else
        Issue.record("Native picker integration requires HanlinAgentCore linked into the app and test target.")
        #endif
    }

    @Test("New conversations use the available native row without requiring a remote credential")
    func nativeOnlyConversationCreationRespectsActualAvailabilityAndCatalogIndices() {
        let cloud = AllModels(name: "cloud", displayName: "Cloud", position: 0, company: "OPENAI")
        let native = AllModels(id: HanlinAppleModelCatalogAdapter.catalogID,
            name: "apple-system-on-device", displayName: "On-device", position: 9, company: "APPLE", systemProvision: false)
        let models = [cloud, native]
        let originalIDs = models.map(\.id)
        #expect(HanlinDefaultChatPolicy.creationModelIndex(in: models, providers: [],
            nativeAvailable: true, downloadedLocalModels: []) == 1)
        #expect(HanlinDefaultChatPolicy.creationModelIndex(in: models, providers: [],
            nativeAvailable: false, downloadedLocalModels: []) == nil)
        let provider = APIKeys(company: "OPENAI", key: "fixture-only", isHidden: false)
        #expect(HanlinDefaultChatPolicy.creationModelIndex(in: models, providers: [provider],
            nativeAvailable: true, downloadedLocalModels: []) == 0)
        provider.isHidden = true
        #expect(HanlinDefaultChatPolicy.creationModelIndex(in: models, providers: [provider],
            nativeAvailable: true, downloadedLocalModels: []) == 1)
        native.isHidden = true
        #expect(HanlinDefaultChatPolicy.creationModelIndex(in: models, providers: [],
            nativeAvailable: true, downloadedLocalModels: []) == nil)
        #expect(models.map(\.id) == originalIDs)
    }

    @Test("Local-only creation requires the original enabled provider and an actual downloaded model")
    func downloadedLocalConversationCreationDoesNotTreatCatalogPresenceAsReadiness() {
        let missing = AllModels(name: "not-downloaded", displayName: "Not downloaded", position: 0, company: "LOCAL", systemProvision: false)
        let installed = AllModels(name: "installed", displayName: "Installed", position: 3, company: "LOCAL", systemProvision: false)
        let models = [missing, installed]
        let local = APIKeys(company: "LOCAL", key: "LOCAL", requestURL: "LOCAL", isHidden: false)
        #expect(HanlinDefaultChatPolicy.creationModelIndex(in: models, providers: [local],
            nativeAvailable: false, downloadedLocalModels: ["installed"]) == 1)
        #expect(HanlinDefaultChatPolicy.creationModelIndex(in: models, providers: [local],
            nativeAvailable: false, downloadedLocalModels: []) == nil)
        local.isHidden = true
        #expect(HanlinDefaultChatPolicy.creationModelIndex(in: models, providers: [local],
            nativeAvailable: false, downloadedLocalModels: ["installed"]) == nil)
    }

    @Test("Canvas presentation retains its original record and model across endpoint changes")
    func canvasPresentationRetainsItsOriginalOrigin() throws {
        let record = ChatRecords(name: "Original Canvas", type: "chat")
        var canvas = CanvasData()
        canvas.content = "print(6 * 7)"
        record.canvas = canvas
        let original = AllModels(name: "original", displayName: "Original", position: 0, company: "CUSTOM")
        var models = [original]
        let presentation = try #require(HanlinCanvasPresentation(record: record, models: models, selectedModelIndex: 0))
        models.removeAll()
        #expect(presentation.record === record)
        #expect(presentation.model === original)
        #expect(presentation.record.canvas?.content == "print(6 * 7)")
        #expect(HanlinCanvasPresentation(record: record, models: models, selectedModelIndex: 0) == nil)
        #expect(HanlinCanvasPresentation(record: record, models: [original], selectedModelIndex: -1) == nil)
        #expect(HanlinCanvasPresentation(record: record, models: [original], selectedModelIndex: 1) == nil)
    }

    @Test("Native picker visibility preserves original indices and explicit selection")
    func nativeVisibilityKeepsOriginalIndices() {
        let nativeID = UUID()
        let cloud = AllModels(name: "cloud", displayName: "Cloud", position: 0, company: "OPENAI")
        let hidden = AllModels(name: "hidden", displayName: "Hidden", position: 1, company: "OPENAI", isHidden: true)
        let native = AllModels(id: nativeID, name: "native", displayName: "Native", position: 2, company: "APPLE")
        let next = AllModels(name: "next", displayName: "Next", position: 3, company: "OPENAI")
        let duplicate = AllModels(id: nativeID, name: "duplicate", displayName: "Duplicate", position: 4, company: "APPLE")
        let models = [cloud, hidden, native, next, duplicate]
        let selectedModelIndex = 2
        #expect(HanlinModelPickerPopover.visibleModelIndices(models, nativeID: nativeID, nativeAvailable: false) == [0, 3])
        #expect(HanlinModelPickerPopover.visibleModelIndices(models, nativeID: nativeID, nativeAvailable: true) == [0, 2, 3])
        #expect(models[selectedModelIndex] === native)
    }

    @Test("Compact picker exposes an available native row beyond favorites and preserves explicit indices")
    func compactNativeVisibilityKeepsFeaturedAndSelectedIndices() {
        let nativeID = UUID()
        let clouds = (0..<6).map { index in
            AllModels(name: "cloud-\(index)", displayName: "Cloud \(index)", position: index, company: "CUSTOM")
        }
        let native = AllModels(id: nativeID, name: "native", displayName: "Native", position: 10, company: "APPLE")
        let duplicate = AllModels(id: nativeID, name: "duplicate", displayName: "Duplicate", position: 11, company: "APPLE")
        let models = clouds + [native, duplicate]
        #expect(HanlinModelPickerPopover.compactFeaturedIndices(models, selectedModelIndex: 5,
            nativeID: nativeID, nativeAvailable: true) == [5, 0, 1, 2, 6])
        #expect(HanlinModelPickerPopover.compactFeaturedIndices(models, selectedModelIndex: 5,
            nativeID: nativeID, nativeAvailable: false) == [5, 0, 1, 2])
        let selectedNativeIndex = 6
        #expect(HanlinModelPickerPopover.compactFeaturedIndices(models, selectedModelIndex: selectedNativeIndex,
            nativeID: nativeID, nativeAvailable: true) == [6, 0, 1, 2])
        #expect(HanlinModelPickerPopover.compactFeaturedIndices(models, selectedModelIndex: selectedNativeIndex,
            nativeID: nativeID, nativeAvailable: false) == [0, 1, 2, 3])
        #expect(models[selectedNativeIndex] === native)
        native.isHidden = true
        #expect(HanlinModelPickerPopover.compactFeaturedIndices(Array(models.dropLast()), selectedModelIndex: 5,
            nativeID: nativeID, nativeAvailable: true) == [5, 0, 1, 2])
    }


    @Test("Native resize callbacks leave the SwiftUI update and reject a superseded delivery")
    func nativeCallbacksAreDeferredAndSuperseded() async {
        let host = HanlinModelSizingHost(content: HanlinModelHostedView(
            content: Text("Model picker"), environment: EnvironmentValues()))
        var oldCallbacks = 0
        var currentCallbacks = 0
        let target = CGSize(width: 344, height: 472)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            host.resize(to: CGSize(width: 286, height: 324), animated: false) { oldCallbacks += 1 }
            host.resize(to: target, animated: false) {
                currentCallbacks += 1
                done.resume()
            }
            #expect(oldCallbacks == 0)
            #expect(currentCallbacks == 0)
        }
        #expect(host.preferredContentSize == target)
        #expect(oldCallbacks == 0)
        #expect(currentCallbacks == 1)
    }

    @Test("Normal navigation waits for the actual native size completion")
    func nativeSizeCompletionOwnsForwardNavigation() {
        let coordinator = HanlinComposerPopupCoordinator()
        coordinator.measuredContainerSize = CGSize(width: 500, height: 768)
        coordinator.open(.model)
        coordinator.pushModelSubroute()
        #expect(coordinator.modelNavigationPath.isEmpty)
        #expect(coordinator.isModelAnimatingExpand)
        coordinator.modelFrameResizeDidComplete(presentationID: coordinator.modelPresentationGeneration,
                                                size: CGSize(width: 286, height: 324))
        #expect(coordinator.modelNavigationPath.isEmpty)
        coordinator.modelFrameResizeDidComplete(presentationID: coordinator.modelPresentationGeneration,
                                                size: coordinator.modelPopoverSize)
        #expect(coordinator.modelNavigationPath == [.allModels])
        #expect(!coordinator.isModelAnimatingExpand)
    }

    @Test("A native callback from an old presentation cannot complete the reopened expansion")
    func staleNativeResizeCannotCompleteReopenedPresentation() {
        let coordinator = HanlinComposerPopupCoordinator()
        coordinator.open(.model)
        let previousGeneration = coordinator.modelPresentationGeneration
        coordinator.pushModelSubroute()
        coordinator.closeAll()
        coordinator.open(.model)
        coordinator.pushModelSubroute()
        coordinator.modelFrameResizeDidComplete(presentationID: previousGeneration, size: coordinator.modelPopoverSize)
        #expect(coordinator.modelNavigationPath.isEmpty)
        #expect(coordinator.isModelAnimatingExpand)
        coordinator.modelFrameResizeDidComplete(presentationID: coordinator.modelPresentationGeneration,
                                                size: coordinator.modelPopoverSize)
        #expect(coordinator.modelNavigationPath == [.allModels])
    }

    @Test("Reentering during the reverse morph uses the already-expanded native frame")
    func reenterWhileExpandedDoesNotWaitForAnotherResize() {
        let coordinator = HanlinComposerPopupCoordinator()
        coordinator.deferAnimationCompletionsForTesting = true
        coordinator.open(.model)
        coordinator.pushModelSubroute()
        coordinator.flushPendingAnimationCompletions()
        coordinator.popModelSubroute()
        coordinator.pushModelSubroute()
        #expect(coordinator.modelNavigationPath == [.allModels])
        coordinator.flushPendingAnimationCompletions()
        #expect(coordinator.modelFrameExpanded)
        #expect(coordinator.modelNavigationPath == [.allModels])
    }

    @Test("Reverse morph completes before shrinking the popover frame")
    func reverseCompletesBeforeShrink() {
        let coordinator = HanlinComposerPopupCoordinator()
        coordinator.deferAnimationCompletionsForTesting = true
        coordinator.toggle(.model)
        coordinator.pushModelSubroute()
        coordinator.flushPendingAnimationCompletions()
        coordinator.popModelSubroute()
        #expect(coordinator.modelNavigationPath.isEmpty)
        #expect(coordinator.modelFrameExpanded)
        #expect(!coordinator.modelDestinationDisappeared)
        coordinator.flushPendingAnimationCompletions()
        #expect(!coordinator.modelFrameExpanded)
        #expect(coordinator.modelDestinationDisappeared)
    }

    @Test("A stale reverse completion cannot shrink a newly reopened picker")
    func staleReverseCannotShrinkNewPresentation() {
        let coordinator = HanlinComposerPopupCoordinator()
        coordinator.deferAnimationCompletionsForTesting = true
        coordinator.toggle(.model)
        coordinator.pushModelSubroute()
        coordinator.flushPendingAnimationCompletions()
        coordinator.popModelSubroute()
        coordinator.closeAll()
        coordinator.toggle(.model)
        coordinator.pushModelSubroute()
        coordinator.flushPendingAnimationCompletions(firstOnly: true)
        #expect(coordinator.modelFrameExpanded)
        #expect(coordinator.isModelAnimatingExpand)
        #expect(coordinator.modelNavigationPath.isEmpty)
        coordinator.flushPendingAnimationCompletions()
        #expect(coordinator.modelNavigationPath == [.allModels])
    }

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

        coordinator.popModelSubroute(reduceMotion: true)
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

    @Test("Detached groups reflect enabled model-supported modes and MCP configuration")
    func detachedCapabilitiesProjectRealModeState() {
        let model = AllModels(name: "test", displayName: "Test", position: 0, company: "OPENAI",
                              supportsSearch: true, supportsTextGen: true, supportsMultimodal: true,
                              supportsReasoning: true, supportReasoningChange: true, supportsToolUse: true)
        let cap = HanlinComposerActionBridge.capabilitySnapshot(for: model)
        func project(search: Bool, knowledge: Bool, thinking: Bool, planning: Bool, tools: Bool, mcp: Int, mcpEnabled: Bool, skills: Bool = false, runtimes: Bool = false) -> [HanlinDetachedCapability] {
            let chips = HanlinComposerActionBridge.activeModeChips(
                capability: cap, ifSearch: search, ifKnowledge: knowledge, ifThink: thinking,
                thinkingLength: 0, ifPlanning: planning, ifAudio: false, ifToolUse: tools,
                activeMCPServerCount: mcp, selectedImageSize: "1:1"
            )
            return HanlinDetachedCapability.enabled(from: chips, mcpEnabled: mcpEnabled, hasModel: cap.hasModel,
                                                     toolUseEnabled: tools && cap.supportsToolUse,
                                                     toolsEligible: true, skillsEligible: skills, runtimesEligible: runtimes)
        }
        #expect(project(search: false, knowledge: false, thinking: false, planning: false, tools: false, mcp: 0, mcpEnabled: true).isEmpty)
        #expect(project(search: false, knowledge: true, thinking: false, planning: false, tools: false, mcp: 0, mcpEnabled: true) == [.search])
        #expect(project(search: true, knowledge: true, thinking: true, planning: true, tools: true, mcp: 2, mcpEnabled: true, skills: true, runtimes: true) == [.search, .thinking, .tools, .skills, .mcp, .runtimes])
        #expect(project(search: false, knowledge: false, thinking: false, planning: false, tools: false, mcp: 2, mcpEnabled: false).isEmpty)
        #expect(project(search: false, knowledge: false, thinking: false, planning: false, tools: false, mcp: 2, mcpEnabled: true, skills: true, runtimes: true).isEmpty)
        #expect(!project(search: false, knowledge: false, thinking: false, planning: false, tools: true, mcp: 2, mcpEnabled: false).contains(.mcp))

        let unsupported = HanlinComposerActionBridge.capabilitySnapshot(for: nil)
        let unsupportedChips = HanlinComposerActionBridge.activeModeChips(
            capability: unsupported, ifSearch: true, ifKnowledge: false, ifThink: true,
            thinkingLength: 0, ifPlanning: false, ifAudio: true, ifToolUse: true,
            activeMCPServerCount: 0, selectedImageSize: "1:1"
        )
        #expect(HanlinDetachedCapability.enabled(from: unsupportedChips, mcpEnabled: true, hasModel: false,
                                                  toolUseEnabled: false, toolsEligible: true, skillsEligible: true, runtimesEligible: true).isEmpty)

        let mandatory = AllModels(name: "fixed-reasoning", displayName: "Fixed", position: 1, company: "OPENAI",
                                  supportsSearch: false, supportsTextGen: true, supportsMultimodal: false,
                                  supportsReasoning: true, supportReasoningChange: false, supportsToolUse: false)
        let fixedChips = HanlinComposerActionBridge.activeModeChips(
            capability: HanlinComposerActionBridge.capabilitySnapshot(for: mandatory), ifSearch: false,
            ifKnowledge: false, ifThink: true, thinkingLength: 0, ifPlanning: true,
            ifAudio: false, ifToolUse: false, activeMCPServerCount: 0, selectedImageSize: "1:1"
        )
        #expect(HanlinDetachedCapability.enabled(from: fixedChips, mcpEnabled: true, hasModel: true,
                                                  toolUseEnabled: false, toolsEligible: false, skillsEligible: false, runtimesEligible: false) == [.thinking])
        #expect(!HanlinDetachedCapability.thinking.canDisable(from: fixedChips))
        let imageModel = AllModels(name: "image", displayName: "Image", position: 2, company: "OPENAI", supportsImageGen: true)
        let imageChips = HanlinComposerActionBridge.activeModeChips(
            capability: HanlinComposerActionBridge.capabilitySnapshot(for: imageModel), ifSearch: false,
            ifKnowledge: false, ifThink: false, thinkingLength: 0, ifPlanning: false,
            ifAudio: false, ifToolUse: false, activeMCPServerCount: 0, selectedImageSize: "1:1"
        )
        #expect(HanlinDetachedCapability.enabled(from: imageChips, mcpEnabled: false, hasModel: true,
                                                  toolUseEnabled: false, toolsEligible: false, skillsEligible: false, runtimesEligible: false) == [.creative])
        #expect(HanlinDetachedCapability.creative.contextAction(imageGenerationActive: true) == .chooseModel)
        #expect(HanlinDetachedCapability.creative.contextAction(imageGenerationActive: false) == .disableModes)
        #expect(HanlinDetachedCapability.skills.contextAction(imageGenerationActive: false) == .disableChatToolUse)
        #expect(HanlinDetachedCapability.runtimes.contextAction(imageGenerationActive: false) == .disableChatToolUse)
        #expect(HanlinDetachedCapability.mcp.contextAction(imageGenerationActive: false) == .clearChatMCPSelection)
        #expect(HanlinDetachedCapabilityChips.usesCompactLayout(width: 509))
        #expect(!HanlinDetachedCapabilityChips.usesCompactLayout(width: 510))
    }

    @Test("Closing model presentation leaves projection unchanged until selected model changes")
    func imageCapabilityFollowsActualModelAfterPickerCancellation() {
        let image = AllModels(name: "image", displayName: "Image", position: 0, company: "OPENAI", supportsImageGen: true)
        let text = AllModels(name: "text", displayName: "Text", position: 1, company: "OPENAI", supportsImageGen: false)
        var selected = image
        func visibleCapabilities() -> [HanlinDetachedCapability] {
            let snapshot = HanlinComposerActionBridge.capabilitySnapshot(for: selected)
            let chips = HanlinComposerActionBridge.activeModeChips(
                capability: snapshot, ifSearch: false, ifKnowledge: false, ifThink: false,
                thinkingLength: 0, ifPlanning: false, ifAudio: false, ifToolUse: false,
                activeMCPServerCount: 0, selectedImageSize: "1:1"
            )
            return HanlinDetachedCapability.enabled(from: chips, mcpEnabled: false, hasModel: snapshot.hasModel,
                                                     toolUseEnabled: false, toolsEligible: false,
                                                     skillsEligible: false, runtimesEligible: false)
        }
        let coordinator = HanlinComposerPopupCoordinator()
        #expect(visibleCapabilities() == [.creative])
        #expect(HanlinDetachedCapability.creative.contextAction(imageGenerationActive: true) == .chooseModel)
        coordinator.open(.model)
        coordinator.closeAll() // Cancellation changes only presentation, not selected model.
        #expect(visibleCapabilities() == [.creative])
        selected = text // Changes the test's selected model; this is not a UI interaction test.
        #expect(visibleCapabilities().isEmpty)
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
