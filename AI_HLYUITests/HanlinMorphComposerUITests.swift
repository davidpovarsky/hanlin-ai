import XCTest

@MainActor
final class HanlinMorphComposerUITests: XCTestCase {
    func testCompactNavigationKeepsDraft() throws {
        try verifyNavigation(width: "390")
    }

    func testWideNavigationKeepsDraft() throws {
        try verifyNavigation(width: "1024")
    }

    private func verifyNavigation(width: String) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE"] = "1"
        app.launchEnvironment["HANLIN_DOCK_ACCEPTANCE_FIXTURES"] = "1"
        app.launchEnvironment["HANLIN_SIMULATE_CONTAINER_WIDTH"] = width
        app.launch()
        defer { app.terminate() }

        let input = app.descendants(matching: .any)["hanlin-chat-input"].firstMatch
        if !input.waitForExistence(timeout: 5) {
            let chat = app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS 'Agent Acceptance Chat' OR identifier CONTAINS 'Agent Acceptance Chat'")
            ).firstMatch
            XCTAssertTrue(chat.waitForExistence(timeout: 15))
            chat.tap()
        }
        XCTAssertTrue(input.waitForExistence(timeout: 20))
        input.tap()
        let draft = "Morph keeps this draft"
        input.typeText(draft)

        let plus = app.buttons["hanlin-composer-general-menu"].firstMatch
        XCTAssertTrue(plus.waitForExistence(timeout: 10))
        plus.tap()
        let panel = app.descendants(matching: .any)["morphing-action-panel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 10))
        let prompts = app.buttons["hanlin-general-prompts-button"].firstMatch
        for _ in 0..<6 where !prompts.isHittable { panel.swipeUp() }
        XCTAssertTrue(prompts.isHittable)
        prompts.tap()
        let back = app.buttons["hanlin-general-subpage-back"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertTrue(panel.exists, "Internal navigation must retain the panel")
        back.tap()
        XCTAssertTrue(panel.exists)
        plus.tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, draft)

        let tools = app.buttons["hanlin-composer-tools-direct"].firstMatch
        XCTAssertTrue(tools.waitForExistence(timeout: 5))
        tools.tap()
        let skills = app.buttons["hanlin-tools-open-skills"].firstMatch
        for _ in 0..<6 where !skills.isHittable { panel.swipeUp() }
        XCTAssertTrue(skills.isHittable)
        skills.tap()
        let toolsBack = app.buttons["hanlin-tools-subpage-back"].firstMatch
        XCTAssertTrue(toolsBack.waitForExistence(timeout: 5))
        XCTAssertTrue(panel.exists)
        toolsBack.tap()
        XCTAssertTrue(skills.waitForExistence(timeout: 5))
        tools.tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, draft)
    }
}
