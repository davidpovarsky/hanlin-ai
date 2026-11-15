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
    var usesAutomaticLineLimits = false
    var onPasteImage: ((UIImage) -> Void)?
    var onPasteFile: ((URL) -> Void)?
    var onSendMessage: (() -> Void)?
    var onMentionTriggered: (() -> Void)?
    var onFocusChange: ((Bool) -> Void)? = nil

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

    static func automaticHeightBounds(for textView: UITextView, isEmpty: Bool, availableHeight: CGFloat) -> (min: CGFloat, max: CGFloat) {
        let font = textView.font ?? UIFont.preferredFont(forTextStyle: .body)
        let insets = textView.textContainerInset.top + textView.textContainerInset.bottom
        // This is only the one/two-line minimum. The six-line maximum comes
        // from actual visual fragments in automaticLimit, not this estimate.
        let sample = NSAttributedString(string: isEmpty ? "M" : "M\nM", attributes: [.font: font])
        let sampleHeight = sample.boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil
        ).height
        let available = max(0, availableHeight)
        let minimum = min(available, ceil(insets + sampleHeight))
        return (minimum, isEmpty ? minimum : available)
    }

    /// Accept only ordered, contiguous document coverage. An empty final range
    /// can represent the legitimate extra line after the document end.
    static func hasContiguousCoverage(_ ranges: [Range<Int>], documentLength: Int) -> Bool {
        guard documentLength >= 0, !ranges.isEmpty else { return false }
        var expected = 0
        var sawExtra = false
        for range in ranges {
            guard range.lowerBound == expected, range.upperBound <= documentLength, !sawExtra else { return false }
            if range.isEmpty {
                guard expected == documentLength else { return false }
                sawExtra = true
            } else {
                expected = range.upperBound
            }
        }
        return expected == documentLength
    }

    /// Reads visual line fragments without switching a TextKit 2 editor to TextKit 1.
    static func visualLineLimit(for textView: UITextView) -> (count: Int, sixthBottom: CGFloat?, complete: Bool) {
        var count = 0
        var sixthBottom: CGFloat?
        if let manager = textView.textLayoutManager {
            guard let content = manager.textContentManager else { return (0, nil, false) }
            let document = content.documentRange
            let documentLength = content.offset(from: document.location, to: document.endLocation)
            guard documentLength >= 0 else { return (0, nil, false) }
            var ranges: [Range<Int>] = []
            var validRanges = true
            var lastBottom: CGFloat = 0
            manager.enumerateTextLayoutFragments(from: nil, options: [.ensuresLayout, .ensuresExtraLineFragment]) { fragment in
                let range = fragment.rangeInElement
                let start = content.offset(from: document.location, to: range.location)
                let end = content.offset(from: document.location, to: range.endLocation)
                guard start >= 0, end >= start, end <= documentLength else {
                    validRanges = false
                    return false
                }
                ranges.append(start..<end)
                guard start == end || !fragment.textLineFragments.isEmpty else {
                    validRanges = false
                    return false
                }
                for line in fragment.textLineFragments {
                    let bottom = fragment.layoutFragmentFrame.minY + line.typographicBounds.maxY
                    guard bottom.isFinite, bottom >= lastBottom else {
                        validRanges = false
                        return false
                    }
                    lastBottom = bottom
                    if count < 7 { count += 1 }
                    if count == 6 {
                        sixthBottom = bottom
                    }
                }
                return true
            }
            guard validRanges, Self.hasContiguousCoverage(ranges, documentLength: documentLength) else { return (0, nil, false) }
        } else {
            // Access only when the view is already using TextKit 1.
            let manager = textView.layoutManager
            manager.ensureLayout(for: textView.textContainer)
            let glyphs = manager.glyphRange(for: textView.textContainer)
            guard glyphs.location == 0 else { return (0, nil, false) }
            manager.enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, _, stop in
                count += 1
                if count == 6 { sixthBottom = rect.maxY }
                if count >= 7 { stop.pointee = true }
            }
            if count < 7 && NSMaxRange(glyphs) < manager.numberOfGlyphs {
                return (0, nil, false)
            }
            if count < 7 && manager.extraLineFragmentTextContainer === textView.textContainer {
                count += 1
                if count == 6 { sixthBottom = manager.extraLineFragmentRect.maxY }
            }
        }
        return (count, sixthBottom, true)
    }

    static func automaticLimit(
        fittingHeight: CGFloat, availableHeight: CGFloat, minimumHeight: CGFloat,
        verticalInsets: CGFloat, count: Int, sixthBottom: CGFloat?, complete: Bool
    ) -> (maximum: CGFloat, forceScroll: Bool) {
        guard complete && count > 0 else { return (minimumHeight, true) }
        if count <= 6 { return (min(max(0, availableHeight), max(minimumHeight, fittingHeight)), false) }
        guard let bottom = sixthBottom else { return (minimumHeight, true) }
        return (min(max(0, availableHeight), max(minimumHeight, ceil(bottom + verticalInsets))), false)
    }

    struct MeasurementTrace {
        let fitting: CGFloat
        let minimum: CGFloat
        let maximum: CGFloat
        let lineCount: Int?
        let sixthBottom: CGFloat?
        let complete: Bool?
        let forcedScroll: Bool
        let height: CGFloat
        let scrolling: Bool
    }

    func measuredHeight(for textView: UITextView, isEmpty: Bool,
                        observeMeasurement: ((MeasurementTrace) -> Void)? = nil) -> CGFloat {
        let width = Self.effectiveMeasurementWidth(for: textView)
        let fitting = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        var bounds = usesAutomaticLineLimits
            ? Self.automaticHeightBounds(for: textView, isEmpty: isEmpty, availableHeight: maxHeight)
            : (min: minHeight, max: max(minHeight, maxHeight))
        var incompleteLayout = false
        var measuredLines: (count: Int, sixthBottom: CGFloat?, complete: Bool)? = nil
        if usesAutomaticLineLimits && !isEmpty {
            let lines = Self.visualLineLimit(for: textView)
            measuredLines = lines
            let limit = Self.automaticLimit(fittingHeight: fitting, availableHeight: maxHeight, minimumHeight: bounds.min,
                verticalInsets: textView.textContainerInset.top + textView.textContainerInset.bottom,
                count: lines.count, sixthBottom: lines.sixthBottom, complete: lines.complete)
            bounds.max = limit.maximum
            incompleteLayout = limit.forceScroll
        }
        textView.isScrollEnabled = !isEmpty && (incompleteLayout || Self.shouldScrollInternally(fittingHeight: fitting, maxHeight: bounds.max))
        let height = Self.calculatedHeight(fittingHeight: fitting, minHeight: bounds.min, maxHeight: bounds.max)
        observeMeasurement?(.init(fitting: fitting, minimum: bounds.min, maximum: bounds.max,
            lineCount: measuredLines?.count, sixthBottom: measuredLines?.sixthBottom,
            complete: measuredLines?.complete, forcedScroll: incompleteLayout, height: height,
            scrolling: textView.isScrollEnabled))
        return height
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
        textView.adjustsFontForContentSizeCategory = true
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

        let clampedHeight = measuredHeight(for: uiView, isEmpty: text.isEmpty)
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
            parent.onFocusChange?(true)
            if textView.textColor == .placeholderText {
                textView.text = ""
                textView.textColor = .label
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isEditing = false
            parent.onFocusChange?(false)
            if parent.text.isEmpty {
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
                let clampedHeight = parent.measuredHeight(for: textView, isEmpty: textView.text.isEmpty)
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
