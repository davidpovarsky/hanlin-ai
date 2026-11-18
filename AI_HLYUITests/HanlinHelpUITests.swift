import XCTest

@MainActor
final class HanlinHelpUITests: XCTestCase {
    func testOfflineGuideCostsAndSupportReturnToTheOriginalProfile() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launch()
        defer { app.terminate() }
        let profile = app.descendants(matching: .any)["hanlin-settings-tab"].firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout: 20) && profile.isHittable)
        profile.tap()
        let settings = app.descendants(matching: .any)["hanlin-settings-list"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        func reveal(_ identifier: String) -> XCUIElement {
            let target = app.descendants(matching: .any)[identifier].firstMatch
            for _ in 0..<10 {
                if target.isHittable { return target }
                settings.swipeUp()
            }
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "unreachable-help-control-" + identifier
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            XCTFail("Profile destination is unreachable: \(identifier)")
            return target
        }
        for (link, page, content) in [
            ("hanlin-help-guide-link", "hanlin-help-guide", "Start a conversation"),
            ("hanlin-help-costs-link", "hanlin-help-costs", "Cloud model costs")
        ] {
            reveal(link).tap()
            XCTAssertTrue(app.descendants(matching: .any)[page].firstMatch.waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts[content].firstMatch.exists)
            XCTAssertEqual(app.webViews.count, 0, "Help must work offline in the native app")
            app.buttons["hanlin-help-done"].firstMatch.tap()
            XCTAssertTrue(settings.waitForExistence(timeout: 5))
        }
        reveal("hanlin-support-link").tap()
        let details = app.staticTexts["hanlin-support-details"].firstMatch
        XCTAssertTrue(details.waitForExistence(timeout: 10))
        XCTAssertTrue(details.label.contains("Version:"))
        XCTAssertTrue(app.buttons["hanlin-support-share"].firstMatch.exists)
        app.buttons["hanlin-support-copy"].firstMatch.tap()
        XCTAssertTrue(app.buttons["hanlin-support-copy"].firstMatch.label.contains("Copied"))
        XCTAssertFalse(app.staticTexts["ai.hanlin@outlook.com"].exists)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "native-hanlin-support-build-details"
        capture.lifetime = .keepAlways
        add(capture)
    }
}
