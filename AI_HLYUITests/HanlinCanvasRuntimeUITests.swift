import XCTest

/// Existing Canvas, Host, CPython and SwiftData. Only initial disposable input is seeded.
@MainActor
final class HanlinCanvasRuntimeUITests: XCTestCase {
    func testOriginalCanvasRunsEmbeddedPythonAndRetainsSourceAfterRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_SIMULATE_CONTAINER_WIDTH"] = "390"
        app.launchEnvironment["HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE"] = "1"
        app.launchEnvironment["HANLIN_CANVAS_ACCEPTANCE_FIXTURES"] = "1"
        app.launchEnvironment["HANLIN_PHASE2_STORE_ID"] = UUID().uuidString
        defer { app.terminate() }

        func openOriginalCanvas() {
            let chat = app.buttons.matching(NSPredicate(
                format: "label CONTAINS 'Agent Acceptance Chat'"
            )).firstMatch
            XCTAssertTrue(chat.waitForExistence(timeout: 20))
            chat.tap()
            let canvas = app.buttons["hanlin-canvas-open"].firstMatch
            XCTAssertTrue(canvas.waitForExistence(timeout: 15) && canvas.isHittable)
            canvas.tap()
            XCTAssertTrue(app.navigationBars["Canvas runtime acceptance"].firstMatch.waitForExistence(timeout: 10))
        }
        func runLocally() {
            let menu = app.buttons["hanlin-canvas-python-menu"].firstMatch
            XCTAssertTrue(menu.waitForExistence(timeout: 15) && menu.isHittable)
            menu.tap()
            let local = app.buttons["hanlin-canvas-python-local"].firstMatch
            XCTAssertTrue(local.waitForExistence(timeout: 10))
            local.tap()
            let output = app.staticTexts["hanlin-canvas-python-output"].firstMatch
            XCTAssertTrue(output.waitForExistence(timeout: 45))
            let result = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label CONTAINS 'CANVAS_LOCAL_RESULT_42'"), object: output)
            XCTAssertEqual(XCTWaiter.wait(for: [result], timeout: 45), .completed,
                           "The actual embedded runtime must compute the result")
        }

        app.launch()
        openOriginalCanvas()
        runLocally()
        let output = app.staticTexts["hanlin-canvas-python-output"].firstMatch
        let originalOutput = output.label
        app.buttons["hanlin-canvas-python-menu"].firstMatch.tap()
        app.buttons["hanlin-canvas-python-remote"].firstMatch.tap()
        let confirmation = app.buttons["hanlin-canvas-python-remote-confirm"].firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 10),
                      "Remote code transfer requires an explicit separate action")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'emkc.org'")).firstMatch.exists)
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertEqual(output.label, originalOutput)
        XCTAssertTrue(app.buttons["hanlin-canvas-python-menu"].firstMatch.isEnabled)
        let first = XCTAttachment(screenshot: app.screenshot())
        first.name = "original-canvas-embedded-python-and-remote-disclosure"
        first.lifetime = .keepAlways
        add(first)
        app.buttons["hanlin-canvas-done"].firstMatch.tap()

        app.terminate()
        app.launch()
        openOriginalCanvas()
        runLocally()
        let restored = XCTAttachment(screenshot: app.screenshot())
        restored.name = "original-canvas-cold-restored-source-computes-again"
        restored.lifetime = .keepAlways
        add(restored)
    }
}
