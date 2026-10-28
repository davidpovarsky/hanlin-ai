//
//  ChatViewBottom.swift
//  AI_HLY
//
//  Created by Codex on 3/7/25.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit


struct InputTextField: UIViewRepresentable {

    // MARK: – Public API
    @Binding var text: String
    var placeholder: String = String(localized: "Message")
    var onPasteImage: ((UIImage) -> Void)?
    var onPasteText: ((String) -> Void)?
    var onPasteFile: ((URL) -> Void)?
    var onSendMessage: (() -> Void)?
    @ScaledMetric(relativeTo: .body) private var fontSize: CGFloat = 16

    // 用于检测 @mention，便于整块删除；若也不需要，可连同相关代码一起删
    private static let mentionRegex =
        try! NSRegularExpression(pattern: "@[^\\s]+", options: [])

    // MARK: – 内部 UITextField
    final class InnerTextField: UITextField {

        var onPasteText: ((String) -> Void)?
        var onPasteImage: ((UIImage) -> Void)?
        var onPasteFile: ((URL) -> Void)?

        override func paste(_ sender: Any?) {
            let pasteboard = UIPasteboard.general
            
            // 图片优先
            if let img = pasteboard.image {
                onPasteImage?(img)
                return
            }
            
            // 粘贴文件 URL
            if let fileURL = pasteboard.url {
                onPasteFile?(fileURL)
                return
            }
            
            if pasteboard.hasStrings {
                super.paste(sender)
                return
            }
            
            // 粘贴文件
            let extMapping: [String: String] = [
                UTType.pdf.identifier: "pdf",
                UTType.commaSeparatedText.identifier: "csv",
                UTType.pythonScript.identifier: "py",
                UTType.plainText.identifier: "txt",
                UTType.json.identifier: "json",
                UTType.log.identifier: "log",
                UTType.html.identifier: "html",
                UTType(filenameExtension: "docx")?.identifier ?? "org.openxmlformats.wordprocessingml.document": "docx",
                UTType(filenameExtension: "xlsx")?.identifier ?? "org.openxmlformats.spreadsheetml.sheet": "xlsx",
                UTType(filenameExtension: "pptx")?.identifier ?? "org.openxmlformats.presentationml.presentation": "pptx",
                UTType(filenameExtension: "md")?.identifier ?? "net.daringfireball.markdown": "md"
            ]
            
            for item in pasteboard.items {
                for (uti, value) in item {
                    guard let data = value as? Data,
                          let ext = extMapping[uti] else { continue }
                    
                    let tmpURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("\(UUID().uuidString).\(ext)")
                    do {
                        try data.write(to: tmpURL)
                        DispatchQueue.main.async {
                            self.onPasteFile?(tmpURL)
                        }
                    } catch {
                        print("写入临时文件失败：\(error)")
                    }
                    return
                }
            }
            
            // 回退到默认粘贴
            super.paste(sender)
        }

        override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
            if action == #selector(paste(_:)) {
                return true
            }
            return super.canPerformAction(action, withSender: sender)
        }

        override var intrinsicContentSize: CGSize {
            let s = super.intrinsicContentSize
            return .init(width: UIView.noIntrinsicMetric,
                         height: max(40, s.height))
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            returnKeyType = .send
        }

        required init?(coder: NSCoder) {
            fatalError("InputTextField 不支持 XIB/Storyboard")
        }
    }

    // MARK: – Coordinator
    final class Coordinator: NSObject, UITextFieldDelegate {

        let parent: InputTextField
        var lastSynced = ""

        init(parent: InputTextField) { self.parent = parent }

        // 删除时整块移除 @xxx
        func textField(_ tf: UITextField,
                       shouldChangeCharactersIn range: NSRange,
                       replacementString str: String) -> Bool {

            guard str.isEmpty else { return true }     // 仅处理删除

            let raw = tf.text ?? ""
            let ns  = raw as NSString
            if let m = Self.matchContaining(index: range.location, in: raw) {
                tf.text      = ns.replacingCharacters(in: m.range, with: "")
                parent.text  = tf.text ?? ""
                lastSynced   = parent.text
                // 让系统自行维护光标，不做额外处理
                return false
            }
            return true
        }

        // 普通输入同步到 @Binding
        func textFieldDidChangeSelection(_ tf: UITextField) {
            guard tf.markedTextRange == nil else { return } // 拼音阶段忽略
            let cur = tf.text ?? ""
            if cur != lastSynced {
                DispatchQueue.main.async {
                    self.parent.text = cur
                    self.lastSynced = cur
                }
            }
        }

        func textFieldShouldReturn(_ tf: UITextField) -> Bool {
            parent.onSendMessage?()
            return true
        }

        // MARK: – Utils
        private static func matchContaining(index: Int,
                                            in text: String) -> NSTextCheckingResult? {
            let ns   = text as NSString
            let full = NSRange(location: 0, length: ns.length)
            return InputTextField.mentionRegex
                .matches(in: text, options: [], range: full)
                .first { NSLocationInRange(index, $0.range) }
        }
    }

    // MARK: – UIViewRepresentable
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> InnerTextField {
        let tf = InnerTextField()
        tf.delegate        = context.coordinator
        tf.onPasteImage    = onPasteImage
        tf.onPasteFile     = onPasteFile
        tf.placeholder     = placeholder
        tf.font            = .systemFont(ofSize: fontSize)
        tf.borderStyle     = .none
        tf.setContentHuggingPriority(.required, for: .horizontal)
        tf.setContentCompressionResistancePriority(.required, for: .horizontal)
        return tf
    }

    func updateUIView(_ uiView: InnerTextField, context: Context) {
        // 拼音候选阶段不更新
        guard uiView.markedTextRange == nil else {
            uiView.placeholder = placeholder
            return
        }

        // 外部 Binding 更新：仅简单同步，不再做光标位置计算
        if uiView.text != text {
            uiView.text = text
            context.coordinator.lastSynced = text
        }
        uiView.placeholder = placeholder
    }
}


struct ChatViewBottom: View {
    var chatRecord: ChatRecords
    let modelTemp: [AllModels]
    let TemporaryRecord: Bool
    let respondIndex: Int
    let onSelectModel: (Int) -> Void
    let onSendUser: () -> Void
    let onSendObserve: () -> Void
    let onCancel: () -> Void

    @Binding var selectedModelIndex: Int
    @Binding var showScrollToBottomButton: Bool
    @Binding var needScrollToBottomButton: Bool
    @Binding var isMultiSelectMode: Bool
    @Binding var selectedMessageIDs: Set<UUID>
    @Binding var chatTemps: [ChatMessages]

    @Binding var showTemperatureSlider: Bool
    @Binding var temperature: Double
    @Binding var showTopPSlider: Bool
    @Binding var topP: Double
    @Binding var showMaxTokensSlider: Bool
    @Binding var maxTokens: Int
    @Binding var showMaxMessagesNumSlider: Bool
    @Binding var maxMessagesNum: Int

    @Binding var message: String
    @Binding var selectedImages: [UIImage]
    @Binding var selectedDocumentURLs: [URL]
    @Binding var selectedURLs: [String]
    @Binding var selectedPrompts: [PromptRepo]
    @Binding var showPhotoSourceOptions: Bool

    @Binding var showModelSuggestions: Bool
    @Binding var filteredModels: [AllModels]

    @Binding var isResponding: Bool
    @Binding var isFeedBack: Bool

    @Binding var ifKnowledge: Bool
    @Binding var ifSearch: Bool
    @Binding var ifToolUse: Bool
    @Binding var ifThink: Bool
    @Binding var ifAudio: Bool
    @Binding var ifPlanning: Bool
    @Binding var thinkingLength: Int

    @Binding var showKnowledgeAlert: Bool
    @Binding var knowledgeAlertMessage: String
    @Binding var showSearchAlert: Bool

    @Binding var selectedImageSize: String
    @Binding var imageReversePrompt: String

    var isInputActive: FocusState<Bool>.Binding

    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\PromptRepo.position, order: .forward)]) private var promptTemps: [PromptRepo]
    @Query private var userInfos: [UserInfo]

    @State private var isViewLoaded = false
    @State private var showCanvas = false
    @State private var inputExpanded = false
    @State private var showModelMenuSheet = false
    @State private var voiceExpanded = false
    @State private var showImagePicker = false
    @State private var showCameraPicker = false
    @State private var showDocumentPicker = false
    @State private var isSourceOptionsVisible = false
    @State private var debounceWorkItem: DispatchWorkItem?
    @State private var selectedViewImage: UIImage?
    @State private var isImageViewerPresented: Bool = false
    @State private var isSelect = false
    @State private var textEditorHeight: CGFloat = 38
    @State private var popupCoordinator = HanlinComposerPopupCoordinator()
    @State private var selectedMCPCountForChat: Int = 0
    @State private var showEmbeddingSettingSheet: Bool = false
    @State private var isEmbeddingModelError: Bool = false

    static func shouldEnableSend(
        message: String,
        selectedImagesCount: Int,
        selectedDocumentsCount: Int,
        selectedPromptsCount: Int,
        isResponding: Bool = false
    ) -> Bool {
        guard !isResponding else { return false }
        let hasText = !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasText || selectedImagesCount > 0 || selectedDocumentsCount > 0 || selectedPromptsCount > 0
    }

    @ScaledMetric(relativeTo: .body) var size_16: CGFloat = 16
    @ScaledMetric(relativeTo: .body) var size_20: CGFloat = 20
    @ScaledMetric(relativeTo: .body) var size_32: CGFloat = 32
    @ScaledMetric(relativeTo: .body) var size_30: CGFloat = 30
    @ScaledMetric(relativeTo: .body) var size_40: CGFloat = 40
    @ScaledMetric(relativeTo: .body) var size_44: CGFloat = 44
    @ScaledMetric(relativeTo: .body) var size_80: CGFloat = 80

    let buttonHeight: CGFloat = 36

    var body: some View {
        VStack {
            // 只有在需要时才显示“画布”和“滚动到底部”按钮
            if (showScrollToBottomButton
                || (chatRecord.canvas?.content.isEmpty == false))  && isMultiSelectMode == false
            {
                HStack(spacing: 12) {
                    Spacer()

                    if chatRecord.canvas?.content.isEmpty == false && selectedModelIndex >= 0 {
                        Button(action: { showCanvas.toggle() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "pencil.and.outline")
                                    .font(.system(size: size_16, weight: .medium))
                                Text("画布 \(chatRecord.canvas?.title ?? "")")
                                    .font(.system(size: size_16, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .foregroundColor(TemporaryRecord ? .primary : .hlBluefont)
                            .frame(height: buttonHeight)
                            .padding(.horizontal, 10)
                            .clipShape(Capsule())
                            .background(
                                GlassView(style: .systemUltraThinMaterial)
                                    .clipShape(Capsule())
                                    .shadow(color: TemporaryRecord ? .primary : .hlBlue, radius: 1)
                            )
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(
                            .spring(response: 0.5, dampingFraction: 0.7),
                            value: chatRecord.canvas?.content.isEmpty == false
                        )
                        .sheet(isPresented: $showCanvas) {
                            AICanvasView(
                                canvas: Binding(
                                    get: { chatRecord.canvas ?? CanvasData() },
                                    set: {
                                        chatRecord.canvas = $0
                                        try? context.save()
                                    }
                                ),
                                model: modelTemp[selectedModelIndex]
                            )
                        }
                    }

                    if showScrollToBottomButton {
                        Button(action: { needScrollToBottomButton.toggle() }) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: size_16, weight: .medium))
                                .foregroundColor(TemporaryRecord ? .primary : .hlBluefont)
                                .frame(width: buttonHeight, height: buttonHeight)
                                .clipShape(Circle())
                                .background(
                                    GlassView(style: .systemUltraThinMaterial)
                                        .clipShape(Circle())
                                        .shadow(color: TemporaryRecord ? .primary : .hlBlue, radius: 1)
                                )
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.spring(response: 0.5, dampingFraction: 0.7),
                                   value: showScrollToBottomButton)
                    }
                }
                .offset(y: isViewLoaded ? 0 : 60) // 初次进入时滑入
                .opacity(isViewLoaded ? 1 : 0)    // 初次进入时淡入
                .animation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0.4), value: isViewLoaded)
                .padding(.horizontal, 15)
            }

            // 多选模式工具栏 + 底部输入面板
            buildMultiSelectAndInputControls()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { // **延迟 0.3 秒触发动画**
                withAnimation {
                    isViewLoaded = true
                }
            }
        }
        .onChange(of: isMultiSelectMode) {
            isViewLoaded = !isMultiSelectMode
        }
        .onChange(of: showPhotoSourceOptions) { _, newValue in
            if newValue && popupCoordinator.activePopup != .general {
                popupCoordinator.open(.general, isInputCurrentlyFocused: isInputActive.wrappedValue)
            } else if !newValue && popupCoordinator.activePopup == .general {
                popupCoordinator.closeAll()
            }
            isSourceOptionsVisible = newValue
        }
        .onChange(of: popupCoordinator.activePopup) { _, newPopup in
            let isGeneral = (newPopup == .general)
            if showPhotoSourceOptions != isGeneral {
                showPhotoSourceOptions = isGeneral
            }
            isSourceOptionsVisible = isGeneral
        }
        .task(id: chatRecord.id) {
            let selection = await MCPRuntimeProvider.shared.selection(
                chatID: chatRecord.id,
                temporary: TemporaryRecord
            )
            selectedMCPCountForChat = selection.count
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: ComposerHeightPreferenceKey.self, value: proxy.size.height)
            }
        )
    }

    /// 底部动画触发状态集合
    private struct BottomAnimationState: Equatable {
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

    private var bottomAnimationState: BottomAnimationState {
        let model = modelTemp.indices.contains(selectedModelIndex) ? modelTemp[selectedModelIndex] : nil

        return BottomAnimationState(
            lastID: chatTemps.last?.id,
            ifSearch: ifSearch,
            ifKnowledge: ifKnowledge,
            selectedURLsIsEmpty: selectedURLs.isEmpty,
            selectedPromptsCount: selectedPrompts.count,
            selectedImagesIsEmpty: selectedImages.isEmpty,
            selectedDocumentString: selectedDocumentURLs.isEmpty,
            showPhotoSourceOptions: showPhotoSourceOptions,
            isInputActive: isInputActive.wrappedValue,
            showModelSuggestions: showModelSuggestions,
            showVisualSuggestion: model.map { !$0.supportsMultimodal && $0.company != "LOCAL" } ?? false,
            showImageSize: model?.supportsImageGen == true
        )
    }

    // MARK: - 多选模式工具栏 + 底部控制面板
    private func buildMultiSelectAndInputControls() -> some View {
        ZStack(alignment: .bottom) {
            HStack {
                Button(action: {
                    // 遍历 selectedMessageIDs 删除对应消息
                    for id in selectedMessageIDs {
                        if let index = chatTemps.firstIndex(where: { $0.id == id }) {
                            let msg = chatTemps[index]
                            context.delete(msg)
                            chatTemps.remove(at: index)
                        }
                    }
                    do {
                        try context.save()
                    } catch {
                        print("删除多选消息失败: \(error)")
                    }
                    // 清空选中记录并退出多选模式
                    selectedMessageIDs.removeAll()
                    isMultiSelectMode = false
                    isViewLoaded = true
                }) {
                    Image(systemName: "trash.circle.fill")
                        .resizable()
                        .frame(width: size_40, height: size_40)
                        .foregroundColor(selectedMessageIDs.isEmpty ? .gray : .hlRed)
                        .cornerRadius(20)
                }
                .disabled(selectedMessageIDs.isEmpty)

                Spacer()

                Button(action: {
                    isMultiSelectMode = false
                    isViewLoaded = true
                }) {
                    Image(systemName: "checkmark.circle.fill")
                        .resizable()
                        .frame(width: size_40, height: size_40)
                        .foregroundColor(TemporaryRecord ? .primary : .hlBluefont)
                        .cornerRadius(20)
                }
            }
            .padding(12)
            .background(
                GlassView(style: .systemUltraThinMaterial) // 毛玻璃背景
                    .clipShape(RoundedRectangle(cornerRadius: 26))
                    .shadow(color: TemporaryRecord ? .primary : .hlBlue, radius: 1)
            )
            .offset(y: isMultiSelectMode ? 0 : 60) // **初次进入时滑入**
            .opacity(isMultiSelectMode ? 1 : 0)    // **初次进入时淡入**
            .animation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0.4), value: isMultiSelectMode)
            .padding(.vertical, 3)
            .padding(.horizontal, 15)

            VStack {
                VStack {
                    if showTemperatureSlider {
                        TemperaturePicker(value: $temperature)
                            .onChange(of: temperature) {
                                chatRecord.temperature = temperature
                                do {
                                    try context.save()
                                } catch {
                                    print("保存 temperature 失败：\(error.localizedDescription)")
                                }
                            }
                    }
                    if showTopPSlider {
                        TopPPicker(value: $topP)
                            .onChange(of: topP) {
                                chatRecord.topP = topP
                                do {
                                    try context.save()
                                } catch {
                                    print("保存 temperature 失败：\(error.localizedDescription)")
                                }
                            }
                    }
                    if showMaxTokensSlider {
                        MaxTokensPicker(value: $maxTokens)
                            .onChange(of: maxTokens) {
                                chatRecord.maxTokens = maxTokens
                                do {
                                    try context.save()
                                } catch {
                                    print("保存 maxTokens 失败：\(error.localizedDescription)")
                                }
                            }
                    }
                    if showMaxMessagesNumSlider {
                        MaxMessagesNumPicker(value: $maxMessagesNum)
                            .onChange(of: maxMessagesNum) {
                                chatRecord.maxMessagesNum = maxMessagesNum
                                do {
                                    try context.save()
                                } catch {
                                    print("保存 maxMessagesNum 失败：\(error.localizedDescription)")
                                }
                            }
                    }
                }
                .transition(.move(edge: .top))

                VStack {
                    messageInput
                }
                .padding(.bottom, 10)
                .onTapGesture {
                    showTemperatureSlider = false
                    showTopPSlider = false
                    showMaxTokensSlider = false
                    showMaxMessagesNumSlider = false
                }
                .background(
                    GlassView(style: .systemUltraThinMaterial) // 毛玻璃背景
                        .clipShape(RoundedRectangle(cornerRadius: 26))
                        .overlay(
                            RoundedRectangle(cornerRadius: 26)
                                .stroke((TemporaryRecord ? Color.primary : Color.hlBluefont).opacity(0.22), lineWidth: 0.8)
                        )
                        .shadow(color: TemporaryRecord ? .primary : .hlBlue, radius: 1)
                )
                .offset(y: isViewLoaded ? 0 : 60) // 初次进入时滑入
                .opacity(isViewLoaded ? 1 : 0)    // 初次进入时淡入
                .animation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0.4), value: isViewLoaded)
                .animation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0.4), value: bottomAnimationState)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 15)
        }
    }

    // MARK: 输入区域
    private var messageInput: some View {
        VStack(spacing: 6) {
            imagePreviewSection
            documentPreviewSection
            linkPreviewSection
            promptSection
            modelSuggestionSection
            activeModeChipsSection
            inputFieldSection
        }
    }

    private var currentModelSnapshot: HanlinComposerActionBridge.ModelCapabilitySnapshot {
        let model = modelTemp.indices.contains(selectedModelIndex) ? modelTemp[selectedModelIndex] : nil
        return HanlinComposerActionBridge.capabilitySnapshot(for: model)
    }

    private var activeChips: [HanlinComposerActiveChip] {
        HanlinComposerActionBridge.activeModeChips(
            capability: currentModelSnapshot,
            ifSearch: ifSearch,
            ifKnowledge: ifKnowledge,
            ifThink: ifThink,
            thinkingLength: thinkingLength,
            ifPlanning: ifPlanning,
            ifAudio: ifAudio,
            ifToolUse: ifToolUse,
            activeMCPServerCount: selectedMCPCountForChat,
            selectedImageSize: selectedImageSize
        )
    }

    @ViewBuilder
    private var activeModeChipsSection: some View {
        let chips = activeChips
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(chips) { chip in
                        Button {
                            isFeedBack.toggle()
                            handleActiveChipTap(chip)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: chip.systemImage)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(chip.title)
                                    .font(.caption2.weight(.medium))
                                    .lineLimit(1)
                                if chip.isRemovable {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .opacity(0.75)
                                }
                            }
                            .foregroundStyle(TemporaryRecord ? .primary : .hlBluefont)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                (TemporaryRecord ? Color.primary : Color.hlBlue).opacity(0.12),
                                in: Capsule()
                            )
                            .overlay(
                                Capsule()
                                    .stroke((TemporaryRecord ? Color.primary : Color.hlBluefont).opacity(0.22), lineWidth: 0.6)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("hanlin-composer-chip-\(chip.id)")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
            .accessibilityIdentifier("hanlin-composer-active-chips")
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private func handleActiveChipTap(_ chip: HanlinComposerActiveChip) {
        switch chip.kind {
        case .search:
            ifSearch = false
        case .knowledge:
            ifKnowledge = false
        case .thinking:
            if currentModelSnapshot.supportReasoningChange {
                ifThink = false
            } else {
                popupCoordinator.open(.general, isInputCurrentlyFocused: isInputActive.wrappedValue)
            }
        case .planning:
            ifPlanning = false
        case .audio:
            ifAudio = false
        case .tools:
            ifToolUse = false
        case .mcp:
            popupCoordinator.presentDirectTools(isInputCurrentlyFocused: isInputActive.wrappedValue)
        case .imageGen:
            popupCoordinator.open(.general, isInputCurrentlyFocused: isInputActive.wrappedValue)
        case .localModel:
            popupCoordinator.open(.general, isInputCurrentlyFocused: isInputActive.wrappedValue)
        }
    }

    // MARK: - 图片预览区域
    private var imagePreviewSection: some View {
        Group {
            if !selectedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(selectedImages.indices, id: \.self) { index in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: selectedImages[index])
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: size_80, height: size_80)
                                    .clipShape(RoundedRectangle(cornerRadius: 15))
                                    .onTapGesture {
                                        selectedViewImage = selectedImages[index] // 记录当前选中的图片
                                        isImageViewerPresented = true // 触发大图预览
                                    }
                                Button(action: {
                                    isFeedBack.toggle()
                                    selectedImages.remove(at: index)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(Color(.hlRed))
                                        .background(.background)
                                        .clipShape(Circle())
                                }
                                .accessibilityIdentifier("hanlin-remove-image-attachment")
                                .sensoryFeedback(.impact, trigger: isFeedBack)
                            }
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("hanlin-composer-image-attachment")
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                        ZStack(alignment: .center) {
                            Menu {
                                Button(action: {
                                    isFeedBack.toggle()
                                    showPhotoSourceOptions = true
                                    showCameraPicker = true
                                }) {
                                    Label("拍摄照片", systemImage: "camera")
                                }
                                Button(action: {
                                    isFeedBack.toggle()
                                    showPhotoSourceOptions = true
                                    showImagePicker = true
                                }) {
                                    Label("相册选择", systemImage: "photo")
                                }
                            } label: {
                                VStack {
                                    Image(systemName: "plus.circle")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 30, height: 30)
                                        .foregroundColor(TemporaryRecord ? .primary : .hlBluefont)
                                        .symbolEffect(.bounce, value: showImagePicker)
                                }
                                .padding(12)
                                .frame(width: size_80, height: size_80)
                                .background(TemporaryRecord ? Color.primary.opacity(0.1) : Color.hlBlue.opacity(0.1))
                                .cornerRadius(size_20)
                            }
                            .sensoryFeedback(.impact, trigger: isFeedBack)
                        }
                    }
                    .padding(6)
                    .sheet(isPresented: $isImageViewerPresented) { // 全屏预览大图
                        if let images = selectedViewImage {
                            ImageViewer(image: images, isPresented: $isImageViewerPresented)
                        }
                    }
                }
                .background(.background.opacity(0.6))
                .cornerRadius(20)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    // MARK: - 文件预览区域
    private var documentPreviewSection: some View {
        Group {
            if !selectedDocumentURLs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(selectedDocumentURLs, id: \.self) { document in
                            HStack {
                                Image(systemName: "doc.text")
                                    .foregroundColor(TemporaryRecord ? .primary : Color(.hlBluefont))
                                    .font(.footnote)
                                Text(document.lastPathComponent)
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Button(action: {
                                    isFeedBack.toggle()
                                    if let index = selectedDocumentURLs.firstIndex(of: document) {
                                        selectedDocumentURLs.remove(at: index)
                                    }
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(Color(.hlRed))
                                }
                                .accessibilityIdentifier("hanlin-remove-document-attachment")
                                .sensoryFeedback(.impact, trigger: isFeedBack)
                            }
                            .padding(6)
                            .background(.background.opacity(0.6))
                            .cornerRadius(20)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("hanlin-composer-document-attachment")
                        }
                    }
                }
                .cornerRadius(20)
                .padding(.top, 12)
                .padding(.horizontal, 12)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    // MARK: - 链接预览区域
    private var linkPreviewSection: some View {
        Group {
            if !selectedURLs.isEmpty, modelTemp[selectedModelIndex].company != "LOCAL" {
                HStack {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(selectedURLs, id: \.self) { url in
                                HStack {
                                    Image(systemName: "link")
                                        .foregroundColor(TemporaryRecord ? .primary : .hlBluefont)
                                        .font(.footnote)
                                    Text(url)
                                        .font(.footnote)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Button(action: {
                                        isFeedBack.toggle()
                                        if let range = message.range(of: url) {
                                            message.removeSubrange(range) // 从 message 中删除 URL
                                        }
                                        selectedURLs.removeAll { $0 == url } // 从解析出的链接中删除
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(Color(.hlRed))
                                    }
                                    .sensoryFeedback(.impact, trigger: isFeedBack)
                                }
                                .padding(6)
                                .background(.background.opacity(0.6))
                                .cornerRadius(20)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                        }
                    }
                    .cornerRadius(20)
                }
                .padding(.top, 12)
                .padding(.horizontal, 12)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    // MARK: - 提示词显示区域
    private var promptSection: some View {
        Group {
            if !selectedPrompts.isEmpty {
                HStack(spacing: 6) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(selectedPrompts, id: \.id) { item in
                                HStack(spacing: 6) {
                                    // 使用自定义图片作为提示词图标
                                    Image("prompt")
                                        .renderingMode(.template)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 20, height: 20)
                                        .foregroundColor(TemporaryRecord ? .primary : .hlBluefont)
                                    Text(item.name ?? "未命名提示词")
                                        .font(.body)
                                        .foregroundColor(TemporaryRecord ? .primary : .hlBluefont)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    Button(action: {
                                        isFeedBack.toggle()
                                        message.append(item.content ?? "")
                                        removePrompt(item)
                                    }) {
                                        Image(systemName: "pencil.circle.fill")
                                            .foregroundColor(Color(.hlGreen))
                                    }
                                    .sensoryFeedback(.impact, trigger: isFeedBack)
                                    Button(action: {
                                        isFeedBack.toggle()
                                        removePrompt(item)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(Color(.hlRed))
                                    }
                                    .sensoryFeedback(.impact, trigger: isFeedBack)
                                }
                                .padding(12)
                                .background(TemporaryRecord ? Color.primary.opacity(0.1) : Color.hlBlue.opacity(0.1))
                                .cornerRadius(20)
                            }
                        }
                    }
                    .cornerRadius(20)
                }
                .padding(.top, 12)
                .padding(.horizontal, 12)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    // MARK: - 模型建议区域
    private var modelSuggestionSection: some View {
        Group {
            if showModelSuggestions && !filteredModels.isEmpty {
                HStack {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(filteredModels, id: \.id) { model in
                                Button(action: {
                                    // 用正则表达式匹配最后一次出现的"@…"
                                    if let range = message.range(of: "@[^\\s]*$", options: .regularExpression) {
                                        message.replaceSubrange(range, with: "@\(model.displayName ?? model.name ?? "未知") ")
                                    }
                                    showModelSuggestions = false
                                    isFeedBack.toggle()
                                }) {
                                    Image(systemName: "at")
                                        .foregroundColor(TemporaryRecord ? .primary : .hlBluefont)
                                        .font(.footnote)
                                    highlightedModelText(for: model.displayName ?? model.name ?? "未知")
                                        .font(.footnote)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                .sensoryFeedback(.impact, trigger: isFeedBack)
                                .padding(6)
                                .background(.background.opacity(0.6))
                                .cornerRadius(20)
                            }
                        }
                    }
                    .cornerRadius(20)
                }
                .padding(.top, 12)
                .padding(.horizontal, 12)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    // MARK: - 输入栏及底部按钮区域
    private var inputFieldSection: some View {
        HStack {
            VStack(spacing: 6) {
                HStack(alignment: .bottom, spacing: 6) {
                    NativeMultilineTextEditor(
                        text: $message,
                        textHeight: $textEditorHeight,
                        placeholderText: String(localized: "Message"),
                        minHeight: 38,
                        maxHeight: 140,
                        onPasteImage: { pastedImage in
                            selectedImages.append(pastedImage)
                        },
                        onPasteFile: { pastedFile in
                            selectedDocumentURLs.append(pastedFile)
                        },
                        onSendMessage: {
                            if Self.shouldEnableSend(
                                message: message,
                                selectedImagesCount: selectedImages.count,
                                selectedDocumentsCount: selectedDocumentURLs.count,
                                selectedPromptsCount: selectedPrompts.count,
                                isResponding: isResponding
                            ) {
                                onSendUser()
                            }
                        },
                        onMentionTriggered: {
                            updateModelSuggestions()
                        }
                    )
                    .padding(.leading, 12)
                    .frame(height: max(size_44, textEditorHeight))
                    .focused(isInputActive)
                    .accessibilityIdentifier("hanlin-chat-input")
                    .onChange(of: message) {
                        debounceWorkItem?.cancel()
                        debounceWorkItem = DispatchWorkItem {
                            updateModelSuggestions()
                            chatRecord.input = message
                            extractURLs(from: message)
                            do {
                                try context.save()
                            } catch {
                                print("Failed to save chat record updates: \(error)")
                            }
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: debounceWorkItem!)
                    }
                    .disabled(isResponding)

                    // 多行输入展开抽屉
                    Button(action: {
                        isFeedBack.toggle()
                        inputExpanded.toggle()
                    }) {
                        Image(systemName: inputExpanded ? "chevron.down" : "chevron.up")
                            .foregroundColor(Color(.systemGray))
                            .padding(.trailing, 12)
                            .padding(.bottom, 10)
                            .symbolEffect(.bounce, value: inputExpanded)
                    }
                    .accessibilityIdentifier("hanlin-composer-expand-editor")
                    .sensoryFeedback(.impact, trigger: isFeedBack)
                    .disabled(isResponding)
                }

                composerBottomToolbar
            }
            .background(.background.opacity(0.6))
            .cornerRadius(20)
            .animation(.spring(response: 0.45, dampingFraction: 0.78), value: popupCoordinator.activePopup)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .sheet(isPresented: $inputExpanded) {
            BottomSheetView(message: $message, isExpanded: $inputExpanded)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $voiceExpanded) {
            VoiceInputView(message: $message, voiceExpanded: $voiceExpanded)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCameraPicker, onDismiss: {
            showPhotoSourceOptions = false
        }) {
            ImagePicker(selectedImages: $selectedImages, sourceType: .camera, maxImageNumber: 5)
                .background(.black)
        }
        .sheet(isPresented: $showImagePicker, onDismiss: {
            showPhotoSourceOptions = false
        }) {
            ImagePicker(selectedImages: $selectedImages, sourceType: .photoLibrary, maxImageNumber: 5)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showDocumentPicker, onDismiss: {
            showPhotoSourceOptions = false
        }) {
            DocumentPicker(selectedDocumentURLs: $selectedDocumentURLs)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showEmbeddingSettingSheet) {
            NavigationStack {
                SelectEmbeddingModelView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("完成") {
                                showEmbeddingSettingSheet = false
                            }
                        }
                    }
            }
        }
        .alert("知识背包错误", isPresented: $showKnowledgeAlert) {
            if isEmbeddingModelError {
                Button("前往设置") {
                    showEmbeddingSettingSheet = true
                }
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text(knowledgeAlertMessage)
        }
        .alert("未启用搜索引擎", isPresented: $showSearchAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text("当前未启用任何搜索引擎，请前往 设置-工具-搜索设置 中开启。")
        }
    }

    // MARK: - 双入口底部控制栏（+ 通用菜单 / 工具直达 / 紧凑模型胶囊 / 麦克风 / 发送）
    private var composerBottomToolbar: some View {
        let accent: Color = TemporaryRecord ? .primary : .hlBluefont
        let isGeneralOpen = popupCoordinator.activePopup == .general
        let isToolsOpen = popupCoordinator.activePopup == .tools
        let isModelOpen = popupCoordinator.activePopup == .model
        let toolsActiveBadgeCount = HanlinComposerActionBridge.activeToolsShortcutCount(
            capability: currentModelSnapshot,
            ifToolUse: ifToolUse,
            activeMCPServerCount: selectedMCPCountForChat
        )

        return HStack(spacing: 8) {
            // Entrypoint 1: General `+` button
            Button {
                isFeedBack.toggle()
                popupCoordinator.toggle(.general, isInputCurrentlyFocused: isInputActive.wrappedValue)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: size_20 + 6, weight: .medium))
                    .foregroundStyle(
                        isResponding
                        ? Color.gray
                        : (isGeneralOpen ? Color.hlRed : accent)
                    )
                    .rotationEffect(.degrees(isGeneralOpen ? 45 : 0))
                    .frame(width: size_32, height: size_32)
                    .animation(.spring(response: 0.35, dampingFraction: 0.78), value: isGeneralOpen)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("hanlin-composer-general-menu")
            .disabled(isResponding)
            .sensoryFeedback(.impact, trigger: isFeedBack)
            .popover(
                isPresented: popupCoordinator.binding(for: .general),
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .bottom
            ) {
                HanlinComposerGeneralActionsView(
                    coordinator: popupCoordinator,
                    capability: currentModelSnapshot,
                    TemporaryRecord: TemporaryRecord,
                    isResponding: isResponding,
                    selectedImagesCount: selectedImages.count,
                    selectedDocumentsCount: selectedDocumentURLs.count,
                    ifSearch: $ifSearch,
                    ifKnowledge: $ifKnowledge,
                    ifThink: $ifThink,
                    thinkingLength: $thinkingLength,
                    ifPlanning: $ifPlanning,
                    ifAudio: $ifAudio,
                    selectedImageSize: $selectedImageSize,
                    imageReversePrompt: $imageReversePrompt,
                    temperature: $temperature,
                    topP: $topP,
                    maxTokens: $maxTokens,
                    maxMessagesNum: $maxMessagesNum,
                    availablePrompts: filteredPromptTemps,
                    selectedPrompts: $selectedPrompts,
                    canObserve: canObserveCurrentChat,
                    onSelectCamera: { showCameraPicker = true },
                    onSelectPhotos: { showImagePicker = true },
                    onSelectDocument: { showDocumentPicker = true },
                    onAttachSampleImage: { attachSampleImageForAcceptance() },
                    onAttachSampleDocument: { attachSampleDocumentForAcceptance() },
                    onCheckSearchAvailability: { checkSearchAvailability() },
                    onShowSearchAlert: { showSearchAlert = true },
                    onCheckKnowledgeAvailability: { checkEmbeddingAvailability() },
                    onShowKnowledgeAlert: { showKnowledgeAlert = true },
                    onOpenLongTextEditor: { inputExpanded = true },
                    onTriggerObserve: { onSendObserve() },
                    onSwitchToToolsPopup: {
                        popupCoordinator.presentDirectTools(isInputCurrentlyFocused: isInputActive.wrappedValue)
                    },
                    onSaveParameterChanges: {
                        chatRecord.temperature = temperature
                        chatRecord.topP = topP
                        chatRecord.maxTokens = maxTokens
                        chatRecord.maxMessagesNum = maxMessagesNum
                        try? context.save()
                    }
                )
                .presentationCompactAdaptation(.popover)
            }

            // Entrypoint 2: Direct 1-Tap Tools / Skills / MCP button
            Button {
                isFeedBack.toggle()
                popupCoordinator.toggle(.tools, isInputCurrentlyFocused: isInputActive.wrappedValue)
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: (ifToolUse && currentModelSnapshot.supportsToolUse) ? "wrench.and.screwdriver.fill" : "wrench.and.screwdriver")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(
                            isResponding
                            ? Color.gray
                            : ((isToolsOpen || (ifToolUse && currentModelSnapshot.supportsToolUse)) ? accent : Color.secondary)
                        )
                        .frame(width: size_32, height: size_32)
                        .background(
                            (isToolsOpen || (ifToolUse && currentModelSnapshot.supportsToolUse))
                            ? (TemporaryRecord ? Color.primary : Color.hlBlue).opacity(0.14)
                            : Color.secondary.opacity(0.08),
                            in: Circle()
                        )
                        .overlay(
                            Circle()
                                .stroke(
                                    (isToolsOpen || (ifToolUse && currentModelSnapshot.supportsToolUse))
                                    ? accent.opacity(0.32)
                                    : Color.clear,
                                    lineWidth: 0.8
                                )
                        )

                    if toolsActiveBadgeCount > 0 {
                        Circle()
                            .fill(accent)
                            .frame(width: 7, height: 7)
                            .offset(x: -1, y: 1)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("hanlin-composer-tools-direct")
            .disabled(isResponding)
            .sensoryFeedback(.impact, trigger: isFeedBack)
            .popover(
                isPresented: popupCoordinator.binding(for: .tools),
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .bottom
            ) {
                HanlinComposerToolsRootView(
                    coordinator: popupCoordinator,
                    capability: currentModelSnapshot,
                    TemporaryRecord: TemporaryRecord,
                    isResponding: isResponding,
                    chatID: chatRecord.id,
                    ifToolUse: $ifToolUse,
                    onMCPSelectionCountChanged: { count in
                        selectedMCPCountForChat = count
                    }
                )
                .presentationCompactAdaptation(.popover)
            }

            // Entrypoint 3: Compact Discoverable Model Picker Capsule
            Button {
                isFeedBack.toggle()
                popupCoordinator.toggle(.model, isInputCurrentlyFocused: isInputActive.wrappedValue)
            } label: {
                composerModelCapsuleLabel(isOpen: isModelOpen, accent: accent)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("hanlin-composer-model-picker")
            .sensoryFeedback(.selection, trigger: isSelect)
            .popover(
                isPresented: popupCoordinator.binding(for: .model),
                attachmentAnchor: .rect(.bounds),
                arrowEdge: .bottom
            ) {
                HanlinModelPickerPopover(
                    coordinator: popupCoordinator,
                    models: modelTemp,
                    selectedModelIndex: $selectedModelIndex,
                    onSelectModel: { index in
                        isSelect.toggle()
                        onSelectModel(index)
                    },
                    TemporaryRecord: TemporaryRecord,
                    ifToolUse: ifToolUse,
                    ifThink: ifThink,
                    ifAudio: ifAudio
                )
                .presentationCompactAdaptation(.popover)
            }

            Spacer(minLength: 4)

            // Permanent Microphone Action
            Button(action: {
                isFeedBack.toggle()
                voiceExpanded.toggle()
            }) {
                Image(systemName: "microphone")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isResponding ? Color.gray : Color(.systemGray))
                    .frame(width: size_30, height: size_30)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("hanlin-chat-mic")
            .sensoryFeedback(.impact, trigger: isFeedBack)
            .disabled(isResponding)

            // Contextual Primary Action: Stop / Send / Observe
            Group {
                if isResponding {
                    Button(action: onCancel) {
                        Image(systemName: "stop.circle.fill")
                            .resizable()
                            .frame(width: size_32, height: size_32)
                            .foregroundColor(.hlRed)
                            .symbolEffect(.breathe, isActive: true)
                    }
                    .accessibilityIdentifier("hanlin-chat-stop")
                    .animation(.spring(response: 0.4, dampingFraction: 0.78), value: isResponding)
                } else if !selectedImages.isEmpty
                            || !selectedDocumentURLs.isEmpty
                            || !selectedPrompts.isEmpty
                            || !message.isEmpty {
                    Button(action: onSendUser) {
                        Image(systemName: "arrowtriangle.up.circle.fill")
                            .resizable()
                            .frame(width: size_32, height: size_32)
                            .foregroundColor(sendButtonColor)
                    }
                    .accessibilityIdentifier("hanlin-chat-send")
                    .animation(.spring(response: 0.4, dampingFraction: 0.78), value: message)
                    .disabled(
                        !Self.shouldEnableSend(
                            message: message,
                            selectedImagesCount: selectedImages.count,
                            selectedDocumentsCount: selectedDocumentURLs.count,
                            selectedPromptsCount: selectedPrompts.count,
                            isResponding: isResponding
                        )
                    )
                } else {
                    Button(action: onSendObserve) {
                        Image(systemName: "eye.circle.fill")
                            .resizable()
                            .frame(width: size_32, height: size_32)
                            .foregroundColor(observeButtonColor)
                    }
                    .accessibilityIdentifier("hanlin-chat-observe")
                    .animation(.spring(response: 0.4, dampingFraction: 0.78), value: message)
                    .disabled(!canObserveCurrentChat)
                }
            }
            .sensoryFeedback(.impact, trigger: isFeedBack)
        }
        .frame(height: size_32)
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func composerModelCapsuleLabel(isOpen: Bool, accent: Color) -> some View {
        let model = modelTemp.indices.contains(selectedModelIndex) ? modelTemp[selectedModelIndex] : nil
        HStack(spacing: 5) {
            if let model {
                if model.identity == "model" {
                    Image(getCompanyIcon(for: model.company ?? "Unknown"))
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: model.icon ?? "circle.dotted.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 16, height: 16)
                }
                Text(model.displayName ?? model.name ?? "Model")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 132, alignment: .leading)
            } else {
                Image(systemName: "cpu")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(modelTemp.isEmpty ? "加载模型..." : "选择模型")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(accent.opacity(0.75))
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(
            (TemporaryRecord ? Color.primary : Color.hlBlue).opacity(isOpen ? 0.2 : 0.11),
            in: Capsule()
        )
        .overlay(
            Capsule()
                .stroke(accent.opacity(isOpen ? 0.45 : 0.22), lineWidth: 0.7)
        )
    }

    private var canObserveCurrentChat: Bool {
        chatTemps.filter { $0.role == "assistant" }.count >= 2
            || !selectedImages.isEmpty
            || !selectedDocumentURLs.isEmpty
            || !selectedPrompts.isEmpty
    }

    private var sendButtonColor: Color {
        TemporaryRecord ? .primary : .hlBluefont
    }

    private var observeButtonColor: Color {
        if respondIndex == 2 { return .hlRed }
        return canObserveCurrentChat ? (TemporaryRecord ? .primary : .hlBluefont) : .gray
    }

    private func checkSearchAvailability() -> Bool {
        do {
            let keys = try context.fetch(FetchDescriptor<SearchKeys>())
            return keys.contains(where: { $0.isUsing })
        } catch {
            return false
        }
    }

    private func checkEmbeddingAvailability() -> Bool {
        do {
            let userF = FetchDescriptor<UserInfo>()
            guard let u = try context.fetch(userF).first,
                  let m = u.chooseEmbeddingModel, !m.isEmpty else {
                knowledgeAlertMessage = "当前没有启用向量模型，请前往“设置-模型-向量模型”中启用向量模型。"
                isEmbeddingModelError = true
                return false
            }
            let kf = FetchDescriptor<KnowledgeChunk>()
            if try context.fetch(kf).isEmpty {
                knowledgeAlertMessage = "当前没有知识内容或知识内容没有进行向量化，请前往知识背包中添加知识内容并选择模型对其向量化。"
                isEmbeddingModelError = false
                return false
            }
            return true
        } catch {
            return false
        }
    }

    private func attachSampleImageForAcceptance() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
        let sampleImage = renderer.image { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        selectedImages.append(sampleImage)
        showPhotoSourceOptions = false
    }

    private func attachSampleDocumentForAcceptance() {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sample-attachment.txt")
        try? "Sample attachment document content for UI acceptance.".write(
            to: tmpURL,
            atomically: true,
            encoding: .utf8
        )
        selectedDocumentURLs.append(tmpURL)
        showPhotoSourceOptions = false
    }

    // 过滤掉已经选中的 Prompt
    private var filteredPromptTemps: [PromptRepo] {
        promptTemps.filter { prompt in
            !selectedPrompts.contains(where: { $0.id == prompt.id })
        }
    }

    // 添加到 selectedPrompts，同时移除 promptTemps
    private func addPrompt(_ prompt: PromptRepo) {
        if !selectedPrompts.contains(where: { $0.id == prompt.id }) {
            selectedPrompts.append(prompt)
        }
    }

    // 从 selectedPrompts 中移除，同时恢复到 promptTemps
    private func removePrompt(_ prompt: PromptRepo) {
        selectedPrompts.removeAll(where: { $0.id == prompt.id })
    }

    // 辅助函数，用于检测输入中最后一个"@"后面的内容并进行过滤：
    private func updateModelSuggestions() {
        // 使用正则匹配最后一个"@"后面的非空白字符
        if let range = message.range(of: "@[^\\s]*$", options: .regularExpression) {
            let query = String(message[range]).dropFirst() // 去掉"@"
            if query.isEmpty {
                // 如果没有输入字符，则默认显示前8个模型
                filteredModels = Array(modelTemp.prefix(8))
            } else {
                // 根据 query 进行不区分大小写的过滤
                filteredModels = modelTemp.filter { model in
                    let modelName = model.displayName ?? model.name ?? ""
                    return modelName.localizedCaseInsensitiveContains(query)
                }
                filteredModels = Array(filteredModels.prefix(8))
            }
            showModelSuggestions = true
        } else {
            showModelSuggestions = false
            filteredModels = []
        }
    }

    // 高亮辅助函数
    private func highlightedModelText(for fullText: String) -> Text {
        var query = ""
        if let range = message.range(of: "@[^\\s]*$", options: .regularExpression) {
            // 使用 dropFirst() 后转换为 String
            query = String(message[range].dropFirst())
        }

        // 如果查询为空，则直接返回全称
        if query.isEmpty {
            return Text(fullText)
        }

        // 尝试在 fullText 中查找 query（不区分大小写）
        if let matchRange = fullText.range(of: query, options: .caseInsensitive) {
            let prefix = String(fullText[..<matchRange.lowerBound])
            let match = String(fullText[matchRange])
            let suffix = String(fullText[matchRange.upperBound...])
            // 根据 TemporaryRecord 状态选择颜色
            let matchColor: Color = TemporaryRecord ? .primary : .hlBluefont
            return Text(prefix) + Text(match).bold().foregroundColor(matchColor) + Text(suffix)
        } else {
            return Text(fullText)
        }
    }

    // 实时检测并更新 URL 数组
    private func extractURLs(from text: String) {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return }

        let matches = detector.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))

        // 利用 Set 去重，提取 URL 字符串
        let extractedURLs = Set(matches.compactMap { match -> String? in
            if let range = Range(match.range, in: text) {
                return String(text[range])
            }
            return nil
        })

        // 将去重后的 URL 转换为数组并排序
        let uniqueURLs = Array(extractedURLs).sorted()

        // 在主线程更新 selectedURLs
        DispatchQueue.main.async {
            self.selectedURLs = uniqueURLs
        }
    }
}

