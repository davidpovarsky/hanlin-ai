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
        .onChange(of: isMultiSelectMode) { newValue in
            if newValue {
                isViewLoaded = false
            } else {
                isViewLoaded = true
            }
        }
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
                    modelSelector
                    if showPhotoSourceOptions {
                        sourceSelector
                    }
                }
                .padding(.bottom, 12)
                .onTapGesture {
                    showTemperatureSlider = false
                    showTopPSlider = false
                    showMaxTokensSlider = false
                    showMaxMessagesNumSlider = false
                }
                .background(
                    GlassView(style: .systemUltraThinMaterial) // 毛玻璃背景
                        .clipShape(RoundedRectangle(cornerRadius: 26))
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
            imageSizeControlSection
            modelSuggestionSection
            inputFieldSection
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
                                .sensoryFeedback(.impact, trigger: isFeedBack)
                            }
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
                                .sensoryFeedback(.impact, trigger: isFeedBack)
                            }
                            .padding(6)
                            .background(.background.opacity(0.6))
                            .cornerRadius(20)
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

    // MARK: - 画幅控制区域
    private var imageSizeControlSection: some View {
        Group {
            if selectedModelIndex >= 0,
               modelTemp[selectedModelIndex].supportsImageGen,
               ["QWEN", "MODELSCOPE", "ZHIPUAI", "HANLIN", "HANLIN_OPEN", "SILICONCLOUD", "OPENAI"].contains(modelTemp[selectedModelIndex].company) {

                VStack {
                    // 针对部分公司显示反向提示词输入框
                    if ["QWEN", "MODELSCOPE", "ZHIPUAI", "HANLIN", "HANLIN_OPEN", "SILICONCLOUD"].contains(modelTemp[selectedModelIndex].company) {
                        TextField("反向提示词", text: $imageReversePrompt)
                            .font(.footnote)
                            .padding(8)
                            .background(.background.opacity(0.6))
                            .cornerRadius(20)
                    }
                    // 画幅选择按钮区域
                    if ["QWEN", "ZHIPUAI", "OPENAI", "HANLIN", "HANLIN_OPEN", "SILICONCLOUD"].contains(modelTemp[selectedModelIndex].company) {
                        HStack(spacing: 6) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    Button(action: {
                                        isFeedBack.toggle()
                                        selectedImageSize = "square"
                                    }) {
                                        HStack {
                                            Image(systemName: "square")
                                                .foregroundColor(selectedImageSize == "square" ? .white : (TemporaryRecord ? .primary : .hlBluefont))
                                                .font(.footnote)
                                            Text("方形画幅")
                                                .font(.footnote)
                                                .foregroundColor(selectedImageSize == "square" ? .white : .primary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                        .padding(6)
                                        .background(selectedImageSize == "square" ? Color(.hlBluefont) : Color(.systemBackground).opacity(0.6))
                                        .cornerRadius(20)
                                    }
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))

                                    Button(action: {
                                        isFeedBack.toggle()
                                        selectedImageSize = "landscape"
                                    }) {
                                        HStack {
                                            Image(systemName: "rectangle")
                                                .foregroundColor(selectedImageSize == "landscape" ? .white : (TemporaryRecord ? .primary : .hlBluefont))
                                                .font(.footnote)
                                            Text("横向画幅")
                                                .font(.footnote)
                                                .foregroundColor(selectedImageSize == "landscape" ? .white : .primary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                        .padding(6)
                                        .background(selectedImageSize == "landscape" ? Color(.hlBluefont) : Color(.systemBackground).opacity(0.6))
                                        .cornerRadius(20)
                                    }
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))

                                    Button(action: {
                                        isFeedBack.toggle()
                                        selectedImageSize = "portrait"
                                    }) {
                                        HStack {
                                            Image(systemName: "rectangle.portrait")
                                                .foregroundColor(selectedImageSize == "portrait" ? .white : (TemporaryRecord ? .primary : .hlBluefont))
                                                .font(.footnote)
                                            Text("纵向画幅")
                                                .font(.footnote)
                                                .foregroundColor(selectedImageSize == "portrait" ? .white : .primary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                        }
                                        .padding(6)
                                        .background(selectedImageSize == "portrait" ? Color(.hlBluefont) : Color(.systemBackground).opacity(0.6))
                                        .cornerRadius(20)
                                    }
                                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                                }
                            }
                            .cornerRadius(20)
                        }
                    }
                }
                .sensoryFeedback(.impact, trigger: isFeedBack)
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
            VStack {
                HStack {
                    InputTextField(
                        text: $message,
                        onPasteImage: { pastedImage in
                            selectedImages.append(pastedImage)
                        },
                        onPasteFile: { pastedFile in
                            selectedDocumentURLs.append(pastedFile)
                        },
                        onSendMessage: {
                            onSendUser()
                        }
                    )
                    .padding(.leading, 12)
                    .frame(height: size_44)
                    .focused(isInputActive)
                    .submitLabel(.send)
                    .onSubmit {
                        onSendUser()
                    }
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

                    // 麦克风
                    Button(action: {
                        isFeedBack.toggle()
                        voiceExpanded.toggle()
                    }) {
                        Image(systemName: "microphone")
                            .foregroundColor(Color(.systemGray))
                            .padding(.trailing, 3)
                    }
                    .sensoryFeedback(.impact, trigger: isFeedBack)
                    .disabled(isResponding)

                    // 多行输入
                    Button(action: {
                        isFeedBack.toggle()
                        inputExpanded.toggle()
                    }) {
                        Image(systemName: inputExpanded ? "chevron.down" : "chevron.up")
                            .foregroundColor(Color(.systemGray))
                            .padding(.trailing, 12)
                            .symbolEffect(.bounce, value: inputExpanded)
                    }
                    .sensoryFeedback(.impact, trigger: isFeedBack)
                    .disabled(isResponding)
                }
                ActionButtonsView(
                    selectedModelIndex: $selectedModelIndex,
                    modelTemp: modelTemp,
                    isResponding: $isResponding,
                    message: $message,
                    selectedImages: $selectedImages,
                    selectedDocumentURLs: $selectedDocumentURLs,
                    selectedPrompts: $selectedPrompts,
                    isFeedBack: $isFeedBack,
                    showPhotoSourceOptions: $showPhotoSourceOptions,
                    isSourceOptionsVisible: $isSourceOptionsVisible,
                    ifKnowledge: $ifKnowledge,
                    ifSearch: $ifSearch,
                    ifToolUse: $ifToolUse,
                    ifThink: $ifThink,
                    ifAudio: $ifAudio,
                    ifPlanning: $ifPlanning,
                    thinkingLength: $thinkingLength,
                    showKnowledgeAlert: $showKnowledgeAlert,
                    knowledgeAlertMessage: $knowledgeAlertMessage,
                    showSearchAlert: $showSearchAlert,
                    chatTemps: $chatTemps,
                    respondIndex: respondIndex,
                    TemporaryRecord: TemporaryRecord,
                    isMenuMode: isMenuMode,
                    showModelMenuSheet: $showModelMenuSheet,
                    onSelectModel: onSelectModel,
                    size32: size_32,
                    size30: size_30,
                    onSendUser: onSendUser,
                    onSendObserve: onSendObserve,
                    onCancel: onCancel
                )
            }
            .background(.background.opacity(0.6))
            .cornerRadius(20)
            .animation(.spring(response: 0.5), value: isSourceOptionsVisible)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .padding(.top, 12)
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
    }

    // MARK: - 判断是否使用菜单模式
    private var isMenuMode: Bool {
        userInfos.first?.modelSelectorStyle == "menu"
    }

    // MARK: 模型选择区域
    private var modelSelector: some View {
        Group {
            if isMenuMode {
                menuStyleSelector
            } else {
                scrollStyleSelector
            }
        }
    }

    // MARK: - 横向滑动模式选择器
    private var scrollStyleSelector: some View {
        HStack {
            let visibleIndices = modelTemp.indices.filter { !modelTemp[$0].isHidden }

            if modelTemp.isEmpty {
                // 数据未加载，显示占位符
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("加载模型中...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(height: 36)
            } else if visibleIndices.isEmpty {
                // 没有可用模型
                Text("暂无可用模型，请前往模型界面开启模型。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(height: 36)
            } else {
                // 正常显示模型列表
                ScrollViewReader { scrollViewProxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(visibleIndices, id: \.self) { index in
                                if let model = modelTemp[safe: index] {
                                    Button(action: {
                                        isSelect.toggle()
                                        onSelectModel(index)
                                    }) {
                                        modelButton(for: model, isSelected: index == selectedModelIndex)
                                    }
                                    .sensoryFeedback(.selection, trigger: isSelect)
                                }
                            }
                        }
                    }
                    .cornerRadius(size_20)
                    .onReceive(NotificationCenter.default.publisher(for: .scrollToModelIndex)) { notification in
                        if let index = notification.object as? Int {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                scrollViewProxy.scrollTo(index, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
    }

    // MARK: - 菜单选择模式选择器（模型按钮已移至 ActionButtonsView，此处仅处理无模型时的提示）
    private var menuStyleSelector: some View {
        HStack {
            let visibleIndices = modelTemp.indices.filter { !modelTemp[$0].isHidden }

            if modelTemp.isEmpty {
                // 数据未加载，显示占位符
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("加载模型中...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(height: 36)
            } else if visibleIndices.isEmpty {
                // 没有可用模型
                Text("暂无可用模型，请前往模型界面开启模型。")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(height: 36)
            }
            // 有模型时不显示任何内容，模型按钮在 ActionButtonsView 中
        }
        .padding(.horizontal, 12)
    }

    private func modelButton(for model: AllModels, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            if isSelected {
                // 激活状态，使用原图颜色
                if model.identity == "model" {
                    Image(getCompanyIcon(for: model.company ?? "Unknown"))
                        .renderingMode(.original)
                        .resizable()
                        .frame(width: size_20, height: size_20)
                        .scaleEffect(1.2)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0.5), value: isSelected)
                } else {
                    Image(systemName: model.icon ?? "circle.dotted.circle")
                        .resizable()
                        .scaledToFill()
                        .frame(width: size_20, height: size_20)
                        .clipShape(Circle())
                        .overlay(
                            Group {
                                gradient(for: 0)
                                    .mask(
                                        Image(systemName: model.icon ?? "circle.dotted.circle")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: size_20, height: size_20)
                                    )
                            }
                        )
                        .scaleEffect(1.2)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0.5), value: isSelected)
                }
            } else {
                if model.identity == "model" {
                    // 非激活状态，使用模板模式配合 foregroundColor 上色
                    Image(getCompanyIcon(for: model.company ?? "Unknown"))
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: size_20, height: size_20)
                        .scaleEffect(1.0)
                        .foregroundColor(Color(.systemGray))
                        .animation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0.5), value: isSelected)
                } else {
                    Image(systemName: model.icon ?? "circle.dotted.circle")
                        .resizable()
                        .scaledToFill()
                        .frame(width: size_20, height: size_20)
                        .scaleEffect(1.0)
                        .foregroundColor(Color(.systemGray))
                        .clipShape(Circle())
                        .animation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0.5), value: isSelected)
                }
            }
            // 选中时展开显示全部信息
            if isSelected {
                Text(model.displayName ?? "Unknown")
                    .font(.caption)
                    .foregroundColor(TemporaryRecord ? .primary : Color(.hlBluefont))
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                if model.supportsToolUse {
                    Text("工具")
                        .font(.caption)
                        .foregroundColor(ifToolUse ? .hlBrown : .gray)
                        .transition(.opacity)
                }
                if model.company?.uppercased() == "LOCAL" {
                    Text("本地")
                        .font(.caption)
                        .foregroundColor(.hlOrange)
                        .transition(.opacity)
                }
                if model.supportsMultimodal {
                    Text("视觉")
                        .font(.caption)
                        .foregroundColor(.hlTeal)
                        .transition(.opacity)
                }
                if model.supportsReasoning {
                    Text("思考")
                        .font(.caption)
                        .foregroundColor(ifThink ? .hlPurple : .gray)
                        .transition(.opacity)
                }
                if model.supportsVoiceGen {
                    Text("语音")
                        .font(.caption)
                        .foregroundColor(ifAudio ? .hlPink : .gray)
                        .transition(.opacity)
                }
                if model.supportsImageGen {
                    Text("生图")
                        .font(.caption)
                        .foregroundColor(.hlGreen)
                        .transition(.opacity)
                }
                if model.price == 0 {
                    Text("免费")
                        .font(.caption)
                        .foregroundColor(.green)
                        .transition(.opacity)
                }
            }
        }
        .padding(10)
        .background(background(for: model, isSelected: isSelected))
        .cornerRadius(size_20)
        .animation(
            .spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0.5),
            value: [isSelected, ifThink, ifToolUse, ifAudio]
        )
    }

    @ViewBuilder
    private func background(for model: AllModels, isSelected: Bool) -> some View {
        let special = specialColor(for: model)

        if let special {
            LinearGradient(
                colors: [
                    (isSelected ? Color(.hlBluefont) : Color(.systemGray)).opacity(0.1),
                    special.opacity(0.1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            (isSelected ? Color(.hlBluefont) : Color(.systemGray)).opacity(0.1)
        }
    }

    private func specialColor(for model: AllModels) -> Color? {
        if model.company?.uppercased() == "LOCAL" {
            return .hlOrange
        } else if model.supportsReasoning {
            return .hlPurple
        } else if model.supportsVoiceGen {
            return .hlPink
        } else if model.supportsImageGen {
            return .hlGreen
        } else if model.supportsMultimodal {
            return .hlTeal
        } else if model.price == 0 {
            return .green
        } else {
            return nil
        }
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

    // MARK: 资源选择区域
    private var sourceSelector: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                if !filteredPromptTemps.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(filteredPromptTemps, id: \.id) { item in
                                Button(action: {
                                    isFeedBack.toggle()
                                    addPrompt(item)
                                }) {
                                    HStack {
                                        // 提示词库
                                        Image("prompt") // 使用自定义图片
                                            .renderingMode(.template)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 20, height: 20) // 调整大小
                                            .foregroundColor(TemporaryRecord ? .primary : .hlBluefont) // 颜色变为 .hlBlue

                                        Text(item.name ?? "提示词")
                                            .font(.body)
                                            .foregroundColor(TemporaryRecord ? .primary : .hlBluefont)
                                            .lineLimit(1) // 限制为 1 行
                                            .truncationMode(.tail) // 文字过长时显示省略号
                                    }
                                    .padding(12)
                                    .background(TemporaryRecord ? Color.primary.opacity(0.1) : Color.hlBlue.opacity(0.1))
                                    .cornerRadius(20)
                                }
                                .sensoryFeedback(.impact, trigger: isFeedBack)
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                            }
                        }
                    }
                    .cornerRadius(20)
                }
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))

            if !modelTemp[selectedModelIndex].supportsMultimodal && modelTemp[selectedModelIndex].company != "LOCAL" {
                Text("⚠️ 当前不是视觉模型，分析图片建议使用视觉模型")
                    .font(.caption.bold())
                    .foregroundColor(TemporaryRecord ? .primary : .hlBluefont)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            HStack(spacing: 6) {

                if modelTemp[selectedModelIndex].company != "LOCAL" {

                    Button(action: {
                        isFeedBack.toggle()
                        showCameraPicker = true
                    }) {
                        VStack {
                            Image(systemName: "camera.circle")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 30, height: 30)
                                .foregroundColor(TemporaryRecord ? .primary : .hlBluefont)
                                .symbolEffect(.bounce, value: showCameraPicker)
                            Text("拍摄照片")
                                .font(.caption.bold())
                                .foregroundColor(TemporaryRecord ? .primary : .hlBluefont)
                                .padding(.top, 3)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(TemporaryRecord ? Color.primary.opacity(0.1) : Color.hlBlue.opacity(0.1))
                        .cornerRadius(size_20)
                    }
                    .sensoryFeedback(.impact, trigger: isFeedBack)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: showPhotoSourceOptions)
                    // 打开相机
                    .sheet(isPresented: $showCameraPicker, onDismiss: {
                        showPhotoSourceOptions = false
                    }) {
                        ImagePicker(selectedImages: $selectedImages, sourceType: .camera, maxImageNumber: 5)
                            .background(.black)
                    }

                    Button(action: {
                        isFeedBack.toggle()
                        showImagePicker = true
                    }) {
                        VStack {
                            Image(systemName: "photo.circle")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 30, height: 30)
                                .foregroundColor(TemporaryRecord ? .primary : .hlBluefont)
                                .symbolEffect(.bounce, value: showImagePicker)
                            Text("相册选择")
                                .font(.caption.bold())
                                .foregroundColor(TemporaryRecord ? .primary : .hlBluefont)
                                .padding(.top, 3)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(TemporaryRecord ? Color.primary.opacity(0.1) : Color.hlBlue.opacity(0.1))
                        .cornerRadius(size_20)
                    }
                    .sensoryFeedback(.impact, trigger: isFeedBack)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: showPhotoSourceOptions)
                    // 打开相册
                    .sheet(isPresented: $showImagePicker, onDismiss: {
                        showPhotoSourceOptions = false
                    }) {
                        ImagePicker(selectedImages: $selectedImages, sourceType: .photoLibrary, maxImageNumber: 5)
                            .ignoresSafeArea()
                    }
                }

                Button(action: {
                    isFeedBack.toggle()
                    showDocumentPicker = true
                }) {
                    VStack {
                        Image(systemName: "document.circle")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30, height: 30)
                            .foregroundColor(selectedDocumentURLs.count >= 5 ? .gray : (TemporaryRecord ? .primary : .hlBluefont))
                            .symbolEffect(.bounce, value: showDocumentPicker)
                        Text("文件文本")
                            .font(.caption.bold())
                            .foregroundColor(selectedDocumentURLs.count >= 5 ? .gray : (TemporaryRecord ? .primary : .hlBluefont))
                            .padding(.top, 3)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(selectedDocumentURLs.count >= 5 ? Color.gray.opacity(0.2) : (TemporaryRecord ? Color.primary.opacity(0.1) : Color.hlBlue.opacity(0.1)))
                    .cornerRadius(size_20)
                }
                .sensoryFeedback(.impact, trigger: isFeedBack)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: showPhotoSourceOptions)
                .disabled(selectedDocumentURLs.count >= 5)
                // 打开文档
                .sheet(isPresented: $showDocumentPicker, onDismiss: {
                    showPhotoSourceOptions = false
                }) {
                    DocumentPicker(selectedDocumentURLs: $selectedDocumentURLs)
                        .ignoresSafeArea()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: showPhotoSourceOptions)
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


/// 底部操作按钮横条
struct ActionButtonsView: View {

    // MARK: - 绑定 / 值参数（全部来自 ChatView）
    @Binding var selectedModelIndex: Int
    let modelTemp: [AllModels]

    @Binding var isResponding: Bool
    @Binding var message: String

    @Binding var selectedImages: [UIImage]
    @Binding var selectedDocumentURLs: [URL]
    @Binding var selectedPrompts: [PromptRepo]

    @Binding var isFeedBack: Bool
    @Binding var showPhotoSourceOptions: Bool
    @Binding var isSourceOptionsVisible: Bool

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

    @Binding var chatTemps: [ChatMessages]
    let respondIndex: Int
    let TemporaryRecord: Bool

    // 菜单模式相关
    let isMenuMode: Bool
    @Binding var showModelMenuSheet: Bool
    let onSelectModel: (Int) -> Void

    // 尺寸
    let size32: CGFloat
    let size30: CGFloat

    // 回调动作
    let onSendUser: () -> Void
    let onSendObserve: () -> Void
    let onCancel: () -> Void

    // 环境
    @Environment(\.modelContext) private var context

    @State private var bounceTrigger = false
    @State private var audioTrigger = false
    @State private var showToolReminder = false
    @State private var showEmbeddingSettingSheet = false
    @State private var isEmbeddingModelError = false

    private let lengthDescriptions: [String: [Int: String]] = [
        "zh": [
            0: "默认",
            1: "短暂",
            2: "中等",
            3: "深度"
        ],
        "en": [
            0: "Default",
            1: "Short",
            2: "Medium",
            3: "Long"
        ]
    ]

    private var currentLang: String {
        let lang = Bundle.main.preferredLocalizations.first ?? "en"
        if lang.hasPrefix("zh") {
            return "zh"
        } else {
            return "en"
        }
    }

    // MARK: - 视图
    var body: some View {
        let valid = modelTemp.indices.contains(selectedModelIndex)

        let model = valid ? modelTemp[selectedModelIndex] : nil

        let bgColorKnowledge = ifKnowledge
        ? (TemporaryRecord ? Color.primary.opacity(0.1) : Color(.hlBluefont).opacity(0.1))
        : Color.clear

        let bgColorSearch = ifSearch
        ? (TemporaryRecord ? Color.primary.opacity(0.1) : Color(.hlAzure).opacity(0.1))
        : Color.clear

        let bgColorImage = TemporaryRecord ? Color.primary.opacity(0.1) : Color(.hlGreen).opacity(0.1)

        let bgColorReasoning = ifThink
        ? (TemporaryRecord ? Color.primary.opacity(0.1) : Color(.hlPurple).opacity(0.1))
        : Color.clear

        let bgColorPlanning = ifPlanning
        ? (TemporaryRecord ? Color.primary.opacity(0.1) : Color(.hlIndigo).opacity(0.1))
        : Color.clear

        let bgColorLocal = TemporaryRecord ? Color.primary.opacity(0.1) : Color(.hlOrange).opacity(0.1)

        let bgColorTool = (ifToolUse || showToolReminder)
        ? (TemporaryRecord ? Color.primary.opacity(0.1) : Color(.hlBrown).opacity(0.1))
        : Color.clear

        let bgColorAudio = ifAudio
        ? (TemporaryRecord ? Color.primary.opacity(0.1) : Color(.hlPink).opacity(0.1))
        : Color.clear

        HStack(spacing: 6) {
            // 菜单模式下的模型选择按钮
            if isMenuMode && valid {
                Button {
                    isFeedBack.toggle()
                    showModelMenuSheet = true
                } label: {
                    if model?.identity == "model" {
                        Image(getCompanyIcon(for: model?.company ?? "Unknown"))
                            .resizable()
                            .scaledToFit()
                            .frame(width: size32 * 0.5, height: size32 * 0.5)
                            .frame(width: size32, height: size32)
                            .background(
                                Circle()
                                    .fill(TemporaryRecord ? Color.primary.opacity(0.1) : Color.hlBlue.opacity(0.1))
                            )
                            .overlay(
                                Circle()
                                    .stroke(TemporaryRecord ? Color.primary : Color.hlBluefont, lineWidth: 2)
                            )
                    } else {
                        Image(systemName: model?.icon ?? "circle.dotted.circle")
                            .resizable()
                            .scaledToFit()
                            .frame(width: size32 * 0.45, height: size32 * 0.45)
                            .foregroundColor(TemporaryRecord ? .primary : .hlBluefont)
                            .frame(width: size32, height: size32)
                            .background(
                                Circle()
                                    .fill(TemporaryRecord ? Color.primary.opacity(0.1) : Color.hlBlue.opacity(0.1))
                            )
                            .overlay(
                                Circle()
                                    .stroke(TemporaryRecord ? Color.primary : Color.hlBluefont, lineWidth: 2)
                            )
                    }
                }
                .sensoryFeedback(.selection, trigger: isFeedBack)
                .sheet(isPresented: $showModelMenuSheet) {
                    ModelMenuSheetView(
                        models: modelTemp,
                        selectedModelIndex: $selectedModelIndex,
                        onSelectModel: { index in
                            onSelectModel(index)
                            showModelMenuSheet = false
                        },
                        TemporaryRecord: TemporaryRecord,
                        ifToolUse: ifToolUse,
                        ifThink: ifThink,
                        ifAudio: ifAudio
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
            }

            // 附件
            if model?.supportsTextGen == true {
                Button {
                    isFeedBack.toggle()
                    showPhotoSourceOptions.toggle()
                } label: {
                    Image(systemName: "plus.circle")
                        .resizable()
                        .frame(width: size32, height: size32)
                        .foregroundColor(
                            (isResponding || selectedImages.count > 4)
                            ? .gray
                            : (isSourceOptionsVisible ? .hlRed
                               : (TemporaryRecord ? .primary : .hlBluefont))
                        )
                        .rotationEffect(.degrees(isSourceOptionsVisible ? 45 : 0))
                        .animation(.spring(response: 0.5), value: isSourceOptionsVisible)
                }
                .disabled(isResponding || selectedImages.count > 4)
                .sensoryFeedback(.impact, trigger: isFeedBack)
                .onChange(of: showPhotoSourceOptions) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        isSourceOptionsVisible = showPhotoSourceOptions
                    }
                }
            }

            // —— 左侧滚动按钮 —— //
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    // 工具调用
                    if model?.supportsToolUse == true {
                        Button {
                            isFeedBack.toggle()
                            ifToolUse.toggle()
                            showToolReminder = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                showToolReminder = false
                            }
                        } label: {
                            HStack {
                                Image(systemName: "hammer.circle")
                                    .resizable()
                                    .scaleEffect(showToolReminder ? 0.8 : 1.0)
                                    .frame(width: size32, height: size32)
                                    .foregroundColor(
                                        ifToolUse
                                        ? (TemporaryRecord ? .primary : .hlBrown)
                                        : .gray
                                    )

                                if showToolReminder {
                                    Text(ifToolUse ? "使用工具" : "禁用工具")
                                        .font(.caption)
                                        .foregroundColor(
                                            ifToolUse
                                            ? (TemporaryRecord ? .primary : .hlBrown)
                                            : .gray
                                        )
                                        .padding(.trailing, 12)
                                        .transition(.opacity.combined(with: .move(edge: .leading)))
                                }
                            }
                        }
                        .sensoryFeedback(.impact, trigger: isFeedBack)
                        .background(bgColorTool)
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(bgColorTool, lineWidth: 1)
                        )
                        .animation(
                            .spring(response: 0.5, dampingFraction: 0.7),
                            value: [ifToolUse, showToolReminder]
                        )
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                        .disabled(isResponding)
                    }

                    if model?.supportsSearch == true {
                        // 知识背包
                        Button {
                            isFeedBack.toggle()
                            if !checkEmbeddingAvailability() {
                                showKnowledgeAlert = true
                            } else {
                                ifKnowledge.toggle()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "backpack.circle")
                                    .resizable()
                                    .scaleEffect(ifKnowledge ? 0.8 : 1.0)
                                    .frame(width: size32, height: size32)
                                    .foregroundColor(
                                        ifKnowledge
                                        ? (TemporaryRecord ? .primary : .hlBluefont)
                                        : .gray
                                    )
                                if ifKnowledge {
                                    Text("知识背包")
                                        .font(.caption)
                                        .foregroundColor(TemporaryRecord ? .primary : .hlBluefont)
                                        .padding(.trailing, 12)
                                        .transition(.opacity.combined(with: .move(edge: .leading)))
                                }
                            }
                        }
                        .disabled(isResponding)
                        .sensoryFeedback(.impact, trigger: isFeedBack)
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
                        .background(bgColorKnowledge)
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(bgColorKnowledge, lineWidth: 1)
                        )
                        .transition(.opacity.combined(with: .move(edge: .leading)))

                        // 联网搜索
                        Button {
                            isFeedBack.toggle()
                            if ifSearch {
                                ifSearch = false
                            } else if checkSearchAvailability() {
                                ifSearch = true
                            } else {
                                showSearchAlert = true
                            }
                        } label: {
                            HStack {
                                Image(systemName: "network")
                                    .resizable()
                                    .scaleEffect(ifSearch ? 0.8 : 1.0)
                                    .frame(width: size30, height: size30)
                                    .foregroundColor(
                                        ifSearch
                                        ? (TemporaryRecord ? .primary : .hlAzure)
                                        : .gray
                                    )
                                if ifSearch {
                                    Text("联网搜索")
                                        .font(.caption)
                                        .foregroundColor(TemporaryRecord ? .primary : .hlAzure)
                                        .padding(.trailing, 12)
                                        .transition(.opacity.combined(with: .move(edge: .leading)))
                                }
                            }
                        }
                        .disabled(isResponding)
                        .sensoryFeedback(.impact, trigger: isFeedBack)
                        .alert("未启用搜索引擎", isPresented: $showSearchAlert) {
                            Button("确定", role: .cancel) { }
                        } message: {
                            Text("当前未启用任何搜索引擎，请前往 设置-工具-搜索设置 中开启。")
                        }
                        .background(bgColorSearch)
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(bgColorSearch, lineWidth: 1)
                        )
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                    }

                    // 规划执行
                    if model?.supportsReasoning == false && model?.company != "LOCAL" {
                        Button {
                            isFeedBack.toggle()
                            ifPlanning.toggle()
                        } label: {
                            HStack {
                                Image(systemName: "location.circle")
                                    .resizable()
                                    .scaledToFit()
                                    .scaleEffect(ifPlanning ? 0.8 : 1.0)
                                    .frame(width: size32, height: size32)
                                    .foregroundColor(
                                        ifPlanning
                                        ? (TemporaryRecord ? .primary : .hlIndigo)
                                        : .gray
                                    )

                                if ifPlanning {
                                    Text("规划执行")
                                        .font(.caption)
                                        .foregroundColor(TemporaryRecord ? .primary : .hlIndigo)
                                        .padding(.trailing, 12)
                                        .transition(.opacity.combined(with: .move(edge: .leading)))
                                }
                            }
                        }
                        .sensoryFeedback(.impact, trigger: isFeedBack)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(bgColorPlanning)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(bgColorPlanning, lineWidth: 1)
                        )
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                        .animation(
                            .spring(response: 0.5, dampingFraction: 0.7),
                            value: ifPlanning
                        )
                    }

                    // 深度思考
                    if model?.supportsReasoning == true {
                        Button {
                            isFeedBack.toggle()
                            if model?.supportReasoningChange == true {
                                ifThink.toggle()
                            } else {
                                bounceTrigger.toggle()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "lightbulb.circle")
                                    .resizable()
                                    .scaledToFit()
                                    .scaleEffect(ifThink ? 0.8 : 1.0)
                                    .frame(width: size32, height: size32)
                                    .foregroundColor(
                                        ifThink
                                        ? (TemporaryRecord ? .primary : .hlPurple)
                                        : .gray
                                    )
                                    .symbolEffect(.pulse, value: bounceTrigger)
                                    .onAppear {
                                        if model?.supportReasoningChange == true {
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                bounceTrigger.toggle()
                                            }
                                        }
                                    }

                                if ifThink {
                                    Text("深度思考")
                                        .font(.caption)
                                        .foregroundColor(TemporaryRecord ? .primary : .hlPurple)
                                        .transition(.opacity.combined(with: .move(edge: .leading)))
                                        .padding(.trailing, ["OPENAI", "GOOGLE", "XAI", "QWEN", "MODELSCOPE", "SILICONCLOUD"].contains(model?.company) ? 0 : 12)

                                    if ["OPENAI", "GOOGLE", "XAI", "QWEN", "MODELSCOPE", "SILICONCLOUD"].contains(model?.company) {

                                        Divider()

                                        Menu {
                                            ForEach(0...3, id: \.self) { value in
                                                Button(action: {
                                                    thinkingLength = value
                                                }) {
                                                    Label(lengthDescriptions[currentLang]?[value] ?? "Unknown",
                                                          systemImage: thinkingLength == value ? "checkmark.circle" : "circle")
                                                }
                                            }
                                        } label: {
                                            HStack {
                                                Image(systemName: "chevron.up.chevron.down")
                                                    .foregroundColor(.hlPurple)
                                                    .imageScale(.small)

                                                Text(lengthDescriptions[currentLang]?[thinkingLength] ?? "")
                                                    .font(.caption)
                                                    .foregroundColor(TemporaryRecord ? .primary : .hlPurple)
                                                    .padding(.trailing, 12)
                                            }
                                            .transition(.opacity.combined(with: .move(edge: .leading)))
                                        }
                                    }
                                }
                            }
                        }
                        .sensoryFeedback(.impact, trigger: isFeedBack)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(bgColorReasoning)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(bgColorReasoning, lineWidth: 1)
                        )
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                        .animation(
                            .spring(response: 0.5, dampingFraction: 0.7),
                            value: [ifThink, model?.supportReasoningChange == true]
                        )
                    }

                    // 语音生成
                    if model?.supportsVoiceGen == true {
                        Button {
                            isFeedBack.toggle()
                            audioTrigger.toggle()
                        } label: {
                            HStack {
                                Image(systemName: "waveform.circle")
                                    .resizable()
                                    .scaledToFit()
                                    .scaleEffect(ifAudio ? 0.8 : 1.0)
                                    .frame(width: size32, height: size32)
                                    .foregroundColor(
                                        ifAudio
                                        ? (TemporaryRecord ? .primary : .hlPink)
                                        : .gray
                                    )
                                    .symbolEffect(.variableColor, value: audioTrigger)

                                if ifAudio {
                                    Text("语音生成")
                                        .font(.caption)
                                        .foregroundColor(TemporaryRecord ? .primary : .hlPink)
                                        .padding(.trailing, 12)
                                        .transition(.opacity.combined(with: .move(edge: .leading)))
                                }
                            }
                        }
                        .sensoryFeedback(.impact, trigger: isFeedBack)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(bgColorAudio)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(bgColorAudio, lineWidth: 1)
                        )
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                        .animation(
                            .spring(response: 0.5, dampingFraction: 0.7),
                            value: ifAudio
                        )
                    }

                    // 图片生成
                    if model?.supportsImageGen == true {
                        Button { isFeedBack.toggle() } label: {
                            HStack {
                                Image(systemName: "camera.aperture")
                                    .resizable()
                                    .scaledToFit()
                                    .scaleEffect(0.8)
                                    .frame(width: size32, height: size32)
                                    .foregroundColor(TemporaryRecord ? .primary : .hlGreen)
                                    .symbolEffect(.rotate, value: isFeedBack)
                                Text("图像生成")
                                    .font(.caption)
                                    .foregroundColor(TemporaryRecord ? .primary : .hlGreen)
                                    .padding(.trailing, 12)
                            }
                        }
                        .sensoryFeedback(.impact, trigger: isFeedBack)
                        .background(bgColorImage)
                        .cornerRadius(20)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(bgColorImage, lineWidth: 1)
                        )
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                    }

                    // 本地运行
                    if model?.company == "LOCAL" {
                        Button { isFeedBack.toggle() } label: {
                            HStack {
                                Image(systemName: "lock.circle")
                                    .resizable()
                                    .scaledToFit()
                                    .scaleEffect(0.8)
                                    .frame(width: size32, height: size32)
                                    .foregroundColor(TemporaryRecord ? .primary : .hlOrange)
                                    .symbolEffect(.wiggle, value: isFeedBack)
                                Text("本地运行")
                                    .font(.caption)
                                    .foregroundColor(TemporaryRecord ? .primary : .hlOrange)
                                    .padding(.trailing, 12)
                            }
                        }
                        .sensoryFeedback(.impact, trigger: isFeedBack)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(bgColorLocal)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(bgColorLocal, lineWidth: 1)
                        )
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                    }
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.7), value: model?.name)
                .animation(
                    .spring(response: 0.5, dampingFraction: 0.7),
                    value: [ifToolUse, ifThink, ifPlanning, ifSearch, ifKnowledge, showToolReminder, model?.company == "LOCAL", model?.supportsImageGen == true]
                )
            }
            .cornerRadius(20)
            .frame(height: size32)

            // —— 右侧状态按钮 —— //
            Group {
                if isResponding {            // 取消
                    Button(action: onCancel) {
                        Image(systemName: "stop.circle.fill")
                            .resizable()
                            .frame(width: size32, height: size32)
                            .foregroundColor(.hlRed)
                            .symbolEffect(.breathe, isActive: true)
                    }
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isResponding)
                } else if !selectedImages.isEmpty
                            || !selectedDocumentURLs.isEmpty
                            || !selectedPrompts.isEmpty
                            || !message.isEmpty {
                    Button(action: onSendUser) {
                        Image(systemName: "arrowtriangle.up.circle.fill")
                            .resizable()
                            .frame(width: size32, height: size32)
                            .foregroundColor(sendButtonColor)
                    }
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: message)
                    .disabled(message.isEmpty)
                } else {                     // 观察
                    Button(action: onSendObserve) {
                        Image(systemName: "eye.circle.fill")
                            .resizable()
                            .frame(width: size32, height: size32)
                            .foregroundColor(observeButtonColor)
                    }
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: message)
                    .sensoryFeedback(.impact, trigger: isFeedBack)
                    .disabled(
                        chatTemps.filter { $0.role == "assistant" }.count < 2 &&
                        selectedImages.isEmpty &&
                        selectedDocumentURLs.isEmpty &&
                        selectedPrompts.isEmpty
                    )
                }
            }
            .sensoryFeedback(.impact, trigger: isFeedBack)
        }
        .frame(height: size32)
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
    }

    // MARK: - 颜色逻辑
    private var sendButtonColor: Color {
        TemporaryRecord ? .primary : .hlBluefont
    }
    private var observeButtonColor: Color {
        if respondIndex == 2 { return .hlRed }
        let assistantCount = chatTemps.filter { $0.role == "assistant" }.count
        let hasAttach = !selectedImages.isEmpty
                     || !selectedDocumentURLs.isEmpty
                     || !selectedPrompts.isEmpty
                     || !message.isEmpty
        return (assistantCount < 2 && !hasAttach)
            ? .gray
            : (TemporaryRecord ? .primary : .hlBluefont)
    }

    // MARK: - 内部检查函数（直接访问数据库）
    private func checkSearchAvailability() -> Bool {
        do {
            let keys = try context.fetch(FetchDescriptor<SearchKeys>())
            return keys.contains(where: { $0.isUsing })
        } catch { return false }
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
        } catch { return false }
    }
}


// MARK: - 模型菜单选择底部抽屉
struct ModelMenuSheetView: View {
    let models: [AllModels]
    @Binding var selectedModelIndex: Int
    let onSelectModel: (Int) -> Void
    let TemporaryRecord: Bool
    let ifToolUse: Bool
    let ifThink: Bool
    let ifAudio: Bool

    @State private var searchText: String = ""
    @ScaledMetric(relativeTo: .body) var size_30: CGFloat = 30

    // 过滤后的可见模型索引
    private var visibleIndices: [Int] {
        let indices = models.indices.filter { !models[$0].isHidden }

        if searchText.isEmpty {
            return indices.sorted { (models[$0].position ?? 0) < (models[$1].position ?? 0) }
        } else {
            let lowercasedSearch = searchText.lowercased()
            return indices.filter { index in
                let model = models[index]
                guard let displayName = model.displayName, !displayName.isEmpty else { return false }
                let pinyinName = displayName.toPinyin()
                return displayName.lowercased().contains(lowercasedSearch) ||
                       pinyinName.lowercased().contains(lowercasedSearch)
            }.sorted { (models[$0].position ?? 0) < (models[$1].position ?? 0) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(visibleIndices, id: \.self) { index in
                    let model = models[index]
                    let isSelected = index == selectedModelIndex

                    Button(action: {
                        onSelectModel(index)
                    }) {
                        HStack {
                            // 模型图标
                            if model.identity == "model" {
                                Image(getCompanyIcon(for: model.company ?? "Unknown"))
                                    .resizable()
                                    .frame(width: size_30, height: size_30)
                            } else {
                                Image(systemName: model.icon ?? "circle.dotted.circle")
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: size_30, height: size_30)
                                    .clipShape(Circle())
                                    .overlay(
                                        gradient(for: 0)
                                            .mask(
                                                Image(systemName: model.icon ?? "circle.dotted.circle")
                                                    .resizable()
                                                    .scaledToFit()
                                                    .frame(width: size_30, height: size_30)
                                            )
                                    )
                            }

                            // 模型信息
                            VStack(alignment: .leading, spacing: 4) {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    Text(model.displayName ?? "Unknown")
                                        .font(.subheadline)
                                        .foregroundColor(isSelected ? (TemporaryRecord ? .primary : .hlBluefont) : .primary)
                                }

                                // 能力标签
                                HStack(spacing: 6) {
                                    if model.supportsToolUse {
                                        Text("工具")
                                            .font(.caption)
                                            .foregroundColor(ifToolUse ? .hlBrown : .gray)
                                    }

                                    if model.supportsMultimodal {
                                        Text("视觉")
                                            .font(.caption)
                                            .foregroundColor(.hlTeal)
                                    } else if model.supportsTextGen {
                                        Text("文本")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }

                                    if model.supportsImageGen {
                                        Text("生图")
                                            .font(.caption)
                                            .foregroundColor(.hlGreen)
                                    }

                                    if model.supportsVoiceGen {
                                        Text("语音")
                                            .font(.caption)
                                            .foregroundColor(ifAudio ? .hlPink : .gray)
                                    }

                                    if model.supportsReasoning {
                                        Text("思考")
                                            .font(.caption)
                                            .foregroundColor(ifThink ? .hlPurple : .gray)
                                    }

                                    if model.company?.uppercased() == "LOCAL" {
                                        Text("本地")
                                            .font(.caption)
                                            .foregroundColor(.hlOrange)
                                    }

                                    Text(priceText(for: model.price))
                                        .font(.caption)
                                        .foregroundColor(priceColor(for: model.price))
                                }
                            }

                            Spacer()

                            // 选中标记
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(TemporaryRecord ? .primary : .hlBluefont)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(
                        isSelected
                            ? (TemporaryRecord ? Color.primary.opacity(0.1) : Color.hlBlue.opacity(0.1))
                            : Color.clear
                    )
                }
            }
            .navigationTitle("选择模型")
        }
    }

    // MARK: - 辅助函数
    private func priceText(for price: Int16) -> String {
        let currentLanguage = Locale.preferredLanguages.first ?? "zh-Hans"
        if currentLanguage.hasPrefix("zh") {
            switch price {
            case 0: return "免费"
            case 1: return "廉价"
            case 2: return "适中"
            default: return "昂贵"
            }
        } else {
            switch price {
            case 0: return "Free"
            case 1: return "Cheap"
            case 2: return "Moderate"
            default: return "Expensive"
            }
        }
    }

    private func priceColor(for price: Int16) -> Color {
        switch price {
        case 0: return .green
        case 1: return .yellow
        case 2: return .orange
        default: return .red
        }
    }
}
