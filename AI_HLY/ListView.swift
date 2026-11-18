import SwiftUI
import SwiftData

struct ListView: View {
    @Binding var requestedSelection: HanlinConversationSelection?
    let onOpenProfile: () -> Void
    let onOpenMiniApps: () -> Void
    let onOpenVision: () -> Void
    @State private var conversationUnavailable = false

    init(requestedSelection: Binding<HanlinConversationSelection?> = .constant(nil),
         onOpenProfile: @escaping () -> Void = {},
         onOpenMiniApps: @escaping () -> Void = {},
         onOpenVision: @escaping () -> Void = {}) {
        self._requestedSelection = requestedSelection
        self.onOpenProfile = onOpenProfile
        self.onOpenMiniApps = onOpenMiniApps
        self.onOpenVision = onOpenVision
    }
    @Environment(\.modelContext) private var modelContext
    @Environment(\.hanlinAIReceivingWindowID) private var receivingWindowID
    private let splitCoordinator = HanlinAppSplitOriginCoordinator.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var chatRecords: [ChatRecords]
    @Query private var allModels: [AllModels]
    @Query private var apiKeys: [APIKeys]
    
    @State private var searchText: String = ""
    @State private var showsSavedMessages = false
    @State private var loadHistoryMessages: Bool = false
    @State private var infoDescriptionCache: [UUID: String] = [:]
    @State private var newlyCreatedChat: ChatRecords?
    
    @State private var showIconSheet = false
    @State private var editingRecord: ChatRecords? = nil
    @State private var editingIcon: String = "bubble.left.circle"
    @State private var editingColor: Color = .hlBlue
    @State private var editingTitle: String = "title"
    
    @State private var navigationPath: [ChatRecords] = []
    @State private var compactWorkspacePath: [HanlinCompactWorkspaceRoute] = []
    @State private var sessionBridge = HanlinActiveComposerSessionBridge()
    @State private var measuredContainerWidth: CGFloat = 0
    @State private var selectedChatRecord: ChatRecords? = nil
    @State private var savedSourceDestination: ChatSourceDestination?
    @State private var matchedSnippets: [UUID: (AttributedString, UUID)] = [:]
    
    @State private var showSafariGuide: Bool = false

    @State private var showValidationAlert: Bool = false
    @State private var validationAlertMessage: String = ""
    @State private var validationSettingType: SettingType? = nil
    @State private var showSettingSheet: Bool = false

    // 设置类型枚举
    enum SettingType {
        case apiKeys        // 模型厂商
        case optimization   // 优化模型
        case embedding      // 向量模型
    }

    // 添加一个强制刷新状态，当需要更新列表时切换该状态
    @State private var forceRefresh: Bool = false

    static func filterAndSortChatRecords(_ records: [ChatRecords], searchText: String) -> [ChatRecords] {
        let baseRecords: [ChatRecords]
        if searchText.isEmpty {
            baseRecords = records
        } else {
            let lowercasedSearchText = searchText.lowercased()
            let pinyinSearchText = searchText.toPinyin().lowercased()
            baseRecords = records.filter { record in
                let recordName = record.name ?? ""
                let lowercasedRecordName = recordName.lowercased()
                let matchName = lowercasedRecordName.contains(lowercasedSearchText)
                let matchNamePinyin = recordName.toPinyin().lowercased().contains(pinyinSearchText)
                let matchMessages = record.messages?.contains { message in
                    message.text?.range(of: searchText, options: .caseInsensitive) != nil
                } ?? false
                return matchName || matchNamePinyin || matchMessages
            }
        }
        let pinnedRecords = baseRecords.filter { $0.isPinned }
            .sorted { $0.lastEdited > $1.lastEdited }
        let unpinnedRecords = baseRecords.filter { !$0.isPinned }
            .sorted { $0.lastEdited > $1.lastEdited }
        return pinnedRecords + unpinnedRecords
    }

    // 修改计算属性，让置顶的记录始终显示在上方
    private var filteredChatRecords: [ChatRecords] {
        Self.filterAndSortChatRecords(chatRecords, searchText: searchText)
    }

    private var defaultInitialChatRecord: ChatRecords? {
        chatRecords
            .filter { ($0.type ?? "chat") == "chat" }
            .max(by: { $0.lastEdited < $1.lastEdited })
            ?? filteredChatRecords.first
    }
    
    private var useCompactWorkspace: Bool {
        let effectiveWidth = HanlinCompactChatWorkspace.effectiveContainerWidth(
            measuredWidth: measuredContainerWidth
        )
        return HanlinCompactChatWorkspace.shouldUseCompactWorkspace(
            isPhoneIdiom: UIDevice.current.userInterfaceIdiom == .phone,
            horizontalSizeClass: horizontalSizeClass,
            availableWidth: effectiveWidth
        )
    }

    var body: some View {
        Group {
            if !useCompactWorkspace {
                NavigationSplitView {
                    sidebarContent
                        .navigationTitle("Hanlin")
                        .safeAreaInset(edge: .bottom) {
                            Color.clear.frame(height: 75)
                        }
                        .toolbar {
                            commonToolbar
                        }
                } detail: {
                    if let selected = selectedChatRecord {
                        let snippetPair = matchedSnippets[selected.id ?? UUID()]
                        let messageID = snippetPair?.1
                        NavigationStack {
                            ChatViewWrapper(chatRecord: selected, matchedMessageID: messageID)
                        }
                        .id(selected.id)
                    } else {
                        ContentUnavailableView("请选择一个对话", systemImage: "bubble.left.and.bubble.right")
                    }
                }
            } else {
                HanlinCompactChatWorkspace(
                    chatRecords: chatRecords,
                    allModels: allModels,
                    path: $compactWorkspacePath,
                    searchText: $searchText,
                    matchedSnippets: matchedSnippets,
                    loadHistoryMessages: loadHistoryMessages,
                    forceRefresh: forceRefresh,
                    onOpenSafariGuide: { showSafariGuide = true },
                    onCreateAuthorizedNewChat: { createAuthorizedNewChatRecord() },
                    onTogglePin: { record in togglePin(record) },
                    onEditRecord: { record in beginEditingRecord(record) },
                    onDeleteRecord: { record in deleteChat(record) },
                    onRefresh: { handleOnAppear() },
                    sessionBridge: sessionBridge,
                    onOpenProfile: onOpenProfile, onOpenMiniApps: onOpenMiniApps,
                    onOpenVision: onOpenVision
                )
            }
        }
        .task(id: requestedSelection?.id) {
            guard let request = requestedSelection else { return }
            guard splitCoordinator.acceptedOrigin(forReceivingWindowID: receivingWindowID) == nil else {
                requestedSelection = nil
                return
            }
            let id = request.conversationID
            do {
                let matches = try modelContext.fetch(FetchDescriptor<ChatRecords>(predicate: #Predicate { $0.id == id }))
                guard matches.count == 1, let record = matches.first else {
                    conversationUnavailable = true
                    requestedSelection = nil
                    return
                }
                savedSourceDestination = request.source
                if let source = request.source {
                    matchedSnippets[id] = (AttributedString(source.quote), source.messageID)
                } else if let messageID = request.messageID {
                    matchedSnippets[id] = (AttributedString(""), messageID)
                } else {
                    matchedSnippets.removeValue(forKey: id)
                }
                selectedChatRecord = record
                sessionBridge.expectedActiveSessionID = id
                if useCompactWorkspace { compactWorkspacePath = [.chat(id)] }
                requestedSelection = nil
            } catch {
                conversationUnavailable = true
                requestedSelection = nil
            }
        }
        .alert("Conversation unavailable", isPresented: $conversationUnavailable) {
            Button("OK", role: .cancel) {}
        } message: { Text("The original conversation could not be opened. Your library item is kept.") }
        .task(id: splitCoordinator.acceptedOrigin(forReceivingWindowID: receivingWindowID)?.id) {
            guard !Task.isCancelled,
                  let request = splitCoordinator.acceptedOrigin(forReceivingWindowID: receivingWindowID) else { return }
            let id = request.chat
            guard let rows = try? modelContext.fetch(FetchDescriptor<ChatRecords>(predicate: #Predicate { $0.id == id })),
                  rows.count == 1, let original = rows.first,
                  splitCoordinator.acceptedOrigin(forReceivingWindowID: receivingWindowID)?.id == request.id else { return }
            selectedChatRecord = original
            sessionBridge.expectedActiveSessionID = id
            if useCompactWorkspace { compactWorkspacePath = [.chat(id)] }
            // ChatViewWrapper acknowledges only after this exact existing chat mounts.
        }
        .environment(\.hanlinComposerSessionBridge, sessionBridge)
        .sheet(isPresented: $showsSavedMessages) { ChatSavedExcerptsView() }
        .environment(\.chatSourceDestination, savedSourceDestination)
        .environment(\.chatOpenSavedSource, { record, destination in
            savedSourceDestination = destination
            matchedSnippets[destination.chatRecordID] = (AttributedString(destination.quote), destination.messageID)
            selectedChatRecord = record
            if useCompactWorkspace { compactWorkspacePath = [.chat(destination.chatRecordID)] }
        })
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            if abs(measuredContainerWidth - newWidth) > 1 {
                let wasCompact = useCompactWorkspace
                let nextEffective = HanlinCompactChatWorkspace.effectiveContainerWidth(measuredWidth: newWidth)
                let willBeCompact = HanlinCompactChatWorkspace.shouldUseCompactWorkspace(
                    isPhoneIdiom: UIDevice.current.userInterfaceIdiom == .phone,
                    horizontalSizeClass: horizontalSizeClass,
                    availableWidth: nextEffective
                )
                if wasCompact != willBeCompact {
                    sessionBridge.beginLayoutModeTransition()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        sessionBridge.endLayoutModeTransition()
                    }
                }
                measuredContainerWidth = newWidth
            }
        }
        .onChange(of: selectedChatRecord) { _, newSelected in
            if !useCompactWorkspace {
                sessionBridge.expectedActiveSessionID = newSelected?.id
            }
        }
        .onChange(of: useCompactWorkspace) { _, isCompact in
            sessionBridge.beginLayoutModeTransition()
            if isCompact {
                if compactWorkspacePath.isEmpty, let selectedID = selectedChatRecord?.id {
                    compactWorkspacePath = [.chat(selectedID)]
                }
                if case .chat(let activeID) = compactWorkspacePath.last {
                    sessionBridge.expectedActiveSessionID = activeID
                } else {
                    sessionBridge.expectedActiveSessionID = nil
                }
            } else {
                if case .chat(let activeID) = compactWorkspacePath.last,
                   let match = chatRecords.first(where: { $0.id == activeID }) {
                    selectedChatRecord = match
                } else if selectedChatRecord == nil {
                    selectedChatRecord = defaultInitialChatRecord
                }
                sessionBridge.expectedActiveSessionID = selectedChatRecord?.id
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                sessionBridge.endLayoutModeTransition()
            }
        }
        .onChange(of: searchText) {
            searchTask?.cancel()
            searchTask = Task {
                do {
                    try await Task.sleep(nanoseconds: 300_000_000)
                    if !Task.isCancelled {
                        searchRecords()
                    }
                } catch {}
            }
        }
        .onAppear {
            handleOnAppear()
            searchText = ""
            if !useCompactWorkspace && selectedChatRecord == nil {
                selectedChatRecord = defaultInitialChatRecord
                sessionBridge.expectedActiveSessionID = selectedChatRecord?.id
            }
        }
        .sheet(isPresented: $showIconSheet) {
            IconAndColorPicker(
                selectedIcon: $editingIcon,
                selectedColor: $editingColor,
                title: $editingTitle
            )
            .onDisappear {
                // 当编辑面板关闭时，将编辑好的 icon/color 回写到对应 record
                guard let editingRecord = editingRecord else { return }
                editingRecord.icon = editingIcon
                editingRecord.color = editingColor.name
                editingRecord.name = editingTitle
                do {
                    try modelContext.save()
                    // 切换 forceRefresh 强制刷新列表
                    forceRefresh.toggle()
                } catch {
                    print("Error saving icon or color: \(error.localizedDescription)")
                }
            }
        }
        .sheet(isPresented: $showSafariGuide) {
            NavigationStack { HanlinHelpView(topic: .guide) }
        }
        .alert("无法新建对话", isPresented: $showValidationAlert) {
            Button("前往设置") {
                showSettingSheet = true
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text(validationAlertMessage)
        }
        .sheet(isPresented: $showSettingSheet) {
            NavigationStack {
                Group {
                    switch validationSettingType {
                    case .apiKeys:
                        APIKeysView()
                    case .optimization:
                        SelectOptimizationModelView()
                    case .embedding:
                        SelectEmbeddingModelView()
                    case .none:
                        EmptyView()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("完成") {
                            showSettingSheet = false
                        }
                    }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var commonToolbar: some ToolbarContent {
        HanlinWorkspaceActions(onOpenProfile: onOpenProfile,
            onOpenMiniApps: onOpenMiniApps, onOpenVision: onOpenVision)
        ToolbarItem(placement: .topBarTrailing) {
            Button { showsSavedMessages = true } label: {
                Label("Saved messages", systemImage: "bookmark")
            }
            .accessibilityIdentifier("hanlin-saved-messages-open")
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                addNewChat()
            } label: {
                Image(systemName: "plus.bubble")
            }
            .accessibilityIdentifier("hanlin-new-chat-button")
        }
        ToolbarItem(placement: .navigationBarLeading) {
            if loadHistoryMessages {
                HStack {
                    ProgressView().font(.caption)
                    Text("正在加载...").font(.caption)
                }
            } else {
                HStack {
                    Button(action: {
                        showSafariGuide = true
                    }) {
                        Label {
                            Text("软件指南")
                                .font(.caption)
                        } icon: {
                            Image(systemName: "text.rectangle.page")
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Main Content
    @State private var searchTask: Task<Void, Never>? = nil
    
    @ViewBuilder
    private var sidebarContent: some View {
        List(selection: $selectedChatRecord) {
            chatRecordsSection
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "搜索聊天与消息内容")
        .onChange(of: searchText) {
            searchTask?.cancel()
            searchTask = Task {
                do {
                    try await Task.sleep(nanoseconds: 300_000_000)
                    if !Task.isCancelled {
                        searchRecords()
                    }
                } catch {}
            }
        }
        .refreshable {
            handleOnAppear()
        }
    }
    
    @ViewBuilder
    private var content: some View {
        List {
            chatRecordsSection
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "搜索聊天与消息内容")
        .onChange(of: searchText) {
            // 取消上一次搜索任务
            searchTask?.cancel()
            
            // 创建新的搜索任务并延迟 300 毫秒
            searchTask = Task {
                do {
                    try await Task.sleep(nanoseconds: 300_000_000)
                    // 若没有被取消，执行搜索逻辑（这里只更新 matchedSnippets）
                    if !Task.isCancelled {
                        searchRecords()
                    }
                } catch {
                    // 被取消或出现其它错误时可忽略
                }
            }
        }
        .onChange(of: navigationPath) { oldPath, newPath in
            let isHidden = !newPath.isEmpty
            NotificationCenter.default.post(name: .hideTabBar, object: isHidden)
        }
        .refreshable {
            handleOnAppear()
        }
        .navigationDestination(for: ChatRecords.self) { chat in
            ChatViewWrapper(chatRecord: chat)
        }
    }
    
    @ViewBuilder
    private func backgroundView(for record: ChatRecords) -> some View {
        if record.isPinned {
            BlurView(style: .systemUltraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .shadow(color: Color.from(name: record.color ?? "hlBlue"), radius: 1)
                .padding(3)
        } else {
            Color.clear
        }
    }
    
    // MARK: - 子视图：聊天记录列表
    @ViewBuilder
    private func chatRecordRow(for record: ChatRecords) -> some View {
        let snippetPair = matchedSnippets[record.id ?? UUID()]
        let snippet = snippetPair?.0

        Button {
            selectedChatRecord = record
        } label: {
            ChatRowView(
                record: record,
                searchText: searchText,
                matchedSnippet: snippet
            )
            .contentShape(Rectangle())
            .contextMenu {
                Button {
                    // 编辑图标操作
                    editingRecord = record
                    editingIcon   = record.icon ?? "bubble.left.circle"
                    editingColor  = Color.from(name: record.color ?? ".hlBlue")
                    editingTitle  = record.name ?? ""
                    showIconSheet = true
                } label: {
                    Label("编辑图标", systemImage: "paintbrush")
                }
                
                Button {
                    togglePin(record)
                } label: {
                    Label(record.isPinned ? "取消置顶" : "置顶消息", systemImage: record.isPinned ? "pin.slash" : "pin")
                }
                
                Button(role: .destructive) {
                    deleteChat(record)
                } label: {
                    Label("删除消息", systemImage: "trash")
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
        .padding(.vertical, 5)
        .listRowInsets(EdgeInsets())
        .listRowBackground(backgroundView(for: record))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deleteChat(record)
            } label: {
                Label("删除消息", systemImage: "trash")
            }
            .tint(Color(.hlRed))
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                togglePin(record)
            } label: {
                Label(
                    record.isPinned ? "取消置顶" : "置顶消息",
                    systemImage: record.isPinned ? "pin.slash" : "pin"
                )
            }
            .tint(Color(.hlBlue))
            
            Button {
                // 进入编辑模式
                editingRecord = record
                editingIcon   = record.icon ?? "bubble.left.circle"
                editingColor  = Color.from(name: record.color ?? ".hlBlue")
                editingTitle  = record.name ?? ""
                showIconSheet = true
            } label: {
                Label("编辑图标", systemImage: "paintbrush")
            }
            .tint(.hlGreen)
        }
        .tag(record)
        .id((record.id?.uuidString ?? "") + String(forceRefresh))
        .accessibilityIdentifier("hanlin-chat-row-\(record.name ?? "")")
    }
    
    // 使用 filteredChatRecords 计算属性替代原来的缓存数据
    private var chatRecordsSection: some View {
        Section {
            ForEach(filteredChatRecords, id: \.id) { record in
                chatRecordRow(for: record)
            }
        }
    }
    
    // MARK: - 其他逻辑
    private func handleOnAppear() {
        loadHistoryMessages = true
        Task {
            let records: [ChatRecords] = chatRecords
            let sortedRecords = await sortChatRecords(records)
            await MainActor.run {
                loadHistoryMessages = false
                infoDescriptionCache = sortedRecords.reduce(into: [:]) {
                    $0[$1.id ?? UUID()] = $1.infoDescription
                }
            }
        }
    }
    
    private func sortChatRecords(_ records: [ChatRecords]) async -> [ChatRecords] {
        var pinnedRecords: [ChatRecords] = []
        var unpinnedRecords: [ChatRecords] = []
        
        for record in records {
            if record.isPinned {
                pinnedRecords.append(record)
            } else {
                unpinnedRecords.append(record)
            }
        }
        
        pinnedRecords.sort { $0.lastEdited > $1.lastEdited }
        unpinnedRecords.sort { $0.lastEdited > $1.lastEdited }
        
        return pinnedRecords + unpinnedRecords
    }
    
    // MARK: - 搜索逻辑
    private func searchRecords() {
        if searchText.isEmpty {
            matchedSnippets.removeAll()
        } else {
            var newMatchedSnippets: [UUID: (AttributedString, UUID)] = [:]
            for record in chatRecords {
                if let messages = record.messages {
                    if let snippetResult = findMatchSnippet(
                        messages: messages,
                        searchText: searchText
                    ) {
                        newMatchedSnippets[record.id ?? UUID()] = snippetResult
                    } else {
                        newMatchedSnippets.removeValue(forKey: record.id ?? UUID())
                    }
                }
            }
            matchedSnippets = newMatchedSnippets
        }
    }
    
    /// Search and slice the same String: case folding may change UTF-8 length.
    /// Context remains forty complete Characters on either side of the match.
    nonisolated static func messageSearchSnippet(in text: String, searchText: String) -> String? {
        guard !searchText.isEmpty,
              let range = text.range(of: searchText, options: .caseInsensitive) else { return nil }
        let start = text.index(range.lowerBound, offsetBy: -40, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: 40, limitedBy: text.endIndex) ?? text.endIndex
        return String(text[start..<end])
    }

    /// 找到第一条包含 searchText 的消息，并返回 (带前后文高亮的片段, 消息ID)
    private func findMatchSnippet(messages: [ChatMessages], searchText: String) -> (AttributedString, UUID)? {
        for msg in messages.reversed() {
            guard let msgText = msg.text, !msgText.isEmpty else { continue }
            if let snippetString = Self.messageSearchSnippet(in: msgText, searchText: searchText) {
                
                var attributed = AttributedString(snippetString)
                attributed.font = .caption
                attributed.foregroundColor = Color(.systemGray)
                
                if let subRange = snippetString.range(of: searchText, options: .caseInsensitive) {
                    let nsRange = NSRange(subRange, in: snippetString)
                    if let attrRange = Range(nsRange, in: attributed) {
                        attributed[attrRange].foregroundColor = .hlBlue
                        attributed[attrRange].font = .caption.bold()
                    }
                }
                return (attributed, msg.id)
            }
        }
        return nil
    }
    
    private func togglePin(_ record: ChatRecords) {
        record.isPinned.toggle()
        do {
            try modelContext.save()
            // 置顶后强制刷新列表视图
            forceRefresh.toggle()
        } catch {
            print("Error saving pin state: \(error.localizedDescription)")
        }
    }
    
    private func deleteChat(_ record: ChatRecords) {
        DispatchQueue.main.async {
            modelContext.delete(record)
            do {
                try modelContext.save()
            } catch {
                print("Error deleting chat: \(error.localizedDescription)")
            }
        }
    }
    
    private func beginEditingRecord(_ record: ChatRecords) {
        editingRecord = record
        editingIcon   = record.icon ?? "bubble.left.circle"
        editingColor  = Color.from(name: record.color ?? ".hlBlue")
        editingTitle  = record.name ?? ""
        showIconSheet = true
    }

    @discardableResult
    private func createAuthorizedNewChatRecord() -> ChatRecords? {
        do {
            // Use the SAME original catalog order as ChatView's saved useModel index.
            // A ready native provider needs no remote API key; downloaded LOCAL models
            // still require their original provider to be enabled.
            let models = try modelContext.fetch(FetchDescriptor<AllModels>(
                sortBy: [SortDescriptor(\AllModels.position, order: .forward)]))
            guard let selectedIndex = HanlinDefaultChatPolicy.creationModelIndex(
                in: models, providers: apiKeys) else {
                validationAlertMessage = String(localized: "No chat model is ready. Enable a provider or make an on-device model available in Settings.")
                validationSettingType = .apiKeys
                showValidationAlert = true
                return nil
            }

            // Optimization remains optional; its own actions validate their model.
            let currentLanguage = Locale.preferredLanguages.first ?? "zh-Hans"
            let chatName = currentLanguage.hasPrefix("zh") ? "新群聊" : "New Group Chat"
            let welcomeText = currentLanguage.hasPrefix("zh")
                ? "欢迎加入新群聊👏" : "Welcome to the new group chat! 👏"
            let newChat = ChatRecords(name: chatName, type: "chat", lastEdited: Date(),
                                      useModel: selectedIndex)
            let welcomeMessage = ChatMessages(role: "information", text: welcomeText,
                reasoning: "", modelDisplayName: "System", timestamp: Date(), record: newChat)
            modelContext.insert(newChat)
            modelContext.insert(welcomeMessage)
            try modelContext.save()
            return newChat
        } catch {
            print("Error saving new chat: \(error.localizedDescription)")
            return nil
        }
    }

    private func addNewChat() {
        guard let newChat = createAuthorizedNewChatRecord() else { return }
        DispatchQueue.main.async {
            if !useCompactWorkspace {
                selectedChatRecord = newChat
            } else if let id = newChat.id {
                compactWorkspacePath.append(.chat(id))
            }
        }
    }
}
