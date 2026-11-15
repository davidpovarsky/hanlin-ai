import SwiftUI
import UIKit
import Testing
@testable import AI_Hanlin

@MainActor
@Suite("Native composer automatic line sizing")
struct NativeComposerLineSizingTests {
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
                        let height = editor.measuredHeight(for: view, isEmpty: false)
                        #expect(view.isScrollEnabled == (target == 7))
                        if target == 6 {
                            #expect(height > minimum)
                            sixLineHeight = height
                        } else if let sixLineHeight {
                            #expect(abs(height - sixLineHeight) <= 2)
                        }
                        found = true
                        break
                    }
                }
                #expect(found)
            }
        }
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
