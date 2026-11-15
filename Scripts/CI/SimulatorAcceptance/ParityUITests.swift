import XCTest

@MainActor
final class ParityUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        let locale = ProcessInfo.processInfo.environment["HANLIN_SIM_ACCEPTANCE_LOCALE"] ?? "en"
        app.launchArguments += ["-AppleLanguages", "(\(locale))", "-AppleLocale", locale == "he" ? "he_IL" : "en_US"]
        app.launch()
        XCTAssertTrue(app.textFields["Name"].waitForExistence(timeout: 15))
        let state = app.staticTexts.matching(NSPredicate(format: "label IN %@", ["No saved value yet", "Reloaded persisted value"])).firstMatch
        XCTAssertTrue(state.waitForExistence(timeout: 10))
        return app
    }

    private func enter(_ text: String, app: XCUIApplication) {
        let field = app.textFields["Name"]
        field.tap()
        let previous = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count))
        field.typeText(text)
        XCTAssertEqual(field.value as? String, text)
    }

    private func save(_ app: XCUIApplication) {
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Saved in canonical private container"].waitForExistence(timeout: 10))
    }

    private func assertName(_ expected: String, app: XCUIApplication) {
        let match = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: app.textFields["Name"])
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: 10), .completed)
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testActualPrivateStorageSurvivesProcessRelaunch() {
        let app = launch()
        defer { app.terminate() }
        enter("Persisted UI27", app: app)
        save(app)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Reloaded persisted value"].waitForExistence(timeout: 10))
        assertName("Persisted UI27", app: app)
        capture(app, name: "real-private-storage-after-relaunch")
    }

    func testReloadReplacesOnlyUnsavedDraft() {
        let app = launch()
        defer { app.terminate() }
        enter("Saved UI27", app: app)
        save(app)
        enter("Unsaved UI27", app: app)
        app.buttons["Reload"].tap()
        XCTAssertTrue(app.staticTexts["Reloaded persisted value"].waitForExistence(timeout: 10))
        assertName("Saved UI27", app: app)
        capture(app, name: "real-reload-after-unsaved-edit")
    }
}
