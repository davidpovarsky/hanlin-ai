import XCTest

@MainActor
final class HanlinContextualTextToolsUITests: XCTestCase {
    func testOriginalTextToolsReceiveTheMessageWithoutReplacingTheConversation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_SIMULATE_CONTAINER_WIDTH"] = "390"
        app.launchEnvironment["HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE"] = "1"
        app.launchEnvironment["HANLIN_CONTEXTUAL_TEXT_ACCEPTANCE"] = "1"
        app.launchEnvironment["HANLIN_PHASE2_STORE_ID"] = UUID().uuidString
        app.launch()
        defer { app.terminate() }
        let chat = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Agent Acceptance Chat'")).firstMatch
        XCTAssertTrue(chat.waitForExistence(timeout: 20))
        chat.tap()
        let select = app.buttons["hanlin-action-select"].firstMatch
        XCTAssertTrue(select.waitForExistence(timeout: 15))
        select.tap()
        let menu = app.buttons["hanlin-text-actions-menu"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10))

        let original = "CONTEXT_TEXT_ORIGINAL_428: The selected message stays in its original conversation."
        for tool in ["translation", "polish", "summary"] {
            menu.tap()
            let action = app.buttons["hanlin-text-action-" + tool].firstMatch
            XCTAssertTrue(action.waitForExistence(timeout: 10))
            action.tap()
            let input = app.textViews["hanlin-writing-tool-input"].firstMatch
            XCTAssertTrue(input.waitForExistence(timeout: 10))
            XCTAssertEqual(input.value as? String, original,
                           "The retained tool must receive the real contextual message")
            app.buttons["hanlin-writing-tool-done"].firstMatch.tap()
            XCTAssertTrue(menu.waitForExistence(timeout: 10))
        }
        app.buttons["hanlin-text-selection-done"].firstMatch.tap()
        XCTAssertTrue(select.waitForExistence(timeout: 10))
        let retained = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS 'CONTEXT_TEXT_ORIGINAL_428' OR value CONTAINS 'CONTEXT_TEXT_ORIGINAL_428'"
        )).firstMatch
        XCTAssertTrue(retained.exists)
        let pixels = XCTAttachment(screenshot: app.screenshot())
        pixels.name = "original-contextual-text-tools-returned-to-message"
        pixels.lifetime = .keepAlways
        add(pixels)
    }
}
