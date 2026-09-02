import XCTest

@MainActor
final class HanlinNativeScriptProductionE2ETests: XCTestCase {
    private let app = XCUIApplication()
    private let documents = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
    private let swiftUIPackageName = "Hanlin NativeScript SwiftUI E2E"
    private let corePackageName = "Hanlin NativeScript Core E2E"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_NATIVESCRIPT_E2E"] = "1"
        app.launch()
    }

    func testProductionSwiftUIInteractionCoreRegressionLifecycleAndRejection() throws {
        openApps()
        importAndInstall(archive: "HanlinNativeScriptSwiftUI")
        importAndInstall(archive: "HanlinNativeScriptCore")

        launchInstalledPackage(named: swiftUIPackageName)
        assertNativeScriptCoreUI()
        assertSwiftUIAndRoundTrip()
        capture(name: "NativeScript-SwiftUI-Interaction")
        closeNativeScriptApp()

        launchInstalledPackage(named: corePackageName)
        assertNativeScriptCoreUI()
        XCTAssertFalse(app.buttons["hanlin-swiftui-increment"].exists, "Plugin-free Core fixture unexpectedly rendered SwiftUI")
        closeNativeScriptApp()

        // A -> B -> A proves teardown and recreation across distinct installed roots.
        launchInstalledPackage(named: swiftUIPackageName)
        assertSwiftUIAndRoundTrip()
        closeNativeScriptApp()

        app.terminate()
        app.launch()
        openApps()
        XCTAssertTrue(app.staticTexts[swiftUIPackageName].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts[corePackageName].waitForExistence(timeout: 20))
        launchInstalledPackage(named: swiftUIPackageName)
        XCTAssertTrue(app.buttons["hanlin-swiftui-increment"].waitForExistence(timeout: 30))
        closeNativeScriptApp()

        importArchive(named: "HanlinNativeScriptUnsupported")
        let unsupportedMessage = app.staticTexts[
            "This Hanlin build supports @nativescript/swift-ui 4.0.2, but the package requires @nativescript/swift-ui 99.0.0."
        ]
        XCTAssertTrue(unsupportedMessage.waitForExistence(timeout: 20), "Unsupported plugin reason was not visible")
        let disabledInstall = app.buttons["hanlin-package-install"]
        XCTAssertTrue(disabledInstall.exists)
        XCTAssertFalse(disabledInstall.isEnabled, "Unsupported native plugin package was installable")
        capture(name: "Unsupported-NativeScript-Plugin-Rejected")
        closeImportSurfaces()

        importArchive(named: "HanlinNativeScriptMalformed")
        XCTAssertTrue(app.staticTexts["Import Error"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["hanlin-package-install"].exists)
        capture(name: "Malformed-Package-Rejected")
    }

    private func importAndInstall(archive: String) {
        importArchive(named: archive)
        let install = app.buttons["hanlin-package-install"]
        XCTAssertTrue(install.waitForExistence(timeout: 30), "Import Preview did not expose Install")
        XCTAssertTrue(waitUntil(timeout: 15) { install.isEnabled }, "\(archive) was not installable")
        install.tap()
        XCTAssertTrue(waitUntil(timeout: 30) { !install.exists }, "\(archive) installation did not finish")
        closeImportSurfaces()
    }

    private func openApps() {
        if app.buttons["hanlin-apps-add"].waitForExistence(timeout: 20) { return }
        let identifiedTab = app.tabBars.buttons["hanlin-apps-tab"]
        if identifiedTab.waitForExistence(timeout: 5) {
            identifiedTab.tap()
        } else {
            let appsTab = app.tabBars.buttons["Apps"]
            XCTAssertTrue(appsTab.waitForExistence(timeout: 10))
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
            NSPredicate(
                format: "label == %@ OR label == %@ OR label == %@",
                archiveName,
                "\(archiveName).hanlinNativeScript",
                "\(archiveName).scripting"
            )
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

    private func launchInstalledPackage(named packageName: String) {
        let package = app.staticTexts[packageName]
        XCTAssertTrue(package.waitForExistence(timeout: 15), "Installed package \(packageName) was unavailable")
        package.tap()
    }

    private func assertNativeScriptCoreUI() {
        XCTAssertTrue(app.buttons["hanlin-nativescript-core-button"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["hanlin-nativescript-device-proof"].waitForExistence(timeout: 10))
    }

    private func assertSwiftUIAndRoundTrip() {
        let increment = app.buttons["hanlin-swiftui-increment"]
        XCTAssertTrue(increment.waitForExistence(timeout: 30), "SwiftUI provider button was not rendered")
        XCTAssertTrue(app.staticTexts["hanlin-swiftui-title"].waitForExistence(timeout: 10))
        let count = app.staticTexts["hanlin-swiftui-count"]
        XCTAssertTrue(count.waitForExistence(timeout: 10))
        XCTAssertEqual(count.label, "SwiftUI count: 0")
        increment.tap()
        XCTAssertTrue(waitUntil(timeout: 10) { count.label == "SwiftUI count: 1" }, "SwiftUI state did not update")
        let event = app.staticTexts["hanlin-swiftui-event-proof"]
        XCTAssertTrue(event.waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntil(timeout: 10) { event.label == "NativeScript event count: 1" }, "SwiftUI event did not reach NativeScript")
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
