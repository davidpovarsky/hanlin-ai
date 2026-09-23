import XCTest

@MainActor
final class AgentSkillsEmbeddedResultsUITests: XCTestCase {
    func testAgentSkillsDeferredExposureAndEmbeddedResultFlow() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_AGENT_SKILLS_EMBEDDED_ACCEPTANCE"] = "1"
        app.launch()

        let input = app.textFields["hanlin-chat-input"].firstMatch
        if !input.waitForExistence(timeout: 5) {
            let seededChat = app.staticTexts["Agent Acceptance Chat"].firstMatch
            XCTAssertTrue(seededChat.waitForExistence(timeout: 15), "The deterministic acceptance chat was not listed.")
            seededChat.tap()
        }
        XCTAssertTrue(input.waitForExistence(timeout: 20), "The chat input field did not appear.")
        input.tap()
        input.typeText("Load acceptance skill and render web view result.")

        let send = app.buttons["hanlin-chat-send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 10), "The chat send button did not appear.")
        send.tap()

        // 1. Shimmering / lightweight execution text appears for skill loading or tool searching
        let activityRow = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'skill' OR label CONTAINS[c] 'load_skill' OR label CONTAINS[c] 'web' OR label CONTAINS[c] 'Thinking'")
        ).firstMatch
        XCTAssertTrue(activityRow.waitForExistence(timeout: 45), "Lightweight tool execution activity was not rendered in chat.")

        // 2. Embedded result card or web surface appears in transcript
        let embeddedResult = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Acceptance Web' OR label CONTAINS[c] 'Embedded result' OR label CONTAINS[c] 'Web'")
        ).firstMatch
        XCTAssertTrue(embeddedResult.waitForExistence(timeout: 45), "The embedded result was not rendered in chat.")

        // 3. Final answer is rendered
        let finalAnswer = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'AGENT_SKILLS_EMBEDDED_ACCEPTANCE_COMPLETE'")
        ).firstMatch
        XCTAssertTrue(finalAnswer.waitForExistence(timeout: 45), "The deterministic provider's final answer was not rendered.")
    }
}
