//
//  Views/ChatView.swift
//  AI_HLY
//
//  Created by 哆啦好多梦 on 3/2/25.
//

import SwiftUI
import AVFoundation
import SwiftData
import UniformTypeIdentifiers

// 聊天界面
@MainActor
struct ChatView: View {
    var chatRecord: ChatRecords
    
    // 输入与会话状态相关
    @State private var message = ""                        // 用户输入的消息
    @State private var isResponding = false                // 是否处于系统响应状态
    @State private var isCancelled = false                 // 是否被打断
    @State private var respondIndex = 0                    // 当前响应请求的索引
    @FocusState private var isInputActive: Bool            // 输入框是否聚焦
    @State private var isObserving = false                 // 是否处于观察模式
    @State private var isRetry = false                     // 是否为重试请求

    @State private var chatTitle = "新群聊"                 // 群聊标题
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
    @State private var lastUpdateTime = Date()              // 最近更新时间，用于刷新控制
    @State private var outPutFeedBackEnabled: Bool = true   // 是否启用输出反馈震动

    // 聊天数据管理相关
    @State private var allMessages: [ChatMessages] = []     // 所有聊天记录
    @State private var loadedMessageCount: Int = 0          // 当前加载的消息数量
    @State private var topVisibleMessageID: UUID? = nil     // 当前顶部可见消息的ID
    @State private var TemporaryRecord: Bool = false        // 是否为临时聊天
    @State private var useSystemMessage: Bool = true        // 是否自定义系统消息
    @State private var systemMessage: String = ""           // 是否系统消息内容
    @State private var showSystemMessageSheet = false       // 打开系统消息设置
    let refreshInterval: TimeInterval = 0.3                 // 刷新间隔时间
    @State private var operationalState: String = ""        // 操作状态文本
    @State private var operationalDescription: String = ""  // 操作描述文本
    @State private var apiManager: APIManager?

    // URL解析与多选操作相关
    @State private var selectedURLs: [String] = []          // 解析出的 URL 列表
    @State private var isMultiSelectMode: Bool = false      // 是否开启多选模式
    @State private var selectedMessageIDs: Set<UUID> = []   // 选中的消息 ID 集合
    var matchedMessageID: UUID?                             // 匹配的消息 ID
    @State private var showScrollToBottomButton = false     // 控制滚动到底部按钮显示
    @State private var needScrollToBottomButton = false     // 是否需要显示滚动到底部按钮
    @State private var ifScroll = false                     // 控制滚动相关状态

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
    @State private var showImportExplanationAlert = false   // 导入聊天记录说明弹窗显示标志
    
    // 便捷输入
    @State private var showModelSuggestions: Bool = false
    @State private var filteredModels: [AllModels] = []
    
    @Environment(\.modelContext) private var context: ModelContext
    @Environment(\.dismiss) private var dismiss
    
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
        let firstVisibleModelIndex = modelTemp.firstIndex(where: { !$0.isHidden }) ?? 0
        
        // 根据匹配消息决定加载数量
        let targetCount: Int
        if let matchedID = matchedMessageID,
           let matchedIndex = sortedMessages.firstIndex(where: { $0.id == matchedID }) {
            let matchedFromBottom = sortedMessages.count - matchedIndex
            targetCount = (matchedFromBottom <= 20) ? 20 : ((matchedFromBottom + 9) / 10) * 10
        } else {
            targetCount = 20
        }
        
        // 根据设备类型动态调整 ifScroll 阈值
        let threshold = UIDevice.current.userInterfaceIdiom == .phone ? 6 : 12
        allMessages = sortedMessages
        loadedMessageCount = min(targetCount, sortedMessages.count)
        ifScroll = (loadedMessageCount < threshold)
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
    
    private func dynamicBottomPadding() -> CGFloat {
        var baseHeight: CGFloat = 216 // 默认最小间距
        if !selectedURLs.isEmpty { baseHeight += 36 }
        if !selectedImages.isEmpty { baseHeight += 86 }
        if !selectedDocumentURLs.isEmpty { baseHeight += 36 }
        if showPhotoSourceOptions { baseHeight += 146 }
        if !selectedPrompts.isEmpty { baseHeight += 66 }
        return baseHeight
    }
    
    var body: some View {
        VStack {
            
            ZStack(alignment: .bottom) {
                
                // 第一部分：可滚动聊天区
                ScrollViewReader { scrollViewProxy in
                    buildScrollContent(scrollViewProxy)
                        .padding(.bottom, 6)
                }
                
                // 渐变背景
                LinearGradient(
                    gradient: Gradient(colors: [Color(.systemBackground).opacity(0), Color(.systemBackground)]),
                    startPoint: .top,
                    endPoint: .center
                )
                .frame(height: 160)
                .zIndex(0)
                
                ChatViewBottom(
                    chatRecord: chatRecord,
                    modelTemp: modelTemp,
                    TemporaryRecord: TemporaryRecord,
                    respondIndex: respondIndex,
                    onSelectModel: selectModel,
                    onSendUser: { handleMessageSending(ifObservingMode: false) },
                    onSendObserve: { handleMessageSending(ifObservingMode: true) },
                    onCancel: handleCancellation,
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
                    message: $message,
                    selectedImages: $selectedImages,
                    selectedDocumentURLs: $selectedDocumentURLs,
                    selectedURLs: $selectedURLs,
                    selectedPrompts: $selectedPrompts,
                    showPhotoSourceOptions: $showPhotoSourceOptions,
                    showModelSuggestions: $showModelSuggestions,
                    filteredModels: $filteredModels,
                    isResponding: $isResponding,
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
                    isInputActive: $isInputActive
                )
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .background(Color(.systemBackground))
        .onAppear {
            handleOnAppear()
            NotificationCenter.default.post(name: .hideTabBar, object: true) // 隐藏 TabBar
        }
        .onDisappear {
            NotificationCenter.default.post(name: .hideTabBar, object: false) // 显示 TabBar
            openHistory()
            if TemporaryRecord {
                context.delete(chatRecord)
                do {
                    try context.save()
                } catch {
                    print("退出时删除临时聊天记录失败: \(error)")
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 群聊名称（中间，带有可编辑功能）
            ToolbarItem(placement: .principal) {
                if TemporaryRecord {
                    HStack {
                        Text(" 临 时 对 话 模 式 ")
                            .font(.caption)
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
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .opacity(isEditingTitle ? 0 : 1)
                            .onTapGesture {
                                newChatTitle = chatTitle
                                isEditingTitle = true
                            }
                        
                        // 编辑模式
                        TextField("请输入群聊名称", text: $newChatTitle, onCommit: {
                            if !newChatTitle.isEmpty {
                                if chatTitle != newChatTitle {
                                    chatTitle = newChatTitle
                                    let currentLanguage = Locale.preferredLanguages.first ?? "zh-Hans"
                                    
                                    let text: String
                                    if currentLanguage.hasPrefix("zh") {
                                        text = "群聊名称被修改为“\(chatTitle)”"
                                    } else {
                                        text = "Group chat name has been changed to \"\(chatTitle)\""
                                    }
                                    
                                    let newMessage = ChatMessages(
                                        role: "information",
                                        text: text,
                                        modelDisplayName: "system",
                                        timestamp: Date(),
                                        record: chatRecord
                                    )
                                    chatRecord.name = chatTitle
                                    chatTemps.append(newMessage)
                                    context.insert(newMessage)
                                    do {
                                        try context.save()
                                    } catch {
                                        print("Failed to save message: \(error)")
                                    }
                                }
                            }
                            isEditingTitle = false
                        })
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: UIScreen.main.bounds.width * 0.3) // 限制输入框宽度
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
                            .font(.body)
                            .foregroundColor(.primary)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                            .animation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0.4), value: TemporaryRecord)
                    } else {
                        Image(systemName: "checkmark.bubble")
                            .font(.body)
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
                    Menu("调整模型参数", systemImage: "slider.horizontal.3"){
                        Button(action: {
                            showTopPSlider = false
                            showMaxTokensSlider = false
                            showMaxMessagesNumSlider = false
                            showTemperatureSlider.toggle()
                        }) {
                            Label("调整采样温度", systemImage: "thermometer.variable")
                        }
                        
                        Button(action: {
                            showTemperatureSlider = false
                            showMaxTokensSlider = false
                            showMaxMessagesNumSlider = false
                            showTopPSlider.toggle()
                        }) {
                            Label("调整累积概率", systemImage: "percent")
                        }
                        
                        Button(action: {
                            showTemperatureSlider = false
                            showTopPSlider = false
                            showMaxMessagesNumSlider = false
                            showMaxTokensSlider.toggle()
                        }) {
                            Label("最大回复长度", systemImage: "textformat.characters.arrow.left.and.right")
                        }
                        
                        Button(action: {
                            showTemperatureSlider = false
                            showTopPSlider = false
                            showMaxTokensSlider = false
                            showMaxMessagesNumSlider.toggle()
                        }) {
                            Label("消息数量上限", systemImage: "arrow.up.and.down.text.horizontal")
                        }
                    }
                    
                    // ------ 聊天记录管理 ------
                    Menu("聊天记录管理", systemImage: "bubble.left.and.bubble.right"){
                        Button(action: {
                            showSystemMessageSheet = true
                        }) {
                            Label("设置系统消息", systemImage: "paintbrush.pointed")
                        }
                        Button(action: {
                            isMultiSelectMode.toggle()
                        }) {
                            Label(isMultiSelectMode ? "退出编辑模式" : "编辑聊天记录", systemImage: "checkmark.circle")
                        }
                        
                        Button(action: {
                            showingExportOptions = true
                        }) {
                            Label("导出聊天记录", systemImage: "square.and.arrow.up")
                        }
                        
                        Button(action: {
                            showImportExplanationAlert = true
                        }) {
                            Label("导入聊天记录", systemImage: "square.and.arrow.down")
                        }
                        
                        Button(action: {
                            showClearChatConfirmation = true
                        }) {
                            Label("清空聊天记录", systemImage: "eraser.line.dashed")
                        }
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.body)
                        .foregroundColor(.primary)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0.4), value: TemporaryRecord)
                }
            }
        }
        .confirmationDialog("选择导出格式", isPresented: $showingExportOptions, titleVisibility: .visible) {
            Button("纯文本 (.txt)") {
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
            Button("JSON文件 (.json)（文本）") {
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
            Button("JSON文件 (.json)（多模态）") {
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
            Button("取消", role: .cancel) { }
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
        .alert(isPresented: $isShowingImportErrorAlert) {
            Alert(title: Text("导入错误"),
                  message: Text(importError ?? "未知错误"),
                  dismissButton: .default(Text("确定")))
        }
        .alert("确认清空聊天记录", isPresented: $showClearChatConfirmation) {
            Button("删除", role: .destructive) {
                newConversation()
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("是否要删除所有聊天记录？删除后不可恢复。")
                .multilineTextAlignment(.leading)
        }
        .alert("导入聊天记录说明", isPresented: $showImportExplanationAlert) {
            Button("继续") {
                isShowingImportPicker = true
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("请提供 JSON 文件，格式要求与本软件导出的 JSON 文件格式一致，本软件采用 OpenAI 的请求 JSON 格式，包括文本对话和含图片的多模态对话，图片使用 base64 数据。")
                    .multilineTextAlignment(.leading)
        }
        .tint(TemporaryRecord ? .primary : nil)
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
                                .font(.caption)
                                .padding()
                        }
                        Spacer()
                    }

                    // 聊天记录
                    ForEach(chatTemps) { msg in
                        createChatBubble(for: msg)
                            .sensoryFeedback(.success, trigger: isOutPut)
                            .id(msg.id)
                    }

                    Spacer()

                    // 底部留白
                    Color.clear
                        .padding(.bottom, dynamicBottomPadding())
                        .animation(.easeInOut(duration: 0.5), value: dynamicBottomPadding())
                        .id("BottomPadding")
                }
                .padding(.horizontal)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(ifScroll ? .top : .bottom)
            .scrollIndicators(.hidden)
            .refreshable {
                loadMoreMessages()
            }
            .onChange(of: scrollTriggerState) {
                if !showScrollToBottomButton {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        scrollToLastMessage(using: scrollViewProxy)
                    }
                }
            }
            .onChange(of: [needScrollToBottomButton, ifScroll]) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    scrollToLastMessage(using: scrollViewProxy)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if let matchedID = matchedMessageID {
                        if chatTemps.contains(where: { $0.id == matchedID }) {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                scrollViewProxy.scrollTo(matchedID, anchor: .center)
                            }
                        } else {
                            print("⚠️ matchedMessageID 不在 chatTemps 中，无法滚动")
                        }
                    }
                }
            }
            .onTapGesture {
                isInputActive = false
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                showTemperatureSlider = false
                showTopPSlider = false
                showMaxTokensSlider = false
                showMaxMessagesNumSlider = false
            }
            .simultaneousGesture(
                DragGesture().onChanged { _ in
                    isInputActive = false
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    showTemperatureSlider = false
                    showTopPSlider = false
                    showMaxTokensSlider = false
                    showMaxMessagesNumSlider = false
                }
            )
            .onScrollGeometryChange(for: Bool.self) { geometry in
                let isScrolledToBottom = geometry.contentOffset.y + geometry.containerSize.height > geometry.contentSize.height - geometry.contentInsets.bottom - geometry.containerSize.height/2
                return isScrolledToBottom
            } action: { wasScrolledToBottom, isScrolledToBottom in
                withAnimation {
                    showScrollToBottomButton = !isScrolledToBottom
                }
            }
    }
    
    // 聊天时滚动到最底层
    private func scrollToLastMessage(using scrollViewProxy: ScrollViewProxy) {
        // 使用带弹性的 Spring 动画，让滚动更柔和
        withAnimation(.interactiveSpring(response: 0.5, dampingFraction: 0.8, blendDuration: 0.5)) {
            scrollViewProxy.scrollTo("BottomPadding", anchor: .bottom)
        }
    }

    // 创建聊天信息
    private func createChatBubble(for msg: ChatMessages) -> some View {
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
            let prev = chatTemps[idx - 1]
            return !(prev.role == "assistant" && prev.groupID == msg.groupID)
        }()
        
        // —— 计算当前消息所在的连续助手组，以及该组的“中点”位置 ——
        let idx = chatTemps.firstIndex(where: { $0.id == msg.id })!
        // 收集同组连续 assistant 的所有 message IDs
        let groupIDs: [UUID] = {
            guard msg.role == "assistant" else { return [msg.id] }
            var ids = [UUID]()
            // 向前收集
            var i = idx
            while i >= 0 {
                let m = chatTemps[i]
                guard m.role == "assistant", m.groupID == msg.groupID else { break }
                ids.insert(m.id, at: 0)
                i -= 1
            }
            // 向后收集
            i = idx + 1
            while i < chatTemps.count {
                let m = chatTemps[i]
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
        let isGroupCenter = groupIndices.count > 1
        && idx == (groupIndices.first! + groupIndices.last!) / 2
        
        // 1. 构造基础气泡
        let bubble = ChatBubbleView(
            temporaryRecord: TemporaryRecord,
            id: msg.id,
            text: msg.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
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
            resources: msg.resources,
            prompts: msg.promptUse,
            locations: msg.locationsInfo,
            routes: msg.routeInfos,
            events: msg.events,
            htmlContent: msg.htmlContent,
            healthCards: msg.healthData,
            codeBlocks: msg.codeBlockData,
            knowledgeCard: msg.knowledgeCard,
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
        
        // 2. 多选模式下，只在“用户消息”或“助手中点”显示勾选框
        return Group {
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
                                    ? .hlGreen
                                    : .gray)
                            }
                        }
                    }
                }
            } else {
                bubble
            }
        }
    }
    
    private func openHistory() {
        // 如果输入框有草稿内容，则优先保存草稿
        if !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            chatRecord.infoDescription = "[草稿] \(message)"
            chatRecord.input = message
        } else if let lastMessage = chatTemps.last {
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
                    chatRecord.infoDescription = "[图像] \(previewText ?? "")"
                } else {
                    chatRecord.infoDescription = "[图像]"
                }
            } else {
                chatRecord.infoDescription = ""
            }
        }
        do {
            try context.save()
        } catch {
            print("Failed to save chat record updates: \(error)")
        }
    }
    
    private func newConversation() {
        // 新建对话逻辑
        deleteChatMessages()
        insertDeleteMessage()
    }
    
    // 插入清空消息
    private func insertDeleteMessage() {
        let currentLanguage = Locale.preferredLanguages.first ?? "zh-Hans"
        
        ifScroll = true
        
        // 适配清空聊天记录的提示
        let clearChatText: String
        if currentLanguage.hasPrefix("zh") {
            clearChatText = "一切都是崭新的✨"
        } else {
            clearChatText = "Everything is brand new ✨"
        }

        // 创建清空聊天记录的消息
        let welcomeMessage = ChatMessages(
            role: "information",
            text: clearChatText,
            reasoning: "",
            modelDisplayName: "系统",
            timestamp: Date(),
            record: chatRecord
        )
        
        chatTemps.append(welcomeMessage)
        context.insert(welcomeMessage)
        do {
            try context.save()
        } catch {
            print("Failed to save message: \(error)")
        }
    }
    
    // 删除聊天记录
    private func deleteChatMessages() {
        chatTemps.removeAll()
        
        if let messages = chatRecord.messages {
            for message in messages {
                context.delete(message)
            }
        }

        do {
            try context.save()
        } catch {
            print("Failed to delete messages from database: \(error)")
        }
    }
    
    // 处理消息发送
    private func handleMessageSending(ifObservingMode: Bool) {
        
        isFeedBack.toggle()
        var userMessage: ChatMessages?
        var isSearch: Bool = false
        showPhotoSourceOptions = false
        operationalState = ""
        operationalDescription = ""
        
        // 新消息处理
        if !ifObservingMode {
            if !isRetry {
                // 新消息建立
                userMessage = ChatMessages(
                    role: "user",
                    text: message,
                    images: selectedImages,
                    reasoning: "",
                    documents: selectedDocumentURLs.map { $0.absoluteString },
                    modelName: modelTemp[selectedModelIndex].name,
                    modelDisplayName: modelTemp[selectedModelIndex].displayName,
                    timestamp: Date(),
                    record: chatRecord
                )
                if !selectedPrompts.isEmpty {
                    let promptCards = selectedPrompts.map { PromptCard(name: $0.name ?? "无名称", content: $0.content ?? "无内容") }
                    userMessage?.promptUse = promptCards
                }
                // 写入用户发送的信息
                if let userMessage = userMessage, !isObserving, !isRetry {
                    chatTemps.append(userMessage)
                    context.insert(userMessage)
                }
                message = ""
                selectedImages.removeAll()
                selectedDocumentURLs = []
                isInputActive = false
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
        
        // 传输数据准备
        var maxMessage = maxMessagesNum
        if maxMessage < 0 {
            maxMessage = 999
        }
        let messagesToSend = chatTemps.suffix(maxMessage).map { chat in
            RequestMessage(
                role: chat.role ?? "system",
                text: chat.text ?? "",
                images: chat.imageArray.isEmpty ? nil : chat.imageArray,
                imageText: chat.images_text ?? "",
                document: (chat.documentURLs?.isEmpty == false) ? chat.documentURLs : nil,
                documentText: chat.document_text ?? "",
                htmlContent: chat.htmlContent ?? "",
                prompt: chat.promptUse,
                modelName: chat.modelName ?? "Unknown",
                modelDisplayName: chat.modelDisplayName ?? "Unknown"
            )
        }
        
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
        var assistantMessage = assistantPlaceholder  // 保存引用，避免反复查找
        let groupBeginMessage = assistantPlaceholder
        
        // 进行API请求
        self.apiManager = APIManager(context: context)
        
        let currentLanguage = Locale.preferredLanguages.first ?? "zh-Hans"
        
        var reasoningStart: Date? = nil
        var reasoningEnd: Date?   = nil
        var reasoningTotal: Double? = nil
        
        Task {
            do {
                let stream: AsyncThrowingStream<StreamData, Swift.Error> = try await apiManager!.sendStreamRequest(
                    messages: messagesToSend,
                    modelName: modelTemp[selectedModelIndex].name ?? "Unknown",
                    groupID: thisGroupID,
                    ifSearch: modelTemp[selectedModelIndex].supportsSearch && ifSearch,
                    ifKnowledge: modelTemp[selectedModelIndex].supportsSearch && ifKnowledge,
                    ifToolUse: modelTemp[selectedModelIndex].supportsToolUse && ifToolUse,
                    ifThink: modelTemp[selectedModelIndex].supportsReasoning && ifThink,
                    ifAudio: modelTemp[selectedModelIndex].supportsVoiceGen && ifAudio,
                    ifPlanning: !modelTemp[selectedModelIndex].supportsReasoning && ifPlanning,
                    thinkingLength: thinkingLength,
                    isObservation: ifObservingMode,
                    temperature: temperature,
                    topP: topP,
                    maxTokens: maxTokens,
                    canvasData: chatRecord.canvas ?? CanvasData(),
                    selectedURLs: selectedURLs,
                    selectedPromptsContent: selectedPrompts.compactMap { $0.content },
                    systemMessage: useSystemMessage ? "Default" : systemMessage,
                    selectedImageSize: selectedImageSize,
                    imageReversePrompt: imageReversePrompt
                )
                
                // 接受流式数据
                for try await data in stream {
                    await MainActor.run {
                        if isCancelled { return }
                        
                        var updated = false
                        
                        // 普通回复文本
                        if let content = data.content {
                            assistantMessage.text?.append(content)
                            if !operationalState.isEmpty { operationalState = "" }
                            if let start = reasoningStart, let end = reasoningEnd {
                                let seg = end.timeIntervalSince(start)
                                reasoningTotal = (reasoningTotal ?? 0) + seg
                            }
                            reasoningStart = nil
                            reasoningEnd   = nil
                            updated = true
                        }
                        
                        // 推理文本
                        if let reasoning = data.reasoning {
                            let now = Date()
                            if reasoningStart == nil { reasoningStart = now }
                            reasoningEnd = now

                            // 初始化一下，防止 nil
                            if groupBeginMessage.reasoning == nil {
                                groupBeginMessage.reasoning = ""
                            }
                            // 追加原始流出的推理片段
                            groupBeginMessage.reasoning! += reasoning

                            // 清除 <think> 标签
                            groupBeginMessage.reasoning = groupBeginMessage.reasoning?
                                .replacingOccurrences(
                                    of: "<\\/?think[^>]*>?",
                                    with: "",
                                    options: .regularExpression
                                )

                            if !operationalState.isEmpty { operationalState = "" }
                            updated = true
                        }
                        
                        // 工具文本
                        if let toolContent = data.toolContent {
                            assistantMessage.toolContent = toolContent
                            if let toolName = data.toolName {
                                assistantMessage.toolName = toolName
                            }
                            updated = true
                        }
                        
                        // 搜索资源信息
                        if let resources = data.resources {
                            assistantMessage.resources = resources
                            updated = true
                        }
                        
                        // 搜索引擎信息
                        if let searchEngine = data.searchEngine {
                            assistantMessage.searchEngine = searchEngine
                            updated = true
                        }
                        
                        // 图像内容
                        if let imageContent = data.image_content, !imageContent.isEmpty {
                            assistantMessage.imageArray = imageContent
                            if !operationalState.isEmpty { operationalState = "" }
                            if let start = reasoningStart, let end = reasoningEnd {
                                let seg = end.timeIntervalSince(start)
                                reasoningTotal = (reasoningTotal ?? 0) + seg
                            }
                            reasoningStart = nil
                            reasoningEnd = nil
                            updated = true
                        }
                        
                        // 图像描述文本
                        if let imageText = data.image_text, !imageText.isEmpty {
                            if let index = chatTemps.lastIndex(where: { !$0.imageArray.isEmpty && ($0.images_text?.isEmpty ?? true) }) {
                                chatTemps[index].images_text = imageText
                                updated = true
                            }
                        }

                        // 文件内容文本
                        if let documentText = data.document_text, !documentText.isEmpty {
                            if let index = chatTemps.lastIndex(where: { $0.documents != nil && ($0.document_text?.isEmpty ?? true) }) {
                                chatTemps[index].document_text = documentText
                                updated = true
                            }
                        }
                        
                        // 自动标题文本
                        if let autoTitle = data.autoTitle, !autoTitle.isEmpty {
                            chatTitle = autoTitle
                            chatRecord.name = chatTitle
                            updated = true
                        }
                        
                        // 搜索返回文本
                        if let searchText = data.search_text, !searchText.isEmpty {
                            let newSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                            let searchMessage = ChatMessages(
                                role: "search",
                                text: newSearchText,
                                searchEngine: data.searchEngine,
                                modelName: "system",
                                modelDisplayName: "system",
                                timestamp: Date(),
                                record: chatRecord
                            )
                            if let assistantIndex = chatTemps.lastIndex(where: { $0.role == "assistant" }) {
                                chatTemps.insert(searchMessage, at: assistantIndex)
                            } else {
                                chatTemps.append(searchMessage)
                            }
                            isSearch = true
                            updated = true
                        }
                        
                        // 位置信息
                        if let locationsInfo = data.locations_info, !locationsInfo.isEmpty {
                            assistantMessage.locationsInfo = locationsInfo
                            updated = true
                        }
                        
                        // 路线信息
                        if let routeInfo = data.route_info, !routeInfo.isEmpty {
                            assistantMessage.routeInfos = routeInfo
                            updated = true
                        }
                        
                        // 事件信息
                        if let eventsInfo = data.events, !eventsInfo.isEmpty {
                            assistantMessage.events = eventsInfo
                            updated = true
                        }
                        
                        // 网页信息
                        if let htmlContent = data.htmlContent, !htmlContent.isEmpty {
                            assistantMessage.htmlContent = htmlContent
                            updated = true
                        }
                        
                        // 健康信息
                        if let healthCard = data.health_info, !healthCard.isEmpty {
                            assistantMessage.healthData = healthCard
                            updated = true
                        }
                        
                        // 代码信息
                        if let codeBlock = data.code_info, !codeBlock.isEmpty {
                            assistantMessage.codeBlockData = codeBlock
                            updated = true
                        }
                        
                        // 知识卡片
                        if let knowledgeCard = data.knowledge_card, !knowledgeCard.isEmpty {
                            assistantMessage.knowledgeCard = knowledgeCard
                            updated = true
                        }
                        
                        // 画布信息
                        if let canvasInfo = data.canvas_info {
                            do {
                                // 调用保存接口，将未保存的 canvasInfo 持久化到 chatRecord
                                _ = try CanvasServices.saveCanvas(
                                    canvasInfo,
                                    to: chatRecord,
                                    in: context
                                )
                                assistantMessage.showCanvas = true
                                updated = true
                            } catch {
                                // 保存失败时的处理
                                print("保存画布失败：\(error)")
                                // 可根据需要弹 alert 或者设置一个 error 状态供 UI 展示
                            }
                        }
                        
                        // 语音信息
                        if let asset = data.audioAsset {
                            assistantMessage.audioAssets = [asset]
                            assistantMessage.audioExpanded = true
                            updated = true
                        }
                        
                        // 更新操作状态文本
                        if let stateText = data.operationalState, !stateText.isEmpty {
                            operationalState = stateText
                            updated = true
                        }
                        
                        // 更新操作状态描述
                        if let descriptionText = data.operationalDescription, !descriptionText.isEmpty {
                            // 1. 去掉首尾空格和换行
                            let trimmed = descriptionText
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            
                            // 2. 折叠多行间的连续空白（包括空格、制表符）成一个换行
                            let collapsedNewlines = trimmed.replacingOccurrences(
                                of: "\\s*\\n+\\s*",
                                with: "\n",
                                options: .regularExpression
                            )
                            
                            // 3. 折叠多余的连续空格或制表符成一个普通空格
                            let normalized = collapsedNewlines.replacingOccurrences(
                                of: "[ \\t]{2,}",
                                with: " ",
                                options: .regularExpression
                            )
                            
                            // 4. 再追加到 operationalDescription
                            operationalDescription.append("\n\(normalized)")
                            updated = true
                        }
                        
                        // 更新信息
                        if updated {
                            let currentTime = Date()
                            if currentTime.timeIntervalSince(lastUpdateTime) > refreshInterval {
                                assistantMessage.id = UUID()
                                assistantMessage.timestamp = currentTime
//                                if outPutFeedBackEnabled { isOutPut.toggle() }
                                lastUpdateTime = currentTime
                            }
                            
                            if let start = reasoningStart, let end = reasoningEnd {
                                let closed = reasoningTotal ?? 0
                                let openSeg = end.timeIntervalSince(start)
                                let totalSeconds = closed + openSeg
                                
                                let text: String
                                if currentLanguage.hasPrefix("zh") {
                                    if totalSeconds < 60 {
                                        text = String(format: "已思考%.1f秒", totalSeconds)
                                    } else if totalSeconds < 3600 {
                                        let minutes = Int(totalSeconds) / 60
                                        let seconds = totalSeconds - Double(minutes * 60)
                                        text = String(format: "已思考%d分钟%.1f秒", minutes, seconds)
                                    } else {
                                        // 支持小时
                                        let hours = Int(totalSeconds) / 3600
                                        let remainder = Int(totalSeconds) % 3600
                                        let minutes = remainder / 60
                                        let seconds = Double(remainder % 60)
                                        text = String(format: "已思考%d小时%d分钟%.1f秒", hours, minutes, seconds)
                                    }
                                } else {
                                    if totalSeconds < 60 {
                                        text = String(format: "Thought for %.1f sec", totalSeconds)
                                    } else if totalSeconds < 3600 {
                                        let minutes = Int(totalSeconds) / 60
                                        let seconds = totalSeconds - Double(minutes * 60)
                                        text = String(format: "Thought for %d min %.1f sec", minutes, seconds)
                                    } else {
                                        // 支持小时
                                        let hours = Int(totalSeconds) / 3600
                                        let remainder = Int(totalSeconds) % 3600
                                        let minutes = remainder / 60
                                        let seconds = Double(remainder % 60)
                                        text = String(format: "Thought for %d hr %d min %.1f sec", hours, minutes, seconds)
                                    }
                                }
                                if text != groupBeginMessage.reasoningTime, !text.isEmpty {
                                    groupBeginMessage.reasoningTime = text
                                }
                            }
                        }
                        
                        if let split = data.splitMarkers {
                            assistantMessage.reasoning = assistantMessage.reasoning?.trimmingCharacters(in: .whitespacesAndNewlines)
                            context.insert(assistantMessage)
                            // 创建助手消息占位符，并保存引用以便后续高效更新
                            let newPlaceholder = ChatMessages(
                                role: "assistant",
                                text: "",
                                images: nil,
                                reasoning: "",
                                documents: nil,
                                modelName: split.modelName,
                                modelDisplayName: split.modelDisplayName,
                                groupID: split.groupID,
                                timestamp: Date(),
                                record: chatRecord
                            )
                            chatTemps.append(newPlaceholder)
                            assistantMessage = newPlaceholder
                        }
                        
                        // 异常提醒
                        if let error = data.errorInfo, !error.isEmpty {
                            var errorMessage = ""
                            if error == "length" {
                                errorMessage = currentLanguage.hasPrefix("zh") ? "⚠️ 输出长度到达模型最大输出长度！可在右上角模型参数中重新设置输出长度。" : "⚠️ The output length has reached the model's maximum output length! You can reset the output length in the model parameters at the top right corner."
                            } else if error == "sensitive" {
                                errorMessage = currentLanguage.hasPrefix("zh") ? "⚠️ 包含敏感内容！" : "⚠️ Contains sensitive content!"
                            } else {
                                errorMessage = error
                            }
                            if !errorMessage.isEmpty {
                                let infoMessage = ChatMessages(
                                    role: "information",
                                    text: errorMessage,
                                    images: [],
                                    reasoning: "",
                                    documents: nil,
                                    modelName: "system",
                                    modelDisplayName: "system",
                                    timestamp: Date(),
                                    record: chatRecord
                                )
                                
                                chatTemps.append(infoMessage)
                            }
                        }
                    }
                }
                
                isObserving = false
                isResponding = false
                respondIndex = 0
                
                // 最终判断：仅当助手消息既没有文本又没有图片时，视为请求异常
                if chatTemps.firstIndex(where: { $0 === assistantMessage }) != nil {
                    let textContent = assistantMessage.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let reasoningContent = assistantMessage.reasoning?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if textContent.isEmpty && reasoningContent.isEmpty && assistantMessage.imageArray.isEmpty {
                        operationalState = ""
                        operationalDescription = ""
                        assistantMessage.text = currentLanguage.hasPrefix("zh") ? "⚠️ 生成内容为空，请重新尝试！" : "⚠️ Generated content is empty, please try again!"
                        assistantMessage.role = "error"
                        assistantMessage.modelName = "system"
                        assistantMessage.modelDisplayName = "system"
                    } else {
                        
                        // 一切正常，进行数据库保存操作
                        do {
                            if outPutFeedBackEnabled { isOutPut.toggle() }
                            operationalState = ""
                            operationalDescription = ""
                            // 去除文本两端的换行符
                            assistantMessage.text = textContent
                            assistantMessage.reasoning = assistantMessage.reasoning?.trimmingCharacters(in: .whitespacesAndNewlines)
                            
                            // 写入搜索消息（如果存在）
                            if let searchMessage = chatTemps.last(where: { $0.role == "search" }), isSearch {
                                searchMessage.record = chatRecord
                                context.insert(searchMessage)
                            }
                            
                            context.insert(assistantMessage)
                            
                            if let outputText = assistantMessage.text?
                                .replacingOccurrences(of: "\n", with: " ")
                                .trimmingCharacters(in: .whitespacesAndNewlines),
                               !outputText.isEmpty {
                                let previewText = outputText.prefix(80)
                                chatRecord.infoDescription = "\(previewText)"
                                chatRecord.lastEdited = assistantMessage.timestamp
                            } else if !assistantMessage.imageArray.isEmpty {
                                if chatTemps.count >= 2 {
                                    let previousMessage = chatTemps[chatTemps.count - 2]
                                    let previewText = previousMessage.text?
                                        .replacingOccurrences(of: "\n", with: " ")
                                        .trimmingCharacters(in: .whitespacesAndNewlines)
                                        .prefix(80) ?? ""
                                    chatRecord.infoDescription = "[图像] \(previewText)"
                                    chatRecord.lastEdited = previousMessage.timestamp
                                } else {
                                    chatRecord.infoDescription = "[图像]"
                                    chatRecord.lastEdited = assistantMessage.timestamp
                                }
                            }
                            
                            try context.save()
                            
                        } catch {
                            let syncErrorText: String
                            if currentLanguage.hasPrefix("zh") {
                                syncErrorText = "⚠️ 数据同步失败: \(error.localizedDescription)，本轮问答不会被同步。"
                            } else {
                                syncErrorText = "⚠️ Data synchronization failed: \(error.localizedDescription). This round of Q&A will not be synchronized."
                            }
                            let errorMessageShow = ChatMessages(
                                role: "information",
                                text: syncErrorText,
                                modelDisplayName: "system",
                                timestamp: Date(),
                                record: chatRecord
                            )
                            chatTemps.append(errorMessageShow)
                            operationalState = ""
                            operationalDescription = ""
                        }
                    }
                }
                
            } catch {
                // 响应异常处理
                await MainActor.run {
                    if let index = chatTemps.lastIndex(where: { $0.role == "assistant" }) {
                        operationalState = ""
                        operationalDescription = ""
                        let responseErrorText: String
                        if currentLanguage.hasPrefix("zh") {
                            responseErrorText = "⚠️ 响应错误：\(error.localizedDescription)"
                        } else {
                            responseErrorText = "⚠️ Response error: \(error.localizedDescription)"
                        }
                        chatTemps[index].text = responseErrorText
                        chatTemps[index].role = "error"
                        chatTemps[index].role = "error"
                        chatTemps[index].modelDisplayName = "system"
                        isResponding = false
                        respondIndex = 0
                    }
                }
            }
        }
    }
    
    // 打断操作
    private func handleCancellation() {
        
        isFeedBack.toggle()
        isCancelled = true
        
        apiManager?.cancelCurrentRequest()
        
        isObserving = false
        isResponding = false
        respondIndex = 0
        operationalState = ""
        operationalDescription = ""
        let currentLanguage = Locale.preferredLanguages.first ?? "zh-Hans"
        let responseInterruptedText: String
        if currentLanguage.hasPrefix("zh") {
            responseInterruptedText = "🛑 响应已打断"
        } else {
            responseInterruptedText = "🛑 Response interrupted"
        }
        
        let infoMessage = ChatMessages(
            role: "information",
            text: responseInterruptedText,
            modelName: "system",
            modelDisplayName: "system",
            timestamp: Date(),
            record: chatRecord
        )
        
        chatTemps.append(infoMessage)
        context.insert(infoMessage)
        
        if isRetry {
            isRetry = false
        }
        
        apiManager = nil
        isCancelled = false
    }
    
    // 重新请求
    private func retryRequest(for message: ChatMessages) {
        // 1. 获取 record.messages 和 chatTemps 中的索引
        guard let recordMsgs = chatRecord.messages,
              let startIndex = recordMsgs.lastIndex(where: { $0.id == message.id }),
              let tempIndex  = chatTemps.lastIndex(where:     { $0.id == message.id })
        else { return }

        let targetGroupID = message.groupID

        // 2. 向前回溯，寻找连续的 assistant 同组消息的起点
        var deleteStartIndex = startIndex
        var backIdx = startIndex - 1
        while backIdx >= 0 {
            let prev = recordMsgs[backIdx]
            if prev.role == "assistant" && prev.groupID == targetGroupID {
                deleteStartIndex = backIdx
                backIdx -= 1
            } else {
                break
            }
        }

        // 3. 删除 record 中从 deleteStartIndex 到末尾的所有消息
        for idx in deleteStartIndex..<recordMsgs.count {
            context.delete(recordMsgs[idx])
        }
        do {
            try context.save()
        } catch {
            print("删除消息失败: \(error)")
            return
        }

        // 4. 在 chatTemps 数组中，同样向前回溯再删除
        var tempDeleteStart = tempIndex
        var tempBack = tempIndex - 1
        while tempBack >= 0 {
            let prevTemp = chatTemps[tempBack]
            if prevTemp.role == "assistant" && prevTemp.groupID == targetGroupID {
                tempDeleteStart = tempBack
                tempBack -= 1
            } else {
                break
            }
        }
        // 从 tempDeleteStart 到末尾一起移除
        chatTemps.removeSubrange(tempDeleteStart...)

        // 5. 标记重试并重新发送
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
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if modelTemp[selectedModelIndex].supportsReasoning {
                ifPlanning = false
                thinkingLength = 0
                if modelTemp[selectedModelIndex].supportReasoningChange {
                    ifThink = false
                } else {
                    ifThink = true
                }
            } else {
                ifThink = false
            }
            if modelTemp[selectedModelIndex].supportsVoiceGen {
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
