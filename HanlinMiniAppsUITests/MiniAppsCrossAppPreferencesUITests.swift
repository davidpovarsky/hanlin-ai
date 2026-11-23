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
        add(screenshot)
        app.terminate()
    }
    func testSharedNewWindowPreferencePersistsAfterProcessRestart() {
        openPreferences()
        let toggle = app.switches["miniapps-new-window"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 15))
        let before = toggle.value as? String
        toggle.tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", before ?? ""), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed)
        let expected = toggle.value as? String
        app.terminate()
        app.launch()
        openPreferences()
        let reopened = app.switches["miniapps-new-window"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 15))
        XCTAssertEqual(reopened.value as? String, expected)
        reopened.tap()
    }
    func testAppleStyleEditorAddsFavoriteWithNativeEditControls() {
        openPreferences()
        let edit = app.buttons["Edit"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 15))
        edit.tap()
        let add = app.buttons["Add to Favorites: Text Studio"]
        XCTAssertTrue(add.waitForExistence(timeout: 15))
        add.tap()
        XCTAssertTrue(add.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Favorites"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Text Studio"].firstMatch.exists)
    }
    private func openPreferences() {
        let button = app.buttons["miniapps-preferences"]
        XCTAssertTrue(button.waitForExistence(timeout: 40))
        button.tap()
    }
}
