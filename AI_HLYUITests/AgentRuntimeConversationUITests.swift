import XCTest

@MainActor
final class AgentRuntimeConversationUITests: XCTestCase {
    func testRealChatUISendsPromptShowsToolActivityAndFinalAnswer() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE"] = "1"
        app.launch()

        let input = app.textFields["hanlin-chat-input"].firstMatch
        if !input.waitForExistence(timeout: 5) {
            let seededChat = app.staticTexts["Agent Acceptance Chat"].firstMatch
            XCTAssertTrue(seededChat.waitForExistence(timeout: 15), "The deterministic acceptance chat was not listed.")
            seededChat.tap()
        }
        XCTAssertTrue(input.waitForExistence(timeout: 20), "The real chat input did not appear.")
        input.tap()
        input.typeText("Run the local Python acceptance tool and report the result.")

        let send = app.buttons["hanlin-chat-send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 10), "The real chat send button did not appear.")
        send.tap()

        let finalAnswer = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'AGENT_UI_ACCEPTANCE_COMPLETE'")
        ).firstMatch
        XCTAssertTrue(finalAnswer.waitForExistence(timeout: 45), "The deterministic provider's final answer was not rendered.")

        let activitySummary = app.buttons["hanlin-agent-activity-summary"].firstMatch
        XCTAssertTrue(activitySummary.waitForExistence(timeout: 10), "The completed agent activity summary was not rendered.")
        activitySummary.tap()

        let failedActivity = app.buttons["hanlin-agent-tool-failed"].firstMatch
        XCTAssertTrue(failedActivity.waitForExistence(timeout: 10), "The intentional tool failure was not presented truthfully in the real chat UI.")
        XCTAssertTrue(
            failedActivity.label.localizedCaseInsensitiveContains("invalid"),
            "The failed activity did not identify the invalid arguments."
        )

        let toolActivity = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Local Python' OR label CONTAINS[c] 'ui-tool-ok'")
        ).firstMatch
        XCTAssertTrue(toolActivity.waitForExistence(timeout: 45), "Tool activity/result was not rendered in the real chat UI.")

    }
}
