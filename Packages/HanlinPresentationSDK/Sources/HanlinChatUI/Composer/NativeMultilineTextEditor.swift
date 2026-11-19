#if canImport(UIKit)
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

public struct ComposerHeightPreferenceKey: PreferenceKey {
    public static let defaultValue: CGFloat = 0
    public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

public struct NativeMultilineTextEditor: UIViewRepresentable {
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

    public init(text: Binding<String>, textHeight: Binding<CGFloat>,
                placeholderText: String = String(localized: "Message"),
                minHeight: CGFloat = 38, maxHeight: CGFloat = 140,
                usesAutomaticLineLimits: Bool = false,
                onPasteImage: ((UIImage) -> Void)? = nil,
                onPasteFile: ((URL) -> Void)? = nil,
                onSendMessage: (() -> Void)? = nil,
                onMentionTriggered: (() -> Void)? = nil,
                onFocusChange: ((Bool) -> Void)? = nil) {
        _text = text; _textHeight = textHeight
        self.placeholderText = placeholderText
        self.minHeight = minHeight; self.maxHeight = maxHeight
        self.usesAutomaticLineLimits = usesAutomaticLineLimits
        self.onPasteImage = onPasteImage; self.onPasteFile = onPasteFile
        self.onSendMessage = onSendMessage; self.onMentionTriggered = onMentionTriggered
        self.onFocusChange = onFocusChange
    }

    static let mentionRegex = try! NSRegularExpression(pattern: "@[^\\s]+", options: [])

    public static func calculatedHeight(
        fittingHeight: CGFloat,
        minHeight: CGFloat = 38,
        maxHeight: CGFloat = 140
    ) -> CGFloat {
        min(maxHeight, max(minHeight, fittingHeight))
    }

    public static func shouldScrollInternally(
        fittingHeight: CGFloat,
        maxHeight: CGFloat = 140
    ) -> Bool {
        fittingHeight > maxHeight
    }

    public static func automaticHeightBounds(for textView: UITextView, isEmpty: Bool, availableHeight: CGFloat) -> (min: CGFloat, max: CGFloat) {
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
    public static func hasContiguousCoverage(_ ranges: [Range<Int>], documentLength: Int) -> Bool {
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
    public static func visualLineLimit(for textView: UITextView, fittingHeight: CGFloat? = nil,
                                observeDiagnostic: ((String) -> Void)? = nil) -> (count: Int, sixthBottom: CGFloat?, complete: Bool) {
        var count = 0
        var sixthBottom: CGFloat?
        if let manager = textView.textLayoutManager {
            observeDiagnostic?("TextKit2")
            guard let content = manager.textContentManager else {
                observeDiagnostic?("missing textContentManager")
                return (0, nil, false)
            }
            let document = content.documentRange
            let documentLength = content.offset(from: document.location, to: document.endLocation)
            guard documentLength >= 0 else {
                observeDiagnostic?("negative document length \(documentLength)")
                return (0, nil, false)
            }
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
            guard validRanges, Self.hasContiguousCoverage(ranges, documentLength: documentLength) else {
                observeDiagnostic?("invalid/partial fragments valid=\(validRanges) ranges=\(ranges) documentLength=\(documentLength) counted=\(count)")
                return (0, nil, false)
            }
        } else {
            // Access only when the view is already using TextKit 1.
            observeDiagnostic?("TextKit1")
            let manager = textView.layoutManager
            let container = textView.textContainer
            let priorSize = container.size
            let priorHeightTracking = container.heightTracksTextView
            let expandsForMeasurement = fittingHeight.map { $0.isFinite && $0 > priorSize.height } ?? false
            // sizeThatFits can leave the compatibility container at viewport
            // height after scrolling changes. Give the same native layout enough
            // measured content space to count its lines, then restore its state.
            if expandsForMeasurement, let fittingHeight {
                container.heightTracksTextView = false
                container.size = CGSize(width: priorSize.width, height: fittingHeight)
                observeDiagnostic?("native fitting container height \(priorSize.height) -> \(fittingHeight); priorHeightTracking=\(priorHeightTracking)")
            }
            defer {
                if expandsForMeasurement {
                    container.size = priorSize
                    container.heightTracksTextView = priorHeightTracking
                }
            }
            manager.ensureLayout(for: container)
            let glyphs = manager.glyphRange(for: container)
            guard glyphs.location == 0 else {
                observeDiagnostic?("nonzero first glyph range=\(glyphs) containerSize=\(textView.textContainer.size)")
                return (0, nil, false)
            }
            manager.enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, _, stop in
                count += 1
                if count == 6 { sixthBottom = rect.maxY }
                if count >= 7 { stop.pointee = true }
            }
            if count < 7 && NSMaxRange(glyphs) < manager.numberOfGlyphs {
                observeDiagnostic?("partial container coverage range=\(glyphs) total=\(manager.numberOfGlyphs) counted=\(count) containerSize=\(textView.textContainer.size)")
                return (0, nil, false)
            }
            if count < 7 && manager.extraLineFragmentTextContainer === textView.textContainer {
                count += 1
                if count == 6 { sixthBottom = manager.extraLineFragmentRect.maxY }
            }
        }
        return (count, sixthBottom, true)
    }

    public static func automaticLimit(
        fittingHeight: CGFloat, availableHeight: CGFloat, minimumHeight: CGFloat,
        verticalInsets: CGFloat, count: Int, sixthBottom: CGFloat?, complete: Bool
    ) -> (maximum: CGFloat, forceScroll: Bool) {
        guard complete && count > 0 else { return (minimumHeight, true) }
        if count <= 6 { return (min(max(0, availableHeight), max(minimumHeight, fittingHeight)), false) }
        guard let bottom = sixthBottom else { return (minimumHeight, true) }
        return (min(max(0, availableHeight), max(minimumHeight, ceil(bottom + verticalInsets))), false)
    }

    public struct MeasurementTrace {
        public let fitting: CGFloat
        public let minimum: CGFloat
        public let maximum: CGFloat
        public let lineCount: Int?
        public let sixthBottom: CGFloat?
        public let complete: Bool?
        public let forcedScroll: Bool
        public let height: CGFloat
        public let scrolling: Bool
        public let layoutDiagnostics: [String]
    }

    public func measuredHeight(for textView: UITextView, isEmpty: Bool,
                        observeMeasurement: ((MeasurementTrace) -> Void)? = nil) -> CGFloat {
        let width = Self.effectiveMeasurementWidth(for: textView)
        let fitting = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        var bounds = usesAutomaticLineLimits
            ? Self.automaticHeightBounds(for: textView, isEmpty: isEmpty, availableHeight: maxHeight)
            : (min: minHeight, max: max(minHeight, maxHeight))
        var incompleteLayout = false
        var layoutDiagnostics: [String] = []
        let layoutObserver: ((String) -> Void)? = observeMeasurement.map { _ in
            { detail in layoutDiagnostics.append(detail) }
        }
        var measuredLines: (count: Int, sixthBottom: CGFloat?, complete: Bool)? = nil
        if usesAutomaticLineLimits && !isEmpty {
            let lines = Self.visualLineLimit(for: textView, fittingHeight: fitting, observeDiagnostic: layoutObserver)
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
            scrolling: textView.isScrollEnabled, layoutDiagnostics: layoutDiagnostics))
        return height
    }

    public static func effectiveMeasurementWidth(for textView: UITextView, fallbackWidth: CGFloat = 240) -> CGFloat {
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

    public func makeUIView(context: Context) -> MultilineInnerTextView {
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

    public func updateUIView(_ uiView: MultilineInnerTextView, context: Context) {
        context.coordinator.parent = self
        uiView.onPasteImage = onPasteImage
        uiView.onPasteFile = onPasteFile
        uiView.onSendMessage = onSendMessage

        guard uiView.markedTextRange == nil else { return }

        context.coordinator.synchronizeText(in: uiView)

        let clampedHeight = measuredHeight(for: uiView, isEmpty: text.isEmpty)
        if abs(textHeight - clampedHeight) > 1 {
            DispatchQueue.main.async {
                self.textHeight = clampedHeight
            }
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NativeMultilineTextEditor
        public var isEditing = false
        private var lastSynchronizedModelText: String

        public init(_ parent: NativeMultilineTextEditor) {
            self.parent = parent
            self.lastSynchronizedModelText = parent.text
        }

        /// The binding also receives programmatic sends, restored drafts and
        /// navigation changes while UIKit can still own first responder. Reconcile
        /// those changes without replacing an unchanged selection or marked text.
        public func synchronizeText(in textView: UITextView) {
            guard textView.markedTextRange == nil else { return }
            let incoming = parent.text
            let modelChanged = incoming != lastSynchronizedModelText
            lastSynchronizedModelText = incoming
            let placeholder = incoming.isEmpty && !isEditing
            let desired = placeholder ? parent.placeholderText : incoming
            let wasPlaceholder = textView.textColor == .placeholderText
            // UIKit can have changed its text storage before its delegate publishes
            // the binding. An unrelated SwiftUI layout update must not replay the
            // unchanged model value over that edit and move the insertion point.
            // Actual sends, restored drafts and conversation changes still reconcile.
            let shouldReconcile = modelChanged || wasPlaceholder != placeholder
            if shouldReconcile && (textView.text != desired || (wasPlaceholder && !placeholder)) {
                let selection = textView.selectedRange
                textView.text = desired
                if isEditing {
                    let count = (desired as NSString).length
                    let start = min(selection.location, count)
                    textView.selectedRange = NSRange(location: start,
                        length: min(selection.length, count - start))
                }
            }
            let desiredColor: UIColor = placeholder ? .placeholderText : .label
            if textView.textColor != desiredColor { textView.textColor = desiredColor }
        }

        public func textViewDidBeginEditing(_ textView: UITextView) {
            isEditing = true
            parent.onFocusChange?(true)
            if textView.textColor == .placeholderText {
                textView.text = ""
                textView.textColor = .label
            }
        }

        public func textViewDidEndEditing(_ textView: UITextView) {
            isEditing = false
            parent.onFocusChange?(false)
            if parent.text.isEmpty {
                textView.text = parent.placeholderText
                textView.textColor = .placeholderText
            }
        }

        public func textViewDidChange(_ textView: UITextView) {
            guard textView.markedTextRange == nil else { return }
            if textView.textColor != .placeholderText {
                let nativeText = textView.text ?? ""
                // A later UIKit edit can begin before SwiftUI renders this
                // binding write. Acknowledge it first so that layout cannot
                // mistake our own earlier edit for an external draft change.
                lastSynchronizedModelText = nativeText
                parent.text = nativeText
                if nativeText.hasSuffix("@") {
                    parent.onMentionTriggered?()
                }
                let clampedHeight = parent.measuredHeight(for: textView, isEmpty: textView.text.isEmpty)
                if abs(parent.textHeight - clampedHeight) > 1 {
                    parent.textHeight = clampedHeight
                }
            }
        }

        public func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            guard text.isEmpty, textView.textColor != .placeholderText else { return true }
            let raw = textView.text ?? ""
            let ns = raw as NSString
            if let match = Self.matchContaining(index: range.location, in: raw) {
                textView.text = ns.replacingCharacters(in: match.range, with: "")
                lastSynchronizedModelText = textView.text ?? ""
                parent.text = lastSynchronizedModelText
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

public final class MultilineInnerTextView: UITextView {
    var onPasteImage: ((UIImage) -> Void)?
    var onPasteFile: ((URL) -> Void)?
    var onSendMessage: (() -> Void)?

    public override var keyCommands: [UIKeyCommand]? {
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

    public override func paste(_ sender: Any?) {
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

    public override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) {
            return true
        }
        return super.canPerformAction(action, withSender: sender)
    }
}

#endif
