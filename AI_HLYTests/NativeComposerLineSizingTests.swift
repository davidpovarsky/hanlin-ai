import SwiftUI
import UIKit
import Testing
@testable import AI_Hanlin

@MainActor
@Suite("Native composer automatic line sizing")
struct NativeComposerLineSizingTests {
    private func independentTextKit2Layout(_ manager: NSTextLayoutManager) throws -> (bottoms: [CGFloat], ranges: [Range<Int>], documentLength: Int) {
        let content = try #require(manager.textContentManager)
        let document = content.documentRange
        let length = content.offset(from: document.location, to: document.endLocation)
        var bottoms: [CGFloat] = []
        var ranges: [Range<Int>] = []
        var validRanges = true
        manager.enumerateTextLayoutFragments(from: nil, options: [.ensuresLayout, .ensuresExtraLineFragment]) { fragment in
            let start = content.offset(from: document.location, to: fragment.rangeInElement.location)
            let end = content.offset(from: document.location, to: fragment.rangeInElement.endLocation)
            guard start >= 0, end >= start, end <= length else { validRanges = false; return false }
            ranges.append(start..<end)
            for line in fragment.textLineFragments {
                bottoms.append(fragment.layoutFragmentFrame.minY + line.typographicBounds.maxY)
            }
            return true
        }
        #expect(validRanges)
        var cursor = 0
        for range in ranges {
            #expect(range.lowerBound == cursor)
            cursor = range.upperBound
        }
        #expect(cursor == length)
        return (bottoms, ranges, length)
    }

    @Test("Editing and focus loss preserve pasted text, selection and whitespace drafts")
    func editingKeepsDraftAndSelection() {
        var draft = ""
        var height: CGFloat = 0
        let editor = NativeMultilineTextEditor(
            text: Binding(get: { draft }, set: { draft = $0 }),
            textHeight: Binding(get: { height }, set: { height = $0 }),
            maxHeight: 1000,
            usesAutomaticLineLimits: true
        )
        let coordinator = NativeMultilineTextEditor.Coordinator(editor)
        let view = UITextView(frame: CGRect(x: 0, y: 0, width: 160, height: 100))
        view.font = .preferredFont(forTextStyle: .body)
        view.textColor = .label
        let pasted = String(repeating: "Pasted draft ", count: 40)
        view.text = pasted
        view.selectedRange = NSRange(location: 4, length: 3)
        coordinator.textViewDidChange(view)
        #expect(draft == pasted)
        #expect(view.selectedRange == NSRange(location: 4, length: 3))
        #expect(view.isScrollEnabled)

        draft = "   "
        view.text = draft
        coordinator.textViewDidEndEditing(view)
        #expect(view.text == "   ")
        #expect(draft == "   ")
    }

    @Test("A layout update cannot replace a native edit before its delegate publishes the binding",
          arguments: ["Model picker keeps this draft", "שלום 👋 טיוטה ארוכה", String(repeating: "Wrapped accessible draft text ", count: 35)])
    func layoutDuringNativeEditPreservesCharactersAndCursor(_ input: String) {
        var draft = ""
        let editor = NativeMultilineTextEditor(
            text: Binding(get: { draft }, set: { draft = $0 }),
            textHeight: .constant(0), maxHeight: 300, usesAutomaticLineLimits: true
        )
        let coordinator = NativeMultilineTextEditor.Coordinator(editor)
        let view = MultilineInnerTextView(frame: CGRect(x: 0, y: 0, width: 220, height: 100))
        view.font = .preferredFont(forTextStyle: .body)
        view.textColor = .label
        coordinator.textViewDidBeginEditing(view)
        // Keep the real UIKit mutation and delegate notification separate so a
        // representable layout update can occur at the observed vulnerable boundary.
        for character in input {
            view.insertText(String(character))
            let cursor = view.selectedRange
            let nativeText = view.text
            coordinator.synchronizeText(in: view)
            #expect(view.text == nativeText)
            #expect(view.selectedRange == cursor)
            coordinator.textViewDidChange(view)
            coordinator.synchronizeText(in: view)
        }
        #expect(view.text == input)
        #expect(draft == input)
        #expect(view.selectedRange == NSRange(location: (input as NSString).length, length: 0))
        draft = ""
        coordinator.synchronizeText(in: view)
        #expect(view.text.isEmpty)
    }

    @Test("Consecutive native edits survive coalesced SwiftUI layout updates",
          arguments: ["Run the local Python acceptance tool and report the result.",
                      "Draft preserved across switch", "שלום 👋🏽 טיוטה ארוכה"])
    func coalescedNativeEditsPreserveTextAndSelection(_ input: String) {
        var draft = ""
        let editor = NativeMultilineTextEditor(
            text: Binding(get: { draft }, set: { draft = $0 }),
            textHeight: .constant(0), maxHeight: 300, usesAutomaticLineLimits: true
        )
        let coordinator = NativeMultilineTextEditor.Coordinator(editor)
        let view = MultilineInnerTextView(frame: CGRect(x: 0, y: 0, width: 220, height: 100))
        view.font = .preferredFont(forTextStyle: .body)
        view.textColor = .label
        coordinator.textViewDidBeginEditing(view)

        for character in input {
            view.insertText(String(character))
            let nativeText = view.text
            let selection = view.selectedRange

            // The previous edit has published its binding, but SwiftUI can
            // coalesce that render until the next native edit is underway.
            coordinator.synchronizeText(in: view)
            #expect(view.text == nativeText)
            #expect(view.selectedRange == selection)
            coordinator.textViewDidChange(view)
            // Intentionally no immediate synchronizeText here: the next loop
            // exercises the production ordering missed by the earlier test.
        }

        #expect(view.text == input)
        #expect(draft == input)
        #expect(view.selectedRange == NSRange(location: (input as NSString).length, length: 0))
        coordinator.synchronizeText(in: view)
        #expect(view.text == input)
    }

    @Test("Retained render snapshots cannot replay over a newer native draft",
          arguments: ["PAIRED_CANCEL_12345678-1234-1234-1234-123456789ABC",
                      "PAIRED_OPEN_12345678-1234-1234-1234-123456789ABC",
                      "שלום 👋🏽 טיוטה\nשורה שנייה"])
    func retainedRenderSnapshotPreservesNativeDraftAndCursor(_ input: String) {
        let draft = HanlinComposerDraft()
        var renderedText = ""
        let editor = NativeMultilineTextEditor(
            text: Binding(get: { renderedText }, set: { draft.text = $0 }),
            textHeight: .constant(0), maxHeight: 300, usesAutomaticLineLimits: true,
            readCurrentTextState: { draft.snapshot }
        )
        let coordinator = NativeMultilineTextEditor.Coordinator(editor)
        let view = MultilineInnerTextView(frame: CGRect(x: 0, y: 0, width: 220, height: 100))
        view.font = .preferredFont(forTextStyle: .body)
        view.textColor = .label
        coordinator.textViewDidBeginEditing(view)

        for character in input {
            let precedingDraft = draft.text
            view.insertText(String(character))
            let nativeText = view.text
            let selection = view.selectedRange
            // A layout can arrive both before and after the real UIKit delegate.
            coordinator.synchronizeText(in: view)
            #expect(view.text == nativeText)
            #expect(view.selectedRange == selection)
            coordinator.textViewDidChange(view)
            #expect(draft.text == nativeText)

            // Exact observed boundary: the write has reached the owner, but the
            // retained render still reads the preceding value (initially empty).
            renderedText = precedingDraft
            coordinator.synchronizeText(in: view)
            #expect(view.text == nativeText)
            #expect(view.selectedRange == selection)
        }

        renderedText = draft.text
        coordinator.synchronizeText(in: view)
        #expect(view.text == input)
        #expect(draft.text == input)
        #expect(view.selectedRange == NSRange(location: (input as NSString).length, length: 0))
    }

    @Test("A genuine clear before render acknowledgement and another draft are authoritative")
    func liveOwnerClearAndReplacementBeforeRenderAcknowledgement() {
        let draft = HanlinComposerDraft()
        var renderedText = ""
        let editor = NativeMultilineTextEditor(
            text: Binding(get: { renderedText }, set: { draft.text = $0 }),
            textHeight: .constant(0), placeholderText: "Message", maxHeight: 300,
            readCurrentTextState: { draft.snapshot }
        )
        let coordinator = NativeMultilineTextEditor.Coordinator(editor)
        let view = MultilineInnerTextView(frame: CGRect(x: 0, y: 0, width: 220, height: 100))
        view.font = .preferredFont(forTextStyle: .body)
        view.textColor = .label
        coordinator.textViewDidBeginEditing(view)
        view.insertText("P")
        coordinator.textViewDidChange(view)
        #expect(draft.text == "P")
        #expect(renderedText.isEmpty)

        // Unlike the stale render's identical empty value, this is an actual
        // write to the current owner. No acknowledgement or timeout is needed.
        draft.text = ""
        coordinator.synchronizeText(in: view)
        #expect(view.text.isEmpty)
        #expect(view.selectedRange == NSRange(location: 0, length: 0))

        draft.text = "שיחה אחרת 👋"
        coordinator.synchronizeText(in: view)
        #expect(view.text == draft.text)
        view.selectedRange = NSRange(location: (draft.text as NSString).length, length: 0)
        renderedText = draft.text
        draft.text = "אב"
        coordinator.synchronizeText(in: view)
        #expect(view.text == "אב")
        #expect(view.selectedRange == NSRange(location: 2, length: 0))

        draft.text = "   "
        coordinator.textViewDidEndEditing(view)
        coordinator.synchronizeText(in: view)
        #expect(view.text == "   ")
        #expect(draft.text == "   ")
    }

    private func withFocusedNativeEditor(
        _ body: (MultilineInnerTextView) throws -> Void
    ) throws {
        let scene = try #require(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        root.loadViewIfNeeded()
        let view = MultilineInnerTextView(frame: CGRect(x: 0, y: 0, width: 220, height: 100))
        view.font = .preferredFont(forTextStyle: .body)
        view.textColor = .label
        root.view.addSubview(view)
        defer {
            view.resignFirstResponder()
            window.isHidden = true
            previousKeyWindow?.makeKey()
        }
        try #require(view.becomeFirstResponder())
        try body(view)
    }

    private func editor(for draft: HanlinComposerDraft,
                        onFocusChange: ((Bool) -> Void)? = nil) -> NativeMultilineTextEditor {
        NativeMultilineTextEditor(
            text: Binding(get: { draft.text }, set: { draft.text = $0 }),
            textHeight: .constant(0), placeholderText: "Message", maxHeight: 300,
            onFocusChange: onFocusChange,
            readCurrentTextState: { draft.snapshot }
        )
    }

    @Test("Equal-string A-to-B rebinding commits pending native input only to A")
    func equalStringOwnerSwitchKeepsPendingInputAndLateDelegateScoped() throws {
        let a = HanlinComposerDraft(text: "Same")
        let b = HanlinComposerDraft(text: "Same")
        var focusA: [Bool] = []
        var focusB: [Bool] = []
        let editorA = editor(for: a, onFocusChange: { focusA.append($0) })
        let editorB = editor(for: b, onFocusChange: { focusB.append($0) })
        let coordinator = NativeMultilineTextEditor.Coordinator(editorA)
        try withFocusedNativeEditor { view in
            view.text = a.text
            view.selectedRange = NSRange(location: 4, length: 0)
            coordinator.textViewDidBeginEditing(view)
            // The original native mutation has happened; its delegate has not.
            view.insertText(" A")
            #expect(view.text == "Same A")
            #expect(a.text == "Same")
            let untouchedB = b.snapshot
            view.delegate = coordinator
            coordinator.rebind(to: editorB, in: view)
            #expect(a.text == "Same A")
            #expect(b.snapshot == untouchedB)
            #expect(view.text == "Same")
            #expect(view.selectedRange == NSRange(location: 4, length: 0))
            #expect(view.isFirstResponder && coordinator.isEditing)
            let committedA = a.snapshot
            // A queued UITextViewDelegate callback carries the same native view,
            // not a captured old string. It must not write a new B revision.
            coordinator.textViewDidChange(view)
            #expect(a.snapshot == committedA)
            #expect(b.snapshot == untouchedB)
            #expect(focusA == [true])
            #expect(focusB.isEmpty)
            view.delegate = nil
            view.insertText(" ב")
            coordinator.textViewDidChange(view)
            #expect(b.text == "Same ב")
            #expect(a.snapshot == committedA)
            coordinator.rebind(to: editorA, in: view)
            #expect(view.text == "Same A")
            #expect(view.isFirstResponder && coordinator.isEditing)
        }
    }

    @Test("Canonically equivalent drafts preserve exact native bytes and UTF-16 selection")
    func canonicalEquivalentOwnerAndNativeReplacementsPreserveExactText() throws {
        let composed = "\u{e9}"
        let decomposed = "e\u{301}"
        #expect(composed == decomposed)
        #expect(!composed.utf8.elementsEqual(decomposed.utf8))
        let a = HanlinComposerDraft(text: decomposed)
        let b = HanlinComposerDraft(text: composed)
        let coordinator = NativeMultilineTextEditor.Coordinator(editor(for: a))
        try withFocusedNativeEditor { view in
            view.text = decomposed
            view.selectedRange = NSRange(location: 2, length: 0)
            coordinator.textViewDidBeginEditing(view)
            let unchangedA = a.snapshot
            let untouchedB = b.snapshot
            coordinator.rebind(to: editor(for: b), in: view)
            #expect(view.text.utf8.elementsEqual(composed.utf8))
            #expect(view.selectedRange == NSRange(location: 1, length: 0))
            #expect(a.snapshot == unchangedA)
            #expect(b.snapshot == untouchedB)
            coordinator.textViewDidChange(view)
            #expect(b.snapshot == untouchedB)

            // This is a real native replacement with a canonically equivalent
            // value whose bytes and UTF-16 length differ.
            view.selectedRange = NSRange(location: 0, length: 1)
            view.insertText(decomposed)
            #expect(view.text.utf8.elementsEqual(decomposed.utf8))
            #expect(view.selectedRange == NSRange(location: 2, length: 0))
            coordinator.textViewDidChange(view)
            #expect(b.text.utf8.elementsEqual(decomposed.utf8))
            #expect(b.snapshot.revision != untouchedB.revision)
            coordinator.synchronizeText(in: view)
            #expect(view.text.utf8.elementsEqual(decomposed.utf8))
            #expect(view.selectedRange == NSRange(location: 2, length: 0))

            b.text = composed
            coordinator.synchronizeText(in: view)
            #expect(view.text.utf8.elementsEqual(composed.utf8))
            #expect(view.selectedRange == NSRange(location: 1, length: 0))
            #expect(a.snapshot == unchangedA)
            #expect(view.isFirstResponder && coordinator.isEditing)
        }
    }

    @Test("An explicit same-value clear defeats an older native mutation before its delegate",
          arguments: [false, true])
    func sameValueClearPrecedesLateNativeDelegate(_ switchOwner: Bool) throws {
        let a = HanlinComposerDraft()
        let b = HanlinComposerDraft()
        let coordinator = NativeMultilineTextEditor.Coordinator(editor(for: a))
        try withFocusedNativeEditor { view in
            view.text = ""
            coordinator.textViewDidBeginEditing(view)
            view.insertText("P")
            #expect(view.text == "P")
            #expect(a.text.isEmpty)
            let initialRevision = a.snapshot.revision
            // This real owner write is distinct from an unchanged empty render.
            a.text = ""
            let clearedA = a.snapshot
            let untouchedB = b.snapshot
            #expect(clearedA.revision != initialRevision)
            if switchOwner {
                coordinator.rebind(to: editor(for: b), in: view)
            }
            coordinator.textViewDidChange(view)
            #expect(view.text.isEmpty)
            #expect(view.selectedRange == NSRange(location: 0, length: 0))
            #expect(a.snapshot == clearedA)
            #expect(b.snapshot == untouchedB)
            #expect(view.isFirstResponder && coordinator.isEditing)
            coordinator.textViewDidChange(view)
            #expect(a.snapshot == clearedA)
            #expect(b.snapshot == untouchedB)
        }
    }

    @Test("Real marked text finishes in its original owner without crossing into another draft",
          arguments: [false, true])
    func markedTextOwnerSwitchPreservesCompositionAndAuthoritativeClear(_ clearOriginal: Bool) throws {
        let a = HanlinComposerDraft(text: "A ")
        let b = HanlinComposerDraft(text: "B")
        let coordinator = NativeMultilineTextEditor.Coordinator(editor(for: a))
        try withFocusedNativeEditor { view in
            view.text = a.text
            view.selectedRange = NSRange(location: 2, length: 0)
            coordinator.textViewDidBeginEditing(view)
            view.setMarkedText("אב", selectedRange: NSRange(location: 2, length: 0))
            try #require(view.markedTextRange != nil)
            #expect(view.text == "A אב")
            coordinator.textViewDidChange(view)
            #expect(a.text == "A ")
            if clearOriginal { a.text = "" }
            let originalBeforeSwitch = a.snapshot
            let untouchedB = b.snapshot
            // Install the real delegate for any synchronous unmark notification.
            view.delegate = coordinator
            coordinator.rebind(to: editor(for: b), in: view)
            #expect(view.markedTextRange == nil)
            #expect(a.text == (clearOriginal ? "" : "A אב"))
            if clearOriginal { #expect(a.snapshot == originalBeforeSwitch) }
            #expect(b.snapshot == untouchedB)
            #expect(view.text == "B")
            #expect(view.isFirstResponder && coordinator.isEditing)
            let finishedA = a.snapshot
            coordinator.textViewDidChange(view)
            #expect(a.snapshot == finishedA)
            #expect(b.snapshot == untouchedB)
        }
    }

    @Test("Sending clears an editing UIKit draft and restored text keeps a valid cursor")
    func programmaticDraftUpdatesWhileEditing() {
        var draft = "Sent message"
        let editor = NativeMultilineTextEditor(
            text: Binding(get: { draft }, set: { draft = $0 }),
            textHeight: .constant(0), placeholderText: "Message", maxHeight: 1000
        )
        let coordinator = NativeMultilineTextEditor.Coordinator(editor)
        let view = UITextView()
        view.textColor = .label
        view.text = draft
        view.selectedRange = NSRange(location: 4, length: 3)
        coordinator.textViewDidBeginEditing(view)
        coordinator.synchronizeText(in: view)
        #expect(view.selectedRange == NSRange(location: 4, length: 3))

        draft = ""
        coordinator.synchronizeText(in: view)
        #expect(view.text == "")
        #expect(view.textColor == .label)
        #expect(view.selectedRange == NSRange(location: 0, length: 0))

        draft = "שלום 👋"
        coordinator.synchronizeText(in: view)
        #expect(view.text == draft)
        view.selectedRange = NSRange(location: (draft as NSString).length, length: 0)
        draft = "אב"
        coordinator.synchronizeText(in: view)
        #expect(view.text == draft)
        #expect(view.selectedRange == NSRange(location: 2, length: 0))

        draft = ""
        coordinator.textViewDidEndEditing(view)
        coordinator.synchronizeText(in: view)
        #expect(view.text == "Message")
        #expect(draft.isEmpty)
    }

    @Test("Wrapped text grows through six lines and scrolls at seven, including RTL")
    func wrappedLinesAndScrolling() {
        let editor = NativeMultilineTextEditor(text: .constant(""), textHeight: .constant(0), maxHeight: 1000, usesAutomaticLineLimits: true)
        for sample in ["word ", "שלום "] {
            let view = MultilineInnerTextView(frame: CGRect(x: 0, y: 0, width: 160, height: 100))
            view.font = .preferredFont(forTextStyle: .body)
            view.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
            view.textContainer.lineFragmentPadding = 0
            view.isScrollEnabled = false
            // Enumerating glyphs opts this test view into its TextKit 1 layout
            // manager; establish that manager before configuring its container.
            let layoutManager = view.layoutManager
            view.layoutIfNeeded()
            // Count the full laid-out text, not only glyphs fitting in the
            // 100-point view. Keep the content width equal to the real editor's
            // bounds minus its horizontal text-container insets.
            view.textContainer.widthTracksTextView = false
            view.textContainer.heightTracksTextView = false
            let contentWidth = view.bounds.width - view.textContainerInset.left - view.textContainerInset.right
            if sample != "word " { view.semanticContentAttribute = .forceRightToLeft }
            view.text = "a"
            let minimum = NativeMultilineTextEditor.automaticHeightBounds(for: view, isEmpty: false, availableHeight: 1000).min
            #expect(editor.measuredHeight(for: view, isEmpty: false) >= minimum)
            var sixLineHeight: CGFloat?
            var sixTrace: NativeMultilineTextEditor.MeasurementTrace?
            var constrainedTrace: NativeMultilineTextEditor.MeasurementTrace?
            for target in [6, 7] {
                var found = false
                for count in 1...500 {
                    view.text = String(repeating: sample, count: count)
                    view.textContainer.size = CGSize(width: contentWidth, height: 10_000)
                    layoutManager.ensureLayout(for: view.textContainer)
                    var lines = 0
                    let range = layoutManager.glyphRange(for: view.textContainer)
                    layoutManager.enumerateLineFragments(forGlyphRange: range) { _, _, _, _, _ in lines += 1 }
                    if lines == target {
                        #expect(range.location == 0 && range.length == layoutManager.numberOfGlyphs)
                        var currentTrace: NativeMultilineTextEditor.MeasurementTrace?
                        let height = editor.measuredHeight(for: view, isEmpty: false) { currentTrace = $0 }
                        let signedDeltaText = sixLineHeight.map { String(describing: height - $0) } ?? "n/a"
                        print("COMPOSER_LAYOUT script=\(sample) target=\(target) trace=\(String(describing: currentTrace)) signedDelta=\(signedDeltaText)")
                        #expect(view.isScrollEnabled == (target == 7))
                        if target == 6 {
                            #expect(height > minimum)
                            sixLineHeight = height
                            sixTrace = currentTrace
                            let constrained = NativeMultilineTextEditor(text: .constant(""), textHeight: .constant(0), maxHeight: height / 2, usesAutomaticLineLimits: true)
                            let constrainedHeight = constrained.measuredHeight(for: view, isEmpty: false) { constrainedTrace = $0 }
                            #expect(constrainedHeight == height / 2)
                            #expect(view.isScrollEnabled)
                            view.isScrollEnabled = false
                        } else if let sixLineHeight {
                            #expect(abs(height - sixLineHeight) <= 2,
                                "script=\(sample) six=\(String(describing: sixTrace)) constrained=\(String(describing: constrainedTrace)) seven=\(String(describing: currentTrace)) signedDelta=\(height - sixLineHeight)")
                        }
                        found = true
                        break
                    }
                }
                #expect(found)
            }
        }
    }

    @Test("TextKit 2 retains its layout manager while wrapped six and seven lines are measured")
    func textKit2WrappedLinesKeepNativeLayout() throws {
        let editor = NativeMultilineTextEditor(text: .constant(""), textHeight: .constant(0), maxHeight: 1000, usesAutomaticLineLimits: true)
        for sample in ["word ", "שלום "] {
            let view = UITextView(usingTextLayoutManager: true)
            view.frame = CGRect(x: 0, y: 0, width: 160, height: 100)
            view.font = .preferredFont(forTextStyle: .body)
            view.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
            view.textContainer.lineFragmentPadding = 0
            view.isScrollEnabled = false
            view.layoutIfNeeded()
            view.textContainer.widthTracksTextView = false
            view.textContainer.heightTracksTextView = false
            let manager = try #require(view.textLayoutManager)
            for target in [6, 7] {
                var found = false
                for count in 1...500 {
                    view.text = String(repeating: sample, count: count)
                    view.textContainer.size = CGSize(width: 152, height: 10_000)
                    let lines = try independentTextKit2Layout(manager)
                    if lines.bottoms.count == target {
                        #expect(lines.bottoms[5] > 0)
                        let height = editor.measuredHeight(for: view, isEmpty: false)
                        #expect(view.isScrollEnabled == (target == 7))
                        if target == 7 {
                            let expected = ceil(lines.bottoms[5] + view.textContainerInset.top + view.textContainerInset.bottom)
                            #expect(height == expected)
                        }
                        #expect(view.textLayoutManager === manager)
                        found = true
                        break
                    }
                }
                #expect(found)
            }
        }
    }

    @Test("TextKit 2 paragraph and trailing empty line coverage rejects an omitted fragment")
    func textKit2ParagraphCoverageAndConservativeFallback() throws {
        let view = UITextView(usingTextLayoutManager: true)
        view.frame = CGRect(x: 0, y: 0, width: 160, height: 100)
        view.font = .preferredFont(forTextStyle: .body)
        view.isScrollEnabled = false
        view.layoutIfNeeded()
        view.textContainer.widthTracksTextView = false
        view.textContainer.heightTracksTextView = false
        view.textContainer.size = CGSize(width: 152, height: 10_000)
        view.text = "one\ntwo\nthree\n"
        let manager = try #require(view.textLayoutManager)
        let native = try independentTextKit2Layout(manager)
        #expect(native.bottoms.count == 4)
        #expect(native.ranges.count >= 2)
        #expect(NativeMultilineTextEditor.hasContiguousCoverage(native.ranges, documentLength: native.documentLength))
        let actual = NativeMultilineTextEditor.visualLineLimit(for: view)
        #expect(actual.complete)
        #expect(actual.count == native.bottoms.count)
        let omitted = Array(native.ranges.dropFirst())
        let complete = NativeMultilineTextEditor.hasContiguousCoverage(omitted, documentLength: native.documentLength)
        #expect(!complete)
        let fallback = NativeMultilineTextEditor.automaticLimit(fittingHeight: 300, availableHeight: 500,
            minimumHeight: 60, verticalInsets: 16, count: native.bottoms.count, sixthBottom: nil, complete: complete)
        #expect(fallback.forceScroll)
        #expect(fallback.maximum == 60)
        #expect(view.textLayoutManager === manager)
    }

    @Test("Empty, accessibility font, and constrained viewport use current font metrics")
    func fontAndViewport() {
        let view = UITextView()
        view.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        view.font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: UITraitCollection(preferredContentSizeCategory: .large))
        let empty = NativeMultilineTextEditor.automaticHeightBounds(for: view, isEmpty: true, availableHeight: 1000)
        let normal = NativeMultilineTextEditor.automaticHeightBounds(for: view, isEmpty: false, availableHeight: 1000)
        #expect(empty.min == empty.max)
        #expect(normal.min > empty.min)
        view.font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge))
        let accessible = NativeMultilineTextEditor.automaticHeightBounds(for: view, isEmpty: false, availableHeight: 1000)
        #expect(accessible.min > normal.min)
        let constrained = NativeMultilineTextEditor.automaticHeightBounds(for: view, isEmpty: false, availableHeight: accessible.min + 10)
        #expect(constrained.max == accessible.min + 10)
        let veryConstrained = NativeMultilineTextEditor.automaticHeightBounds(for: view, isEmpty: false, availableHeight: accessible.min / 2)
        #expect(veryConstrained.min == accessible.min / 2)
        #expect(veryConstrained.max == accessible.min / 2)
    }
}
