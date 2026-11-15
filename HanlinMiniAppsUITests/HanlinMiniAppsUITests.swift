import XCTest

@MainActor
final class HanlinMiniAppsUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.itorah.hanlinminiapps")

    override func setUpWithError() throws {
        continueAfterFailure = false
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
        let manage = app.buttons["miniapps.manage"]
        XCTAssertTrue(manage.waitForExistence(timeout: 30))
        manage.tap()
        let importPackage = app.buttons["miniapps.import"]
        XCTAssertTrue(importPackage.waitForExistence(timeout: 15))
        importPackage.tap()
        XCTAssertTrue(app.buttons["hanlin-file-importer"].waitForExistence(timeout: 15))
    }

    private func openParity() throws {
        let row = app.descendants(matching: .any)["miniapps.catalog.hanlin.demo.swift-parity"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30))
        row.tap()
        let open = app.buttons["miniapps.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        open.tap()
    }
}
