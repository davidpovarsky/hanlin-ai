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
        let disclosure = XCTAttachment(screenshot: app.screenshot())
        disclosure.name = "original-canvas-remote-consent-before-dismissal"
        disclosure.lifetime = .keepAlways
        add(disclosure)

        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.exists && cancel.isHittable {
            cancel.tap()
        } else {
            // In regular-width iOS, confirmationDialog presents a popover and
            // omits Cancel. Dismiss it through the original outside-tap gesture.
            let popover = app.popovers.containing(
                .button, identifier: "hanlin-canvas-python-remote-confirm"
            ).firstMatch
            XCTAssertTrue(popover.waitForExistence(timeout: 5),
                          "A missing Cancel is valid only for the native confirmation popover")
            XCTAssertTrue(output.exists && !output.frame.isEmpty)
            let outputCenter = CGPoint(x: output.frame.midX, y: output.frame.midY)
            XCTAssertTrue(app.windows.firstMatch.frame.contains(outputCenter))
            XCTAssertFalse(popover.frame.contains(outputCenter),
                           "The dismissal point must be outside the remote confirmation")
            // The noninteractive output is inside Canvas, so this gesture dismisses
            // the confirmation without activating a different Canvas action.
            output.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(confirmation.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Canvas runtime acceptance"].firstMatch.exists,
                      "Dismissing consent must keep the original Canvas open")
        XCTAssertEqual(output.label, originalOutput)
        XCTAssertTrue(app.buttons["hanlin-canvas-python-menu"].firstMatch.isEnabled)
        XCTAssertFalse(app.buttons["hanlin-canvas-python-cancel"].firstMatch.exists,
                       "Dismissing remote consent must not start Python execution")
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
