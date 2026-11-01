//
//  HanlinComposerSessionBridge.swift
//  AI_HLY
//
//  Strongly typed @MainActor session bridge connecting the single persistent compact
//  composer dock to the currently mounted ChatView's live @State bindings and callbacks,
//  or to the unsent compact Home draft when on the root home screen (§4.3 & §4.4).
//

import Foundation
import Observation
import SwiftData
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Environment Keys for Compact Persistent Composer Ownership

private struct HanlinExternalCompactComposerHostKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

private struct HanlinExternalDockHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

private struct HanlinComposerSessionBridgeKey: EnvironmentKey {
    static let defaultValue: HanlinActiveComposerSessionBridge? = nil
}

extension EnvironmentValues {
    var hanlinExternalCompactComposerHost: Bool {
        get { self[HanlinExternalCompactComposerHostKey.self] }
        set { self[HanlinExternalCompactComposerHostKey.self] = newValue }
    }

    var hanlinExternalDockHeight: CGFloat {
        get { self[HanlinExternalDockHeightKey.self] }
        set { self[HanlinExternalDockHeightKey.self] = newValue }
    }

    var hanlinComposerSessionBridge: HanlinActiveComposerSessionBridge? {
        get { self[HanlinComposerSessionBridgeKey.self] }
        set { self[HanlinComposerSessionBridgeKey.self] = newValue }
    }
}

// MARK: - Per-Chat Transient Draft & Attachment Cache

@MainActor
struct HanlinChatDraftSnapshot {
    var message: String
    var selectedImages: [UIImage]
    var selectedDocumentURLs: [URL]
    var selectedURLs: [String]
    var selectedPrompts: [PromptRepo]
    var selectedModelIndex: Int
    var ifKnowledge: Bool
    var ifSearch: Bool
    var ifToolUse: Bool
    var ifThink: Bool
    var ifAudio: Bool
    var ifPlanning: Bool
    var thinkingLength: Int
    var selectedImageSize: String
    var imageReversePrompt: String
    var temporaryRecord: Bool = false
}

// MARK: - Active Composer Session Bridge

@MainActor
@Observable
final class HanlinActiveComposerSessionBridge {

    struct Endpoint {
        let sessionID: UUID
        let registrationToken: UUID
        var isReadyToSend: Bool
        var chatRecord: ChatRecords
        var modelTemp: [AllModels]
        var temporaryRecord: Bool
        var respondIndex: Int

        // Live bindings into the mounted ChatView
        var selectedModelIndex: Binding<Int>
        var showScrollToBottomButton: Binding<Bool>
        var needScrollToBottomButton: Binding<Bool>
        var isMultiSelectMode: Binding<Bool>
        var selectedMessageIDs: Binding<Set<UUID>>
        var chatTemps: Binding<[ChatMessages]>

        var showTemperatureSlider: Binding<Bool>
        var temperature: Binding<Double>
        var showTopPSlider: Binding<Bool>
        var topP: Binding<Double>
        var showMaxTokensSlider: Binding<Bool>
        var maxTokens: Binding<Int>
        var showMaxMessagesNumSlider: Binding<Bool>
        var maxMessagesNum: Binding<Int>

        var message: Binding<String>
        var selectedImages: Binding<[UIImage]>
        var selectedDocumentURLs: Binding<[URL]>
        var selectedURLs: Binding<[String]>
        var selectedPrompts: Binding<[PromptRepo]>
        var showPhotoSourceOptions: Binding<Bool>

        var showModelSuggestions: Binding<Bool>
        var filteredModels: Binding<[AllModels]>

        var isResponding: Binding<Bool>
        var isFeedBack: Binding<Bool>

        var ifKnowledge: Binding<Bool>
        var ifSearch: Binding<Bool>
        var ifToolUse: Binding<Bool>
        var ifThink: Binding<Bool>
        var ifAudio: Binding<Bool>
        var ifPlanning: Binding<Bool>
        var thinkingLength: Binding<Int>

        var showKnowledgeAlert: Binding<Bool>
        var knowledgeAlertMessage: Binding<String>
        var showSearchAlert: Binding<Bool>

        var selectedImageSize: Binding<String>
        var imageReversePrompt: Binding<String>

        // Live callbacks into the mounted ChatView's authoritative production methods
        var onSelectModel: (Int) -> Void
        var onSendUser: () -> Void
        var onSendObserve: () -> Void
        var onCancel: () -> Void
        var validateSendAcceptance: (() -> Bool)? = nil
    }

    /// Currently mounted chat endpoint (`nil` when on Home or Library).
    private(set) var activeEndpoint: Endpoint?

    /// Optional authoritative active session ID set by the workspace router to reject out-of-order registrations.
    var expectedActiveSessionID: UUID?

    /// Cached per-chat draft & attachment snapshots across compact and wide navigation switches.
    private(set) var perChatDrafts: [UUID: HanlinChatDraftSnapshot] = [:]

    /// Tracks active temporary chat IDs across layout transitions so temporary chats are excluded from recent lists and preserved on resize.
    private(set) var temporaryChatIDs: Set<UUID> = []

    /// Pending one-time first-turn handoff created from the compact Home screen.
    private(set) var pendingFirstTurn: HanlinPendingFirstTurn?

    /// Set of submission IDs already accepted, guaranteeing at-most-once execution.
    private(set) var completedSubmissionIDs: Set<UUID> = []

    /// Prevents temporary chat deletion in `ChatView.onDisappear` when layout mode transitions between compact and wide.
    var isTransitioningLayoutMode: Bool = false

    func beginLayoutModeTransition() {
        isTransitioningLayoutMode = true
    }

    func endLayoutModeTransition() {
        isTransitioningLayoutMode = false
    }

    func setTemporaryChat(_ isTemporary: Bool, for sessionID: UUID) {
        if isTemporary {
            temporaryChatIDs.insert(sessionID)
        } else {
            temporaryChatIDs.remove(sessionID)
        }
        if var snapshot = perChatDrafts[sessionID] {
            snapshot.temporaryRecord = isTemporary
            perChatDrafts[sessionID] = snapshot
        }
    }

    func isTemporaryChat(_ sessionID: UUID) -> Bool {
        temporaryChatIDs.contains(sessionID) || (perChatDrafts[sessionID]?.temporaryRecord == true)
    }

    // MARK: - Home ("new") Unsent Draft State

    /// Unpersisted placeholder record used only for binding compatibility while on the compact Home root.
    /// Never inserted into SwiftData `ModelContext`.
    let homePlaceholderRecord = ChatRecords(
        name: String(localized: "New Group Chat"),
        type: "chat",
        lastEdited: Date()
    )

    var homeMessage: String = ""
    var homeSelectedImages: [UIImage] = []
    var homeSelectedDocumentURLs: [URL] = []
    var homeSelectedURLs: [String] = []
    var homeSelectedPrompts: [PromptRepo] = []
    var homeSelectedModelIndex: Int = 0
    var homeIfKnowledge: Bool = false
    var homeIfSearch: Bool = false
    var homeIfToolUse: Bool = true
    var homeIfThink: Bool = false
    var homeIfAudio: Bool = false
    var homeIfPlanning: Bool = false
    var homeThinkingLength: Int = 0
    var homeSelectedImageSize: String = "square"
    var homeImageReversePrompt: String = ""
    var homeTemperature: Double = 0.8
    var homeTopP: Double = 0.9
    var homeMaxTokens: Int = 2048
    var homeMaxMessagesNum: Int = 20
    var homeShowTemperatureSlider: Bool = false
    var homeShowTopPSlider: Bool = false
    var homeShowMaxTokensSlider: Bool = false
    var homeShowMaxMessagesNumSlider: Bool = false
    var homeShowPhotoSourceOptions: Bool = false
    var homeShowModelSuggestions: Bool = false
    var homeFilteredModels: [AllModels] = []
    var homeShowKnowledgeAlert: Bool = false
    var homeKnowledgeAlertMessage: String = ""
    var homeShowSearchAlert: Bool = false
    var homeIsFeedBack: Bool = false

    init() {}

    // MARK: - Endpoint Registration & Generation Protection (§4.3)

    func restoreCachedDraftIfNeeded(into endpoint: Endpoint) {
        guard pendingFirstTurn?.targetChatID != endpoint.sessionID,
              let cached = perChatDrafts[endpoint.sessionID] else {
            return
        }
        if endpoint.message.wrappedValue.isEmpty && !cached.message.isEmpty {
            endpoint.message.wrappedValue = cached.message
            if endpoint.chatRecord.modelContext != nil {
                endpoint.chatRecord.input = cached.message
            }
        }
        if endpoint.selectedImages.wrappedValue.isEmpty && !cached.selectedImages.isEmpty {
            endpoint.selectedImages.wrappedValue = cached.selectedImages
        }
        if endpoint.selectedDocumentURLs.wrappedValue.isEmpty && !cached.selectedDocumentURLs.isEmpty {
            endpoint.selectedDocumentURLs.wrappedValue = cached.selectedDocumentURLs
        }
        if endpoint.selectedURLs.wrappedValue.isEmpty && !cached.selectedURLs.isEmpty {
            endpoint.selectedURLs.wrappedValue = cached.selectedURLs
        }
        if endpoint.selectedPrompts.wrappedValue.isEmpty && !cached.selectedPrompts.isEmpty {
            endpoint.selectedPrompts.wrappedValue = cached.selectedPrompts
        }
        endpoint.ifKnowledge.wrappedValue = cached.ifKnowledge
        endpoint.ifSearch.wrappedValue = cached.ifSearch
        endpoint.ifToolUse.wrappedValue = cached.ifToolUse
        endpoint.ifThink.wrappedValue = cached.ifThink
        endpoint.ifAudio.wrappedValue = cached.ifAudio
        endpoint.ifPlanning.wrappedValue = cached.ifPlanning
        endpoint.thinkingLength.wrappedValue = cached.thinkingLength
        endpoint.selectedImageSize.wrappedValue = cached.selectedImageSize
        endpoint.imageReversePrompt.wrappedValue = cached.imageReversePrompt
        if endpoint.modelTemp.indices.contains(cached.selectedModelIndex) && !endpoint.modelTemp[cached.selectedModelIndex].isHidden {
            endpoint.selectedModelIndex.wrappedValue = cached.selectedModelIndex
        }
    }

    func register(endpoint: Endpoint) {
        if let expectedID = expectedActiveSessionID, endpoint.sessionID != expectedID {
            return
        }
        restoreCachedDraftIfNeeded(into: endpoint)
        activeEndpoint = endpoint
        snapshotDraft(from: endpoint)
        fulfillPendingFirstTurnIfReady()
    }

    func update(endpoint: Endpoint) {
        guard let current = activeEndpoint,
              current.sessionID == endpoint.sessionID,
              current.registrationToken == endpoint.registrationToken else {
            // Even when not the compact external activeEndpoint (e.g. wide split view), keep per-chat draft snapshot fresh
            if expectedActiveSessionID == nil || expectedActiveSessionID == endpoint.sessionID {
                snapshotDraft(from: endpoint)
            }
            return
        }
        activeEndpoint = endpoint
        snapshotDraft(from: endpoint)
        fulfillPendingFirstTurnIfReady()
    }

    func unregister(sessionID: UUID, token: UUID) {
        guard let current = activeEndpoint,
              current.sessionID == sessionID,
              current.registrationToken == token else {
            return
        }
        snapshotDraft(from: current)
        activeEndpoint = nil

        if let pending = pendingFirstTurn,
           pending.targetChatID == sessionID,
           pending.isPendingHandoff {
            restoreHomeDraft(from: pending)
            var cancelled = pending
            cancelled.status = .cancelled(reason: "Target chat view disappeared before first-turn handoff completed.")
            pendingFirstTurn = cancelled
        }
    }

    func snapshotDraft(from endpoint: Endpoint) {
        if endpoint.temporaryRecord {
            temporaryChatIDs.insert(endpoint.sessionID)
        } else {
            temporaryChatIDs.remove(endpoint.sessionID)
        }
        perChatDrafts[endpoint.sessionID] = HanlinChatDraftSnapshot(
            message: endpoint.message.wrappedValue,
            selectedImages: endpoint.selectedImages.wrappedValue,
            selectedDocumentURLs: endpoint.selectedDocumentURLs.wrappedValue,
            selectedURLs: endpoint.selectedURLs.wrappedValue,
            selectedPrompts: endpoint.selectedPrompts.wrappedValue,
            selectedModelIndex: endpoint.selectedModelIndex.wrappedValue,
            ifKnowledge: endpoint.ifKnowledge.wrappedValue,
            ifSearch: endpoint.ifSearch.wrappedValue,
            ifToolUse: endpoint.ifToolUse.wrappedValue,
            ifThink: endpoint.ifThink.wrappedValue,
            ifAudio: endpoint.ifAudio.wrappedValue,
            ifPlanning: endpoint.ifPlanning.wrappedValue,
            thinkingLength: endpoint.thinkingLength.wrappedValue,
            selectedImageSize: endpoint.selectedImageSize.wrappedValue,
            imageReversePrompt: endpoint.imageReversePrompt.wrappedValue,
            temporaryRecord: endpoint.temporaryRecord
        )
    }

    func clearCachedDraft(for sessionID: UUID) {
        perChatDrafts.removeValue(forKey: sessionID)
        temporaryChatIDs.remove(sessionID)
    }

    // MARK: - Guarded Action Dispatch (§4.3)

    @discardableResult
    func performSendUser(expectedSessionID: UUID) -> Bool {
        guard let endpoint = activeEndpoint,
              endpoint.sessionID == expectedSessionID,
              endpoint.isReadyToSend,
              !endpoint.isResponding.wrappedValue,
              endpoint.modelTemp.indices.contains(endpoint.selectedModelIndex.wrappedValue) else {
            return false
        }
        guard ChatViewBottom.shouldEnableSend(
            message: endpoint.message.wrappedValue,
            selectedImagesCount: endpoint.selectedImages.wrappedValue.count,
            selectedDocumentsCount: endpoint.selectedDocumentURLs.wrappedValue.count,
            selectedPromptsCount: endpoint.selectedPrompts.wrappedValue.count,
            isResponding: endpoint.isResponding.wrappedValue
        ) else {
            return false
        }
        endpoint.onSendUser()
        snapshotDraft(from: endpoint)
        return true
    }

    @discardableResult
    func performSendObserve(expectedSessionID: UUID) -> Bool {
        guard let endpoint = activeEndpoint,
              endpoint.sessionID == expectedSessionID,
              endpoint.isReadyToSend,
              !endpoint.isResponding.wrappedValue,
              endpoint.modelTemp.indices.contains(endpoint.selectedModelIndex.wrappedValue) else {
            return false
        }
        endpoint.onSendObserve()
        return true
    }

    @discardableResult
    func performCancel(expectedSessionID: UUID) -> Bool {
        guard let endpoint = activeEndpoint,
              endpoint.sessionID == expectedSessionID else {
            return false
        }
        endpoint.onCancel()
        return true
    }

    // MARK: - Safe First Turn From Compact Home (§4.4)

    /// Initiates a one-time first-turn submission from the compact Home screen.
    /// Returns the created `ChatRecords.id` to navigate to, or `nil` if refused/invalid.
    @discardableResult
    func beginHomeFirstTurn(
        availableModels: [AllModels],
        createAuthorizedChat: () -> ChatRecords?
    ) -> UUID? {
        // 1. Refuse duplicate tap / keyboard Return if a submission is already in flight
        if let existing = pendingFirstTurn, existing.isPendingHandoff {
            return nil
        }

        // 2. Validate payload using ChatViewBottom.shouldEnableSend and model availability
        guard ChatViewBottom.shouldEnableSend(
            message: homeMessage,
            selectedImagesCount: homeSelectedImages.count,
            selectedDocumentsCount: homeSelectedDocumentURLs.count,
            selectedPromptsCount: homeSelectedPrompts.count,
            isResponding: false
        ) else {
            return nil
        }

        guard availableModels.indices.contains(homeSelectedModelIndex),
              !availableModels[homeSelectedModelIndex].isHidden else {
            return nil
        }
        let validModelIndex = homeSelectedModelIndex

        var submission = HanlinPendingFirstTurn(
            submissionID: UUID(),
            text: homeMessage,
            images: homeSelectedImages,
            documentURLs: homeSelectedDocumentURLs,
            selectedURLs: homeSelectedURLs,
            prompts: homeSelectedPrompts,
            selectedModelIndex: validModelIndex,
            ifSearch: homeIfSearch,
            ifKnowledge: homeIfKnowledge,
            ifToolUse: homeIfToolUse,
            ifThink: homeIfThink,
            thinkingLength: homeThinkingLength,
            ifPlanning: homeIfPlanning,
            ifAudio: homeIfAudio,
            selectedImageSize: homeSelectedImageSize,
            imageReversePrompt: homeImageReversePrompt,
            temperature: homeTemperature,
            topP: homeTopP,
            maxTokens: homeMaxTokens,
            maxMessagesNum: homeMaxMessagesNum,
            status: .created
        )

        // 3. Invoke canonical new-chat creator once; if it fails, preserve Home draft and attachments
        guard let createdRecord = createAuthorizedChat(),
              let targetID = createdRecord.id else {
            submission.status = .failed(reason: "New chat creation prerequisite check failed.")
            pendingFirstTurn = submission
            return nil
        }

        createdRecord.useModel = validModelIndex
        submission.status = .awaitingEndpoint(targetChatID: targetID)
        pendingFirstTurn = submission

        // Clear Home draft fields while payload is in-flight; restored automatically if cancelled/failed before acceptance
        clearHomeDraftFields()

        fulfillPendingFirstTurnIfReady()
        return targetID
    }

    private func clearHomeDraftFields() {
        homeMessage = ""
        homeSelectedImages.removeAll()
        homeSelectedDocumentURLs.removeAll()
        homeSelectedURLs.removeAll()
        homeSelectedPrompts.removeAll()
    }

    private func restoreHomeDraft(from pending: HanlinPendingFirstTurn) {
        if homeMessage.isEmpty {
            homeMessage = pending.text
        }
        if homeSelectedImages.isEmpty {
            homeSelectedImages = pending.images
        }
        if homeSelectedDocumentURLs.isEmpty {
            homeSelectedDocumentURLs = pending.documentURLs
        }
        if homeSelectedURLs.isEmpty {
            homeSelectedURLs = pending.selectedURLs
        }
        if homeSelectedPrompts.isEmpty {
            homeSelectedPrompts = pending.prompts
        }
        homeSelectedModelIndex = pending.selectedModelIndex
        homeIfSearch = pending.ifSearch
        homeIfKnowledge = pending.ifKnowledge
        homeIfToolUse = pending.ifToolUse
        homeIfThink = pending.ifThink
        homeThinkingLength = pending.thinkingLength
        homeIfPlanning = pending.ifPlanning
        homeIfAudio = pending.ifAudio
        homeSelectedImageSize = pending.selectedImageSize
        homeImageReversePrompt = pending.imageReversePrompt
    }

    func cancelPendingFirstTurn(reason: String = "Cancelled by navigation") {
        guard var pending = pendingFirstTurn, pending.isPendingHandoff else { return }
        restoreHomeDraft(from: pending)
        pending.status = .cancelled(reason: reason)
        pendingFirstTurn = pending
    }

    func failPendingFirstTurn(reason: String) {
        guard var pending = pendingFirstTurn, pending.isPendingHandoff else { return }
        restoreHomeDraft(from: pending)
        pending.status = .failed(reason: reason)
        pendingFirstTurn = pending
    }

    private func fulfillPendingFirstTurnIfReady() {
        guard var pending = pendingFirstTurn,
              case .awaitingEndpoint(let targetID) = pending.status,
              !completedSubmissionIDs.contains(pending.submissionID),
              let endpoint = activeEndpoint,
              endpoint.sessionID == targetID,
              endpoint.isReadyToSend,
              !endpoint.isResponding.wrappedValue else {
            return
        }

        // Strict model validation: never silently fall back to an unintended model if the selected index is invalid
        guard endpoint.modelTemp.indices.contains(pending.selectedModelIndex),
              !endpoint.modelTemp[pending.selectedModelIndex].isHidden else {
            if !endpoint.modelTemp.isEmpty {
                failPendingFirstTurn(reason: "Selected model index \(pending.selectedModelIndex) is unavailable in target chat.")
            }
            return
        }

        // Enter .dispatching state with the endpoint's registrationToken before invoking onSendUser
        pending.status = .dispatching(targetChatID: targetID, registrationToken: endpoint.registrationToken)
        pendingFirstTurn = pending

        // Transfer payload into the mounted ChatView's live bindings once
        let resolvedModelIndex = pending.selectedModelIndex
        if endpoint.selectedModelIndex.wrappedValue != resolvedModelIndex {
            endpoint.onSelectModel(resolvedModelIndex)
        }
        endpoint.ifSearch.wrappedValue = pending.ifSearch
        endpoint.ifKnowledge.wrappedValue = pending.ifKnowledge
        endpoint.ifToolUse.wrappedValue = pending.ifToolUse
        endpoint.ifThink.wrappedValue = pending.ifThink
        endpoint.thinkingLength.wrappedValue = pending.thinkingLength
        endpoint.ifPlanning.wrappedValue = pending.ifPlanning
        endpoint.ifAudio.wrappedValue = pending.ifAudio
        endpoint.selectedImageSize.wrappedValue = pending.selectedImageSize
        endpoint.imageReversePrompt.wrappedValue = pending.imageReversePrompt
        endpoint.temperature.wrappedValue = pending.temperature
        endpoint.topP.wrappedValue = pending.topP
        endpoint.maxTokens.wrappedValue = pending.maxTokens
        endpoint.maxMessagesNum.wrappedValue = pending.maxMessagesNum

        endpoint.message.wrappedValue = pending.text
        endpoint.selectedImages.wrappedValue = pending.images
        endpoint.selectedDocumentURLs.wrappedValue = pending.documentURLs
        endpoint.selectedURLs.wrappedValue = pending.selectedURLs
        endpoint.selectedPrompts.wrappedValue = pending.prompts

        let previousUserMessageCount = endpoint.chatTemps.wrappedValue.filter { $0.role == "user" }.count

        // Invoke the mounted ChatView's authoritative handleMessageSending(ifObservingMode: false)
        endpoint.onSendUser()

        // Verify that the send was not synchronously cancelled/unregistered and that acceptance succeeded
        guard let currentPending = pendingFirstTurn,
              currentPending.submissionID == pending.submissionID,
              case .dispatching(let activeTargetID, let token) = currentPending.status,
              activeTargetID == targetID,
              token == endpoint.registrationToken else {
            return
        }

        let isAccepted = endpoint.validateSendAcceptance?() ?? true
        guard isAccepted else {
            failPendingFirstTurn(reason: "Target ChatView rejected first-turn send.")
            return
        }

        completedSubmissionIDs.insert(pending.submissionID)
        var accepted = currentPending
        let currentUserMessages = endpoint.chatTemps.wrappedValue.filter { $0.role == "user" }
        if currentUserMessages.count > previousUserMessageCount {
            accepted.acceptedUserMessageID = currentUserMessages.last?.id
        }
        accepted.status = .dispatched(targetChatID: targetID)
        pendingFirstTurn = accepted
        snapshotDraft(from: endpoint)
    }
}
