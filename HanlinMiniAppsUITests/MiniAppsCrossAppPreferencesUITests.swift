import XCTest

@MainActor
final class MiniAppsCrossAppPreferencesUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.itorah.hanlinminiapps")
    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }
    override func tearDownWithError() throws {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Shared MiniApps preferences"
        screenshot.lifetime = .keepAlways
        self.add(screenshot)
        app.terminate()
    }
    func testSharedNewWindowPreferencePersistsAfterProcessRestart() {
        openPreferences()
        let toggle = app.switches["miniapps-new-window"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 15))
        let before = toggle.value as? String
        tapNativeSwitch(in: toggle)
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", before ?? ""), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed)
        let expected = toggle.value as? String
        app.terminate()
        app.launch()
        openPreferences()
        let reopened = app.switches["miniapps-new-window"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 15))
        XCTAssertEqual(reopened.value as? String, expected)
        tapNativeSwitch(in: reopened)
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", before ?? ""), object: reopened)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 10), .completed)
    }
    func testAppleStyleEditorAddsFavoriteWithNativeEditControls() {
        openPreferences()
        let edit = app.buttons["miniapps-editor-edit"]
        let close = app.buttons["miniapps-editor-dismiss"]
        XCTAssertTrue(edit.waitForExistence(timeout: 15))
        XCTAssertTrue(close.waitForExistence(timeout: 15))
        XCTAssertLessThan(close.frame.midX, edit.frame.midX, "English Apps uses leading dismissal and trailing Edit.")
        edit.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 10))
        XCTAssertEqual(app.navigationBars.buttons.matching(identifier: "miniapps-editor-edit").count, 1,
                       "Editing must retain one native EditButton in its Done state, regardless of system language or symbol rendering.")
        XCTAssertEqual(app.buttons.matching(identifier: "miniapps-editor-dismiss").count, 0,
                       "The separate sheet-dismissal action must be absent during editing.")
        let add = app.buttons["Add to Favorites: Text Studio"]
        XCTAssertTrue(add.waitForExistence(timeout: 15))
        add.tap()
        XCTAssertTrue(add.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Favorites"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Text Studio"].firstMatch.exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Apps editor with one Done"
        screenshot.lifetime = .keepAlways
        self.add(screenshot)
        edit.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        close.tap()
        XCTAssertTrue(app.buttons["miniapps-preferences"].waitForExistence(timeout: 10),
                      "The editor's own dismissal action must close the actual preferences sheet.")
    }
    private func tapNativeSwitch(in row: XCUIElement) {
        // SwiftUI exposes a labeled switch row and its actual UISwitch as a
        // nested switch. The row's center is its label, not the control thumb.
        let control = row.switches.firstMatch
        XCTAssertTrue(control.waitForExistence(timeout: 10))
        XCTAssertTrue(control.isHittable)
        control.tap()
    }

    private func openPreferences() {
        let button = app.buttons["miniapps-preferences"]
        XCTAssertTrue(button.waitForExistence(timeout: 40))
        button.tap()
    }
}
