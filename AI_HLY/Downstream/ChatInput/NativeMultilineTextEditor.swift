//
//  NativeMultilineTextEditor.swift
//  AI_HLY
//
//  Native multiline UITextView-backed composer editor embedded inside the
//  original BLUE ChatViewBottom.swift shell.
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ComposerHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct NativeMultilineTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var textHeight: CGFloat
    var placeholderText: String = String(localized: "Message")
    var minHeight: CGFloat = 38
    var maxHeight: CGFloat = 140
    var onPasteImage: ((UIImage) -> Void)?
    var onPasteFile: ((URL) -> Void)?
    var onSendMessage: (() -> Void)?
    var onMentionTriggered: (() -> Void)?

    static let mentionRegex = try! NSRegularExpression(pattern: "@[^\\s]+", options: [])

    static func calculatedHeight(
        fittingHeight: CGFloat,
        minHeight: CGFloat = 38,
        maxHeight: CGFloat = 140
    ) -> CGFloat {
        min(maxHeight, max(minHeight, fittingHeight))
    }

    static func shouldScrollInternally(
        fittingHeight: CGFloat,
        maxHeight: CGFloat = 140
    ) -> Bool {
        fittingHeight > maxHeight
    }

    static func effectiveMeasurementWidth(for textView: UITextView, fallbackWidth: CGFloat = 240) -> CGFloat {
        let boundsWidth = textView.bounds.width
        if boundsWidth > 20 {
            return boundsWidth
        }
        let frameWidth = textView.frame.width
        if frameWidth > 20 {
            return frameWidth
        }
        return fallbackWidth
    }

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

        guard uiView.markedTextRange == nil else { return }

        let isEditing = context.coordinator.isEditing

        if text.isEmpty && !isEditing {
            uiView.text = placeholderText
            uiView.textColor = .placeholderText
        } else if !text.isEmpty && uiView.textColor == .placeholderText {
            uiView.text = text
            uiView.textColor = .label
        } else if uiView.textColor != .placeholderText && uiView.text != text && !isEditing {
            uiView.text = text
        }

        let targetWidth = Self.effectiveMeasurementWidth(for: uiView)
        let fittingSize = uiView.sizeThatFits(
            CGSize(width: targetWidth, height: .greatestFiniteMagnitude)
        )
        let clampedHeight = Self.calculatedHeight(
            fittingHeight: fittingSize.height,
            minHeight: minHeight,
            maxHeight: maxHeight
        )
        uiView.isScrollEnabled = Self.shouldScrollInternally(
            fittingHeight: fittingSize.height,
            maxHeight: maxHeight
        )
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
            guard textView.markedTextRange == nil else { return }
            if textView.textColor != .placeholderText {
                parent.text = textView.text
                if textView.text.hasSuffix("@") {
                    parent.onMentionTriggered?()
                }
                let targetWidth = NativeMultilineTextEditor.effectiveMeasurementWidth(for: textView)
                let fittingSize = textView.sizeThatFits(
                    CGSize(width: targetWidth, height: .greatestFiniteMagnitude)
                )
                let clampedHeight = NativeMultilineTextEditor.calculatedHeight(
                    fittingHeight: fittingSize.height,
                    minHeight: parent.minHeight,
                    maxHeight: parent.maxHeight
                )
                textView.isScrollEnabled = NativeMultilineTextEditor.shouldScrollInternally(
                    fittingHeight: fittingSize.height,
                    maxHeight: parent.maxHeight
                )
                if abs(parent.textHeight - clampedHeight) > 1 {
                    parent.textHeight = clampedHeight
                }
            }
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            guard text.isEmpty, textView.textColor != .placeholderText else { return true }
            let raw = textView.text ?? ""
            let ns = raw as NSString
            if let match = Self.matchContaining(index: range.location, in: raw) {
                textView.text = ns.replacingCharacters(in: match.range, with: "")
                parent.text = textView.text ?? ""
                return false
            }
            return true
        }

        private static func matchContaining(index: Int, in text: String) -> NSTextCheckingResult? {
            let ns = text as NSString
            let full = NSRange(location: 0, length: ns.length)
            return NativeMultilineTextEditor.mentionRegex
                .matches(in: text, options: [], range: full)
                .first { NSLocationInRange(index, $0.range) }
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
        if !currentText.isEmpty && textColor != .placeholderText {
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
                    print("写入临时文件失败：\(error)")
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
