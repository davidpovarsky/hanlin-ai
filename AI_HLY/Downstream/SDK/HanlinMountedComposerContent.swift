import SwiftUI

/// Adapts the existing live endpoint to the original composer, without keeping
/// another draft, model selection, tool catalog, or send implementation.
@MainActor
struct HanlinMountedComposerContent: View {
    let endpoint: HanlinActiveComposerSessionBridge.Endpoint
    var isInputActive: FocusState<Bool>.Binding
    var availableWorkspaceSize: CGSize

    var body: some View {
        ChatViewBottom(
            chatRecord: endpoint.chatRecord,
            modelTemp: endpoint.modelTemp,
            TemporaryRecord: endpoint.temporaryRecord,
            respondIndex: endpoint.respondIndex,
            onSelectModel: endpoint.onSelectModel,
            onSendUser: endpoint.onSendUser,
            onSendObserve: endpoint.onSendObserve,
            onCancel: endpoint.onCancel,
            selectedModelIndex: endpoint.selectedModelIndex,
            showScrollToBottomButton: endpoint.showScrollToBottomButton,
            needScrollToBottomButton: endpoint.needScrollToBottomButton,
            isMultiSelectMode: endpoint.isMultiSelectMode,
            selectedMessageIDs: endpoint.selectedMessageIDs,
            chatTemps: endpoint.chatTemps,
            showTemperatureSlider: endpoint.showTemperatureSlider,
            temperature: endpoint.temperature,
            showTopPSlider: endpoint.showTopPSlider,
            topP: endpoint.topP,
            showMaxTokensSlider: endpoint.showMaxTokensSlider,
            maxTokens: endpoint.maxTokens,
            showMaxMessagesNumSlider: endpoint.showMaxMessagesNumSlider,
            maxMessagesNum: endpoint.maxMessagesNum,
            message: endpoint.message,
            selectedImages: endpoint.selectedImages,
            selectedDocumentURLs: endpoint.selectedDocumentURLs,
            selectedURLs: endpoint.selectedURLs,
            selectedPrompts: endpoint.selectedPrompts,
            showPhotoSourceOptions: endpoint.showPhotoSourceOptions,
            showModelSuggestions: endpoint.showModelSuggestions,
            filteredModels: endpoint.filteredModels,
            isResponding: endpoint.isResponding,
            isFeedBack: endpoint.isFeedBack,
            ifKnowledge: endpoint.ifKnowledge,
            ifSearch: endpoint.ifSearch,
            ifToolUse: endpoint.ifToolUse,
            ifThink: endpoint.ifThink,
            ifAudio: endpoint.ifAudio,
            ifPlanning: endpoint.ifPlanning,
            thinkingLength: endpoint.thinkingLength,
            showKnowledgeAlert: endpoint.showKnowledgeAlert,
            knowledgeAlertMessage: endpoint.knowledgeAlertMessage,
            showSearchAlert: endpoint.showSearchAlert,
            selectedImageSize: endpoint.selectedImageSize,
            imageReversePrompt: endpoint.imageReversePrompt,
            isInputActive: isInputActive,
            dockContextKey: endpoint.sessionID.uuidString,
            availableWorkspaceSize: availableWorkspaceSize,
            readCurrentMessageState: endpoint.readCurrentMessageState,
            capabilityDraft: endpoint.capabilityDraft,
            composerCapabilities: HanlinComposerCapabilities.catalog()
        )
    }
}
