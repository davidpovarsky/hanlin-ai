import XCTest

/// Original app/Host UI with a declared HTTP provider and embedded-renderer
/// fixture. These cases do not claim a live cloud model or companion process.
@MainActor
final class AgentSkillsEmbeddedResultsUITests: XCTestCase {
    func testAgentSkillsDeferredExposureAndEmbeddedResultFlow() throws {
        continueAfterFailure = false
        let app = launchSkillsApp(fallback: false)
        defer { app.terminate() }
        let input = openOriginalChat(in: app)
        input.tap()
        input.typeText("EMBEDDED_FLOW_ACCEPTANCE: load the original skill and show its result.")
        let send = app.buttons["hanlin-chat-send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 10) && send.isHittable)
        send.tap()

        // This opt-in provider only finishes after the actual load_skill result,
        // newly exposed schema, tool_search result and successful web receipt.
        let allow = app.buttons["hanlin-tool-consent-allow-once"].firstMatch
        // The original selectable Markdown paragraph is a native TextView.
        // Run 44264369849's real snapshot reports elementType 52, not StaticText.
        let final = app.textViews.matching(NSPredicate(
            format: "label CONTAINS 'AGENT_SKILLS_EMBEDDED_ACCEPTANCE_COMPLETE'")).firstMatch
        let nextStep = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            final.exists || allow.exists
        }, object: app)
        let nextStepResult = XCTWaiter.wait(for: [nextStep], timeout: 60)
        if nextStepResult != .completed { attachHierarchy(in: app, name: "original-embedded-flow-wait-failure") }
        XCTAssertEqual(nextStepResult, .completed,
                       "Original model/Host did not reach its next visible step")
        if allow.exists {
            let request = app.descendants(matching: .any)["hanlin-tool-consent-original-request"].firstMatch
            XCTAssertTrue(request.exists)
            XCTAssertTrue(request.label.contains("Acceptance Web Surface"))
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(
                format: "label CONTAINS 'create_web_view'")).firstMatch.exists)
            allow.tap()
        }
        XCTAssertTrue(final.waitForExistence(timeout: 60), "Original tool/exposure flow did not complete: \(app.debugDescription)")

        let toggle = app.descendants(matching: .any)["hanlin-reasoning-toggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        reveal(toggle, in: app)
        toggle.tap()
        for id in ["ui-load-skill-call", "ui-tool-search-call", "ui-web-call"] {
            let activity = app.descendants(matching: .any)["hanlin-agent-activity-" + id].firstMatch
            XCTAssertTrue(activity.waitForExistence(timeout: 10), "Missing actual original call: \(id)")
            let completed = activity.descendants(matching: .any).matching(
                NSPredicate(format: "value == 'Completed' OR label == 'Completed'")).firstMatch
            XCTAssertTrue(completed.exists, "Original call did not complete successfully: \(id)")
        }
        toggle.tap()

        let surface = app.staticTexts["acceptance_embedded_surface"].firstMatch
        XCTAssertTrue(surface.waitForExistence(timeout: 10), "The actual resolver fixture must render inside the original transcript")
        let expand = app.buttons["expansion_action_sheet"].firstMatch
        reveal(expand, in: app)
        XCTAssertTrue(expand.isHittable, "Declared valid expansion must be reachable")
        expand.tap()
        let done = app.navigationBars.buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(identifier: "acceptance_embedded_surface")
            .allElementsBoundByIndex.contains(where: { $0.isHittable }),
            "The expanded original surface must actually be visible above the transcript")
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))
        XCTAssertTrue(final.exists, "Closing expansion must retain the original answer")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "original-agent-skill-and-embedded-result"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testUnresolvableEmbeddedHandlerFallback() throws {
        continueAfterFailure = false
        let app = launchSkillsApp(fallback: true)
        defer { app.terminate() }
        _ = openOriginalChat(in: app)
        let original = app.textViews.matching(NSPredicate(
            format: "label CONTAINS 'UNRESOLVED_RESULT_ORIGINAL_MESSAGE'")).firstMatch
        let originalAppeared = original.waitForExistence(timeout: 10)
        if !originalAppeared { attachHierarchy(in: app, name: "original-embedded-fallback-wait-failure") }
        XCTAssertTrue(originalAppeared, "The seeded original result must actually be visible")
        let fallback = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS 'UNRESOLVED_HANDLER_NATIVE_FALLBACK_CONTENT'")).firstMatch
        XCTAssertTrue(fallback.waitForExistence(timeout: 10), "Unavailable handler must preserve native fallback content")
        XCTAssertEqual(app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'expansion_action_'")).count, 0,
            "Unresolved explicit expansion must not create a dead sheet/full-screen button")
        XCTAssertFalse(app.staticTexts["acceptance_embedded_surface"].exists,
                       "Unknown original owner must not borrow the unrelated injected resolver")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "original-unresolved-handler-native-fallback"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func launchSkillsApp(fallback: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_AGENT_SKILLS_EMBEDDED_ACCEPTANCE"] = "1"
        app.launchEnvironment[fallback ? "HANLIN_EMBEDDED_FALLBACK_FIXTURE" : "HANLIN_EMBEDDED_RESULT_STRICT_ACCEPTANCE"] = "1"
        app.launch()
        return app
    }

    private func openOriginalChat(in app: XCUIApplication) -> XCUIElement {
        let field = app.textFields["hanlin-chat-input"].firstMatch
        let editor = app.textViews["hanlin-chat-input"].firstMatch
        if !field.exists && !editor.exists {
            let chat = app.staticTexts["Agent Acceptance Chat"].firstMatch
            XCTAssertTrue(chat.waitForExistence(timeout: 20))
            chat.tap()
        }
        if field.exists { return field }
        XCTAssertTrue(editor.waitForExistence(timeout: 20), "Original native Composer must be available")
        return editor
    }

    private func attachHierarchy(in app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<5 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTFail("Original result control is not reachable: \(element.identifier)")
    }
}
