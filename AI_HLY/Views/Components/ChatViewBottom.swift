//
//  ChatViewBottom.swift
//  AI_HLY
//
//  SwiftChat Full Demo-inspired Native Multiline Liquid Glass Composer
//  Preserving all Hanlin 278-feature matrix input capabilities and 2026-10-19 minimal everyday controls.
//

import HanlinScriptUI
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

struct ComposerHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Native Multiline Text Editor with Real Placeholder and Paste Support

struct NativeMultilineTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var textHeight: CGFloat
    var placeholderText: String
    var minHeight: CGFloat = 38
    var maxHeight: CGFloat = 140
    var onPasteImage: ((UIImage) -> Void)?
    var onPasteFile: ((URL) -> Void)?
    var onSendMessage: (() -> Void)?
    var onMentionTriggered: (() -> Void)?

    func makeUIView(context: Context) -> MultilineInnerTextView {
        let textView = MultilineInnerTextView()
        textView.delegate = context.coordinator
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        textView.textContainer.lineFragmentPadding = 0
        textView.tintColor = UIColor.tintColor
        textView.isScrollEnabled = false
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        textView.onPasteImage = onPasteImage
        textView.onPasteFile = onPasteFile
        textView.onSendMessage = onSendMessage
        textView.accessibilityIdentifier = "hanlin-chat-input"
        textView.isAccessibilityElement = true

        if text.isEmpty {
            textView.text = placeholderText
            textView.textColor = .placeholderText
        } else {
            textView.text = text
            textView.textColor = .label
        }

        return textView
    }

    func updateUIView(_ uiView: MultilineInnerTextView, context: Context) {
        context.coordinator.parent = self
        uiView.onPasteImage = onPasteImage
        uiView.onPasteFile = onPasteFile
        uiView.onSendMessage = onSendMessage

        let isEditing = context.coordinator.isEditing

        if text.isEmpty && !isEditing {
            uiView.text = placeholderText
            uiView.textColor = .placeholderText
        } else if !text.isEmpty && uiView.textColor == .placeholderText {
            uiView.text = text
            uiView.textColor = .label
        } else if !text.isEmpty && uiView.text != text && !isEditing {
            uiView.text = text
        }

        let fittingSize = uiView.sizeThatFits(CGSize(width: max(uiView.frame.width, 240), height: .greatestFiniteMagnitude))
        let clampedHeight = min(maxHeight, max(minHeight, fittingSize.height))
        uiView.isScrollEnabled = fittingSize.height > maxHeight
        if abs(textHeight - clampedHeight) > 1 {
            DispatchQueue.main.async {
                self.textHeight = clampedHeight
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NativeMultilineTextEditor
        var isEditing = false

        init(_ parent: NativeMultilineTextEditor) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            isEditing = true
            if textView.textColor == .placeholderText {
                textView.text = ""
                textView.textColor = .label
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isEditing = false
            if textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                textView.text = parent.placeholderText
                textView.textColor = .placeholderText
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            if textView.textColor != .placeholderText {
                parent.text = textView.text
                if textView.text.hasSuffix("@") {
                    parent.onMentionTriggered?()
                }
                let fittingSize = textView.sizeThatFits(CGSize(width: max(textView.frame.width, 240), height: .greatestFiniteMagnitude))
                let clampedHeight = min(parent.maxHeight, max(parent.minHeight, fittingSize.height))
                textView.isScrollEnabled = fittingSize.height > parent.maxHeight
                if abs(parent.textHeight - clampedHeight) > 1 {
                    parent.textHeight = clampedHeight
                }
            }
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            return true
        }
    }
}

final class MultilineInnerTextView: UITextView {
    var onPasteImage: ((UIImage) -> Void)?
    var onPasteFile: ((URL) -> Void)?
    var onSendMessage: (() -> Void)?

    override var keyCommands: [UIKeyCommand]? {
        let returnCommand = UIKeyCommand(
            input: "\r",
            modifierFlags: [],
            action: #selector(handleHardwareReturn)
        )
        returnCommand.wantsPriorityOverSystemBehavior = true

        let shiftReturnCommand = UIKeyCommand(
            input: "\r",
            modifierFlags: .shift,
            action: #selector(handleHardwareShiftReturn)
        )
        shiftReturnCommand.wantsPriorityOverSystemBehavior = true

        return [returnCommand, shiftReturnCommand]
    }

    @objc private func handleHardwareReturn() {
        guard markedTextRange == nil else { return }
        let currentText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !currentText.isEmpty {
            onSendMessage?()
        }
    }

    @objc private func handleHardwareShiftReturn() {
        insertText("\n")
    }

    override func paste(_ sender: Any?) {
        let pasteboard = UIPasteboard.general

        if let img = pasteboard.image {
            onPasteImage?(img)
            return
        }

        if let fileURL = pasteboard.url {
            onPasteFile?(fileURL)
            return
        }

        if pasteboard.hasStrings {
            super.paste(sender)
            return
        }

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
                    print("Failed to write temporary pasted file: \(error)")
                }
                return
            }
        }

        super.paste(sender)
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) {
            return true
        }
        return super.canPerformAction(action, withSender: sender)
    }
}

// MARK: - Active Capability Badge

struct ActiveCapabilityBadge: View {
    let name: String
    let color: Color
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(name)
                .font(.caption2.weight(.medium))
                .foregroundColor(.primary)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
                .overlay(
                    Capsule()
                        .stroke(color.opacity(0.25), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Main SwiftChat-Native Composer View

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
    @State private var voiceExpanded = false
    @State private var showImagePicker = false
    @State private var showCameraPicker = false
    @State private var showDocumentPicker = false
    @State private var showManageModelsSheet = false
    @State private var selectedViewImage: UIImage?
    @State private var isImageViewerPresented: Bool = false
    @State private var isSelect = false
    @State private var textEditorHeight: CGFloat = 38
    @State private var debounceWorkItem: DispatchWorkItem?

    @ScaledMetric(relativeTo: .body) var size_16: CGFloat = 16
    @ScaledMetric(relativeTo: .body) var size_40: CGFloat = 40
    @ScaledMetric(relativeTo: .body) var size_80: CGFloat = 80
    let buttonHeight: CGFloat = 36

    private var canSend: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !selectedImages.isEmpty
            || !selectedDocumentURLs.isEmpty
            || !selectedPrompts.isEmpty
    }

    private var hasAttachments: Bool {
        !selectedImages.isEmpty
            || !selectedDocumentURLs.isEmpty
            || !selectedURLs.isEmpty
            || !selectedPrompts.isEmpty
    }

    var body: some View {
        VStack(spacing: 4) {
            // 1. Floating Canvas & Scroll-To-Bottom Buttons
            if (showScrollToBottomButton || (chatRecord.canvas?.content.isEmpty == false)) && !isMultiSelectMode {
                floatingButtonsBar
            }

            // 2. Multi-Select Toolbar OR SwiftChat Liquid Glass Composer
            if isMultiSelectMode {
                multiSelectToolbar
            } else {
                composerContainer
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: ComposerHeightPreferenceKey.self, value: proxy.size.height)
            }
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation {
                    isViewLoaded = true
                }
            }
        }
        .onChange(of: isMultiSelectMode) {
            isViewLoaded = !isMultiSelectMode
        }
    }

    // MARK: - Floating Buttons (Canvas + Scroll To Bottom)

    private var floatingButtonsBar: some View {
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
                    .background(
                        Capsule()
                            .fill(.regularMaterial)
                            .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                            .shadow(color: Color.black.opacity(0.08), radius: 4, y: 2)
                    )
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
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
                        .background(
                            Circle()
                                .fill(.regularMaterial)
                                .overlay(Circle().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                                .shadow(color: Color.black.opacity(0.08), radius: 4, y: 2)
                        )
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .offset(y: isViewLoaded ? 0 : 60)
        .opacity(isViewLoaded ? 1 : 0)
        .padding(.horizontal, 16)
    }

    // MARK: - Multi-Select Toolbar

    private var multiSelectToolbar: some View {
        HStack {
            Button(action: {
                for id in selectedMessageIDs {
                    if let index = chatTemps.firstIndex(where: { $0.id == id }) {
                        context.delete(chatTemps[index])
                        chatTemps.remove(at: index)
                    }
                }
                try? context.save()
                selectedMessageIDs.removeAll()
                isMultiSelectMode = false
                isViewLoaded = true
            }) {
                Image(systemName: "trash.circle.fill")
                    .resizable()
                    .frame(width: size_40, height: size_40)
                    .foregroundColor(selectedMessageIDs.isEmpty ? .gray : .hlRed)
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
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                .shadow(color: Color.black.opacity(0.06), radius: 8, y: 2)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 3)
    }

    // MARK: - SwiftChat Multiline Liquid Glass Composer

    private var composerContainer: some View {
        VStack(spacing: 6) {
            // Parameter Pickers (when toggled via + menu)
            parameterPickersSection

            // Model Suggestions (@ Mention)
            if showModelSuggestions && !filteredModels.isEmpty {
                modelSuggestionSection
            }

            // Attachment Previews Strip
            if hasAttachments {
                attachmentTray
            }

            // External Accessory Bar: Model Selector + Compact Capability Summary
            composerAccessoryBar
                .padding(.horizontal, 4)

            // Main Liquid Glass Input Capsule (uncluttered input row only)
            HStack(alignment: .bottom, spacing: 8) {
                // + Menu (Attachments & Contextual Advanced Tools)
                plusAttachmentMenu

                // Multiline Auto-Growing Input
                NativeMultilineTextEditor(
                    text: $message,
                    textHeight: $textEditorHeight,
                    placeholderText: String(localized: "Message"),
                    minHeight: 38,
                    maxHeight: 140,
                    onPasteImage: { img in selectedImages.append(img) },
                    onPasteFile: { url in selectedDocumentURLs.append(url) },
                    onSendMessage: { handleSend() },
                    onMentionTriggered: { updateModelSuggestions() }
                )
                .accessibilityIdentifier("hanlin-chat-input")
                .frame(height: textEditorHeight)
                .focused(isInputActive)
                .onChange(of: message) {
                    handleMessageChange()
                }

                // Voice Input
                Button(action: {
                    isFeedBack.toggle()
                    voiceExpanded = true
                }) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color.secondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.impact, trigger: isFeedBack)

                // Send / Stop Button
                sendOrStopButton
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                if #available(iOS 26, *) {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.regularMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                        )
                        .shadow(color: Color.black.opacity(0.06), radius: 8, y: 2)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .offset(y: isViewLoaded ? 0 : 60)
        .opacity(isViewLoaded ? 1 : 0)
        .animation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0.4), value: isViewLoaded)
        .sheet(isPresented: $voiceExpanded) {
            VoiceInputView(message: $message, voiceExpanded: $voiceExpanded)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCameraPicker) {
            ImagePicker(selectedImages: $selectedImages, sourceType: .camera, maxImageNumber: 5)
                .background(.black)
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImages: $selectedImages, sourceType: .photoLibrary, maxImageNumber: 5)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPicker(selectedDocumentURLs: $selectedDocumentURLs)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $isImageViewerPresented) {
            if let img = selectedViewImage {
                ImageViewer(image: img, isPresented: $isImageViewerPresented)
            }
        }
        .sheet(isPresented: $showManageModelsSheet) {
            ModelMenuSheetView(
                models: modelTemp,
                selectedModelIndex: $selectedModelIndex,
                onSelectModel: { idx in
                    onSelectModel(idx)
                    showManageModelsSheet = false
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

    // MARK: - Plus (+) Menu: Attachments & Contextual Tools

    private var plusAttachmentMenu: some View {
        Menu {
            Section(String(localized: "添加附件")) {
                Button {
                    isFeedBack.toggle()
                    showCameraPicker = true
                } label: {
                    Label(String(localized: "拍照"), systemImage: "camera")
                }

                Button {
                    isFeedBack.toggle()
                    showImagePicker = true
                } label: {
                    Label(String(localized: "相册选择"), systemImage: "photo.on.rectangle")
                }

                Button {
                    isFeedBack.toggle()
                    showDocumentPicker = true
                } label: {
                    Label(String(localized: "文件文档"), systemImage: "doc")
                }
                .disabled(selectedDocumentURLs.count >= 5)
            }

            Section(String(localized: "智能工具 (Contextual Tools)")) {
                Button {
                    isFeedBack.toggle()
                    ifSearch.toggle()
                } label: {
                    Label(
                        ifSearch ? String(localized: "网页搜索 (开启)") : String(localized: "网页搜索"),
                        systemImage: ifSearch ? "checkmark.circle.fill" : "globe"
                    )
                }

                Button {
                    isFeedBack.toggle()
                    ifThink.toggle()
                } label: {
                    Label(
                        ifThink ? String(localized: "深度思考 (开启)") : String(localized: "深度思考"),
                        systemImage: ifThink ? "checkmark.circle.fill" : "brain"
                    )
                }

                Button {
                    isFeedBack.toggle()
                    ifKnowledge.toggle()
                } label: {
                    Label(
                        ifKnowledge ? String(localized: "知识库 (开启)") : String(localized: "知识库"),
                        systemImage: ifKnowledge ? "checkmark.circle.fill" : "backpack"
                    )
                }

                Button {
                    isFeedBack.toggle()
                    ifToolUse.toggle()
                } label: {
                    Label(
                        ifToolUse ? String(localized: "工具/MCP (开启)") : String(localized: "工具/MCP"),
                        systemImage: ifToolUse ? "checkmark.circle.fill" : "hammer"
                    )
                }

                Button {
                    isFeedBack.toggle()
                    ifPlanning.toggle()
                } label: {
                    Label(
                        ifPlanning ? String(localized: "规划模式 (开启)") : String(localized: "规划模式"),
                        systemImage: ifPlanning ? "checkmark.circle.fill" : "list.bullet.clipboard"
                    )
                }

                Button {
                    isFeedBack.toggle()
                    ifAudio.toggle()
                } label: {
                    Label(
                        ifAudio ? String(localized: "语音输出 (开启)") : String(localized: "语音输出"),
                        systemImage: ifAudio ? "checkmark.circle.fill" : "speaker.wave.2"
                    )
                }
            }

            Section(String(localized: "高级参数")) {
                Button {
                    showTemperatureSlider.toggle()
                } label: {
                    Label(String(localized: "温度设置"), systemImage: "slider.horizontal.3")
                }

                Button {
                    showTopPSlider.toggle()
                } label: {
                    Label(String(localized: "Top-P 设置"), systemImage: "slider.horizontal.below.rectangle")
                }

                Button {
                    showMaxTokensSlider.toggle()
                } label: {
                    Label(String(localized: "最大 Token 数"), systemImage: "character.textbox")
                }

                Button {
                    showMaxMessagesNumSlider.toggle()
                } label: {
                    Label(String(localized: "最大上下文消息数"), systemImage: "number")
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(TemporaryRecord ? .primary : Color.hlBluefont)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.secondary.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Send / Stop Button

    private var sendOrStopButton: some View {
        Group {
            if isResponding {
                Button(action: onCancel) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "停止生成"))
                .accessibilityIdentifier("hanlin-chat-stop")
            } else {
                Button(action: handleSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(canSend ? (TemporaryRecord ? .primary : Color.hlBlue) : Color.secondary.opacity(0.3))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel(String(localized: "发送消息"))
                .accessibilityIdentifier("hanlin-chat-send")
            }
        }
    }

    // MARK: - External Composer Accessory Bar: Model Selector + Compact Capability Summary

    private var activeCapabilityItems: [(id: String, name: String, icon: String, color: Color)] {
        var items: [(id: String, name: String, icon: String, color: Color)] = []
        if ifSearch {
            items.append(("search", String(localized: "搜索"), "globe", .hlAzure))
        }
        if ifThink {
            items.append(("think", String(localized: "思考"), "brain", .hlPurple))
        }
        if ifKnowledge {
            items.append(("knowledge", String(localized: "知识库"), "backpack", .hlBluefont))
        }
        if ifToolUse {
            items.append(("tools", String(localized: "工具"), "hammer", .hlBrown))
        }
        if ifPlanning {
            items.append(("planning", String(localized: "规划"), "list.bullet.clipboard", .hlIndigo))
        }
        if ifAudio {
            items.append(("audio", String(localized: "语音"), "speaker.wave.2", .hlPink))
        }
        return items
    }

    private var composerAccessoryBar: some View {
        HStack(spacing: 8) {
            modelSelectorCapsule
                .layoutPriority(1)

            Spacer(minLength: 6)

            if !activeCapabilityItems.isEmpty {
                Menu {
                    ForEach(activeCapabilityItems, id: \.id) { item in
                        Button {
                            isFeedBack.toggle()
                            switch item.id {
                            case "search": ifSearch = false
                            case "think": ifThink = false
                            case "knowledge": ifKnowledge = false
                            case "tools": ifToolUse = false
                            case "planning": ifPlanning = false
                            case "audio": ifAudio = false
                            default: break
                            }
                        } label: {
                            Label(
                                "\(item.name) (\(String(localized: "点击关闭")))",
                                systemImage: item.icon
                            )
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        ForEach(activeCapabilityItems.prefix(4), id: \.id) { item in
                            Image(systemName: item.icon)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(item.color)
                        }
                        if activeCapabilityItems.count == 1, let first = activeCapabilityItems.first {
                            Text(first.name)
                                .font(.caption2.weight(.medium))
                                .foregroundColor(first.color)
                                .lineLimit(1)
                        } else {
                            Text("\(activeCapabilityItems.count)")
                                .font(.caption2.monospacedDigit().weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                Capsule()
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                            )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("hanlin-active-capabilities-pill")
            }

            if respondIndex > 0 && message.isEmpty && !isResponding {
                Button(action: onSendObserve) {
                    Text(String(localized: "继续生成"))
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Capsule()
                                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Model Selector Capsule

    private var modelSelectorCapsule: some View {
        let visibleIndices = modelTemp.indices.filter { !modelTemp[$0].isHidden }
        let currentModelIndex: Int = {
            if modelTemp.indices.contains(selectedModelIndex) && !modelTemp[$selectedModelIndex.wrappedValue].isHidden {
                return selectedModelIndex
            }
            return visibleIndices.first ?? 0
        }()
        let currentModel = modelTemp.indices.contains(currentModelIndex) ? modelTemp[currentModelIndex] : nil

        return Menu {
            let topIndices = Array(visibleIndices.prefix(8))
            ForEach(topIndices, id: \.self) { index in
                let m = modelTemp[index]
                Button {
                    isSelect.toggle()
                    onSelectModel(index)
                } label: {
                    HStack {
                        Text(m.displayName ?? m.name ?? String(localized: "未知"))
                        if index == selectedModelIndex {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            Divider()

            Button {
                showManageModelsSheet = true
            } label: {
                Label(String(localized: "选择与添加模型..."), systemImage: "square.stack.3d.up")
            }
        } label: {
            HStack(spacing: 5) {
                if let model = currentModel {
                    if model.identity == "model" {
                        Image(getCompanyIcon(for: model.company ?? "Unknown"))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: model.icon ?? "circle.dotted.circle")
                            .font(.system(size: 11))
                    }
                    Text(model.displayName ?? model.name ?? "Model")
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(String(localized: "选择模型"))
                        .font(.caption.weight(.medium))
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundColor(.primary.opacity(0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("hanlin-model-selector")
    }

    // MARK: - Attachment Previews Strip

    private var attachmentTray: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Images
                ForEach(selectedImages.indices, id: \.self) { idx in
                    HStack(spacing: 4) {
                        Image(uiImage: selectedImages[idx])
                            .resizable()
                            .scaledToFill()
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .onTapGesture {
                                selectedViewImage = selectedImages[idx]
                                isImageViewerPresented = true
                            }
                        Button {
                            selectedImages.remove(at: idx)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(4)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
                }

                // Documents
                ForEach(selectedDocumentURLs.indices, id: \.self) { idx in
                    let url = selectedDocumentURLs[idx]
                    HStack(spacing: 4) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                        Text(url.lastPathComponent)
                            .font(.caption2)
                            .lineLimit(1)
                        Button {
                            selectedDocumentURLs.remove(at: idx)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
                }

                // URLs
                ForEach(selectedURLs.indices, id: \.self) { idx in
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.system(size: 12))
                            .foregroundColor(.accentColor)
                        Text(selectedURLs[idx])
                            .font(.caption2)
                            .lineLimit(1)
                        Button {
                            selectedURLs.remove(at: idx)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
                }

                // Prompts
                ForEach(selectedPrompts.indices, id: \.self) { idx in
                    HStack(spacing: 4) {
                        Image(systemName: "text.bubble.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.purple)
                        Text(selectedPrompts[idx].name ?? "Prompt")
                            .font(.caption2)
                            .lineLimit(1)
                        Button {
                            selectedPrompts.remove(at: idx)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Parameter Pickers Section

    @ViewBuilder
    private var parameterPickersSection: some View {
        VStack {
            if showTemperatureSlider {
                TemperaturePicker(value: $temperature)
                    .onChange(of: temperature) {
                        chatRecord.temperature = temperature
                        try? context.save()
                    }
            }
            if showTopPSlider {
                TopPPicker(value: $topP)
                    .onChange(of: topP) {
                        chatRecord.topP = topP
                        try? context.save()
                    }
            }
            if showMaxTokensSlider {
                MaxTokensPicker(value: $maxTokens)
                    .onChange(of: maxTokens) {
                        chatRecord.maxTokens = maxTokens
                        try? context.save()
                    }
            }
            if showMaxMessagesNumSlider {
                MaxMessagesNumPicker(value: $maxMessagesNum)
                    .onChange(of: maxMessagesNum) {
                        chatRecord.maxMessagesNum = maxMessagesNum
                        try? context.save()
                    }
            }
        }
        .transition(.move(edge: .top))
    }

    // MARK: - Model Suggestions (@ Mention)

    private var modelSuggestionSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(filteredModels, id: \.id) { model in
                    Button {
                        if let range = message.range(of: "@[^\\s]*$", options: .regularExpression) {
                            message.replaceSubrange(range, with: "@\(model.displayName ?? model.name ?? "未知") ")
                        }
                        showModelSuggestions = false
                        isFeedBack.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "at")
                                .font(.caption2)
                                .foregroundColor(TemporaryRecord ? .primary : .hlBluefont)
                            Text(model.displayName ?? model.name ?? "Unknown")
                                .font(.caption2.weight(.medium))
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.regularMaterial))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: - Handlers

    private func handleSend() {
        guard canSend else { return }
        onSendUser()
    }

    private func handleMessageChange() {
        debounceWorkItem?.cancel()
        debounceWorkItem = DispatchWorkItem {
            updateModelSuggestions()
            if !TemporaryRecord {
                chatRecord.input = message
                try? context.save()
            }
            extractURLs(from: message)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: debounceWorkItem!)
    }

    private func updateModelSuggestions() {
        if let range = message.range(of: "@[^\\s]*$", options: .regularExpression) {
            let query = String(message[range]).dropFirst()
            if query.isEmpty {
                filteredModels = Array(modelTemp.prefix(8))
            } else {
                filteredModels = modelTemp.filter { model in
                    let name = model.displayName ?? model.name ?? ""
                    return name.localizedCaseInsensitiveContains(query)
                }
                filteredModels = Array(filteredModels.prefix(8))
            }
            showModelSuggestions = true
        } else {
            showModelSuggestions = false
            filteredModels = []
        }
    }

    private func extractURLs(from text: String) {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return }
        let matches = detector.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
        let extractedURLs = Set(matches.compactMap { match -> String? in
            if let range = Range(match.range, in: text) {
                return String(text[range])
            }
            return nil
        })
        DispatchQueue.main.async {
            self.selectedURLs = Array(extractedURLs).sorted()
        }
    }
}

// MARK: - Model Menu Sheet View (Preserved Verbatim for Model Management)

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

                            VStack(alignment: .leading, spacing: 4) {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    Text(model.displayName ?? "Unknown")
                                        .font(.subheadline)
                                        .foregroundColor(isSelected ? (TemporaryRecord ? .primary : .hlBluefont) : .primary)
                                }

                                HStack(spacing: 6) {
                                    if model.supportsToolUse {
                                        Text(String(localized: "工具"))
                                            .font(.caption)
                                            .foregroundColor(ifToolUse ? .hlBrown : .gray)
                                    }

                                    if model.supportsMultimodal {
                                        Text(String(localized: "视觉"))
                                            .font(.caption)
                                            .foregroundColor(.hlTeal)
                                    } else if model.supportsTextGen {
                                        Text(String(localized: "文本"))
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }

                                    if model.supportsImageGen {
                                        Text(String(localized: "生图"))
                                            .font(.caption)
                                            .foregroundColor(.hlOrange)
                                    }
                                }
                            }
                            .padding(.leading, 8)

                            Spacer()

                            if isSelected {
                                Image(systemName: "checkmark")
                                    .foregroundColor(TemporaryRecord ? .primary : .hlBluefont)
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "选择模型"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: String(localized: "搜索模型名称"))
        }
    }
}
