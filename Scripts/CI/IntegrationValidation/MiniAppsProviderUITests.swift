import XCTest

final class MiniAppsProviderUITests: XCTestCase {
    @MainActor
    private func launchLibrary() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let parity = app.descendants(matching: .any)["hanlin-miniapp-hanlin.demo.swift-parity"].firstMatch
        XCTAssertTrue(parity.waitForExistence(timeout: 45), "The real canonical library did not load")
        return app
    }

    @MainActor
    func testCanonicalLibraryLaunchesRealCompiledSwiftApp() {
        let app = launchLibrary()
        app.descendants(matching: .any)["hanlin-miniapp-hanlin.demo.swift-parity"].firstMatch.tap()
        let open = app.buttons["hanlin-miniapps-open"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        XCTAssertTrue(app.steppers.firstMatch.waitForExistence(timeout: 20), "The actual Swift Parity view did not appear")
        XCTAssertTrue(app.buttons["Save"].exists)
        XCTAssertTrue(app.buttons["Reload"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Real compiled Swift Parity application"
        attachment.lifetime = .keepAlways
        add(attachment)
        let close = app.buttons["hanlin-miniapps-app-close"]
        XCTAssertTrue(close.exists)
        close.tap()
        XCTAssertTrue(app.buttons["hanlin-miniapps-open"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testManagementPresentsExistingPackageImportScreen() {
        let app = launchLibrary()
        app.buttons["hanlin-miniapps-management"].tap()
        let importing = app.buttons["hanlin-miniapps-package-import"]
        XCTAssertTrue(importing.waitForExistence(timeout: 10))
        importing.tap()
        XCTAssertTrue(app.buttons["hanlin-file-importer"].waitForExistence(timeout: 10), "Original package importer was not presented")
        XCTAssertTrue(app.descendants(matching: .any)["hanlin-share-inbox-link"].firstMatch.exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Existing package management and import screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testOrdinaryInstalledScriptUICatalogAndStatefulLaunch() {
        let app = launchLibrary()
        app.buttons["hanlin-miniapps-management"].tap()
        app.buttons["hanlin-miniapps-package-import"].tap()
        let package = app.buttons["MiniApps-Ordinary-ScriptUI"]
        XCTAssertTrue(package.waitForExistence(timeout: 10), "The actual package was not staged in this simulator app's Documents")
        package.tap()
        let install = app.buttons["hanlin-package-install"]
        XCTAssertTrue(install.waitForExistence(timeout: 90), "Canonical package preview/compilation did not succeed")
        XCTAssertTrue(install.isEnabled)
        install.tap()
        let installed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: install)
        wait(for: [installed], timeout: 90)
        app.buttons["Done"].firstMatch.tap() // Original import sheet.
        app.buttons["Done"].firstMatch.tap() // Package management cover.
        let row = app.staticTexts["Production ScriptUI TSX"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30), "An ordinary installed default-JSC app is absent from the canonical catalog")
        row.tap()
        app.buttons["hanlin-miniapps-open"].tap()
        XCTAssertTrue(app.staticTexts["Count 0"].waitForExistence(timeout: 30), "The actual ScriptUI runtime did not render the installed app")
        app.buttons["Increment"].tap()
        XCTAssertTrue(app.staticTexts["Count 1"].waitForExistence(timeout: 10), "Actual ScriptUI callback/state did not update")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Ordinary installed default-JSC app running real state callback"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["hanlin-script-app-close"].tap()
    }
}
