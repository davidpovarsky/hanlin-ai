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
