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
    func testPreferencesUsesEnglishAndHebrewNativeToolbarLayouts() {
        // Package title/row/dismissal strings come from the real en/he resources.
        // Native EditButton may render a symbol: never guess its translated label.
        let variants: [(language: String, locale: String, title: String,
                        newWindow: String, dismissal: String, isRTL: Bool)] = [
            ("en", "en_US", "Apps", "Open shared MiniApps in a new window", "Done", false),
            ("he", "he_IL", "אפליקציות", "פתיחת מיני־אפליקציות משותפות בחלון חדש", "סיום", true)
        ]
        for (index, variant) in variants.enumerated() {
            if index > 0 {
                app.terminate()
                app.launchArguments = ["-AppleLanguages", "(\(variant.language))",
                                       "-AppleLocale", variant.locale]
                app.launch()
            }
            openPreferences()
            let edit = app.buttons["miniapps-editor-edit"]
            let close = app.buttons["miniapps-editor-dismiss"]
            XCTAssertTrue(edit.waitForExistence(timeout: 15))
            XCTAssertTrue(close.waitForExistence(timeout: 15))
            let toolbar = app.navigationBars.containing(.button, identifier: "miniapps-editor-edit").firstMatch
            XCTAssertTrue(toolbar.waitForExistence(timeout: 10))
            XCTAssertTrue(toolbar.staticTexts[variant.title].waitForExistence(timeout: 10),
                          "The actual preferences sheet must show its package-localized title.")
            let newWindow = app.switches["miniapps-new-window"]
            XCTAssertTrue(newWindow.waitForExistence(timeout: 10))
            XCTAssertEqual(newWindow.label, variant.newWindow)
            XCTAssertEqual(close.label, variant.dismissal)
            XCTAssertTrue(close.isHittable)
            XCTAssertTrue(edit.isHittable)
            if variant.isRTL {
                XCTAssertGreaterThan(close.frame.midX, edit.frame.midX,
                                     "Hebrew must place leading dismissal on the right and trailing Edit on the left.")
            } else {
                XCTAssertLessThan(close.frame.midX, edit.frame.midX,
                                  "English must place leading dismissal on the left and trailing Edit on the right.")
            }
            let normal = XCTAttachment(screenshot: app.screenshot())
            normal.name = "MiniApps \(variant.language) native toolbar"
            normal.lifetime = .keepAlways
            self.add(normal)
            edit.tap()
            XCTAssertTrue(close.waitForNonExistence(timeout: 10))
            XCTAssertEqual(toolbar.buttons.count, 1,
                           "Editing must expose exactly one native toolbar confirmation.")
            XCTAssertEqual(toolbar.buttons.matching(identifier: "miniapps-editor-edit").count, 1)
            XCTAssertEqual(app.buttons.matching(identifier: "miniapps-editor-dismiss").count, 0)
            let editing = XCTAttachment(screenshot: app.screenshot())
            editing.name = "MiniApps \(variant.language) one native confirmation"
            editing.lifetime = .keepAlways
            self.add(editing)
            edit.tap()
            XCTAssertTrue(close.waitForExistence(timeout: 10))
            close.tap()
            XCTAssertTrue(app.buttons["miniapps-preferences"].waitForExistence(timeout: 10),
                          "The localized editor must dismiss its actual sheet.")
        }
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
