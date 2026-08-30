import XCTest

@MainActor
final class HanlinNativeScriptProductionE2ETests: XCTestCase {
    private let app = XCUIApplication()
    private let documents = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
    private let packageName = "Hanlin NativeScript Production E2E"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launch()
    }

    func testProductionImportInstallRunPersistenceAndMalformedRejection() throws {
        openApps()
        importArchive(named: "HanlinNativeScriptProduction")

        let install = app.buttons["hanlin-package-install"]
        XCTAssertTrue(install.waitForExistence(timeout: 30), "Import Preview did not expose Install")
        XCTAssertTrue(waitUntil(timeout: 15) { install.isEnabled }, "NativeScript package was not installable")
        install.tap()
        XCTAssertTrue(waitUntil(timeout: 30) { !install.exists }, "NativeScript package installation did not finish")
        closeImportSurfaces()

        launchInstalledPackage()
        assertNativeScriptCoreUI()
        capture(name: "NativeScript-Core-UI")
        closeNativeScriptApp()

        app.terminate()
        app.launch()
        openApps()
        XCTAssertTrue(app.staticTexts[packageName].waitForExistence(timeout: 20), "Installed package did not persist after relaunch")
        launchInstalledPackage()
        assertNativeScriptCoreUI()
        closeNativeScriptApp()

        importArchive(named: "HanlinNativeScriptMalformed")
        XCTAssertTrue(app.staticTexts["Import Error"].waitForExistence(timeout: 20), "Malformed package did not produce a visible import error")
        XCTAssertFalse(app.buttons["hanlin-package-install"].exists, "Malformed package unexpectedly offered installation")
        capture(name: "Malformed-Package-Rejected")
    }

    private func openApps() {
        let identifiedTab = app.tabBars.buttons["hanlin-apps-tab"]
        if identifiedTab.waitForExistence(timeout: 5) {
            identifiedTab.tap()
        } else {
            let appsTab = app.tabBars.buttons["Apps"]
            XCTAssertTrue(appsTab.waitForExistence(timeout: 10), "Apps tab was unavailable")
            appsTab.tap()
        }
        XCTAssertTrue(app.buttons["hanlin-apps-add"].waitForExistence(timeout: 15))
    }

    private func importArchive(named archiveName: String) {
        app.buttons["hanlin-apps-add"].tap()
        let importLink = app.buttons["hanlin-import-script-package"]
        XCTAssertTrue(importLink.waitForExistence(timeout: 10))
        importLink.tap()
        let importer = app.buttons["hanlin-file-importer"]
        XCTAssertTrue(importer.waitForExistence(timeout: 10))
        importer.tap()

        let archive = documents.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@ OR label == %@", archiveName, "\(archiveName).scripting")
        ).firstMatch
        if !archive.waitForExistence(timeout: 10) {
            let browse = documents.buttons["Browse"]
            if browse.exists { browse.tap() }
        }
        XCTAssertTrue(archive.waitForExistence(timeout: 20), "Staged archive \(archiveName) was absent from Files")
        archive.tap()
    }

    private func closeImportSurfaces() {
        for _ in 0..<2 {
            let done = app.buttons["Done"].firstMatch
            if done.waitForExistence(timeout: 5) { done.tap() }
        }
        XCTAssertTrue(app.buttons["hanlin-apps-add"].waitForExistence(timeout: 10))
    }

    private func launchInstalledPackage() {
        let package = app.staticTexts[packageName]
        XCTAssertTrue(package.waitForExistence(timeout: 15), "Installed NativeScript package card was unavailable")
        package.tap()
    }

    private func assertNativeScriptCoreUI() {
        XCTAssertTrue(app.buttons["hanlin-nativescript-core-button"].waitForExistence(timeout: 30), "NativeScript Core Button was not rendered")
        XCTAssertTrue(app.staticTexts["hanlin-nativescript-device-proof"].waitForExistence(timeout: 10), "Native iOS API proof label was not rendered")
    }

    private func closeNativeScriptApp() {
        let close = app.buttons["hanlin-script-app-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        close.tap()
        XCTAssertTrue(app.buttons["hanlin-apps-add"].waitForExistence(timeout: 15))
    }

    @discardableResult
    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return condition()
    }

    private func capture(name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
