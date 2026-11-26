import HanlinLocalization
//
//  Views/ChatView.swift
//  AI_HLY
//
//  Created by 哆啦好多梦 on 3/2/25.
//

import SwiftUI
import HanlinChatUI
import HanlinPresentationKit
import HanlinRichUI
import AVFoundation
import SwiftData
import UniformTypeIdentifiers
import HanlinHostContracts
import HanlinPlatformContracts

// 聊天界面
@MainActor
struct ChatView: View {
    @Environment(\.locale) private var hanlinLocalizationLocale

    var chatRecord: ChatRecords
    var surface: HanlinConversationSurface = .full
    var externalComposerBottomInset: CGFloat? = nil
    var availableComposerWorkspaceSize: CGSize? = nil
    @Environment(\.scenePhase) private var chatScenePhase
    // 输入与会话状态相关
    @State private var composerDraft = HanlinComposerDraft()

    // One owner for native edits, restored drafts and send clears. Keeping the
    // value behind the original ChatView's stable reference lets the external
    // compact composer read it before SwiftUI refreshes a retained Binding.
    private var message: String {
        get { composerDraft.text }
        nonmutating set { composerDraft.text = newValue }
    }

    private var messageBinding: Binding<String> {
        let draft = composerDraft
        return Binding(get: { draft.text }, set: { draft.text = $0 })
    }
    @State private var isResponding = false                // 是否处于系统响应状态
    @State private var isCancelled = false                 // 是否被打断
    @State private var respondIndex = 0                    // 当前响应请求的索引
    @FocusState private var isInputActive: Bool            // 输入框是否聚焦
    @State private var isObserving = false                 // 是否处于观察模式
    @State private var isRetry = false                     // 是否为重试请求
    @State private var retryMessagesOverride: [ChatMessages]?
    @State private var sessionScopeID = UUID()

    private var effectiveChatSessionID: UUID {
        chatRecord.id ?? sessionScopeID
    }

    @State private var chatTitle = String(localized: "新群聊", bundle: HanlinLocalization.bundle)                 // 群聊标题
    @State private var isEditingTitle = false              // 是否正在编辑群聊标题
    @State private var newChatTitle = ""                   // 编辑群聊标题时的临时变量

    // 媒体与附件相关
    @State private var selectedImages: [UIImage] = []      // 存储选定的图片
    @State private var showPhotoSourceOptions = false      // 控制图片来源选择框的显示
    @State private var showFastImagePicker = false         // 控制相册选择器的显示
    @State private var showFastCameraPicker = false        // 控制相机选择器的显示
    @State private var selectedDocumentURLs: [URL] = []    // 存储选定的文档 URL
    @State private var selectedImageSize: String = "square"// 选定的生成画幅
    @State private var imageReversePrompt: String = ""     // 反向提示词
    @State private var audioEngine = AVAudioEngine()
    @State private var audioPlayerNode = AVAudioPlayerNode()

    // 搜索与模型选择相关
    @State private var ifSearch = false                    // 控制是否进行联网搜索
    @State private var ifKnowledge = false                 // 控制是否进行知识库搜索
    @State private var ifToolUse = true                    // 控制是否进行工具使用
    @State private var ifThink = false                     // 控制是否进行深度思考
    @State private var ifAudio = false                     // 控制是否进行语音生成
    @State private var ifPlanning = false                  // 控制是否进行规划生成
    @State private var thinkingLength: Int = 0             // 控制思维长度
    @State private var ImageSize: String = "Square"        // 控制图像生成的画幅
    @State private var showModelSheet = false              // 控制模型列表的显示
    @State private var loadHistoryMessages = false         // 控制历史数据加载状态
    @State private var selectedModelIndex: Int = -1        // 当前选中的模型
    @State private var showKnowledgeAlert = false          // 显示知识库的错误
    @State private var KnowledgeAlertMessgae: String = ""  // 错误信息
    @State private var showSearchAlert = false             // 显示搜索引擎未启用提示弹窗

    // 参数调整（滑块）相关
    @State private var showTemperatureSlider = false       // 控制采样温度滑块显示
    @State private var temperature: Double = 0.8           // 采样温度参数（默认 0.8）
    @State private var showTopPSlider = false              // 控制累积概率滑块显示
    @State private var topP: Double = 0.9                  // 累积概率参数（默认 0.9）
    @State private var showMaxTokensSlider = false         // 控制最大回复长度滑块显示
    @State private var maxTokens: Int = 2048               // 最大输出参数（默认 2048）
    @State private var showMaxMessagesNumSlider = false    // 控制消息数量上限滑块显示
    @State private var maxMessagesNum: Int = 20            // 消息数量上限（默认 20）

    // 反馈与动画相关
    @State private var isFeedBack = false                   // 是否需要震动反馈
    @State private var isOutPut = false                     // 输出反馈状态（用于触发动画）
    @State private var outPutFeedBackEnabled: Bool = true   // 是否启用输出反馈震动

    // 聊天数据管理相关
    @State private var allMessages: [ChatMessages] = []     // 所有聊天记录
    @State private var loadedMessageCount: Int = 0          // 当前加载的消息数量
    @State private var topVisibleMessageID: UUID? = nil     // 当前顶部可见消息的ID
    @State private var TemporaryRecord: Bool = false        // 是否为临时聊天
    @State private var useSystemMessage: Bool = true        // 是否自定义系统消息
    @State private var systemMessage: String = ""           // 是否系统消息内容
    @State private var showSystemMessageSheet = false       // 打开系统消息设置
    @State private var operationalState: String = ""        // 操作状态文本
    @State private var operationalDescription: String = ""  // 操作描述文本
    @State private var apiManager: APIManager?
    @State private var agentSessionOwner = HanlinAppAgentSessionOwner()
    @State private var richPresentation = HanlinAppRichPresentation()
    @State private var showsResearchSources = false
    @Environment(\.openURL) private var openRichURL

    #if HANLIN_A2UI_POC
    @State private var a2uiPresentation: HanlinA2UIAppPresentation?
    @State private var a2uiSubmittingAction: HanlinA2UIAppPresentation.PendingAction?
    @State private var a2uiOriginalModelChoice: A2UIModelChoice?
    @State private var a2uiHistoryUnavailable = false

    private struct A2UIModelChoice: Equatable, Sendable {
        let id: UUID
        let company: String?
        let name: String?
    }

    private struct A2UIHistoryScope: Equatable, Sendable {
        let conversationID: UUID?
        let temporary: Bool
        let model: A2UIModelChoice?
        let session: HanlinHostSession?
    }

    private var a2uiModelChoice: A2UIModelChoice? {
        guard modelTemp.indices.contains(selectedModelIndex) else { return nil }
        let model = modelTemp[selectedModelIndex]
        return .init(id: model.id, company: model.company, name: model.name)
    }
    #endif
    @State private var activeAgentCoordinator: AgentRunCoordinator?
    @State private var activeTurnProjection: HanlinConversationStreamProjection?
    @State private var agentRunReadCache = HanlinAgentRunReadCache()
    @State private var activeAgentRun: AgentRun?
    @State private var activeAgentMessage: ChatMessages?

    // URL解析与多选操作相关
    @State private var selectedURLs: [String] = []          // 解析出的 URL 列表
    @State private var isMultiSelectMode: Bool = false      // 是否开启多选模式
    @State private var selectedMessageIDs: Set<UUID> = []   // 选中的消息 ID 集合
    @Environment(\.chatSourceDestination) private var sourceDestination
    @State private var nativeSelectionIDs: Set<UUID> = []
    @State private var pendingSourceScroll: UUID?
    @State private var sourceScrollTask: Task<Void, Never>?
    @State private var sourceScrollGeneration = UUID()
    @State private var sourceScrollHasRevealed = false
    @State private var sourceScrollNeedsCorrection = false
    @State private var revealedSourceRequest: UUID?
    private var effectiveMatchedMessageID: UUID? {
        if let sourceDestination, sourceDestination.chatRecordID == chatRecord.id { return sourceDestination.messageID }
        return matchedMessageID
    }
    var matchedMessageID: UUID?                             // 匹配的消息 ID
    @State private var showScrollToBottomButton = false     // 控制滚动到底部按钮显示
    @State private var needScrollToBottomButton = false     // 是否需要显示滚动到底部按钮
    @State private var autoFollowController = ChatAutoFollowController(onTrace: { event, fields in
        #if DEBUG || HANLIN_TESTING
        if ProcessInfo.processInfo.environment["HANLIN_COMPOSER_EDIT_DIAGNOSTICS"] == "1" {
            // Controller fields contain geometry, counters and policy state only.
            print("HANLIN_TRANSCRIPT_AUTOFOLLOW event=\(event) fields=\(fields)")
        }
        #endif
        guard AgentDiagnosticsConfiguration.level != .off else { return }
        NativeToolTraceLogger.shared.log(event, fields)
    })
    @State private var transcriptScrollView = ChatScrollViewHandle()
    @State private var measuredComposerHeight: CGFloat = 0
    @State private var chatContainerWidth: CGFloat = 0

    private struct TranscriptBottomTarget: Hashable {
        let conversationID: UUID
    }

    // 提示词管理相关
    @State private var selectedPrompts: [PromptRepo] = []   // 选中的提示词

    // 导出与导入相关
    @State private var showingExportOptions = false         // 是否显示导出选项菜单
    @State private var isShowingExportPicker = false        // 是否显示文件导出选择器
    @State private var exportDocument: ChatExportDocument?  // 导出文件文档
    @State private var exportUTType: UTType = .plainText    // 导出文件类型（默认纯文本）
    // 用于分享的临时文件 URL
    @State private var exportFileURL: URL? = nil
    // 控制分享界面显示
    @State private var showShareSheet: Bool = false
    @State private var exportedImage: UIImage? = nil
    @State private var showImageShareSheet: Bool = false

    @State private var isShowingImportPicker = false        // 是否显示文件导入选择器
    @State private var importError: String? = nil           // 导入错误信息
    @State private var isShowingImportErrorAlert = false    // 是否显示导入错误弹窗
    @State private var showClearChatConfirmation = false    // 清空聊天记录确认弹窗显示标志
    @State private var showClearChatError = false
    @State private var showImportExplanationAlert = false   // 导入聊天记录说明弹窗显示标志
    
    // 便捷输入
    @State private var showModelSuggestions: Bool = false
    @State private var filteredModels: [AllModels] = []
    
    @Environment(\.modelContext) private var context: ModelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.hanlinExternalCompactComposerHost) private var isExternalCompactComposerHost
    @Environment(\.hanlinExternalDockHeight) private var externalDockHeight
    @Environment(\.hanlinComposerSessionBridge) private var sessionBridge

    @State private var composerRegistrationToken = UUID()
    @State private var measuredWorkspaceSize: CGSize = .zero
    @State private var chatTemps: [ChatMessages] = []
    @State private var modelTemp: [AllModels] = []
    @Query private var userInfos: [UserInfo]
    
    private func handleOnAppear() {
        loadHistoryMessages = true
        
        // 直接在主线程内读取 SwiftData 数据（View 已标记 @MainActor）
        let messages: [ChatMessages] = chatRecord.messages ?? []
        
        do {
            let fetchDesc = FetchDescriptor<AllModels>(
                sortBy: [ SortDescriptor(\AllModels.position, order: .forward) ]
            )
            self.modelTemp = try context.fetch(fetchDesc)
        } catch {
            print("Failed to fetch AllModels:", error)
            self.modelTemp = []
        }
        
        let feedbackEnabled = (try? context.fetch(FetchDescriptor<UserInfo>()).first?.outPutFeedBack) ?? true
        
        // 同步参数设置
        message = chatRecord.input ?? ""
        temperature = chatRecord.temperature
        topP = chatRecord.topP
        maxTokens = chatRecord.maxTokens
        maxMessagesNum = chatRecord.maxMessagesNum
        useSystemMessage = chatRecord.useSystemMessage
        systemMessage = chatRecord.systemMessage ?? ""
        
        // 对聊天记录和模型数据排序
        let sortedMessages = messages.sorted { $0.timestamp < $1.timestamp }
        let firstVisibleModelIndex = HanlinDefaultChatPolicy.defaultModelIndex(in: modelTemp) ?? 0
        
        // 根据匹配消息决定加载数量
        let targetCount: Int
        if let matchedID = effectiveMatchedMessageID,
           let matchedIndex = sortedMessages.firstIndex(where: { $0.id == matchedID }) {
            let matchedFromBottom = sortedMessages.count - matchedIndex
            targetCount = (matchedFromBottom <= 20) ? 20 : ((matchedFromBottom + 9) / 10) * 10
        } else {
            targetCount = 20
        }
        
        allMessages = sortedMessages
        loadedMessageCount = min(targetCount, sortedMessages.count)
        chatTemps = Array(sortedMessages.suffix(loadedMessageCount))
        topVisibleMessageID = chatTemps.first?.id
        
        chatTitle = chatRecord.name ?? "Unknown"
        loadHistoryMessages = false
        outPutFeedBackEnabled = feedbackEnabled
        selectedModelIndex = chatRecord.useModel ?? -1
        if selectedModelIndex >= 0 && selectedModelIndex < modelTemp.count && modelTemp[selectedModelIndex].isHidden == false {
            selectModel(at: selectedModelIndex)
        } else {
            selectedModelIndex = firstVisibleModelIndex
            selectModel(at: selectedModelIndex)
        }
        
        // 延时后通知模型选择区域滚动
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                NotificationCenter.default.post(name: .scrollToModelIndex, object: selectedModelIndex)
            }
        }
    }
    
    private func loadMoreMessages() {
        // 每次增加10条，但不超过所有消息总数
        let newCount = min(allMessages.count, loadedMessageCount + 15)
        if newCount > loadedMessageCount {
            loadedMessageCount = newCount
            // 从 allMessages 中取出最新 newCount 条（即后面的 newCount 条），保持顺序
            chatTemps = Array(allMessages.suffix(newCount))
        }
    }
    
    static func calculateDynamicBottomPadding(
        measuredComposerHeight: CGFloat,
        hasURLs: Bool,
        hasImages: Bool,
        hasDocuments: Bool,
        showPhotoSourceOptions: Bool,
        hasPrompts: Bool
    ) -> CGFloat {
        if measuredComposerHeight.isFinite, measuredComposerHeight > 40 {
            return max(96, min(measuredComposerHeight + 20, 680))
        }
        var baseHeight: CGFloat = 116
        if hasURLs { baseHeight += 32 }
        if hasImages { baseHeight += 44 }
        if hasDocuments { baseHeight += 32 }
        if showPhotoSourceOptions { baseHeight += 110 }
        if hasPrompts { baseHeight += 44 }
        return baseHeight
    }

    private func dynamicBottomPadding() -> CGFloat {
        if let inset = externalComposerBottomInset, inset.isFinite { return max(0, inset) }
        if isExternalCompactComposerHost {
            let height = externalDockHeight + 24
            return height.isFinite ? max(24, height) : 24
        }
        return Self.calculateDynamicBottomPadding(
            measuredComposerHeight: measuredComposerHeight,
            hasURLs: !selectedURLs.isEmpty,
            hasImages: !selectedImages.isEmpty,
            hasDocuments: !selectedDocumentURLs.isEmpty,
            showPhotoSourceOptions: showPhotoSourceOptions,
            hasPrompts: !selectedPrompts.isEmpty
        )
    }

    private func makeExternalComposerEndpoint() -> HanlinActiveComposerSessionBridge.Endpoint {
        HanlinActiveComposerSessionBridge.Endpoint(
            sessionID: effectiveChatSessionID,
            registrationToken: composerRegistrationToken,
            isReadyToSend: !loadHistoryMessages && !modelTemp.isEmpty,
            chatRecord: chatRecord,
            modelTemp: modelTemp,
            temporaryRecord: TemporaryRecord,
            respondIndex: respondIndex,
            selectedModelIndex: $selectedModelIndex,
            showScrollToBottomButton: $showScrollToBottomButton,
            needScrollToBottomButton: $needScrollToBottomButton,
            isMultiSelectMode: $isMultiSelectMode,
            selectedMessageIDs: $selectedMessageIDs,
            chatTemps: $chatTemps,
            showTemperatureSlider: $showTemperatureSlider,
            temperature: $temperature,
            showTopPSlider: $showTopPSlider,
            topP: $topP,
            showMaxTokensSlider: $showMaxTokensSlider,
            maxTokens: $maxTokens,
            showMaxMessagesNumSlider: $showMaxMessagesNumSlider,
            maxMessagesNum: $maxMessagesNum,
            message: messageBinding,
            selectedImages: $selectedImages,
            selectedDocumentURLs: $selectedDocumentURLs,
            selectedURLs: $selectedURLs,
            selectedPrompts: $selectedPrompts,
            showPhotoSourceOptions: $showPhotoSourceOptions,
            showModelSuggestions: $showModelSuggestions,
            filteredModels: $filteredModels,
            isResponding: agentBusyBinding,
            isFeedBack: $isFeedBack,
            ifKnowledge: $ifKnowledge,
            ifSearch: $ifSearch,
            ifToolUse: $ifToolUse,
            ifThink: $ifThink,
            ifAudio: $ifAudio,
            ifPlanning: $ifPlanning,
            thinkingLength: $thinkingLength,
            showKnowledgeAlert: $showKnowledgeAlert,
            knowledgeAlertMessage: $KnowledgeAlertMessgae,
            showSearchAlert: $showSearchAlert,
            selectedImageSize: $selectedImageSize,
            imageReversePrompt: $imageReversePrompt,
            onSelectModel: selectModel,
            onSendUser: { handleMessageSending(ifObservingMode: false) },
            onSendObserve: { handleMessageSending(ifObservingMode: true) },
            onCancel: handleCancellation,
            validateSendAcceptance: { [self] in
                isResponding || chatTemps.contains(where: { $0.role == "user" })
            },
            readCurrentMessageState: { [composerDraft] in composerDraft.snapshot }
        )
    }

    private struct ComposerBridgeSyncState: Equatable {
        var temporaryRecord: Bool
        var respondIndex: Int
        var isResponding: Bool
        var selectedImagesCount: Int
        var selectedDocumentURLs: [URL]
        var selectedURLs: [String]
        var selectedPromptsCount: Int
        var selectedModelIndex: Int
        var ifKnowledge: Bool
        var ifSearch: Bool
        var ifToolUse: Bool
        var ifThink: Bool
        var ifAudio: Bool
        var ifPlanning: Bool
    }

    private var agentBusyBinding: Binding<Bool> {
        Binding(get: { isResponding || agentSessionOwner.inlineToolIsRunning }, set: { isResponding = $0 })
    }

    private var composerBridgeSyncState: ComposerBridgeSyncState {
        ComposerBridgeSyncState(
            temporaryRecord: TemporaryRecord,
            respondIndex: respondIndex,
            isResponding: isResponding || agentSessionOwner.inlineToolIsRunning,
            selectedImagesCount: selectedImages.count,
            selectedDocumentURLs: selectedDocumentURLs,
            selectedURLs: selectedURLs,
            selectedPromptsCount: selectedPrompts.count,
            selectedModelIndex: selectedModelIndex,
            ifKnowledge: ifKnowledge,
            ifSearch: ifSearch,
            ifToolUse: ifToolUse,
            ifThink: ifThink,
            ifAudio: ifAudio,
            ifPlanning: ifPlanning
        )
    }

    private func syncComposerEndpointWithBridge() {
        guard let sessionBridge else { return }
        sessionBridge.update(endpoint: makeExternalComposerEndpoint())
    }

    private var resolvedChatShell: ShellDescriptor {
        (try? richPresentation.profile(for: chatRecord, conversationID: effectiveChatSessionID).shell)
            ?? .init(id: "hanlin.standard", title: "Hanlin")
    }

    @ViewBuilder
    private var chatWorkspaceStack: some View {
        if resolvedChatShell.usesSourcesSidebar {
            HanlinResearchShell(showsSources: $showsResearchSources) {
                canonicalChatWorkspace
            } sources: {
                List(researchSources, id: \.link) { source in
                    if let url = URL(string: source.link) { Link(source.title, destination: url) }
                }
                .navigationTitle(Text("Sources", bundle: HanlinLocalization.bundle))
            }
        } else { canonicalChatWorkspace }
    }

    private var researchSources: [Resource] {
        var seen = Set<String>()
        return chatTemps.flatMap { $0.resources ?? [] }.filter { seen.insert($0.link).inserted }
    }

    @ViewBuilder
    private var canonicalComposer: some View {
        if !isExternalCompactComposerHost {
            HanlinMountedComposerContent(endpoint: makeExternalComposerEndpoint(),
                isInputActive: $isInputActive,
                availableWorkspaceSize: availableComposerWorkspaceSize ?? measuredWorkspaceSize)
        }
    }

    private var canonicalChatWorkspace: some View {
        Group {
            if surface == .composer {
                canonicalComposer
            } else {
                HanlinChatView(shell: resolvedChatShell,
                               showsComposerBackdrop: !isExternalCompactComposerHost) {
                    ScrollViewReader { scrollViewProxy in
                        buildScrollContent(scrollViewProxy).padding(.bottom, 6)
                    }
                    // A reader may retain a pending scroll context until its native
                    // scroll view attaches. Never carry that context to another chat.
                    // Keyboard, split-view resizing and activity updates keep this ID.
                    .id(effectiveChatSessionID)
                } composer: {
                    canonicalComposer
                }
            }
        }
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { newSize in
                guard newSize.width.isFinite, newSize.height.isFinite,
                      newSize.width > 0, newSize.height > 0 else { return }
                if abs(measuredWorkspaceSize.width - newSize.width) > 1 || abs(measuredWorkspaceSize.height - newSize.height) > 1 {
                    measuredWorkspaceSize = newSize
                }
            }
            .onPreferenceChange(ComposerHeightPreferenceKey.self) { newHeight in
                guard newHeight.isFinite, newHeight > 0,
                      abs(measuredComposerHeight - newHeight) > 1 else { return }
                measuredComposerHeight = newHeight
            }
    }

    // Opaque boundaries keep the original modifier order without adding layout containers.
    private var agentConnectedWorkspace: some View {
        chatWorkspaceStack
        .chatMotionPreferences()
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Button(hanlin: "Standard conversation") { richPresentation.select("hanlin.standard", conversation: chatRecord,
                        conversationID: effectiveChatSessionID, context: context, temporary: TemporaryRecord) }
                    Button(hanlin: "Research conversation") { richPresentation.select("hanlin.research", conversation: chatRecord,
                        conversationID: effectiveChatSessionID, context: context, temporary: TemporaryRecord) }
                    if resolvedChatShell.usesSourcesSidebar { Button(hanlin: "Sources") { showsResearchSources.toggle() } }
                } label: { Label(hanlin: "Conversation presentation", systemImage: "rectangle.3.group") }
                .disabled(isResponding)
            }
        }
        #if HANLIN_A2UI_POC
        .environment(\.hanlinA2UIAppPresentation, a2uiPresentation)
        .environment(\.hanlinA2UIResultProjectionSource, a2uiPresentation?.toolSource)
        #if (DEBUG || HANLIN_TESTING) && targetEnvironment(simulator)
        .safeAreaInset(edge: .top) {
            if HanlinNativeA2UIAcceptanceProvider.isEnabled {
                HanlinA2UIAcceptanceStatusView(isResponding: isResponding, conversationID: chatRecord.id)
            } else if AgentRuntimeUIAcceptanceProvider.phase2StoreID != nil {
                HanlinPhase2AcceptanceStatusView(isResponding: isResponding, conversationID: chatRecord.id)
            }
        }
        #endif
        .task(id: A2UIHistoryScope(conversationID: chatRecord.id, temporary: TemporaryRecord,
            model: a2uiModelChoice, session: agentSessionOwner.session?.identity)) { @MainActor in
            guard let originalID = chatRecord.id else { return }
            let originalConversation = chatRecord
            let originalScene = sessionScopeID
            let originalTemporary = TemporaryRecord || sessionBridge?.isTemporaryChat(originalID) == true
            if a2uiPresentation == nil { a2uiPresentation = HanlinA2UIAppPresentation() }
            agentSessionOwner.presentation = a2uiPresentation
            a2uiHistoryUnavailable = false
            do {
                try await agentSessionOwner.restoreHistory(conversation: originalConversation,
                    conversationID: originalID, sceneID: originalScene,
                    temporary: originalTemporary, modelContext: context)
                for run in chatTemps.compactMap(\.agentRun) where run.id != activeAgentRun?.id {
                    a2uiPresentation?.synchronizeTools(run, isLive: false)
                }
            } catch is CancellationError {
                return
            } catch let error as HanlinHostError where error == .staleContext || error == .cancelled {
                return
            } catch {
                guard !Task.isCancelled, chatRecord === originalConversation, sessionScopeID == originalScene else { return }
                a2uiHistoryUnavailable = true
                NativeToolTraceLogger.shared.log("a2ui_history_restore_failed", ["code": "unavailable"])
            }
        }
        .safeAreaInset(edge: .top) {
            if a2uiHistoryUnavailable {
                Label(hanlin: "Some rich content could not be restored.", systemImage: "exclamationmark.bubble")
                    .font(HanlinTypography.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    .accessibilityIdentifier("hanlin-a2ui-history-unavailable")
            }
        }
        .onChange(of: a2uiPresentation?.pendingAction?.request.requestID) { _, _ in
            guard let action = a2uiPresentation?.takePendingAction(), !isResponding,
                  a2uiPresentation?.isCurrent(action) == true,
                  a2uiModelChoice == a2uiOriginalModelChoice else { return }
            a2uiSubmittingAction = action
            handleMessageSending(ifObservingMode: false, continuationText: String(localized: "Form submitted", bundle: HanlinLocalization.bundle))
        }
        .onChange(of: a2uiModelChoice) { _, current in
            guard let original = a2uiOriginalModelChoice, original != current else { return }
            if isResponding { handleCancellation() }
            agentSessionOwner.cancel()
            a2uiOriginalModelChoice = nil
        }
        #endif
    }

    private var lifecycleWorkspace: some View {
        agentConnectedWorkspace
        .toolbar((horizontalSizeClass == .compact || isExternalCompactComposerHost) ? .hidden : .visible, for: .tabBar)
        .background(Color(.systemBackground))
        .background {
            // Observe typing below the transcript. Neither the workspace nor
            // its SwiftData conversation changes for every native keystroke.
            HanlinDraftPersistence(draft: composerDraft, record: chatRecord, temporary: TemporaryRecord)
        }
        .onAppear {
            #if HANLIN_A2UI_POC
            if a2uiPresentation == nil { a2uiPresentation = HanlinA2UIAppPresentation() }
            agentSessionOwner.presentation = a2uiPresentation
            #endif
            composerRegistrationToken = UUID()
            if sessionBridge?.isTemporaryChat(effectiveChatSessionID) == true {
                TemporaryRecord = true
            }
            handleOnAppear()
            // Inline and external composers share the mounted chat's send endpoint.
            // Imported first turns must also dispatch in the wide iPad layout.
            sessionBridge?.register(endpoint: makeExternalComposerEndpoint())
            if horizontalSizeClass == .compact || isExternalCompactComposerHost {
                NotificationCenter.default.post(name: .hideTabBar, object: true) // 仅在紧凑模式下隐藏 TabBar
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: HanlinConversationMutation.didChange)) { notification in
            guard let change = HanlinConversationMutation.change(from: notification, in: context.container),
                  change.originalRow == ObjectIdentifier(chatRecord) else { return }
            applyConversationChange(change)
        }
        .onChange(of: chatScenePhase) { _, phase in
            if phase != .active, !TemporaryRecord {
                openHistory()
            }
        }
        .onChange(of: TemporaryRecord) { _, newValue in
            if isResponding { handleCancellation() }
            agentSessionOwner.cancel()
            sessionBridge?.setTemporaryChat(newValue, for: effectiveChatSessionID)
        }
        .onChange(of: chatRecord.id) { _, _ in
            agentSessionOwner.cancel()
            cancelSourceScroll()
            autoFollowController.invalidateLayout()
            autoFollowController.resumeFollowing(reason: "conversationChanged")
            transcriptScrollView.activate(conversationID: effectiveChatSessionID)
        }
        .onChange(of: sessionBridge?.expectedActiveSessionID) { _, current in
            if sessionBridge != nil, current != effectiveChatSessionID { agentSessionOwner.cancel() }
        }
        .onChange(of: composerBridgeSyncState) { _, _ in
            syncComposerEndpointWithBridge()
        }
        .onDisappear {
            // The workspace router supplies actual selection ownership. A sheet/full-screen
            // result that leaves that original selection mounted does not revoke its Session.
            if let sessionBridge, sessionBridge.expectedActiveSessionID != effectiveChatSessionID {
                agentSessionOwner.cancel()
            }
            sessionBridge?.unregister(sessionID: effectiveChatSessionID, token: composerRegistrationToken)
            if horizontalSizeClass == .compact || isExternalCompactComposerHost {
                NotificationCenter.default.post(name: .hideTabBar, object: false) // 显示 TabBar
            }
            openHistory()
            if TemporaryRecord && sessionBridge?.isTransitioningLayoutMode != true {
                agentSessionOwner.cancel() // Revoke synchronously before deleting the original conversation.
                sessionBridge?.clearCachedDraft(for: effectiveChatSessionID)
                do {
                    try HanlinConversationMutation.delete(chatRecord, in: context, temporary: true)
                } catch {
                    print("退出时删除临时聊天记录失败: \(error)")
                }
            }
        }
    }

    private var navigationWorkspace: some View {
        lifecycleWorkspace
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 群聊名称（中间，带有可编辑功能）
            ToolbarItem(placement: .principal) {
                if TemporaryRecord {
                    HStack {
                        Text(" 临 时 对 话 模 式 ", bundle: HanlinLocalization.bundle)
                            .font(HanlinTypography.caption)
                            .padding(6)
                    }
                    .background(
                        BlurView(style: .systemUltraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 26))
                            .shadow(color: .primary, radius: 1)
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: TemporaryRecord)
                } else {
                    ZStack {
                        // 普通显示模式
                        Text(chatTitle)
                            .font(HanlinTypography.headline)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .opacity(isEditingTitle ? 0 : 1)
                            .onTapGesture {
                                newChatTitle = chatTitle
                                isEditingTitle = true
                            }
                        
                        // 编辑模式
                        TextField(String(localized: "请输入群聊名称", bundle: HanlinLocalization.bundle, locale: hanlinLocalizationLocale), text: $newChatTitle, onCommit: {
                            if !newChatTitle.isEmpty {
                                if chatTitle != newChatTitle {
                                    do {
                                        let newMessage = try HanlinConversationMutation.rename(chatRecord,
                                            title: newChatTitle, announceChange: true, in: context,
                                            temporary: TemporaryRecord)
                                        chatTitle = newChatTitle
                                        if let newMessage, !chatTemps.contains(where: { $0.id == newMessage.id }) {
                                            chatTemps.append(newMessage)
                                        }
                                    } catch {
                                        print("Failed to save message: \(error)")
                                    }
                                }
                            }
                            isEditingTitle = false
                        })
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(minWidth: 120, maxWidth: 220) // 限制输入框宽度
                        .multilineTextAlignment(.center)
                        .opacity(isEditingTitle ? 1 : 0) // 仅编辑模式可见
                    }
                }
            }
            
            // 在右上角菜单按钮左侧增加 TemporaryRecord 状态图标
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    TemporaryRecord.toggle() // 点击切换状态
                }) {
                    if TemporaryRecord {
                        Image(systemName: "exclamationmark.bubble.fill")
                            .font(HanlinTypography.body)
                            .foregroundColor(.primary)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                            .animation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0.4), value: TemporaryRecord)
                    } else {
                        Image(systemName: "checkmark.bubble")
                            .font(HanlinTypography.body)
                            .foregroundColor(.primary)
                            .transition(.opacity.combined(with: .move(edge: .leading)))
                            .animation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0.4), value: TemporaryRecord)
                    }
                }
                .buttonStyle(.plain)
            }
            
            // 右侧按钮
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    // ------ 调整参数 ------
                    Menu(hanlin: "调整模型参数", systemImage: "slider.horizontal.3"){
                        Button(action: {
                            showTopPSlider = false
                            showMaxTokensSlider = false
                            showMaxMessagesNumSlider = false
                            showTemperatureSlider.toggle()
                        }) {
                            Label(hanlin: "调整采样温度", systemImage: "thermometer.variable")
                        }
                        
                        Button(action: {
                            showTemperatureSlider = false
                            showMaxTokensSlider = false
                            showMaxMessagesNumSlider = false
                            showTopPSlider.toggle()
                        }) {
                            Label(hanlin: "调整累积概率", systemImage: "percent")
                        }
                        
                        Button(action: {
                            showTemperatureSlider = false
                            showTopPSlider = false
                            showMaxMessagesNumSlider = false
                            showMaxTokensSlider.toggle()
                        }) {
                            Label(hanlin: "最大回复长度", systemImage: "textformat.characters.arrow.left.and.right")
                        }
                        
                        Button(action: {
                            showTemperatureSlider = false
                            showTopPSlider = false
                            showMaxTokensSlider = false
                            showMaxMessagesNumSlider.toggle()
                        }) {
                            Label(hanlin: "消息数量上限", systemImage: "arrow.up.and.down.text.horizontal")
                        }
                    }
                    
                    // ------ 聊天记录管理 ------
                    Menu(hanlin: "聊天记录管理", systemImage: "bubble.left.and.bubble.right"){
                        Button(action: {
                            showSystemMessageSheet = true
                        }) {
                            Label(hanlin: "设置系统消息", systemImage: "paintbrush.pointed")
                        }
                        Button(action: {
                            isMultiSelectMode.toggle()
                        }) {
                            Label(isMultiSelectMode ? "退出编辑模式" : "编辑聊天记录", systemImage: "checkmark.circle")
                        }
                        
                        Button(action: {
                            showingExportOptions = true
                        }) {
                            Label(hanlin: "导出聊天记录", systemImage: "square.and.arrow.up")
                        }
                        
                        Button(action: {
                            showImportExplanationAlert = true
                        }) {
                            Label(hanlin: "导入聊天记录", systemImage: "square.and.arrow.down")
                        }
                        
                        Button(action: {
                            showClearChatConfirmation = true
                        }) {
                            Label(hanlin: "清空聊天记录", systemImage: "eraser.line.dashed")
                        }
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(HanlinTypography.body)
                        .foregroundColor(.primary)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0.4), value: TemporaryRecord)
                }
            }
        }
    }

    var body: some View {
        navigationWorkspace
        .confirmationDialog(Text("选择导出格式", bundle: HanlinLocalization.bundle), isPresented: $showingExportOptions, titleVisibility: .visible) {
            Button(hanlin: "纯文本 (.txt)") {
                exportUTType = UTType.plainText
                let exportText = generateExportText(for: .txt)
                let fileName = "ChatExport.txt"
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                do {
                    try exportText.write(to: tempURL, atomically: true, encoding: .utf8)
                    exportFileURL = tempURL
                    showShareSheet = true
                } catch {
                    print("写入临时文件失败：\(error)")
                }
            }
            Button(hanlin: "JSON文件 (.json)（文本）") {
                exportUTType = UTType.json
                let exportText = generateExportText(for: .json, includeImages: false)
                let fileName = "ChatExport_text.json"
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                do {
                    try exportText.write(to: tempURL, atomically: true, encoding: .utf8)
                    exportFileURL = tempURL
                    showShareSheet = true
                } catch {
                    print("写入临时文件失败：\(error)")
                }
            }
            Button(hanlin: "JSON文件 (.json)（多模态）") {
                exportUTType = UTType.json
                let exportText = generateExportText(for: .json, includeImages: true)
                let fileName = "ChatExport_multimodal.json"
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                do {
                    try exportText.write(to: tempURL, atomically: true, encoding: .utf8)
                    exportFileURL = tempURL
                    showShareSheet = true
                } catch {
                    print("写入临时文件失败：\(error)")
                }
            }
            Button(hanlin: "取消", role: .cancel) { }
        }
        .sheet(isPresented: $showShareSheet, onDismiss: {
            // 分享结束后清除临时文件 URL
            exportFileURL = nil
        }) {
            if let fileURL = exportFileURL {
                ActivityViewController(activityItems: [fileURL])
            } else {
                // 安全兜底，防止 nil 时不显示内容
                EmptyView()
            }
        }
        .sheet(isPresented: $showSystemMessageSheet) {
            SystemMessageSettingsView(useSystemMessage: $useSystemMessage, systemMessage: $systemMessage)
        }
        .fileImporter(
            isPresented: $isShowingImportPicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            receiveChatImport(result)
        }
        .alert(isPresented: $isShowingImportErrorAlert) {
            Alert(title: Text("导入错误", bundle: HanlinLocalization.bundle),
                  message: Text(importError ?? "未知错误"),
                  dismissButton: .default(Text("确定", bundle: HanlinLocalization.bundle)))
        }
        .alert(Text("确认清空聊天记录", bundle: HanlinLocalization.bundle), isPresented: $showClearChatConfirmation) {
            Button(hanlin: "删除", role: .destructive) {
                newConversation()
            }
            Button(hanlin: "取消", role: .cancel) { }
        } message: {
            Text("是否要删除所有聊天记录？删除后不可恢复。", bundle: HanlinLocalization.bundle)
                .multilineTextAlignment(.leading)
        }
        .alert(Text("Unable to clear chat history", bundle: HanlinLocalization.bundle), isPresented: $showClearChatError) {
            Button(hanlin: "OK", role: .cancel) { }
        } message: {
            Text("The conversation was not cleared. Please try again.", bundle: HanlinLocalization.bundle)
        }
        .alert(Text("导入聊天记录说明", bundle: HanlinLocalization.bundle), isPresented: $showImportExplanationAlert) {
            Button(hanlin: "继续") {
                isShowingImportPicker = true
            }
            Button(hanlin: "取消", role: .cancel) { }
        } message: {
            Text("请提供 JSON 文件，格式要求与本软件导出的 JSON 文件格式一致，本软件采用 OpenAI 的请求 JSON 格式，包括文本对话和含图片的多模态对话，图片使用 base64 数据。", bundle: HanlinLocalization.bundle)
                    .multilineTextAlignment(.leading)
        }
        .tint(TemporaryRecord ? .primary : nil)
    }
    private func receiveChatImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                guard url.startAccessingSecurityScopedResource() else {
                    importError = "无法访问所选文件的权限。"
                    isShowingImportErrorAlert = true
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }
                do {
                    let data = try Data(contentsOf: url)
                    // 尝试先按多模态 JSON 格式解析
                    if let importedMessages = try? JSONDecoder().decode([ExportMessage].self, from: data) {
                        importMessages(importedMessages: importedMessages)
                    }
                    // 如果失败，再尝试解析纯文本 JSON 格式
                    else if let simpleMessages = try? JSONDecoder().decode([[String: String]].self, from: data) {
                        importSimpleMessages(simpleMessages: simpleMessages)
                    } else {
                        importError = "文件格式错误，请检查文件是否为导出时的正确格式。"
                        isShowingImportErrorAlert = true
                    }
                } catch {
                    importError = error.localizedDescription
                    isShowingImportErrorAlert = true
                }
            }
        case .failure(let error):
            importError = error.localizedDescription
            isShowingImportErrorAlert = true
        }
    }

    /// 用于触发滚动的状态集合
    private struct ScrollTriggerState: Equatable {
        var lastID: UUID?
        var ifSearch: Bool
        var ifKnowledge: Bool
        var selectedURLsIsEmpty: Bool
        var selectedPromptsCount: Int
        var selectedImagesIsEmpty: Bool
        var selectedDocumentString: Bool
        var showPhotoSourceOptions: Bool
        var isInputActive: Bool
        var showModelSuggestions: Bool
        var showVisualSuggestion: Bool
        var showImageSize: Bool
    }
    
    /// Route saved excerpts through this existing chat, preserving its composer/run.
    /// First reveal the lazy row, then correct its position after Markdown finishes layout.
    @MainActor
    private func revealMatchedSource(using proxy: ScrollViewProxy) {
        guard let id = effectiveMatchedMessageID,
              let index = allMessages.firstIndex(where: { $0.id == id }) else {
            cancelSourceScroll()
            return
        }
        cancelSourceScroll()
        revealedSourceRequest = sourceDestination?.id
        autoFollowController.cancelPendingScroll()
        autoFollowController.pauseFollowing(reason: "savedSource")
        let count = allMessages.count - index
        if count > loadedMessageCount {
            loadedMessageCount = min(allMessages.count, max(count + 5, loadedMessageCount))
            chatTemps = Array(allMessages.suffix(loadedMessageCount))
        }
        pendingSourceScroll = id
        scheduleSourceScroll(using: proxy)
    }

    /// The initial reveal and Markdown correction share a cancellable request.
    /// A retained proxy must never position a detached or replaced transcript.
    private func scheduleSourceScroll(using proxy: ScrollViewProxy) {
        guard let id = pendingSourceScroll else { return }
        guard effectiveMatchedMessageID == id, chatTemps.contains(where: { $0.id == id }) else {
            cancelSourceScroll()
            return
        }
        guard !sourceScrollHasRevealed || sourceScrollNeedsCorrection,
              sourceScrollTask == nil, nativeSelectionIDs.isEmpty,
              !autoFollowController.state.isUserInteracting else { return }
        let conversationID = effectiveChatSessionID
        guard transcriptScrollView.layout(conversationID: conversationID) != nil else { return }
        let viewportGeneration = transcriptScrollView.generation
        let requestGeneration = sourceScrollGeneration
        sourceScrollTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled, sourceScrollGeneration == requestGeneration else { return }
            sourceScrollTask = nil
            guard pendingSourceScroll == id else { return }
            guard effectiveMatchedMessageID == id, effectiveChatSessionID == conversationID,
                  chatTemps.contains(where: { $0.id == id }) else {
                cancelSourceScroll()
                return
            }
            guard nativeSelectionIDs.isEmpty, !autoFollowController.state.isUserInteracting,
                  let layout = transcriptScrollView.layout(conversationID: conversationID,
                      expectedGeneration: viewportGeneration) else { return }
            if layout.hasScrollableContent {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) { proxy.scrollTo(id, anchor: .center) }
            }
            sourceScrollHasRevealed = true
            if sourceScrollNeedsCorrection {
                pendingSourceScroll = nil
                sourceScrollNeedsCorrection = false
            }
        }
    }

    private func cancelSourceScroll() {
        sourceScrollTask?.cancel()
        sourceScrollTask = nil
        sourceScrollGeneration = UUID()
        pendingSourceScroll = nil
        sourceScrollHasRevealed = false
        sourceScrollNeedsCorrection = false
    }

    private var scrollTriggerState: ScrollTriggerState {
        ScrollTriggerState(
            lastID: chatTemps.last?.id,
            ifSearch: ifSearch,
            ifKnowledge: ifKnowledge,
            selectedURLsIsEmpty: selectedURLs.isEmpty,
            selectedPromptsCount: selectedPrompts.count,
            selectedImagesIsEmpty: selectedImages.isEmpty,
            selectedDocumentString: selectedDocumentURLs.isEmpty,
            showPhotoSourceOptions: showPhotoSourceOptions,
            isInputActive: isInputActive,
            showModelSuggestions: showModelSuggestions,
            showVisualSuggestion: selectedModelIndex >= 0 && !modelTemp[selectedModelIndex].supportsMultimodal && modelTemp[selectedModelIndex].company != "LOCAL",
            showImageSize: selectedModelIndex >= 0 && modelTemp[selectedModelIndex].supportsImageGen
        )
    }

    // MARK: - 可滚动聊天区
    private func buildScrollContent(_ scrollViewProxy: ScrollViewProxy) -> some View {
        
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8, pinnedViews: []) {
                    // 加载数据提示
                    HStack {
                        Spacer()
                        if loadHistoryMessages {
                            ProgressView()
                                .font(HanlinTypography.caption)
                                .padding()
                        }
                        Spacer()
                    }

                    // 聊天记录
                    ForEach(chatTemps) { msg in
                        createChatBubble(for: msg)
                            .id(msg.id)
                    }

                    Spacer()

                    // 底部留白
                    Color.clear
                        // Give the lazy scroll target an actual finite extent;
                        // padding around an unconstrained Color has no intrinsic
                        // content height during initial/reattachment measurement.
                        .frame(height: dynamicBottomPadding())
                        .animation(.easeInOut(duration: 0.5), value: dynamicBottomPadding())
                        .id(TranscriptBottomTarget(conversationID: effectiveChatSessionID))
                }
                .onChange(of: agentSessionOwner.consent.pending?.id) { _, _ in
                    traceAutoFollowBoundary("consent-changed")
                    scheduleAutoFollow(using: scrollViewProxy, animated: true)
                }
                .padding(.horizontal)
                .frame(maxWidth: .infinity)
                .chatScrollImmediateContentTouches { [transcriptScrollView, conversationID = effectiveChatSessionID] scrollView in
                    transcriptScrollView.bind(scrollView, conversationID: conversationID)
                    traceAutoFollowBoundary(scrollView == nil ? "viewport-unbound" : "viewport-bound")
                    scheduleScrollWhenViewportReady(using: scrollViewProxy)
                }
            }
            .hanlinFeedback(.success, trigger: isOutPut)
            // One measured policy owns positioning. A mutable default bottom
            // anchor also restores offsets during HostingScrollView attachment,
            // bypassing the finite-viewport and current-request checks below.
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("hanlin-chat-transcript")
            .refreshable {
                loadMoreMessages()
            }
            .onChange(of: needScrollToBottomButton) {
                cancelSourceScroll()
                autoFollowController.resumeFollowing()
                scheduleAutoFollow(using: scrollViewProxy, animated: true, force: true)
            }
            .task(id: sourceDestination?.id) {
                revealMatchedSource(using: scrollViewProxy)
            }
            .onChange(of: allMessages.count) {
                if let sourceDestination, revealedSourceRequest != sourceDestination.id {
                    revealMatchedSource(using: scrollViewProxy)
                }
            }
            .task(id: effectiveMatchedMessageID) {
                revealMatchedSource(using: scrollViewProxy)
            }
            .environment(\.chatMarkdownSelectionActivity, { id, active in
                if active, !nativeSelectionIDs.contains(id) {
                    nativeSelectionIDs.insert(id)
                    cancelSourceScroll()
                    autoFollowController.pauseFollowing(reason: "textSelection")
                } else if !active, nativeSelectionIDs.contains(id) { nativeSelectionIDs.remove(id) }
            })
            .environment(\.chatMarkdownDidRender, { messageID in
                guard pendingSourceScroll == messageID else { return }
                sourceScrollNeedsCorrection = true
                scheduleSourceScroll(using: scrollViewProxy)
            })
            // The original text views own link and selection interactions.
            // Dismiss composer controls alongside their tap recognizers instead
            // of cancelling the native link tap before its delegate can route it.
            .simultaneousGesture(
                TapGesture().onEnded { _ in
                    isInputActive = false
                    if nativeSelectionIDs.isEmpty {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    showTemperatureSlider = false
                    showTopPSlider = false
                    showMaxTokensSlider = false
                    showMaxMessagesNumSlider = false
                }
            )
            .simultaneousGesture(
                DragGesture().onChanged { _ in
                    isInputActive = false
                    if nativeSelectionIDs.isEmpty {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                    showTemperatureSlider = false
                    showTopPSlider = false
                    showMaxTokensSlider = false
                    showMaxMessagesNumSlider = false
                }
            )
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.containerSize.width
            } action: { _, newWidth in
                if newWidth.isFinite, newWidth > 0, abs(chatContainerWidth - newWidth) > 1 {
                    chatContainerWidth = newWidth
                }
            }
            .onScrollGeometryChange(for: Bool?.self) { geometry in
                ChatAutoFollowLayout(contentHeight: Double(geometry.contentSize.height),
                    viewportHeight: Double(geometry.containerSize.height),
                    topInset: Double(geometry.contentInsets.top),
                    bottomInset: Double(geometry.contentInsets.bottom))
                    .isNearBottom(contentOffsetY: Double(geometry.contentOffset.y))
            } action: { _, measuredNearBottom in
                guard let isScrolledToBottom = measuredNearBottom else { return }
                autoFollowController.updateNearBottom(isScrolledToBottom)
                withAnimation(.easeOut(duration: 0.16)) {
                    showScrollToBottomButton = !isScrolledToBottom
                }
            }
            .onScrollGeometryChange(for: ChatAutoFollowLayout.self) { geometry in
                ChatAutoFollowLayout(contentHeight: Double(geometry.contentSize.height).rounded(),
                    viewportHeight: Double(geometry.containerSize.height).rounded(),
                    topInset: Double(geometry.contentInsets.top).rounded(),
                    bottomInset: Double(geometry.contentInsets.bottom).rounded())
            } action: { _, layout in
                autoFollowController.updateLayout(layout)
                scheduleSourceScroll(using: scrollViewProxy)
                scheduleAutoFollow(using: scrollViewProxy, animated: false, measuredLayout: layout)
            }
            .onScrollPhaseChange { _, newPhase in
                switch newPhase {
                case .tracking, .interacting, .decelerating:
                    cancelSourceScroll()
                    autoFollowController.userInteractionBegan()
                case .idle:
                    autoFollowController.userInteractionEnded()
                case .animating:
                    break
                @unknown default:
                    break
                }
            }
            .onAppear {
                transcriptScrollView.activate(conversationID: effectiveChatSessionID)
                autoFollowController.invalidateLayout()
                scheduleScrollWhenViewportReady(using: scrollViewProxy)
            }
            .task(id: effectiveChatSessionID) {
                guard !Task.isCancelled else { return }
                transcriptScrollView.activate(conversationID: effectiveChatSessionID)
                scheduleScrollWhenViewportReady(using: scrollViewProxy)
            }
            .onDisappear {
                guard transcriptScrollView.deactivate(conversationID: effectiveChatSessionID) else { return }
                cancelSourceScroll()
                autoFollowController.invalidateLayout()
            }
    }

    private func scheduleScrollWhenViewportReady(using proxy: ScrollViewProxy) {
        let conversationID = effectiveChatSessionID
        transcriptScrollView.whenReady(conversationID: conversationID) {
            guard effectiveChatSessionID == conversationID else { return }
            scheduleSourceScroll(using: proxy)
            scheduleAutoFollow(using: proxy, animated: false)
        }
    }
    
    // 聊天时滚动到最底层
    private func scrollToLastMessage(using scrollViewProxy: ScrollViewProxy, animated: Bool = true) {
        let target = TranscriptBottomTarget(conversationID: effectiveChatSessionID)
        if animated {
            withAnimation(.easeOut(duration: 0.18)) {
                scrollViewProxy.scrollTo(target, anchor: .bottom)
            }
        } else {
            scrollViewProxy.scrollTo(target, anchor: .bottom)
        }
    }

    private func scheduleAutoFollow(
        using scrollViewProxy: ScrollViewProxy,
        animated: Bool,
        force: Bool = false,
        measuredLayout: ChatAutoFollowLayout? = nil
    ) {
        guard pendingSourceScroll == nil, force || nativeSelectionIDs.isEmpty else {
            traceAutoFollowBoundary("request-blocked-by-selection-or-source")
            return
        }
        let conversationID = effectiveChatSessionID
        guard let attachedLayout = transcriptScrollView.layout(conversationID: conversationID) else {
            autoFollowController.invalidateLayout()
            traceAutoFollowBoundary("request-without-current-viewport")
            return
        }
        // SwiftUI can report content growth before UIKit commits contentSize.
        // Keep that current measurement for admission instead of overwriting it
        // with the earlier native size. Execution still rechecks the actual
        // attached viewport, generation and scroll range below.
        let layout = measuredLayout ?? attachedLayout
        autoFollowController.updateLayout(layout)
        traceAutoFollowBoundary("request", layout: layout)
        let viewportGeneration = transcriptScrollView.generation
        autoFollowController.scheduleScroll(animated: animated, force: force) { animate in
            guard pendingSourceScroll == nil, force || nativeSelectionIDs.isEmpty,
                  effectiveChatSessionID == conversationID,
                  transcriptScrollView.layout(conversationID: conversationID,
                      expectedGeneration: viewportGeneration)?.hasScrollableContent == true else {
                traceAutoFollowBoundary("execution-rejected")
                return
            }
            traceAutoFollowBoundary("perform")
            scrollToLastMessage(using: scrollViewProxy, animated: animate)
        }
    }

    private func traceAutoFollowBoundary(_ event: String, layout: ChatAutoFollowLayout? = nil) {
        #if DEBUG || HANLIN_TESTING
        guard ProcessInfo.processInfo.environment["HANLIN_COMPOSER_EDIT_DIAGNOSTICS"] == "1" else { return }
        // Never include draft text, request arguments or tool results.
        let geometry = layout.map {
            "content=\($0.contentHeight) viewport=\($0.viewportHeight) top=\($0.topInset) bottom=\($0.bottomInset)"
        } ?? "layout=unmeasured"
        print("HANLIN_TRANSCRIPT_BOUNDARY event=\(event) mode=\(autoFollowController.state.mode.rawValue) nearBottom=\(autoFollowController.state.isNearBottom) interacting=\(autoFollowController.state.isUserInteracting) sourcePending=\(pendingSourceScroll != nil) nativeSelection=\(!nativeSelectionIDs.isEmpty) generation=\(transcriptScrollView.generation) \(geometry)")
        #endif
    }

    private func richMessageContext(for row: ChatMessages) -> HanlinRichMessageContext? {
        guard row.role == "assistant", let state = richPresentation.state(for: row, conversation: chatRecord,
            conversationID: effectiveChatSessionID, context: context, temporary: TemporaryRecord) else { return nil }
        return .init(state: state, isStreaming: isResponding && row.groupID == chatTemps.last(where: { $0.role == "assistant" })?.groupID,
            perform: performRichAction)
    }

    @MainActor
    private func performRichAction(_ action: PresentationAction) async throws -> PresentationValue {
        guard action.identity.appID == "hanlin", action.identity.conversationID == effectiveChatSessionID,
              let source = chatTemps.first(where: { $0.id == action.identity.messageID && $0.role == "assistant" }),
              !isResponding else { throw HanlinHostError.staleContext }
        if action.name == "tool" {
            guard modelTemp.indices.contains(selectedModelIndex), source.modelName == modelTemp[selectedModelIndex].name,
                  let alias = action.parameters["name"]?.string else { throw HanlinHostError.staleContext }
            let arguments = try HanlinJSONValue.decodeCanonicalJSON(JSONEncoder().encode(action.parameters["args"] ?? .object([:])))
            guard let row = chatTemps.first(where: { $0.groupID == source.groupID && $0.agentRun != nil }),
                  row.agentRun != nil else { throw HanlinHostError.staleContext }
            var coordinator: AgentRunCoordinator?
            var deniedThisInvocation = false
            let originalSession = agentSessionOwner.session?.identity
            func canPublish() -> Bool {
                originalSession != nil && agentSessionOwner.session?.identity == originalSession
                    && !chatRecord.isDeleted && !row.isDeleted
            }
            func publish() {
                guard canPublish(), let coordinator else { return }
                row.agentRun = coordinator.run
                if activeAgentRun?.id == coordinator.runID { activeAgentRun = coordinator.run }
                #if HANLIN_A2UI_POC
                a2uiPresentation?.synchronizeTools(coordinator.run, isLive: true)
                #endif
            }
            do {
                let result = try await agentSessionOwner.executeInlineTool(rowID: source.id, partID: action.partID,
                    alias: alias, arguments: arguments) { event in
                        if case .toolApprovalChanged(let approval) = event, approval.disposition == .notApproved { deniedThisInvocation = true }
                        if coordinator == nil, let latest = row.agentRun { coordinator = AgentRunCoordinator(continuingActivity: latest) }
                        coordinator?.consume([event]); publish()
                    }
                guard canPublish() else { throw HanlinHostError.staleContext }
                coordinator?.complete(); publish()
                if !TemporaryRecord { try context.save() }
                return (try? JSONDecoder().decode(PresentationValue.self, from: Data(result.utf8))) ?? .string(result)
            } catch {
                if Task.isCancelled || error as? HanlinHostError == .cancelled { coordinator?.cancel() }
                else if deniedThisInvocation { coordinator?.complete() }
                else { coordinator?.fail(error) }
                publish()
                if canPublish(), !TemporaryRecord { try? context.save() }
                throw error
            }
        }
        guard let event = action.parameters["event"]?.object,
              let type = event["type"]?.string else { throw HanlinHostError.invalidArguments }
        if type == "open_url" {
            guard let destination = event["params"]?.object?["url"]?.string, let url = URL(string: destination),
                  ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { throw HanlinHostError.invalidArguments }
            return await withCheckedContinuation { continuation in
                openRichURL(url) { accepted in continuation.resume(returning: .bool(accepted)) }
            }
        }
        guard type == "continue_conversation" else { throw HanlinHostError.unknownTool }
        let arguments = try HanlinJSONValue.decodeCanonicalJSON(JSONEncoder().encode(PresentationValue.object(event)))
        let request: HanlinHostInteractionRequest?
        if agentSessionOwner.session != nil {
            request = try agentSessionOwner.inlineInteraction(rowID: source.id, partID: action.partID,
                actionID: type, arguments: arguments)
        } else { request = nil }
        let label = event["humanFriendlyMessage"]?.string ?? String(localized: "Form submitted", bundle: HanlinLocalization.bundle)
        let data = String(decoding: try arguments.canonicalJSONData(), as: UTF8.self)
        handleMessageSending(ifObservingMode: false, continuationText: label + "\n" + data, richInteraction: request)
        return .object(["submitted": .bool(true)])
    }

    // 创建聊天信息
    private func createChatBubble(for msg: ChatMessages) -> AnyView {
        // 是否是最后一条助手消息
        let isLastAssistant = chatTemps.last(where: { $0.role == "assistant" })?.id == msg.id
        
        // 是否在最后一组助手消息中
        let lastAssistantGroupID = chatTemps
            .last(where: { $0.role == "assistant" })?
            .groupID

        let isLastAssistantGroup = (msg.role == "assistant"
            && msg.groupID == lastAssistantGroupID)
        
        // 绑定展开状态
        let reasoningExpandedBinding = Binding<Bool>(
            get: { msg.reasoningExpanded ?? false },
            set: { msg.reasoningExpanded = $0 }
        )
        let toolContentExpandedBinding = Binding<Bool>(
            get: { msg.toolContentExpanded ?? false },
            set: { msg.toolContentExpanded = $0 }
        )
        let audioExpandedBinding = Binding<Bool>(
            get: { msg.audioExpanded ?? false },
            set: { msg.audioExpanded = $0 }
        )
        
        // 计算 splitMarker（同组且都是assistant时不分隔）
        let splitMarker: Bool = {
            guard let idx = chatTemps.firstIndex(where: { $0.id == msg.id }) else { return true }
            if idx == 0 { return true }
            guard let prev = chatTemps[safe: idx - 1] else { return true }
            return !(prev.role == "assistant" && prev.groupID == msg.groupID)
        }()
        
        // —— 计算当前消息所在的连续助手组，以及该组的"中点"位置 ——
        // 安全获取 idx，如果找不到则返回 EmptyView
        guard let idx = chatTemps.firstIndex(where: { $0.id == msg.id }) else {
            return AnyView(EmptyView())
        }
        
        // 收集同组连续 assistant 的所有 message IDs
        let groupIDs: [UUID] = {
            guard msg.role == "assistant" else { return [msg.id] }
            var ids = [UUID]()
            // 向前收集
            var i = idx
            while i >= 0 {
                guard let m = chatTemps[safe: i] else { break }
                guard m.role == "assistant", m.groupID == msg.groupID else { break }
                ids.insert(m.id, at: 0)
                i -= 1
            }
            // 向后收集
            i = idx + 1
            while i < chatTemps.count {
                guard let m = chatTemps[safe: i] else { break }
                guard m.role == "assistant", m.groupID == msg.groupID else { break }
                ids.append(m.id)
                i += 1
            }
            return ids
        }()
        // 找到这一组消息在 chatTemps 中的索引
        let groupIndices = chatTemps.enumerated()
            .filter { groupIDs.contains($0.element.id) }
            .map { $0.offset }
        let isGroupCenter: Bool = {
            guard groupIndices.count > 1,
                  let first = groupIndices.first,
                  let last = groupIndices.last else { return false }
            return idx == (first + last) / 2
        }()

        let groupMessages = groupIDs.compactMap { groupID in
            chatTemps.first(where: { $0.id == groupID })
        }
        let precedingSearchMessages: [ChatMessages] = {
            guard let firstGroupIndex = groupIndices.first, firstGroupIndex > 0 else { return [] }
            var messages: [ChatMessages] = []
            var index = firstGroupIndex - 1
            while index >= 0, let candidate = chatTemps[safe: index], candidate.role == "search" {
                messages.insert(candidate, at: 0)
                index -= 1
            }
            return messages
        }()
        let storedActivityRun = (activeAgentRun?.groupID == msg.groupID ? activeAgentRun : nil)
            ?? groupMessages.lazy.compactMap { agentRunReadCache.run(for: $0) }.first
        let activityRun = storedActivityRun
            ?? LegacyAgentActivityAdapter.run(for: precedingSearchMessages + groupMessages)
        let rawMsgText = (msg.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackFinalAnswer = splitMarker && !groupMessages.contains(where: { !($0.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            ? (AgentTranscriptValidation.finalAnswer(in: storedActivityRun?.transcriptItems ?? [])?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            : ""
        let legacyBubbleText = !rawMsgText.isEmpty ? rawMsgText : fallbackFinalAnswer
        #if HANLIN_A2UI_POC
        let exactCanonicalBody = a2uiPresentation?.projection(uiRunID: activityRun?.id,
            rowID: msg.id, text: msg.text ?? "") != nil
        let bubbleText = exactCanonicalBody ? (msg.text ?? "") : legacyBubbleText
        #else
        let bubbleText = legacyBubbleText
        #endif
        
        let toolApproval: ChatToolApprovalPresentation? = {
            guard groupIDs.first == msg.id,
                  let pendingRowID = agentSessionOwner.pendingApprovalRowID,
                  groupIDs.contains(pendingRowID),
                  let request = agentSessionOwner.consent.pending else { return nil }
            return ChatToolApprovalPresentation.original(request) { allowed in
                agentSessionOwner.consent.answer(id: request.id, allowed: allowed)
            }
        }()

        // 1. 构造基础气泡
        let bubble = VStack(alignment: .leading, spacing: 8) {
        ChatBubbleView(
            temporaryRecord: TemporaryRecord,
            containerWidth: chatContainerWidth,
            id: msg.id,
            text: bubbleText,
            saveTranlatedText: msg.translatedText,
            images: msg.imageArray,
            imagesText: msg.images_text,
            reasoning: msg.reasoning?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            reasoningTime: msg.reasoningTime,
            isReasoningExpanded: reasoningExpandedBinding,
            toolContent: msg.toolContent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            toolName: msg.toolName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            isToolContentExpanded: toolContentExpandedBinding,
            uploadDocument: msg.documentURLs,
            documentText: msg.document_text,
            resources: groupIDs.last == msg.id ? groupMessages.flatMap { $0.resources ?? [] } : msg.resources,
            prompts: msg.promptUse,
            locations: msg.locationsInfo,
            routes: msg.routeInfos,
            events: msg.events,
            htmlContent: msg.htmlContent,
            healthCards: msg.healthData,
            codeBlocks: msg.codeBlockData,
            knowledgeCard: msg.knowledgeCard,
            nativeUIBlocks: msg.nativeUIBlocks,
            agentRun: activityRun,
            toolApproval: toolApproval,
            showsAgentActivitySummary: groupIDs.first == msg.id,
            showsAllSources: groupIDs.last == msg.id,
            isAgentTranscriptOwner: false,
            isRenderedByAgentTranscript: false,
            searchEngine: msg.searchEngine,
            audioAssets: msg.audioAssets,
            isVoiceExpanded: audioExpandedBinding,
            showCanvas: msg.showCanvas ?? false,
            canvas: chatRecord.canvas,
            role: msg.role ?? "system",
            model: msg.modelDisplayName ?? "Unknown",
            modelCompany: modelTemp.first(where: { $0.name == msg.modelName })?.company ?? "UNKNOWN",
            modelIdentity: modelTemp.first(where: { $0.name == msg.modelName })?.identity ?? "model",
            modelIcon: modelTemp.first(where: { $0.name == msg.modelName })?.icon ?? "circle.dotted.circle",
            isLastAssistant: isLastAssistant,
            isLastAssistantGroup: isLastAssistantGroup,
            splitMarker: splitMarker,
            isResponding: isResponding,
            operationalState: operationalState,
            operationalDescription: operationalDescription,
            onRetry: (msg.role == "assistant" || msg.role == "error") ? { retryRequest(for: msg) } : nil,
            onContinue: msg.role == "assistant" && msg.modelFinishReason == "length" ? {
                guard !isResponding else { return }
                handleMessageSending(ifObservingMode: false, continuationText: String(localized: "Continue from where the answer stopped. Preserve the previous answer and do not repeat completed actions or tool calls.", bundle: HanlinLocalization.bundle))
            } : nil,
            onDelete: {
                // 如果是助手组消息，删除整组，否则删除单条
                if msg.role == "assistant" {
                    for gid in groupIDs {
                        if let i = chatTemps.firstIndex(where: { $0.id == gid }) {
                            context.delete(chatTemps[i])
                            chatTemps.remove(at: i)
                        }
                    }
                    do { try context.save() } catch { print("删除组消息失败:", error) }
                } else {
                    if let i = chatTemps.firstIndex(where: { $0.id == msg.id }) {
                        context.delete(chatTemps[i])
                        do { try context.save() } catch { print("删除消息失败:", error) }
                        chatTemps.remove(at: i)
                    }
                }
            }
        )
        }
        .environment(\.hanlinRichMessageContext, richMessageContext(for: msg))
        .environment(\.chatExcerptSource, ChatExcerptSource(
            chatRecordID: chatRecord.id, messageID: msg.id, groupID: msg.groupID,
            runID: activityRun?.id, title: chatRecord.name ?? String(localized: "Conversation", bundle: HanlinLocalization.bundle)
        ))
        
        // 2. 多选模式下，只在"用户消息"或"助手中点"显示勾选框
        return AnyView(Group {
            if isMultiSelectMode {
                ZStack {
                    bubble
                        .offset(x: msg.role == "user" ? -32 : 0)
                    
                    // 仅对用户消息或助手组中点显示
                    if msg.role != "assistant"
                        || groupIDs.count == 1
                        || isGroupCenter
                    {
                        HStack {
                            Spacer()
                            Button {
                                if msg.role == "assistant" {
                                    // 全组切换
                                    let allSelected = Set(groupIDs).isSubset(of: selectedMessageIDs)
                                    if allSelected {
                                        selectedMessageIDs.subtract(groupIDs)
                                    } else {
                                        selectedMessageIDs.formUnion(groupIDs)
                                    }
                                } else {
                                    // 单条切换
                                    if selectedMessageIDs.contains(msg.id) {
                                        selectedMessageIDs.remove(msg.id)
                                    } else {
                                        selectedMessageIDs.insert(msg.id)
                                    }
                                }
                            } label: {
                                Image(systemName:
                                        (msg.role == "assistant"
                                         ? groupIDs.contains(where: { selectedMessageIDs.contains($0) })
                                         : selectedMessageIDs.contains(msg.id))
                                      ? "checkmark.circle.fill"
                                      : "circle"
                                )
                                .resizable()
                                .frame(width: 22, height: 22)
                                .foregroundColor(
                                    (msg.role == "assistant"
                                     ? groupIDs.contains(where: { selectedMessageIDs.contains($0) })
                                     : selectedMessageIDs.contains(msg.id))
                                    ? .hanlinHLGreen
                                    : .gray)
                            }
                        }
                    }
                }
            } else {
                bubble
            }
        })
    }
    
    private func openHistory() {
        // A disappearing/deleted view must not mutate a detached original row.
        guard (try? HanlinConversationMutation.requireOriginal(chatRecord, in: context,
            temporary: TemporaryRecord)) != nil else { return }
        // 如果输入框有草稿内容，则优先保存草稿
        if !message.isEmpty {
            chatRecord.infoDescription = "[\(String(localized: "Draft", bundle: HanlinLocalization.bundle))] \(message)"
            chatRecord.input = message
        } else {
            chatRecord.input = ""
            if let lastMessage = chatTemps.last {
            if let text = lastMessage.text,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // 如果最后一条消息有文字，则保存文字预览
                let previewText = markdownToPlainText(text)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "\r", with: " ")
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                
                chatRecord.infoDescription = "\(previewText)"
            } else if !lastMessage.imageArray.isEmpty {
                // 如果最后一条消息没有文字但有图像，则使用倒数第二条消息的文字
                if chatTemps.count >= 2 {
                    let secondLastMessage = chatTemps[chatTemps.count - 2]
                    let previewText = secondLastMessage.text?.replacingOccurrences(of: "\n", with: " ").prefix(80)
                    chatRecord.infoDescription = "[\(String(localized: "Image", bundle: HanlinLocalization.bundle))] \(previewText ?? "")"
                } else {
                    chatRecord.infoDescription = "[\(String(localized: "Image", bundle: HanlinLocalization.bundle))]"
                }
                } else {
                    chatRecord.infoDescription = ""
                }
            }
        }
        do {
            try context.save()
        } catch {
            print("Failed to save chat record updates: \(error)")
        }
    }
    
    private func newConversation() {
        if isResponding { handleCancellation() }
        let clearedText = HanlinConversationMutation.originalClearedText
        do {
            guard let conversationID = chatRecord.id else { throw HanlinHostError.staleContext }
            let replacement = try agentSessionOwner.clearHistory(conversation: chatRecord,
                conversationID: conversationID, modelContext: context, temporary: TemporaryRecord,
                replacementText: clearedText)
            // Publish the success state only after the single original-store save succeeds.
            applyClearedHistory(replacement)
        } catch {
            showClearChatError = true
        }
    }

    private func applyClearedHistory(_ replacement: ChatMessages) {
        guard chatTemps.count != 1 || chatTemps.first?.id != replacement.id else { return }
        allMessages = [replacement]
        loadedMessageCount = 1
        chatTemps = [replacement]
        topVisibleMessageID = replacement.id
        selectedMessageIDs.removeAll()
        isMultiSelectMode = false
        cancelSourceScroll()
        autoFollowController.invalidateLayout()
        autoFollowController.resumeFollowing(reason: "conversationCleared")
    }

    private func applyConversationChange(_ change: HanlinConversationMutation.Change) {
        switch change.kind {
        case .metadata:
            chatTitle = chatRecord.name ?? "Unknown"
            if let id = change.messageID,
               let announcement = chatRecord.messages?.first(where: { $0.id == id }),
               !chatTemps.contains(where: { $0.id == id }) { chatTemps.append(announcement) }
        case .historyCleared:
            if let id = change.messageID, let replacement = chatRecord.messages?.first(where: { $0.id == id }) {
                applyClearedHistory(replacement)
            }
        case .deleted:
            chatTemps = []
            allMessages = []
            loadedMessageCount = 0
            selectedMessageIDs.removeAll()
            cancelSourceScroll()
        }
    }

    // MARK: - Shared automatic conversation metadata
    private func autoGenerateTitleIfNeeded() {
        HanlinConversationAutoMetadata.schedule(for: chatRecord, messages: chatTemps,
            in: context, temporary: TemporaryRecord)
    }

    // 处理消息发送
    private func handleMessageSending(ifObservingMode: Bool, continuationText: String? = nil, richInteraction: HanlinHostInteractionRequest? = nil) {
        guard !agentSessionOwner.inlineToolIsRunning else { return }
        guard modelTemp.indices.contains(selectedModelIndex) else { return }
        let requestModelName = modelTemp[selectedModelIndex].name ?? "Unknown"
        let requestModelID = modelTemp[selectedModelIndex].id
        let requestModelCompany = modelTemp[selectedModelIndex].company
        let requestCapabilities = (
            search: modelTemp[selectedModelIndex].supportsSearch,
            tools: modelTemp[selectedModelIndex].supportsToolUse,
            reasoning: modelTemp[selectedModelIndex].supportsReasoning,
            voice: modelTemp[selectedModelIndex].supportsVoiceGen)
        let nativeInteraction: HanlinHostInteractionRequest?
        #if HANLIN_A2UI_POC
        let originalAction = a2uiSubmittingAction
        a2uiSubmittingAction = nil
        if let originalAction {
            guard a2uiPresentation?.isCurrent(originalAction) == true,
                  a2uiModelChoice == a2uiOriginalModelChoice else { return }
        } else { a2uiOriginalModelChoice = a2uiModelChoice }
        nativeInteraction = richInteraction ?? originalAction?.request
        #else
        nativeInteraction = richInteraction
        #endif
        if nativeInteraction != nil { isRetry = false; isObserving = false; retryMessagesOverride = nil }

        let turnLease: HanlinConversationRunLease
        do {
            turnLease = try .acquire(container: context.container, conversationID: effectiveChatSessionID)
        } catch { return }
        
        isFeedBack.toggle()
        var userMessage: ChatMessages?
        showPhotoSourceOptions = false
        operationalState = ""
        operationalDescription = ""
        
        // 新消息处理
        if !ifObservingMode {
            if !isRetry {
                // 新消息建立
                userMessage = ChatMessages(
                    role: "user",
                    text: continuationText ?? message,
                    images: continuationText == nil ? selectedImages : [],
                    reasoning: "",
                    documents: continuationText == nil ? selectedDocumentURLs.map { $0.absoluteString } : [],
                    modelName: modelTemp[selectedModelIndex].name,
                    modelDisplayName: modelTemp[selectedModelIndex].displayName,
                    timestamp: Date(),
                    record: chatRecord
                )
                if continuationText == nil && !selectedPrompts.isEmpty {
                    let promptCards = selectedPrompts.map { PromptCard(name: $0.name ?? "无名称", content: $0.content ?? "无内容") }
                    userMessage?.promptUse = promptCards
                }
                // 写入用户发送的信息
                if let userMessage = userMessage, !isObserving, !isRetry {
                    chatTemps.append(userMessage)
                    context.insert(userMessage)
                    // 异步自动命名（不阻塞主对话）
                    autoGenerateTitleIfNeeded()
                }
                if continuationText == nil {
                    message = ""
                    selectedImages.removeAll()
                    selectedDocumentURLs = []
                    isInputActive = false
                }
            }
        } else {
            message = ""
            selectedImages.removeAll()
            selectedDocumentURLs = []
        }
        
        // 传递信息初始化
        isCancelled = false
        isObserving = ifObservingMode
        isResponding = true
        respondIndex = ifObservingMode ? 2 : 1
        autoFollowController.beginRun()
        
        // 传输数据准备
        let requestHistory = retryMessagesOverride ?? chatTemps
        let messagesToSend = HanlinConversationStreamProjection.requestMessages(
            from: requestHistory, limit: maxMessagesNum)
        
        let thisGroupID = UUID()
        // 创建助手消息占位符，并保存引用以便后续高效更新
        let assistantPlaceholder = ChatMessages(
            role: "assistant",
            text: "",
            images: nil,
            reasoning: "",
            documents: nil,
            modelName: modelTemp[selectedModelIndex].name,
            modelDisplayName: modelTemp[selectedModelIndex].displayName,
            groupID: thisGroupID,
            timestamp: Date(),
            record: chatRecord
        )
        chatTemps.append(assistantPlaceholder)
        let groupBeginMessage = assistantPlaceholder
        let agentCoordinator = AgentRunCoordinator(
            groupID: thisGroupID,
            providerID: requestModelCompany,
            modelID: requestModelName
        )
        groupBeginMessage.agentRun = agentCoordinator.run
                    #if HANLIN_A2UI_POC
                    a2uiPresentation?.synchronizeTools(agentCoordinator.run, isLive: true)
                    #endif
        activeAgentCoordinator = agentCoordinator
        activeAgentRun = agentCoordinator.run
        activeAgentMessage = groupBeginMessage
        agentSessionOwner.onApprovalEvent = { rowID, approval in
            guard rowID == groupBeginMessage.id, activeAgentCoordinator === agentCoordinator else { return }
            agentCoordinator.consume([.toolApprovalChanged(approval)])
            groupBeginMessage.agentRun = agentCoordinator.run
            activeAgentRun = agentCoordinator.run
        }
        
        // 进行API请求
        // Register the already-created original row, not a second SDK-specific message.
        context.insert(assistantPlaceholder)
        let originalSDKRequest: HanlinAppAgentSessionOwner.Request?
        if let conversationID = chatRecord.id {
            originalSDKRequest = .init(conversation: chatRecord, conversationID: conversationID,
                sceneID: sessionScopeID, rowID: assistantPlaceholder.id, uiRunID: agentCoordinator.runID,
                temporary: TemporaryRecord, interaction: nativeInteraction)
        } else { originalSDKRequest = nil }
        let requestAPIManager = APIManager(context: context, agentSessionOwner: agentSessionOwner)
        requestAPIManager.presentationInstructions = richPresentation.instructions(conversation: chatRecord, conversationID: effectiveChatSessionID)
        _ = richPresentation.state(for: assistantPlaceholder, conversation: chatRecord, conversationID: effectiveChatSessionID, context: context, temporary: TemporaryRecord)
        self.apiManager = requestAPIManager
        
        let turnProjection = HanlinConversationStreamProjection(record: chatRecord, context: context,
            messages: chatTemps, assistant: assistantPlaceholder, coordinator: agentCoordinator, lease: turnLease)
        activeTurnProjection = turnProjection
        turnLease.onRevoke {
            guard activeTurnProjection === turnProjection else { return }
            handleCancellation()
        }

        Task {
            defer { turnLease.release() }
            do {
                let assistantToolScope = await MCPRuntimeProvider.shared.requestScope(
                    chatID: effectiveChatSessionID,
                    temporary: TemporaryRecord
                )
                guard activeAgentCoordinator === agentCoordinator, !Task.isCancelled else { return }
                #if HANLIN_A2UI_POC
                if let originalAction, a2uiPresentation?.isCurrent(originalAction) != true {
                    throw HanlinHostError.staleContext
                }
                #endif
                let stream: AsyncThrowingStream<StreamData, Swift.Error> = try await requestAPIManager.sendStreamRequest(
                    messages: messagesToSend,
                    modelName: requestModelName,
                    modelRecordID: requestModelID,
                    groupID: thisGroupID,
                    runID: agentCoordinator.runID,
                    ifSearch: requestCapabilities.search && ifSearch,
                    ifKnowledge: requestCapabilities.search && ifKnowledge,
                    ifToolUse: requestCapabilities.tools && ifToolUse,
                    assistantToolScope: assistantToolScope,
                    ifThink: requestCapabilities.reasoning && ifThink,
                    ifAudio: requestCapabilities.voice && ifAudio,
                    ifPlanning: !requestCapabilities.reasoning && ifPlanning,
                    thinkingLength: thinkingLength,
                    isObservation: ifObservingMode,
                    temperature: temperature,
                    topP: topP,
                    maxTokens: maxTokens,
                    canvasData: chatRecord.canvas ?? CanvasData(),
                    selectedURLs: nativeInteraction == nil ? selectedURLs : [],
                    selectedPromptsContent: nativeInteraction == nil ? selectedPrompts.compactMap { $0.content } : [],
                    systemMessage: useSystemMessage ? "Default" : systemMessage,
                    selectedImageSize: selectedImageSize,
                    imageReversePrompt: imageReversePrompt,
                    agentSDKRequest: originalSDKRequest
                )
                
                // 接受流式数据
                let presentationBuffer = HanlinChatStreamBuffer { data in
                    guard !isCancelled, activeAgentCoordinator === agentCoordinator else { return }
                    #if HANLIN_A2UI_POC
                    let canonical = a2uiPresentation?.hasCanonicalParts(
                        uiRunID: agentCoordinator.runID, rowID: groupBeginMessage.id) == true
                    #else
                    let canonical = false
                    #endif
                    turnProjection.messages = chatTemps
                    turnProjection.consume(data, hasCanonicalParts: canonical)
                    activeAgentRun = agentCoordinator.run
                    #if HANLIN_A2UI_POC
                    a2uiPresentation?.synchronizeTools(agentCoordinator.run, isLive: true)
                    #endif
                    chatTemps = turnProjection.messages
                    operationalState = turnProjection.operationalState
                    operationalDescription = turnProjection.operationalDescription
                }
                // Deliver pending text before finalization or an error. A cancelled
                // or replaced run is rejected by the callback's ownership guard.
                defer { presentationBuffer.flush(); presentationBuffer.cancel() }
                for try await data in stream {
                    try Task.checkCancellation()
                    presentationBuffer.append(data)
                }
                presentationBuffer.flush()

                await MainActor.run {
                    guard activeAgentCoordinator === agentCoordinator else { return }
                    isObserving = false
                    isResponding = false
                    respondIndex = 0
                    #if HANLIN_A2UI_POC
                    let canonical = a2uiPresentation?.hasCanonicalParts(
                        uiRunID: agentCoordinator.runID, rowID: groupBeginMessage.id) == true
                    let structured = a2uiPresentation?.hasStructuredContent(
                        uiRunID: agentCoordinator.runID, rowID: groupBeginMessage.id,
                        text: (canonical ? groupBeginMessage : turnProjection.assistantMessage).text ?? "") == true
                    #else
                    let canonical = false
                    let structured = false
                    #endif
                    do {
                        turnProjection.messages = chatTemps
                        try turnProjection.finish(hasCanonicalParts: canonical, hasStructuredContent: structured)
                        if turnProjection.completionStatus == "completed", outPutFeedBackEnabled { isOutPut.toggle() }
                    } catch {
                        turnProjection.appendPersistenceError(error)
                    }
                    Task { await requestAPIManager.completeAgentDiagnostics(status: turnProjection.completionStatus) }
                    #if HANLIN_A2UI_POC
                    a2uiPresentation?.synchronizeTools(agentCoordinator.run, isLive: true)
                    #endif
                    chatTemps = turnProjection.messages
                    operationalState = turnProjection.operationalState
                    operationalDescription = turnProjection.operationalDescription
                    activeAgentRun = agentCoordinator.run
                    autoFollowController.runEnded()
                    activeAgentCoordinator = nil
                    activeAgentMessage = nil
                    activeTurnProjection = nil
                }
                
            } catch {
                // 响应异常处理
                await MainActor.run {
                    guard activeAgentCoordinator === agentCoordinator else { return }
                    turnProjection.fail(error)
                    Task { await requestAPIManager.completeAgentDiagnostics(status: "failed", error: error) }
                    #if HANLIN_A2UI_POC
                    a2uiPresentation?.synchronizeTools(agentCoordinator.run, isLive: true)
                    #endif
                    chatTemps = turnProjection.messages
                    operationalState = turnProjection.operationalState
                    operationalDescription = turnProjection.operationalDescription
                    activeAgentRun = agentCoordinator.run
                    autoFollowController.runEnded()
                    activeAgentCoordinator = nil
                    activeAgentMessage = nil
                    activeTurnProjection = nil
                    isResponding = false
                    respondIndex = 0
                }
            }
        }
    }
    
    // 打断操作
    private func handleCancellation() {
        agentSessionOwner.cancel()
        
        isFeedBack.toggle()
        isCancelled = true
        
        let cancelledAPIManager = apiManager
        cancelledAPIManager?.cancelCurrentRequest()
        Task { await cancelledAPIManager?.completeAgentDiagnostics(status: "cancelled") }
        if let projection = activeTurnProjection {
            projection.messages = chatTemps
            projection.cancel()
            chatTemps = projection.messages
            activeAgentRun = projection.agentCoordinator.run
            #if HANLIN_A2UI_POC
            a2uiPresentation?.synchronizeTools(projection.agentCoordinator.run, isLive: true)
            #endif
        } else {
            HanlinConversationStreamProjection.appendCancellation(
                to: &chatTemps, record: chatRecord, context: context)
        }
        activeTurnProjection = nil
        activeAgentCoordinator = nil
        autoFollowController.runEnded()
        autoFollowController.cancelPendingScroll()
        activeAgentMessage = nil
        
        isObserving = false
        isResponding = false
        respondIndex = 0
        operationalState = ""
        operationalDescription = ""
        if isRetry {
            isRetry = false
        }
        
        apiManager = nil
        isCancelled = false
    }
    
    // 重新请求
    private func retryRequest(for message: ChatMessages) {
        let previousMessages = chatTemps
        guard ChatTurnStateOperations.cleanupTurnForRetry(
            targetMessage: message,
            chatTemps: &chatTemps,
            context: nil
        ) else { return }
        let remainingIDs = Set(chatTemps.map(\.id))
        let removedMessages = previousMessages.filter { !remainingIDs.contains($0.id) }
        let ctx = context
        DispatchQueue.main.async {
            for removed in removedMessages {
                ctx.delete(removed)
            }
            try? ctx.save()
        }

        retryMessagesOverride = nil
        isRetry = true
        handleMessageSending(ifObservingMode: isObserving)
        isRetry = false
    }
    
    private func selectModel(at index: Int) {
        selectedModelIndex = index
        chatRecord.useModel = index
        do {
            try context.save()
        } catch {
            print("Save Error")
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
            // 安全检查索引边界
            guard selectedModelIndex >= 0,
                  selectedModelIndex < modelTemp.count else { return }
            
            let model = modelTemp[selectedModelIndex]
            if model.supportsReasoning {
                ifPlanning = false
                thinkingLength = 0
                if model.supportReasoningChange {
                    ifThink = false
                } else {
                    ifThink = true
                }
            } else {
                ifThink = false
            }
            if model.supportsVoiceGen {
                ifAudio = true
            } else {
                ifAudio = false
            }
        }
        
        // 发布通知，附带选中的模型索引，触发滚动到对应位置
        NotificationCenter.default.post(name: .scrollToModelIndex, object: index)
    }
    
    /// 生成导出文本，仅保留 role == "user" 和 "assistant" 的消息
    /// - Parameters:
    ///   - format: 导出格式，目前支持 .txt 和 .json
    ///   - includeImages: 针对 JSON 格式，是否包含图片（仅在 .json 格式下生效）
    private func generateExportText(for format: ExportFormat, includeImages: Bool = true) -> String {
        let filteredMessages = chatTemps.filter { $0.role == "user" || $0.role == "assistant" }
        
        switch format {
        case .txt:
            // 文本格式：每条消息输出 "User:" 或 "Assistant:" 后跟文本内容
            var txtContent = ""
            for msg in filteredMessages {
                let roleStr = (msg.role == "user") ? "User" : msg.modelDisplayName ?? "Assistant"
                let textContent = msg.text ?? ""
                txtContent.append("\(roleStr): \(textContent)\n\n")
            }
            return txtContent
            
        case .json:
            if !includeImages {
                // 纯文本 JSON 格式：每条消息导出为 { "role": "user"/"assistant", "content": "文本内容" }
                var arrayOfObjects = [[String: String]]()
                for msg in filteredMessages {
                    let role = (msg.role == "user") ? "user" : "assistant"
                    let text = msg.text ?? ""
                    arrayOfObjects.append(["role": role, "content": text])
                }
                do {
                    let data = try JSONEncoder().encode(arrayOfObjects)
                    return String(data: data, encoding: .utf8) ?? ""
                } catch {
                    print("JSON 编码失败: \(error)")
                    return ""
                }
            } else {
                // 多模态 JSON 格式：生成 OpenAI 兼容格式
                struct ExportMessage: Codable {
                    let role: String
                    let content: [ExportContentItem]
                }
                struct ExportContentItem: Codable {
                    let type: String
                    let text: String?
                    let image_url: ImageURLItem?
                }
                struct ImageURLItem: Codable {
                    let url: String
                }
                
                var exportMessages: [ExportMessage] = []
                for msg in filteredMessages {
                    let role = (msg.role == "user") ? "user" : "assistant"
                    var contentItems: [ExportContentItem] = []
                    
                    // 添加图片项（若有）
                    let images = msg.imageArray
                    if !images.isEmpty {
                        for image in images {
                            if let imageData = image.jpegData(compressionQuality: 0.8) {
                                let base64String = imageData.base64EncodedString()
                                let imageItem = ExportContentItem(
                                    type: "image_url",
                                    text: nil,
                                    image_url: ImageURLItem(url: "data:image/jpeg;base64,\(base64String)")
                                )
                                contentItems.append(imageItem)
                            }
                        }
                    }
                    
                    // 添加文本项（若有）
                    if let text = msg.text, !text.isEmpty {
                        let textItem = ExportContentItem(
                            type: "text",
                            text: text,
                            image_url: nil
                        )
                        contentItems.append(textItem)
                    }
                    
                    let exportMsg = ExportMessage(role: role, content: contentItems)
                    exportMessages.append(exportMsg)
                }
                
                do {
                    let data = try JSONEncoder().encode(exportMessages)
                    return String(data: data, encoding: .utf8) ?? ""
                } catch {
                    print("JSON 编码失败: \(error)")
                    return ""
                }
            }
        }
    }
    
    /// 解析多模态 JSON 格式数据（包括图片）
    private func importMessages(importedMessages: [ExportMessage]) {
        for exportMsg in importedMessages {
            var combinedText = ""
            var images: [UIImage] = []
            // 遍历内容项，将文本项合并，并处理图片项
            for item in exportMsg.content {
                if item.type == "text", let text = item.text {
                    combinedText.append(text)
                } else if item.type == "image_url", let urlString = item.image_url?.url {
                    // 检查 base64 格式（例如 "data:image/jpeg;base64,..."）
                    if let base64String = urlString.components(separatedBy: "base64,").last,
                       let imageData = Data(base64Encoded: base64String),
                       let image = UIImage(data: imageData) {
                        images.append(image)
                    }
                }
            }
            let newMessage = ChatMessages(
                role: exportMsg.role, // role 由 JSON 数据提供
                text: combinedText,
                images: images,
                reasoning: "",
                documents: nil,
                modelName: "glm-4v-flash_hanlin",
                modelDisplayName: "Hanlin-GLM4V", // 固定使用 Hanlin-GLM4V
                timestamp: Date(),
                record: chatRecord
            )
            chatTemps.append(newMessage)
            context.insert(newMessage)
        }
        // 更新会话预览信息
        if let lastMessage = chatTemps.last {
            chatRecord.infoDescription = String(lastMessage.text?.prefix(90) ?? "")
            chatRecord.lastEdited = lastMessage.timestamp
        }
        do {
            try context.save()
        } catch {
            print("导入聊天记录保存失败: \(error)")
        }
    }

    /// 解析纯文本 JSON 格式数据：数组中每个对象为 { "role": "user"/"assistant", "content": "文本内容" }
    private func importSimpleMessages(simpleMessages: [[String: String]]) {
        for dict in simpleMessages {
            guard let role = dict["role"], let content = dict["content"] else { continue }
            let newMessage = ChatMessages(
                role: role,
                text: content,
                images: [],
                reasoning: "",
                documents: nil,
                modelName: "glm-4v-flash_hanlin",
                modelDisplayName: "Hanlin-GLM4V",
                timestamp: Date(),
                record: chatRecord
            )
            chatTemps.append(newMessage)
            context.insert(newMessage)
        }
        // 同步预览信息
        if let lastMessage = chatTemps.last {
            chatRecord.infoDescription = String(lastMessage.text?.prefix(90) ?? "")
            chatRecord.lastEdited = lastMessage.timestamp
        }
        do {
            try context.save()
        } catch {
            print("导入聊天记录保存失败: \(error)")
        }
    }
    
}

extension Notification.Name {
    static let scrollToModelIndex = Notification.Name("scrollToModelIndex")
}

@MainActor
enum ChatTurnStateOperations {
    @discardableResult
    static func upsertSearchMessage(
        existing: ChatMessages?,
        text: String,
        searchEngine: String?,
        assistantMessage: ChatMessages,
        record: ChatRecords,
        in chatTemps: inout [ChatMessages]
    ) -> ChatMessages {
        if let existing {
            existing.text = text
            if let searchEngine, !searchEngine.isEmpty {
                existing.searchEngine = searchEngine
            }
            if !chatTemps.contains(where: { $0.id == existing.id }) {
                if let assistantIndex = chatTemps.firstIndex(where: { $0.id == assistantMessage.id }) {
                    chatTemps.insert(existing, at: assistantIndex)
                } else {
                    chatTemps.append(existing)
                }
            }
            return existing
        }

        let searchMsg = ChatMessages(
            role: "search",
            text: text,
            searchEngine: searchEngine,
            modelName: "system",
            modelDisplayName: "system",
            timestamp: Date(),
            record: record
        )
        if let assistantIndex = chatTemps.firstIndex(where: { $0.id == assistantMessage.id }) {
            chatTemps.insert(searchMsg, at: assistantIndex)
        } else {
            chatTemps.append(searchMsg)
        }
        return searchMsg
    }

    @discardableResult
    static func cleanupTurnForRetry(
        targetMessage: ChatMessages,
        chatTemps: inout [ChatMessages],
        context: ModelContext? = nil
    ) -> Bool {
        guard let tempIndex = chatTemps.lastIndex(where: { $0.id == targetMessage.id }) else {
            return false
        }
        var groupStart = tempIndex
        while groupStart > 0 {
            guard let previous = chatTemps[safe: groupStart - 1] else { break }
            if previous.role != "user" {
                groupStart -= 1
            } else {
                break
            }
        }

        let removedMessages = Array(chatTemps.suffix(from: groupStart))
        if let context {
            for removed in removedMessages {
                context.delete(removed)
            }
            try? context.save()
        }
        chatTemps.removeSubrange(groupStart..<chatTemps.count)
        return true
    }
}
