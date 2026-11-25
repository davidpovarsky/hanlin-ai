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

    private func assertOpen() {
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        waitUntilHittable(close)
        XCTAssertTrue(library.exists)
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(library.frame.minX, window.minX, accuracy: 2,
            "The real history layer must reveal from physical left, also in Hebrew.")
        XCTAssertLessThan(library.frame.width, window.width * 0.9)
        XCTAssertFalse(editor.isHittable, "The exposed workspace strip must not edit or send a chat.")
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
