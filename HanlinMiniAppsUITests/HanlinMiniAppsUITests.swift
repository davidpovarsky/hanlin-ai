import XCTest

@MainActor
final class HanlinMiniAppsUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.itorah.hanlinminiapps")

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    }

    override func tearDownWithError() throws {
        if testRun?.hasSucceeded == false {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.lifetime = .keepAlways
            add(screenshot)
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "MiniApps accessibility tree"
            tree.lifetime = .keepAlways
            add(tree)
        }
        app.terminate()
    }

    func testStandaloneCatalogOpensRealCompiledApp() throws {
        app.launch()
        try openParity()
        XCTAssertTrue(app.textFields["Name"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["hanlin.demo.swift-parity"].exists)
        XCTAssertTrue(app.buttons["Save"].exists)
        XCTAssertTrue(app.buttons["Reload"].exists)
    }

    func testPrivateStateSurvivesStandaloneProcessRelaunch() throws {
        app.launch()
        try openParity()
        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 15))
        let value = "MiniApps-" + String(UUID().uuidString.prefix(8))
        name.tap()
        let oldValue = name.value as? String ?? ""
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldValue.count) + value)
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Saved in canonical private container"].waitForExistence(timeout: 15))
        app.terminate()
        app.launch()
        try openParity()
        let restored = app.textFields["Name"]
        XCTAssertTrue(restored.waitForExistence(timeout: 15))
        XCTAssertTrue(NSPredicate(format: "value == %@", value).evaluate(with: restored)
                      || XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                        predicate: NSPredicate(format: "value == %@", value), object: restored
                      )], timeout: 15) == .completed)
    }

    func testPackageImportUsesExistingPreviewScreen() throws {
        app.launch()
        let manage = app.buttons["hanlin-miniapps-management"]
        XCTAssertTrue(manage.waitForExistence(timeout: 30))
        manage.tap()
        let importPackage = app.buttons["hanlin-miniapps-package-import"]
        XCTAssertTrue(importPackage.waitForExistence(timeout: 15))
        importPackage.tap()
        XCTAssertTrue(app.buttons["hanlin-file-importer"].waitForExistence(timeout: 15))
    }

    func testInstalledScriptUIAppearsAndRunsAfterRestart() throws {
        executionTimeAllowance = 240
        app.launch()
        let manage = app.buttons["hanlin-miniapps-management"]
        XCTAssertTrue(manage.waitForExistence(timeout: 30))
        manage.tap()
        let importPackage = app.buttons["hanlin-miniapps-package-import"]
        XCTAssertTrue(importPackage.waitForExistence(timeout: 15))
        importPackage.tap()
        let archive = app.buttons["HanlinScriptUIValid"]
        XCTAssertTrue(archive.waitForExistence(timeout: 15), "The production package fixture must be staged in this app's Documents.")
        archive.tap()
        let install = app.buttons["hanlin-package-install"]
        XCTAssertTrue(install.waitForExistence(timeout: 30))
        XCTAssertTrue(install.isEnabled)
        install.tap()
        let installed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: install)
        XCTAssertEqual(XCTWaiter.wait(for: [installed], timeout: 60), .completed)
        app.navigationBars["Script Package"].buttons["Done"].tap()
        let close = app.buttons["hanlin-miniapps-management-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 15))
        close.tap()
        try openScriptUI()
        let increment = app.buttons["Increment"]
        XCTAssertTrue(increment.waitForExistence(timeout: 30))
        increment.tap()
        XCTAssertTrue(app.staticTexts["Count 1"].waitForExistence(timeout: 15))
        app.terminate()
        app.launch()
        try openScriptUI()
        XCTAssertTrue(app.staticTexts["Count 0"].waitForExistence(timeout: 30))
    }

    private func openScriptUI() throws {
        let row = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH 'hanlin-miniapp-' AND label CONTAINS %@", "Hanlin ScriptUI Valid"
        )).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        row.tap()
        let open = app.buttons["hanlin-miniapps-open"]
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        open.tap()
    }

    private func openParity() throws {
        let row = app.descendants(matching: .any)["hanlin-miniapp-hanlin.demo.swift-parity"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        row.tap()
        let open = app.buttons["hanlin-miniapps-open"]
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        open.tap()
    }
}
