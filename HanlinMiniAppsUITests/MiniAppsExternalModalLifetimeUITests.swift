import XCTest

/// The fixture is installed through the original package UI. Its real JSC
/// invocation must survive an actual nested SwiftUI full-screen presentation.
@MainActor
final class MiniAppsExternalModalLifetimeUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.itorah.hanlinminiapps")
    private let requestID = "4f2ecda0-9c21-46a2-b2e1-8cd4f017c623"

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 300
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
    }

    override func tearDownWithError() throws {
        if testRun?.hasSucceeded == false {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "external-modal-failure"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "external-modal-accessibility"
            tree.lifetime = .keepAlways
            add(tree)
        }
        app.terminate()
    }

    func testExternalInvocationSurvivesNestedFullScreenModal() throws {
        app.launch()
        let addApp = app.buttons["hanlin-apps-add"].firstMatch
        XCTAssertTrue(addApp.waitForExistence(timeout: 40))
        addApp.tap()
        let importPackage = app.buttons["hanlin-import-script-package"].firstMatch
        XCTAssertTrue(importPackage.waitForExistence(timeout: 15))
        importPackage.tap()
        let packages = app.collectionViews["hanlin-package-import-list"]
        XCTAssertTrue(packages.waitForExistence(timeout: 15))
        let archive = app.buttons["MiniAppsExternalModal"].firstMatch
        for _ in 0..<8 {
            if archive.exists && archive.isHittable { break }
            packages.swipeUp()
        }
        XCTAssertTrue(archive.exists && archive.isHittable)
        archive.tap()
        let install = app.buttons["hanlin-package-install"].firstMatch
        XCTAssertTrue(install.waitForExistence(timeout: 30))
        XCTAssertTrue(install.isEnabled)
        install.tap()
        XCTAssertTrue(install.waitForNonExistence(timeout: 60), "The original compiler and installer must finish")
        let previewDone = app.navigationBars["Script Package"].buttons["Done"]
        XCTAssertTrue(previewDone.waitForExistence(timeout: 15))
        previewDone.tap()
        let closeAdd = app.buttons["hanlin-apps-add-done"].firstMatch
        XCTAssertTrue(closeAdd.waitForExistence(timeout: 15))
        closeAdd.tap()
        XCTAssertTrue(app.buttons["hanlin-package-card-External Modal Fixture"].firstMatch.waitForExistence(timeout: 20))

        // Public XCUIApplication URL launching, iOS 16.4+; no Safari/private hook.
        app.open(try XCTUnwrap(URL(string: "hanlinminiapps://x-callback-url/run?request=" + requestID)))
        XCTAssertTrue(app.staticTexts["Context " + requestID].waitForExistence(timeout: 40))
        XCTAssertTrue(app.staticTexts["Input Shared modal input 20261123"].exists)
        XCTAssertFalse(app.buttons["hanlin-script-app-close"].exists,
                       "The external invocation owns Close; the nested runtime must not expose a second teardown control")
        let increment = app.buttons["Increment counter"]
        XCTAssertTrue(increment.waitForExistence(timeout: 15))
        increment.tap()
        XCTAssertTrue(app.staticTexts["Counter 1"].waitForExistence(timeout: 10))
        capture("external-modal-context-before")
        app.buttons["Open nested full screen"].tap()
        XCTAssertTrue(app.staticTexts["Nested modal is active"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Modal context " + requestID].exists)
        capture("external-modal-full-screen")
        app.buttons["Dismiss nested full screen"].tap()
        XCTAssertTrue(app.staticTexts["Nested modal is active"].waitForNonExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Counter 1"].waitForExistence(timeout: 15), "The original JS state must survive covering presentation")
        XCTAssertTrue(app.staticTexts["Context " + requestID].exists)
        XCTAssertTrue(increment.isHittable)
        increment.tap()
        XCTAssertTrue(app.staticTexts["Counter 2"].waitForExistence(timeout: 10))
        capture("external-modal-dismissed")
        app.buttons["Complete modal invocation"].tap()
        XCTAssertTrue(app.staticTexts["Modal invocation survived"].waitForExistence(timeout: 30),
                      "The same real engine must complete and persist its actual external result")
        XCTAssertFalse(app.staticTexts["Cancelled"].exists)
        capture("external-modal-result-saved")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
