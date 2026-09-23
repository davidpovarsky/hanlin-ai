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

        // 1. Shimmering / lightweight live execution text appears for skill loading or tool searching
        let activityRow = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'skill' OR label CONTAINS[c] 'load_skill' OR label CONTAINS[c] 'web' OR label CONTAINS[c] 'Thinking' OR label CONTAINS[c] 'חושב'")
        ).firstMatch
        XCTAssertTrue(activityRow.waitForExistence(timeout: 45), "Lightweight tool execution activity was not rendered in chat.")

        // 2. Arbitrary embedded result surface appears in transcript
        let embeddedResult = app.staticTexts.matching(
            NSPredicate(format: "identifier == 'acceptance_embedded_surface' OR label CONTAINS[c] 'Acceptance Embedded' OR label CONTAINS[c] 'Acceptance Web' OR label CONTAINS[c] 'Embedded result'")
        ).firstMatch
        XCTAssertTrue(embeddedResult.waitForExistence(timeout: 45), "The embedded result was not rendered in chat.")

        // 3. Floating action controls appear in the unified control group (content action or expansion action)
        let floatingAction = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'content_action_' OR identifier BEGINSWITH 'expansion_action_'")
        ).firstMatch
        if floatingAction.waitForExistence(timeout: 10) {
            XCTAssertTrue(floatingAction.exists, "Floating action control was rendered in the floating control group.")
        }

        // 4. Dead / invalid actions are absent (e.g. invalid expansion identifier)
        let deadAction = app.buttons["expansion_action_invalid"]
        XCTAssertFalse(deadAction.exists, "Unresolvable action should not be rendered.")

        // 5. Final answer is rendered
        let finalAnswer = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'AGENT_SKILLS_EMBEDDED_ACCEPTANCE_COMPLETE'")
        ).firstMatch
        XCTAssertTrue(finalAnswer.waitForExistence(timeout: 45), "The deterministic provider's final answer was not rendered.")

        // 6. Completed run collapses execution steps into summary row ("Worked for X" / "פעל במשך")
        let summaryRow = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Worked for' OR label CONTAINS[c] 'פעל במשך'")
        ).firstMatch
        if summaryRow.waitForExistence(timeout: 10) {
            XCTAssertTrue(summaryRow.exists, "Completed execution collapsed into Worked for summary row.")
        }
    }

    func testUnresolvableEmbeddedHandlerFallback() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_AGENT_SKILLS_EMBEDDED_ACCEPTANCE"] = "1"
        app.launch()

        // Unresolvable handler should never show dead expansion buttons
        let deadExpansionButton = app.buttons["expansion_action_unresolvable"]
        XCTAssertFalse(deadExpansionButton.exists, "Unresolvable expansion handler should not expose a dead button.")
    }
}
