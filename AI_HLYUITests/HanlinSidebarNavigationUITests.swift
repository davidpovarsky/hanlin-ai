import XCTest

/// Exercises the original Hanlin workspace. Run on an actual compact viewport
/// (iPhone or an OS-resized iPad window); no simulated app width is supplied.
@MainActor
final class HanlinSidebarNavigationUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { app.terminate() }

    private var close: XCUIElement { app.buttons["hanlin-history-done"].firstMatch }
    private var library: XCUIElement {
        app.descendants(matching: .any)["hanlin-compact-conversation-library"].firstMatch
    }
    private var editor: XCUIElement {
        app.textViews.matching(NSPredicate(
            format: "identifier == 'hanlin-chat-input' OR identifier == 'hanlin-composer-surface'"
        )).firstMatch
    }

    private func launch(language: String = "en", locale: String = "en_US") {
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE"] = "1"
        app.launchEnvironment["HANLIN_DOCK_ACCEPTANCE_FIXTURES"] = "1"
        app.launchEnvironment["HANLIN_COMPOSER_EDIT_DIAGNOSTICS"] = "1"
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 15))
        XCTAssertLessThan(app.windows.firstMatch.frame.width, 640,
            "Use a real compact device/window for this selector.")
        XCTAssertTrue(app.descendants(matching: .any)["hanlin-compact-chat-workspace"]
            .firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
    }

    private func waitUntilHittable(_ element: XCUIElement, _ expected: Bool = true) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == %@", NSNumber(value: expected)), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed)
    }

    private func tap(_ identifier: String) {
        let element = app.buttons[identifier].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 10), identifier)
        waitUntilHittable(element)
        element.tap()
    }

    private func assertOpenLayout() {
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        waitUntilHittable(close)
        XCTAssertTrue(library.exists)
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(library.frame.minX, window.minX, accuracy: 2,
            "The real history layer must reveal from physical left, also in Hebrew.")
        XCTAssertLessThan(library.frame.width, window.width * 0.9)
    }

    private func assertOpen() {
        assertOpenLayout()
        // A retained editor can have an on-screen hit point while interaction
        // is disabled. Check that permission here; the grouped-history test
        // also taps the exposed strip and verifies the actual no-edit/no-send behavior.
        XCTAssertFalse(editor.isEnabled, "The exposed workspace strip must not edit or send a chat.")
    }

    private func assertClosed() {
        waitUntilHittable(close, false)
        waitUntilHittable(editor)
        XCTAssertFalse(app.buttons["hanlin-history-delete-action"].firstMatch.isHittable)
    }

    private func drag(fromX: CGFloat, toX: CGFloat, y: CGFloat) {
        let viewport = app.descendants(matching: .any)["hanlin-sidebar-reveal"].firstMatch
        XCTAssertTrue(viewport.exists)
        viewport.coordinate(withNormalizedOffset: CGVector(dx: fromX, dy: y))
            .press(forDuration: 0.05, thenDragTo:
                viewport.coordinate(withNormalizedOffset: CGVector(dx: toX, dy: y)))
    }

    private func attach(_ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = name + "-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }


    private func attachEditorDiagnostics(_ name: String, allowedFixtureValues: Set<String>) {
        let matches = app.textViews.matching(NSPredicate(
            format: "identifier == 'hanlin-chat-input' OR identifier == 'hanlin-composer-surface'"
        ))
        let historyExists = library.exists
        let historyFrameDescription = historyExists ? String(describing: library.frame) : "<not in AX>"
        var lines = [
            "matchingTextViewCount=\(matches.count)",
            "windowFrame=\(app.windows.firstMatch.frame)",
            "historyExists=\(historyExists) historyFrame=\(historyFrameDescription)",
            "historyCloseExists=\(close.exists)",
            "keyboardExists=\(app.keyboards.firstMatch.exists)"
        ]
        for (index, candidate) in matches.allElementsBoundByIndex.enumerated() {
            let value = candidate.value as? String
            let recordedValue: String
            if let value, allowedFixtureValues.contains(value) {
                recordedValue = String(reflecting: value)
            } else {
                recordedValue = "<unexpected value redacted; UTF16=\(value?.utf16.count ?? -1)>"
            }
            lines.append(
                "textView[\(index)] identifier=\(String(reflecting: candidate.identifier))"
                + " exists=\(candidate.exists) enabled=\(candidate.isEnabled)"
                + " hittable=\(candidate.isHittable) frame=\(candidate.frame) value=\(recordedValue)"
            )
        }
        let state = XCTAttachment(string: lines.joined(separator: "\n"))
        state.name = name + "-editor-attributes"
        state.lifetime = .keepAlways
        add(state)
        attach(name)
    }

    func testHistorySeparatesPinnedAndTodayWithoutDuplicatingChats() throws {
        launch()
        tap("hanlin-history-open")
        assertOpen()
        attachEditorDiagnostics("history-original-empty-draft", allowedFixtureValues: ["", "Message"])

        let pinned = app.staticTexts["hanlin-history-section-pinned"].firstMatch
        let today = app.staticTexts["hanlin-history-section-today"].firstMatch
        XCTAssertTrue(pinned.waitForExistence(timeout: 10))
        XCTAssertTrue(today.waitForExistence(timeout: 10))
        XCTAssertLessThan(pinned.frame.minY, today.frame.minY)
        let pinnedRows = app.buttons.matching(identifier: "hanlin-chat-row-Older Archived Thread")
        XCTAssertEqual(pinnedRows.count, 1, "Pinned conversations must not be repeated in date sections.")
        XCTAssertTrue(pinnedRows.firstMatch.isHittable)
        let todayRow = app.buttons["hanlin-chat-row-Architecture Review Notes"].firstMatch
        XCTAssertTrue(todayRow.exists)
        XCTAssertGreaterThan(todayRow.frame.minY, today.frame.minY)
        XCTAssertGreaterThan(todayRow.frame.width, library.frame.width * 0.6)
        attach("grouped-history-pinned-and-today")
        tap("hanlin-history-done")
        assertClosed()

        let fixtureDraft = "Sidebar draft 149101"
        let home = app.descendants(matching: .any)["hanlin-compact-home-screen"].firstMatch
        let transcript = app.descendants(matching: .any)["hanlin-chat-transcript"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Hanlin"].firstMatch.exists)
        XCTAssertFalse(transcript.exists)
        editor.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        editor.typeText(fixtureDraft)
        XCTAssertEqual(editor.value as? String, fixtureDraft)

        tap("hanlin-history-open")
        assertOpen()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 10),
            "Opening history must dismiss the composer keyboard.")
        attachEditorDiagnostics("history-with-fixture-draft", allowedFixtureValues: [fixtureDraft])

        let windowElement = app.windows.firstMatch
        let windowFrame = windowElement.frame
        let historyFrame = library.frame
        let editorFrame = editor.frame
        let stripStart = max(windowFrame.minX, historyFrame.maxX)
        let exposedStrip = CGRect(
            x: stripStart, y: windowFrame.minY,
            width: max(0, windowFrame.maxX - stripStart), height: windowFrame.height)
        let visibleEditor = editorFrame.intersection(windowFrame).intersection(exposedStrip)
        guard !visibleEditor.isNull, !visibleEditor.isEmpty,
              visibleEditor.width > 4, visibleEditor.height > 4,
              [visibleEditor.minX, visibleEditor.minY, visibleEditor.maxX, visibleEditor.maxY]
                .allSatisfy({ $0.isFinite }) else {
            XCTFail("The test requires a measured, on-screen editor region in the exposed strip; no fallback tap is allowed.")
            return
        }
        let tapPoint = CGPoint(x: visibleEditor.midX, y: visibleEditor.midY)
        let geometry = XCTAttachment(string:
            "window=\(windowFrame) history=\(historyFrame) editor=\(editorFrame)"
            + " exposedStrip=\(exposedStrip) visibleEditor=\(visibleEditor) tapPoint=\(tapPoint)")
        geometry.name = "history-exposed-strip-physical-tap"
        geometry.lifetime = .keepAlways
        add(geometry)
        // Use the physical window point, not editor.tap(), which may scroll or
        // otherwise resolve a different hit point for the retained AX element.
        windowElement.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: tapPoint.x - windowFrame.minX, dy: tapPoint.y - windowFrame.minY))
            .tap()

        assertClosed()
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 2),
            "Tapping the exposed workspace must only close history, without focusing the editor.")
        XCTAssertEqual(editor.value as? String, fixtureDraft,
            "Closing history through the exposed strip must not change or send the draft.")
        XCTAssertTrue(home.exists)
        XCTAssertTrue(app.navigationBars["Hanlin"].firstMatch.exists)
        XCTAssertFalse(transcript.exists, "The strip tap must not create or navigate to a chat.")
        XCTAssertFalse(app.buttons["hanlin-chat-stop"].firstMatch.exists,
            "The strip tap must not start a response.")
        attachEditorDiagnostics("history-closed-after-strip-tap", allowedFixtureValues: [fixtureDraft])

        // Positive control: the same retained editor must still accept a real
        // edit after history closes. A tap may place the caret within the draft,
        // so validate one exact insertion without assuming a caret position.
        XCTAssertTrue(editor.isEnabled)
        editor.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        editor.typeText("7")
        let editedDraft = try XCTUnwrap(editor.value as? String)
        XCTAssertEqual(editedDraft.utf16.count, fixtureDraft.utf16.count + 1)
        XCTAssertEqual(editedDraft.replacingOccurrences(of: "7", with: ""), fixtureDraft)
        XCTAssertFalse(transcript.exists)
        attachEditorDiagnostics("history-editor-positive-control", allowedFixtureValues: [editedDraft])
    }

    func testHistoryRevealKeepsDraftAndOriginalProfileRoute() throws {
        launch()
        editor.tap()
        editor.typeText("Sidebar retains the original draft")
        tap("hanlin-history-open")
        assertOpen()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 10))
        attach("history-open-with-original-library")

        tap("hanlin-settings-tab")
        XCTAssertTrue(app.descendants(matching: .any)["hanlin-settings-list"]
            .firstMatch.waitForExistence(timeout: 10))
        tap("hanlin-profile-done")
        assertOpen()
        tap("hanlin-history-done")
        assertClosed()
        XCTAssertEqual(editor.value as? String, "Sidebar retains the original draft")

        for _ in 0..<2 {
            tap("hanlin-history-open")
            assertOpen()
            tap("hanlin-history-done")
            assertClosed()
        }
        XCTAssertEqual(editor.value as? String, "Sidebar retains the original draft")
        XCTAssertEqual(app.textViews.matching(NSPredicate(
            format: "identifier == 'hanlin-chat-input' OR identifier == 'hanlin-composer-surface'"
        )).count, 1, "The original persistent editor must not be duplicated.")
    }

    func testPhysicalDragsAndReactivationKeepGestureConfigurationCurrent() throws {
        launch()
        let starts: [(CGFloat, CGFloat)] = [(0.12, 0.20), (0.30, 0.42), (0.40, 0.68)]
        for (x, y) in starts {
            drag(fromX: x, toX: 0.95, y: y)
            assertOpen()
            // Close from the exposed workspace, outside the native row actions.
            drag(fromX: 0.96, toX: 0.08, y: y)
            assertClosed()
        }
        tap("hanlin-history-open")
        library.swipeUp()
        assertOpen()
        tap("hanlin-history-done")

        // The same mounted recognizer is disabled while inactive, then enabled
        // again without changing the app window or creating another recognizer.
        let previousFrame = app.windows.firstMatch.frame
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertEqual(app.windows.firstMatch.frame.width, previousFrame.width, accuracy: 2)
        drag(fromX: 0.20, toX: 0.95, y: 0.25)
        assertOpen()
        attach("history-reopened-after-scene-reactivation")
        drag(fromX: 0.96, toX: 0.08, y: 0.25)
        assertClosed()
    }

    func testSearchSelectionAndNativeBackPreserveSeparateDrafts() throws {
        launch()
        editor.tap()
        editor.typeText("Retained home draft")
        tap("hanlin-history-open")
        assertOpen()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("Architecture")
        let row = app.buttons["hanlin-chat-row-Architecture Review Notes"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        waitUntilHittable(row)
        row.tap()
        assertClosed()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 10),
            "Closing the retained history layer must resign its native search.")
        XCTAssertTrue(app.descendants(matching: .any)["hanlin-chat-transcript"]
            .firstMatch.waitForExistence(timeout: 10))
        XCTAssertNotEqual(editor.value as? String, "Retained home draft")

        editor.tap()
        editor.typeText("Retained selected chat draft")
        tap("hanlin-history-open")
        assertOpen()
        tap("hanlin-history-done")
        assertClosed()
        XCTAssertEqual(editor.value as? String, "Retained selected chat draft")

        // The physical left edge belongs to native back on this English route.
        drag(fromX: 0.01, toX: 0.90, y: 0.45)
        let recent = app.buttons["hanlin-compact-view-all-button"].firstMatch
        XCTAssertTrue(recent.waitForExistence(timeout: 10))
        waitUntilHittable(recent)
        assertClosed()
        XCTAssertEqual(editor.value as? String, "Retained home draft")
        attach("native-back-retained-home-draft")
    }

    func testNativeHistoryRowSwipeRemainsAvailable() throws {
        launch()
        tap("hanlin-history-open")
        assertOpen()
        let row = app.buttons["hanlin-chat-row-Agent Acceptance Chat"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        waitUntilHittable(row)
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo:
                row.coordinate(withNormalizedOffset: CGVector(dx: 0.48, dy: 0.5)))
        let delete = app.buttons["hanlin-history-delete-action"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 10))
        waitUntilHittable(delete)
        XCTAssertTrue(row.exists, "A partial native row swipe must not delete the conversation.")
        assertOpen()
        attach("native-row-action-with-sidebar-still-open")
    }

    func testHebrewHistoryKeepsPhysicalRevealAndMirroredControls() throws {
        launch(language: "he", locale: "he_IL")
        drag(fromX: 0.20, toX: 0.95, y: 0.25)
        assertOpen()
        let newChat = app.buttons["hanlin-new-chat-button"].firstMatch
        XCTAssertTrue(newChat.waitForExistence(timeout: 10))
        XCTAssertLessThan(newChat.frame.midX, close.frame.midX,
            "History contents must remain RTL while the layer opens on physical left.")
        tap("hanlin-settings-tab")
        XCTAssertTrue(app.descendants(matching: .any)["hanlin-settings-list"]
            .firstMatch.waitForExistence(timeout: 10))
        tap("hanlin-profile-done")
        assertOpen()
        attach("hebrew-history-physical-left")
        tap("hanlin-history-done")
        assertClosed()
    }
}
