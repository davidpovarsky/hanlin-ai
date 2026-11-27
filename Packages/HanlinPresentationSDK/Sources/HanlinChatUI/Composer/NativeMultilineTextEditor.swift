import HanlinLocalization
#if canImport(UIKit)
//
//  NativeMultilineTextEditor.swift
//  AI_HLY
//
//  Native multiline UITextView-backed composer editor embedded inside the
//  original BLUE ChatViewBottom.swift shell.
//

import SwiftUI
import HanlinPresentationKit
import UniformTypeIdentifiers
import UIKit

public struct ComposerHeightPreferenceKey: PreferenceKey {
    public static let defaultValue: CGFloat = 0
    public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

public struct NativeMultilineTextEditor: UIViewRepresentable {
    /// One host-owned draft value, with explicit ownership and write identity.
    /// A host changes revision for every authoritative write, including an
    /// explicit clear whose string equals the preceding rendered value.
    public struct TextState: Equatable, Sendable {
        public let ownerID: UUID
        public let revision: UUID
        public let text: String

        public init(ownerID: UUID, revision: UUID, text: String) {
            self.ownerID = ownerID
            self.revision = revision
            self.text = text
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.ownerID == rhs.ownerID && lhs.revision == rhs.revision
                && lhs.text.utf8.elementsEqual(rhs.text.utf8)
        }
    }

    /// One-shot caret placement after an explicit suggestion replacement.
    /// It is accepted only for the matching text and draft owner.
    public struct SelectionRequest: Sendable {
        public let id: UUID
        public let ownerID: UUID?
        public let text: String
        public let range: NSRange

        public init(text: String, range: NSRange, ownerID: UUID? = nil) {
            self.id = UUID()
            self.ownerID = ownerID
            self.text = text
            self.range = range
        }
    }

    /// Reports the existing native view to its owning host without changing text or focus.
    public enum LifecycleEvent: Sendable {
        case attached
        case focusChanged(Bool)
        case detached
    }

    @Binding var text: String
    @Binding var textHeight: CGFloat
    var placeholderText: String = String(localized: "Message", bundle: HanlinLocalization.bundle)
    var minHeight: CGFloat = 38
    var maxHeight: CGFloat = 140
    var usesAutomaticLineLimits = false
    var onPasteImage: ((UIImage) -> Void)?
    var onPasteFile: ((URL) -> Void)?
    var onSendMessage: (() -> Void)?
    var onMentionTriggered: (() -> Void)?
    var onCapabilityQueryChange: ((HanlinComposerCapabilityQuery?) -> Void)?
    var selectionRequest: SelectionRequest?
    var onFocusChange: ((Bool) -> Void)? = nil
    var onLifecycleEvent: ((UITextView, LifecycleEvent) -> Void)? = nil
    /// Optional synchronous read of the same owner mutated by the text Binding.
    /// Hosts that retain bindings across independently rendered views provide
    /// this to avoid replaying a render snapshot over a newer native edit.
    var readCurrentTextState: (() -> TextState?)? = nil

    private var currentTextState: TextState? {
        readCurrentTextState?()
    }

    private var currentText: String {
        currentTextState?.text ?? text
    }

    public init(text: Binding<String>, textHeight: Binding<CGFloat>,
                placeholderText: String = String(localized: "Message", bundle: HanlinLocalization.bundle),
                minHeight: CGFloat = 38, maxHeight: CGFloat = 140,
                usesAutomaticLineLimits: Bool = false,
                onPasteImage: ((UIImage) -> Void)? = nil,
                onPasteFile: ((URL) -> Void)? = nil,
                onSendMessage: (() -> Void)? = nil,
                onMentionTriggered: (() -> Void)? = nil,
                onFocusChange: ((Bool) -> Void)? = nil,
                onLifecycleEvent: ((UITextView, LifecycleEvent) -> Void)? = nil,
                readCurrentTextState: (() -> TextState?)? = nil,
                onCapabilityQueryChange: ((HanlinComposerCapabilityQuery?) -> Void)? = nil,
                selectionRequest: SelectionRequest? = nil) {
        _text = text; _textHeight = textHeight
        self.placeholderText = placeholderText
        self.minHeight = minHeight; self.maxHeight = maxHeight
        self.usesAutomaticLineLimits = usesAutomaticLineLimits
        self.onPasteImage = onPasteImage; self.onPasteFile = onPasteFile
        self.onSendMessage = onSendMessage; self.onMentionTriggered = onMentionTriggered
        self.onFocusChange = onFocusChange
        self.onLifecycleEvent = onLifecycleEvent
        self.readCurrentTextState = readCurrentTextState
        self.onCapabilityQueryChange = onCapabilityQueryChange
        self.selectionRequest = selectionRequest
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
        let font = textView.font ?? HanlinTypography.uiFont(.body)
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
            var expectedStart = 0
            var reachedVisibleLimit = false
            manager.enumerateTextLayoutFragments(from: nil, options: [.ensuresLayout, .ensuresExtraLineFragment]) { fragment in
                let range = fragment.rangeInElement
                let start = content.offset(from: document.location, to: range.location)
                let end = content.offset(from: document.location, to: range.endLocation)
                guard start == expectedStart, end >= start, end <= documentLength else {
                    validRanges = false
                    return false
                }
                ranges.append(start..<end)
                expectedStart = end
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
                    count += 1
                    if count == 6 { sixthBottom = bottom }
                    if count == 7 {
                        // A contiguous prefix with seven native visual lines is
                        // sufficient to cap the editor at six. Do not lay out
                        // and enumerate every following paragraph per keystroke.
                        reachedVisibleLimit = true
                        return false
                    }
                }
                return true
            }
            guard validRanges, reachedVisibleLimit || Self.hasContiguousCoverage(ranges, documentLength: documentLength) else {
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
        let shouldScroll = !isEmpty && (incompleteLayout || Self.shouldScrollInternally(fittingHeight: fitting, maxHeight: bounds.max))
        if textView.isScrollEnabled != shouldScroll {
            textView.isScrollEnabled = shouldScroll
        }
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
        textView.font = HanlinTypography.uiFont(.body)
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
        textView.isUserInteractionEnabled = context.environment.isEnabled

        let initialText = currentText
        if initialText.isEmpty {
            textView.text = placeholderText
            textView.textColor = .placeholderText
        } else {
            textView.text = initialText
            textView.textColor = .label
        }

        onLifecycleEvent?(textView, .attached)
        return textView
    }

    public func updateUIView(_ uiView: MultilineInnerTextView, context: Context) {
        // Honor SwiftUI interaction ownership even while an IME composition is active.
        uiView.isUserInteractionEnabled = context.environment.isEnabled
        context.coordinator.rebind(to: self, in: uiView)
        onLifecycleEvent?(uiView, .attached)
        uiView.onPasteImage = onPasteImage
        uiView.onPasteFile = onPasteFile
        uiView.onSendMessage = onSendMessage

        guard uiView.markedTextRange == nil else { return }

        context.coordinator.synchronizeText(in: uiView)
        context.coordinator.applySelectionRequest(in: uiView)

        context.coordinator.updateHeight(in: uiView, deferred: true)
    }

    public static func dismantleUIView(_ uiView: MultilineInnerTextView, coordinator: Coordinator) {
        coordinator.detach()
        coordinator.parent.onLifecycleEvent?(uiView, .detached)
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public final class Coordinator: NSObject, UITextViewDelegate {
        private struct PendingVersionedEcho {
            let ownerID: UUID
            let baselineRevision: UUID
            let publishedText: String
        }

        var parent: NativeMultilineTextEditor
        public var isEditing = false
        private var lastSynchronizedModelText: String
        private var lastSynchronizedTextState: TextState?
        private var pendingVersionedEcho: PendingVersionedEcho?
        private var isRebindingOwner = false
        private var isSynchronizingText = false
        private var appliedSelectionRequestID: UUID?
        private var isAttached = true
        private var measurementGeneration: UInt64 = 0
        private var heightUpdateTask: Task<Void, Never>?
        private struct MeasurementKey: Equatable {
            let generation: UInt64
            let width: CGFloat
            let minimum: CGFloat
            let maximum: CGFloat
            let automatic: Bool
            let isEmpty: Bool
            let font: UIFont?
            let insets: UIEdgeInsets
        }
        private var cachedMeasurement: (key: MeasurementKey, height: CGFloat, scrolling: Bool)?

        private func measurementKey(for textView: UITextView) -> MeasurementKey {
            MeasurementKey(generation: measurementGeneration,
                width: NativeMultilineTextEditor.effectiveMeasurementWidth(for: textView),
                minimum: parent.minHeight, maximum: parent.maxHeight,
                automatic: parent.usesAutomaticLineLimits,
                isEmpty: textView.textColor == .placeholderText || (textView.text ?? "").isEmpty,
                font: textView.font, insets: textView.textContainerInset)
        }

        private func invalidateMeasurement() {
            measurementGeneration &+= 1
            cachedMeasurement = nil
            heightUpdateTask?.cancel()
            heightUpdateTask = nil
        }

        fileprivate func detach() {
            isAttached = false
            invalidateMeasurement()
        }

        /// A native edit and its SwiftUI acknowledgement share one measurement.
        /// Unrelated streaming/tool updates cannot force the same TextKit layout.
        fileprivate func updateHeight(in textView: UITextView, deferred: Bool) {
            let key = measurementKey(for: textView)
            let height: CGFloat
            if let cachedMeasurement, cachedMeasurement.key == key {
                height = cachedMeasurement.height
                if textView.isScrollEnabled != cachedMeasurement.scrolling {
                    textView.isScrollEnabled = cachedMeasurement.scrolling
                }
            } else {
                height = parent.measuredHeight(for: textView, isEmpty: key.isEmpty)
                cachedMeasurement = (key, height, textView.isScrollEnabled)
            }
            heightUpdateTask?.cancel()
            heightUpdateTask = nil
            guard abs(parent.textHeight - height) > 1 else { return }
            if !deferred {
                parent.textHeight = height
                return
            }
            // Never write SwiftUI state during updateUIView. Re-check the native
            // owner/layout after yielding so an old measurement cannot resize a
            // replacement conversation, or a view already removed from the tree.
            heightUpdateTask = Task { @MainActor [weak self, weak textView] in
                await Task.yield()
                guard !Task.isCancelled, let self, let textView, self.isAttached,
                      self.measurementKey(for: textView) == key else { return }
                if abs(self.parent.textHeight - height) > 1 { self.parent.textHeight = height }
                self.heightUpdateTask = nil
            }
        }
        #if DEBUG || HANLIN_TESTING
        private let editDiagnosticsEnabled = ProcessInfo.processInfo.environment["HANLIN_COMPOSER_EDIT_DIAGNOSTICS"] == "1"
        private var editDiagnosticSequence = 0
        private let editDiagnosticID = UUID().uuidString

        /// Opt-in native acceptance trace. Never includes text, prompts or hashes.
        private func traceEdit(_ event: String, in textView: UITextView,
                               detail: String = "") {
            guard editDiagnosticsEnabled, editDiagnosticSequence < 512 else { return }
            editDiagnosticSequence += 1
            let native = textView.text ?? ""
            let model = parent.currentText
            let selection = textView.selectedRange
            print("HANLIN_COMPOSER_EDIT id=\(editDiagnosticID) nativeID=\(ObjectIdentifier(textView)) sequence=\(editDiagnosticSequence) event=\(event) nativeUTF16=\(native.utf16.count) modelUTF16=\(model.utf16.count) renderedUTF16=\(parent.text.utf16.count) synchronizedUTF16=\(lastSynchronizedModelText.utf16.count) nativeEqualsModel=\(native.utf8.elementsEqual(model.utf8)) selection=\(selection.location):\(selection.length) editing=\(isEditing) firstResponder=\(textView.isFirstResponder) marked=\(textView.markedTextRange != nil) \(detail)")
        }
        #endif

        public init(_ parent: NativeMultilineTextEditor) {
            self.parent = parent
            let state = parent.currentTextState
            self.lastSynchronizedTextState = state
            self.lastSynchronizedModelText = state?.text ?? parent.text
        }

        /// Keep one native editor and its focus while changing the draft owner.
        /// A pending edit belongs to the old owner even when A and B contain
        /// identical strings. An intervening authoritative write wins over it.
        public func rebind(to newParent: NativeMultilineTextEditor, in textView: UITextView) {
            isAttached = true
            let oldOwner = parent.currentTextState?.ownerID
            let newOwner = newParent.currentTextState?.ownerID
            guard oldOwner != newOwner else {
                parent = newParent
                return
            }

            isRebindingOwner = true
            invalidateMeasurement()
            defer { isRebindingOwner = false }
            // UIKit's unmarkText finishes the existing composition. Keep its
            // original owner installed until the native value is committed.
            if textView.markedTextRange != nil {
                textView.unmarkText()
            }
            if isEditing, textView.textColor != .placeholderText,
               ownerMatchesLastSynchronization() {
                publishNativeTextIfChanged(textView.text ?? "")
            }
            pendingVersionedEcho = nil
            parent = newParent
            synchronizeText(in: textView)
        }

        private func ownerMatchesLastSynchronization() -> Bool {
            let state = parent.currentTextState
            if let pending = pendingVersionedEcho, let state {
                if state.ownerID == pending.ownerID && state.revision == pending.baselineRevision {
                    return true
                }
                pendingVersionedEcho = nil
            }
            return state == lastSynchronizedTextState
                && (state?.text ?? parent.text).utf8.elementsEqual(lastSynchronizedModelText.utf8)
        }

        @discardableResult
        private func publishNativeTextIfChanged(_ nativeText: String) -> Bool {
            let beforeState = parent.currentTextState
            let changed = !nativeText.utf8.elementsEqual(parent.currentText.utf8)
            // Acknowledge before the binding write, which can invalidate a
            // rendered view synchronously. The state is then read from the
            // same owner; no render acknowledgement or timer is involved.
            lastSynchronizedModelText = nativeText
            if changed { parent.text = nativeText }
            let afterState = parent.currentTextState
            if let beforeState, let afterState,
               changed,
               beforeState.ownerID == afterState.ownerID,
               beforeState.revision == afterState.revision,
               !afterState.text.utf8.elementsEqual(nativeText.utf8) {
                pendingVersionedEcho = PendingVersionedEcho(
                    ownerID: afterState.ownerID,
                    baselineRevision: afterState.revision,
                    publishedText: nativeText
                )
            } else {
                pendingVersionedEcho = nil
            }
            lastSynchronizedTextState = afterState
            return changed
        }

        /// The binding also receives programmatic sends, restored drafts and
        /// navigation changes while UIKit can still own first responder. Reconcile
        /// those changes without replacing an unchanged selection or marked text.
        public func synchronizeText(in textView: UITextView) {
            guard textView.markedTextRange == nil else { return }
            isSynchronizingText = true
            defer { isSynchronizingText = false }
            let incomingState = parent.currentTextState
            if let pending = pendingVersionedEcho {
                if let incomingState,
                   incomingState.ownerID == pending.ownerID,
                   incomingState.revision == pending.baselineRevision,
                   isEditing,
                   textView.textColor != .placeholderText {
                    #if DEBUG || HANLIN_TESTING
                    traceEdit("model-pending-versioned-echo", in: textView)
                    #endif
                    return
                }
                pendingVersionedEcho = nil
            }
            let incoming = incomingState?.text ?? parent.text
            let modelChanged = !incoming.utf8.elementsEqual(lastSynchronizedModelText.utf8)
                || incomingState != lastSynchronizedTextState
            #if DEBUG || HANLIN_TESTING
            traceEdit("model-update", in: textView, detail: "modelChanged=\(modelChanged)")
            #endif
            lastSynchronizedModelText = incoming
            lastSynchronizedTextState = incomingState
            let placeholder = incoming.isEmpty && !isEditing
            let desired = placeholder ? parent.placeholderText : incoming
            let wasPlaceholder = textView.textColor == .placeholderText
            // UIKit can have changed its text storage before its delegate publishes
            // the binding. An unrelated SwiftUI layout update must not replay the
            // unchanged model value over that edit and move the insertion point.
            // Actual sends, restored drafts and conversation changes still reconcile.
            let shouldReconcile = modelChanged || wasPlaceholder != placeholder
            if shouldReconcile && (!(textView.text ?? "").utf8.elementsEqual(desired.utf8) || (wasPlaceholder && !placeholder)) {
                #if DEBUG || HANLIN_TESTING
                traceEdit("model-reconcile", in: textView, detail: "placeholder=\(placeholder) wasPlaceholder=\(wasPlaceholder)")
                #endif
                let selection = textView.selectedRange
                textView.text = desired
                invalidateMeasurement()
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

        func applySelectionRequest(in textView: UITextView) {
            guard let request = parent.selectionRequest,
                  appliedSelectionRequestID != request.id,
                  request.ownerID == nil || request.ownerID == parent.currentTextState?.ownerID,
                  request.text.utf8.elementsEqual((textView.text ?? "").utf8),
                  Range(request.range, in: request.text) != nil else { return }
            appliedSelectionRequestID = request.id
            isSynchronizingText = true
            textView.selectedRange = request.range
            isSynchronizingText = false
        }

        private func publishCapabilityQuery(in textView: UITextView) {
            guard !isRebindingOwner, !isSynchronizingText, isEditing else { return }
            let query = HanlinComposerCapabilityQuery.parse(
                text: textView.textColor == .placeholderText ? "" : (textView.text ?? ""),
                selection: textView.selectedRange, hasMarkedText: textView.markedTextRange != nil)
            parent.onCapabilityQueryChange?(query)
        }

        public func textViewDidBeginEditing(_ textView: UITextView) {
            isEditing = true
            if textView.textColor == .placeholderText {
                textView.text = ""
                textView.textColor = .label
                invalidateMeasurement()
            }
            #if DEBUG || HANLIN_TESTING
            traceEdit("focus-begin", in: textView)
            #endif
            parent.onFocusChange?(true)
            parent.onLifecycleEvent?(textView, .focusChanged(true))
        }

        public func textViewDidEndEditing(_ textView: UITextView) {
            isEditing = false
            #if DEBUG || HANLIN_TESTING
            traceEdit("focus-end", in: textView)
            #endif
            parent.onFocusChange?(false)
            parent.onLifecycleEvent?(textView, .focusChanged(false))
            if parent.currentText.isEmpty {
                textView.text = parent.placeholderText
                textView.textColor = .placeholderText
                invalidateMeasurement()
            }
        }

        public func textViewDidChange(_ textView: UITextView) {
            invalidateMeasurement()
            guard !isRebindingOwner else { return }
            guard textView.markedTextRange == nil else {
                parent.onCapabilityQueryChange?(nil)
                return
            }
            // An explicit clear/replacement can arrive before the delegate for
            // an older native mutation. Do not resurrect that older value.
            if parent.currentTextState != nil, !ownerMatchesLastSynchronization() {
                synchronizeText(in: textView)
                return
            }
            if textView.textColor != .placeholderText {
                let nativeText = textView.text ?? ""
                #if DEBUG || HANLIN_TESTING
                traceEdit("native-before-publish", in: textView)
                #endif
                let changed = publishNativeTextIfChanged(nativeText)
                #if DEBUG || HANLIN_TESTING
                traceEdit("native-after-publish", in: textView)
                #endif
                if changed && nativeText.hasSuffix("@") {
                    parent.onMentionTriggered?()
                }
                publishCapabilityQuery(in: textView)
                updateHeight(in: textView, deferred: false)
            }
        }

        public func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            #if DEBUG || HANLIN_TESTING
            traceEdit("native-should-change", in: textView,
                      detail: "range=\(range.location):\(range.length) replacementUTF16=\(text.utf16.count)")
            #endif
            guard text.isEmpty, textView.textColor != .placeholderText else { return true }
            let raw = textView.text ?? ""
            let ns = raw as NSString
            if let match = Self.matchContaining(index: range.location, in: raw) {
                textView.text = ns.replacingCharacters(in: match.range, with: "")
                textView.selectedRange = NSRange(location: match.range.location, length: 0)
                textViewDidChange(textView)
                return false
            }
            return true
        }

        public func textViewDidChangeSelection(_ textView: UITextView) {
            #if DEBUG || HANLIN_TESTING
            traceEdit("selection-change", in: textView)
            #endif
            publishCapabilityQuery(in: textView)
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

    #if DEBUG || HANLIN_TESTING
    // Observe the real responder caller only when the existing edit diagnostic is enabled.
    // Bound both frame count and symbol length; never record draft text or selection content.
    public override func resignFirstResponder() -> Bool {
        let recordsDiagnostics = ProcessInfo.processInfo.environment["HANLIN_COMPOSER_EDIT_DIAGNOSTICS"] == "1"
        let wasFirstResponder = isFirstResponder
        let callerFrames = recordsDiagnostics
            ? Thread.callStackSymbols.prefix(24).map { String($0.prefix(512)) }
            : []
        let result = super.resignFirstResponder()
        if recordsDiagnostics {
            print("HANLIN_COMPOSER_RESPONDER nativeID=\(ObjectIdentifier(self)) action=resign before=\(wasFirstResponder) after=\(isFirstResponder) result=\(result) callers=\(callerFrames.joined(separator: " | "))")
        }
        return result
    }
    #endif

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
