import XCTest

/// Exercises the actual application target with the existing seeded acceptance chat.
/// The service fixture supplies data; controls and navigation remain application UI.
@MainActor
final class HanlinSimulatorAcceptanceUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = "Final application screen"
        capture.lifetime = .keepAlways
        add(capture)
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    private func launch(language: String, locale: String, largeText: Bool = false) throws {
        let cohort = try XCTUnwrap(ProcessInfo.processInfo.environment["HANLIN_SIM_ACCEPTANCE_LOCALE"],
                                   "Runner must supply the test-bundle locale cohort")
        try XCTSkipIf(cohort != language, "This fixed-language case requires the \(language) cohort; received \(cohort)")
        app.launchArguments += ["-AppleLanguages", "(\(cohort))", "-AppleLocale", locale]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE"] = "1"
        app.launchEnvironment["HANLIN_DOCK_ACCEPTANCE_FIXTURES"] = "1"
        app.launch()
    }

    private func openAcceptanceChat() -> XCUIElement {
        let input = app.descendants(matching: .any)["hanlin-chat-input"].firstMatch
        if !input.waitForExistence(timeout: 5) {
            let chat = app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS %@ OR identifier CONTAINS %@", "Agent Acceptance Chat", "Agent Acceptance Chat")
            ).firstMatch
            XCTAssertTrue(chat.waitForExistence(timeout: 20), "The seeded acceptance conversation must be reachable in the actual app")
            chat.tap()
        }
        XCTAssertTrue(input.waitForExistence(timeout: 20))
        return input
    }

    private func assertInsideWindow(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertGreaterThan(element.frame.height, 0, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.minY, window.frame.minY - 1, file: file, line: line)
        XCTAssertLessThanOrEqual(element.frame.maxY, window.frame.maxY + 1, file: file, line: line)
    }

    private func enterDraft(_ draft: String, in input: XCUIElement) {
        input.tap()
        if let existing = input.value as? String, !existing.isEmpty {
            input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count + 1))
        }
        input.typeText(draft)
        XCTAssertEqual(input.value as? String, draft)
    }

    func testEnglishDraftSurvivesPortraitLandscapeRoundTrip() throws {
        try launch(language: "en", locale: "en_US")
        let input = openAcceptanceChat()
        let draft = "Rotation draft " + UUID().uuidString
        enterDraft(draft, in: input)
        XCUIDevice.shared.orientation = .landscapeLeft
        let window = app.windows.firstMatch
        let landscape = expectation(for: NSPredicate { _, _ in window.frame.width > window.frame.height }, evaluatedWith: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 10), .completed, "A landscape viewport is required")
        XCTAssertEqual(input.value as? String, draft)
        assertInsideWindow(input)
        XCUIDevice.shared.orientation = .portrait
        let portrait = expectation(for: NSPredicate { _, _ in window.frame.height > window.frame.width }, evaluatedWith: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [portrait], timeout: 10), .completed, "The viewport must return to portrait")
        XCTAssertEqual(input.value as? String, draft)
        assertInsideWindow(input)
    }

    func testHebrewLargeTextPanelRoundTripPreservesDraft() throws {
        try launch(language: "he", locale: "he_IL", largeText: true)
        let input = openAcceptanceChat()
        let draft = "RTL accessible draft " + UUID().uuidString
        enterDraft(draft, in: input)
        let launcher = app.buttons["hanlin-composer-general-menu"].firstMatch
        XCTAssertTrue(launcher.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(launcher.frame.midX, input.frame.midX, "The actual launcher must appear on the RTL side")
        launcher.tap()
        let panel = app.descendants(matching: .any)["morphing-action-panel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 10))
        assertInsideWindow(panel)
        launcher.tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 10))
        XCTAssertEqual(input.value as? String, draft)
        assertInsideWindow(input)
    }

    func testDraftSurvivesLeavingAndReturningToSeededChat() throws {
        try launch(language: "en", locale: "en_US")
        let input = openAcceptanceChat()
        let draft = "Restored draft " + UUID().uuidString
        enterDraft(draft, in: input)
        let home = app.tabBars.buttons["hanlin-home-tab"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 10) && home.isHittable, "The home tab must be reachable for a genuine navigation round trip")
        home.tap()
        let row = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@ OR identifier CONTAINS %@", "Agent Acceptance Chat", "Agent Acceptance Chat")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "Returning to the conversation list must expose the same chat")
        row.tap()
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        XCTAssertEqual(input.value as? String, draft, "Returning to the same chat must restore the draft")
    }
}
