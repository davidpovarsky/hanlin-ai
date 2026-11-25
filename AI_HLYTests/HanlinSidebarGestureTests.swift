import SwiftUI
import Testing
import UIKit
@testable import AI_Hanlin

@MainActor
@Suite("Sidebar reveal gesture routing")
struct HanlinSidebarGestureTests {
    private func configuration(open: Bool = false, hasBack: Bool = false,
                               direction: LayoutDirection = .leftToRight) -> HanlinSidebarPan.Configuration {
        .init(isEnabled: true, isPresented: open, reservesBackGesture: hasBack,
              contentDirection: direction, size: CGSize(width: 390, height: 844),
              sidebarWidth: 304)
    }

    @Test("Only physical horizontal gestures in the opening or closing direction begin")
    func horizontalDirectionAndBounds() {
        var closed = configuration()
        let center = CGPoint(x: 150, y: 400)
        #expect(closed.acceptsStart(at: center, velocity: CGPoint(x: 600, y: 30)))
        #expect(!closed.acceptsStart(at: center, velocity: CGPoint(x: -600, y: 30)))
        #expect(!closed.acceptsStart(at: center, velocity: CGPoint(x: 200, y: 400)))
        #expect(!closed.acceptsStart(at: CGPoint(x: -5, y: 400), velocity: CGPoint(x: 600, y: 0)))
        #expect(!closed.acceptsStart(at: CGPoint(x: 150, y: 900), velocity: CGPoint(x: 600, y: 0)))
        closed.isEnabled = false
        #expect(!closed.acceptsStart(at: center, velocity: CGPoint(x: 600, y: 0)))

        let open = configuration(open: true)
        #expect(open.acceptsStart(at: center, velocity: CGPoint(x: -600, y: 30)))
        #expect(!open.acceptsStart(at: center, velocity: CGPoint(x: 600, y: 30)))
    }

    @Test("A pushed route retains its native back edge in both layout directions")
    func navigationEdgeOwnership() {
        let rightward = CGPoint(x: 600, y: 0)
        #expect(configuration().acceptsStart(at: CGPoint(x: 8, y: 300), velocity: rightward))
        #expect(!configuration(hasBack: true).acceptsStart(at: CGPoint(x: 8, y: 300), velocity: rightward))
        #expect(configuration(hasBack: true).acceptsStart(at: CGPoint(x: 80, y: 300), velocity: rightward))
        let rtl = configuration(hasBack: true, direction: .rightToLeft)
        #expect(!rtl.acceptsStart(at: CGPoint(x: 382, y: 300), velocity: rightward))
        #expect(rtl.acceptsStart(at: CGPoint(x: 8, y: 300), velocity: rightward))
    }

    @Test("Text editing, row swipe actions and horizontal scrollers retain their gestures")
    func nativeInteractionsKeepOwnership() {
        let row = UICollectionViewCell(frame: CGRect(x: 0, y: 0, width: 300, height: 60))
        let rowLabel = UIView(frame: row.bounds)
        row.contentView.addSubview(rowLabel)
        #expect(HanlinSidebarPan.Coordinator.preservesNativeInteraction(startingAt: rowLabel, inSidebar: true))
        #expect(!HanlinSidebarPan.Coordinator.preservesNativeInteraction(startingAt: rowLabel, inSidebar: false))

        let editor = UITextView()
        let editorChild = UIView()
        editor.addSubview(editorChild)
        #expect(HanlinSidebarPan.Coordinator.preservesNativeInteraction(startingAt: editorChild, inSidebar: false))
        #expect(HanlinSidebarPan.Coordinator.preservesNativeInteraction(startingAt: UISlider(), inSidebar: false))

        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 300, height: 600))
        scroll.contentSize = CGSize(width: 300, height: 1200)
        #expect(!HanlinSidebarPan.Coordinator.preservesNativeInteraction(startingAt: scroll, inSidebar: false))
        scroll.contentSize.width = 900
        #expect(HanlinSidebarPan.Coordinator.preservesNativeInteraction(startingAt: scroll, inSidebar: false))
    }

    @Test("Interrupted gestures restore state and overshoot never escapes the reveal bounds")
    func cancellationAndProjection() {
        #expect(HanlinSidebarDragPolicy.progress(isPresented: false, translation: -100, width: 300) == 0)
        #expect(HanlinSidebarDragPolicy.progress(isPresented: true, translation: 100, width: 300) == 1)
        #expect(HanlinSidebarDragPolicy.progress(isPresented: false, translation: 150, width: 300) == 0.5)
        #expect(!HanlinSidebarDragPolicy.destination(
            isPresented: false, translation: 250, velocity: 500, width: 300, cancelled: true))
        #expect(HanlinSidebarDragPolicy.destination(
            isPresented: true, translation: -250, velocity: -500, width: 300, cancelled: true))
        #expect(HanlinSidebarDragPolicy.destination(
            isPresented: false, translation: 170, velocity: 0, width: 300, cancelled: false))
        #expect(!HanlinSidebarDragPolicy.destination(
            isPresented: true, translation: -170, velocity: 0, width: 300, cancelled: false))
        #expect(!HanlinSidebarDragPolicy.destination(
            isPresented: false, translation: .nan, velocity: 500, width: 300, cancelled: false))
    }

    @Test("Search owns only its mounted window even without a composer, and stale anchors cannot clear it")
    func searchWindowOwnershipWithoutComposer() {
        let owner = HanlinCompactKeyboardOwner()
        let replacementOwner = HanlinCompactKeyboardOwner()
        let firstWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let secondWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 500, height: 700))
        let focused = HanlinCompactSearchFocusRegistration.Anchor(owner: owner, focused: true)
        let hidden = HanlinCompactSearchFocusRegistration.Anchor(owner: owner, focused: false)

        firstWindow.addSubview(focused)
        firstWindow.addSubview(hidden)
        #expect(owner.editor == nil)
        #expect(owner.ownsKeyboardFocus(in: firstWindow))
        #expect(!owner.ownsKeyboardFocus(in: secondWindow))
        hidden.disconnect()
        #expect(owner.ownsKeyboardFocus(in: firstWindow))

        focused.removeFromSuperview()
        #expect(!owner.ownsKeyboardFocus(in: firstWindow))
        secondWindow.addSubview(focused)
        #expect(!owner.ownsKeyboardFocus(in: firstWindow))
        #expect(owner.ownsKeyboardFocus(in: secondWindow))

        focused.update(owner: replacementOwner, focused: true)
        #expect(!owner.ownsKeyboardFocus(in: secondWindow))
        #expect(replacementOwner.ownsKeyboardFocus(in: secondWindow))
        focused.update(owner: replacementOwner, focused: false)
        #expect(!replacementOwner.ownsKeyboardFocus(in: secondWindow))
        focused.disconnect()
    }
}


@MainActor
@Suite("Sidebar native accessibility ownership")
struct HanlinSidebarAccessibilityOwnershipTests {
    @Test("History temporarily owns editor accessibility without changing editing state")
    func historyTemporarilyOwnsEditorAccessibility() {
        let owner = HanlinCompactKeyboardOwner()
        let editor = UITextView()
        editor.isAccessibilityElement = true
        editor.accessibilityElementsHidden = false
        editor.isUserInteractionEnabled = false
        editor.text = "Preserve the original draft"
        editor.selectedRange = NSRange(location: 3, length: 4)
        owner.observe(editor, event: .attached)

        owner.setHistoryPresented(true)
        #expect(!editor.isAccessibilityElement)
        #expect(editor.accessibilityElementsHidden)
        #expect(!editor.isUserInteractionEnabled)
        #expect(editor.text == "Preserve the original draft")
        #expect(editor.selectedRange == NSRange(location: 3, length: 4))

        // A repeated native update must reassert the gate without replacing
        // the original snapshot with these transient native values.
        editor.isAccessibilityElement = true
        editor.accessibilityElementsHidden = false
        owner.observe(editor, event: .attached)
        #expect(!editor.isAccessibilityElement)
        #expect(editor.accessibilityElementsHidden)

        owner.setHistoryPresented(false)
        #expect(editor.isAccessibilityElement)
        #expect(!editor.accessibilityElementsHidden)
        #expect(!editor.isUserInteractionEnabled)
        #expect(editor.text == "Preserve the original draft")
        #expect(editor.selectedRange == NSRange(location: 3, length: 4))

        // Once ownership ends, a later close must not overwrite another
        // accessibility choice made while History is already closed.
        editor.isAccessibilityElement = false
        editor.accessibilityElementsHidden = true
        owner.setHistoryPresented(false)
        #expect(!editor.isAccessibilityElement)
        #expect(editor.accessibilityElementsHidden)
    }

    @Test("Replacement and detach restore only the registered editor's original accessibility")
    func replacementAndDetachRestoreScopedAccessibility() {
        let owner = HanlinCompactKeyboardOwner()
        let oldEditor = UITextView()
        oldEditor.isAccessibilityElement = true
        oldEditor.accessibilityElementsHidden = false
        let currentEditor = UITextView()
        currentEditor.isAccessibilityElement = false
        currentEditor.accessibilityElementsHidden = false
        owner.observe(oldEditor, event: .attached)
        owner.setHistoryPresented(true)

        owner.observe(currentEditor, event: .attached)
        #expect(oldEditor.isAccessibilityElement)
        #expect(!oldEditor.accessibilityElementsHidden)
        #expect(!currentEditor.isAccessibilityElement)
        #expect(currentEditor.accessibilityElementsHidden)

        owner.observe(oldEditor, event: .detached)
        #expect(owner.editor === currentEditor)
        #expect(currentEditor.accessibilityElementsHidden)

        owner.observe(currentEditor, event: .detached)
        #expect(owner.editor == nil)
        #expect(!currentEditor.isAccessibilityElement)
        #expect(!currentEditor.accessibilityElementsHidden)
        owner.setHistoryPresented(false)
    }

    @Test("History ownership applies to a later attachment and preserves previously hidden editors")
    func historyBeforeAttachmentPreservesPriorHiddenState() {
        let owner = HanlinCompactKeyboardOwner()
        owner.setHistoryPresented(true)
        let editor = UITextView()
        editor.isAccessibilityElement = false
        editor.accessibilityElementsHidden = true
        owner.observe(editor, event: .attached)
        #expect(!editor.isAccessibilityElement)
        #expect(editor.accessibilityElementsHidden)

        owner.setHistoryPresented(false)
        #expect(!editor.isAccessibilityElement)
        #expect(editor.accessibilityElementsHidden)
        owner.observe(editor, event: .detached)

        // A closed workspace must not hide the next native editor.
        let successor = UITextView()
        successor.isAccessibilityElement = true
        successor.accessibilityElementsHidden = false
        owner.observe(successor, event: .attached)
        #expect(successor.isAccessibilityElement)
        #expect(!successor.accessibilityElementsHidden)
    }
}
