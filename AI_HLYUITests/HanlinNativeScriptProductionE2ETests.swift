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
        let disabledInstall = app.buttons["hanlin-package-install"].firstMatch
        XCTAssertTrue(disabledInstall.exists)
        XCTAssertFalse(disabledInstall.isEnabled, "Unsupported native plugin package was installable")
        capture(name: "Unsupported-NativeScript-Plugin-Rejected")
        closeImportSurfaces()

        importArchive(named: "HanlinNativeScriptMalformed")
        XCTAssertTrue(app.staticTexts["Import Error"].firstMatch.waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["hanlin-package-install"].firstMatch.exists)
        capture(name: "Malformed-Package-Rejected")
    }

    private func importAndInstall(archive: String) {
        importArchive(named: archive)
        let install = app.buttons["hanlin-package-install"].firstMatch
        XCTAssertTrue(install.waitForExistence(timeout: 30), "Import Preview did not expose Install")
        XCTAssertTrue(waitUntil(timeout: 15) { install.isEnabled }, "\(archive) was not installable")
        install.tap()
        XCTAssertTrue(waitUntil(timeout: 30) { !install.exists }, "\(archive) installation did not finish")
        closeImportSurfaces()
    }

    private var appsAddButton: XCUIElement {
        let direct = app.buttons["hanlin-apps-add"].firstMatch
        if direct.exists { return direct }
        let navDirect = app.navigationBars.buttons["hanlin-apps-add"].firstMatch
        if navDirect.exists { return navDirect }
        let byId = app.descendants(matching: .any).matching(identifier: "hanlin-apps-add").firstMatch
        if byId.exists { return byId }
        let byLabel = app.buttons["Add App"].firstMatch
        if byLabel.exists { return byLabel }
        let navByLabel = app.navigationBars.buttons["Add App"].firstMatch
        if navByLabel.exists { return navByLabel }
        return direct
    }

    private func revealAppsAddButtonIfNeeded() {
        if appsAddButton.exists { return }
        let overflowCandidates = [
            app.navigationBars.buttons["OverflowBarButtonItem"].firstMatch,
            app.buttons["OverflowBarButtonItem"].firstMatch,
            app.navigationBars.buttons["More"].firstMatch,
            app.buttons["More"].firstMatch
        ]
        for overflow in overflowCandidates {
            if overflow.exists {
                overflow.tap()
                _ = appsAddButton.waitForExistence(timeout: 3)
                return
            }
        }
    }

    @discardableResult
    private func ensureAppsAddButton(timeout: TimeInterval = 20) -> XCUIElement {
        if appsAddButton.waitForExistence(timeout: min(timeout, 5)) {
            return appsAddButton
        }
        revealAppsAddButtonIfNeeded()
        XCTAssertTrue(appsAddButton.waitForExistence(timeout: timeout), "hanlin-apps-add button did not exist")
        return appsAddButton
    }

    private func openApps() {
        if appsAddButton.waitForExistence(timeout: 5) { return }
        revealAppsAddButtonIfNeeded()
        if appsAddButton.waitForExistence(timeout: 3) { return }

        let candidates = [
            app.buttons["hanlin-apps-tab"].firstMatch,
            app.tabBars.buttons["hanlin-apps-tab"].firstMatch,
            app.tabs["hanlin-apps-tab"].firstMatch,
            app.buttons["Apps"].firstMatch,
            app.tabBars.buttons["Apps"].firstMatch,
            app.tabs["Apps"].firstMatch
        ]
        var tapped = false
        for candidate in candidates {
            if candidate.waitForExistence(timeout: 3) {
                candidate.tap()
                tapped = true
                break
            }
        }
        if !tapped {
            let fallback = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier == 'hanlin-apps-tab' OR label == 'Apps'")
            ).firstMatch
            if fallback.waitForExistence(timeout: 10) {
                fallback.tap()
            }
        }
        ensureAppsAddButton(timeout: 20)
    }

    private func importArchive(named archiveName: String) {
        ensureAppsAddButton(timeout: 15).tap()
        let importLink = app.buttons["hanlin-import-script-package"].firstMatch
        XCTAssertTrue(importLink.waitForExistence(timeout: 10))
        importLink.tap()

        let directArchive = app.buttons[archiveName].firstMatch
        if directArchive.waitForExistence(timeout: 3) {
            directArchive.tap()
            return
        }

        let importer = app.buttons["hanlin-file-importer"].firstMatch
        XCTAssertTrue(importer.waitForExistence(timeout: 10))
        importer.tap()

        let targetPredicate = NSPredicate(
            format: "label == %@ OR label == %@ OR label == %@ OR identifier == %@ OR identifier == %@ OR identifier == %@",
            archiveName,
            "\(archiveName).hanlinNativeScript",
            "\(archiveName).scripting",
            archiveName,
            "\(archiveName).hanlinNativeScript",
            "\(archiveName).scripting"
        )
        let candidateArchives = [
            app.buttons[archiveName].firstMatch,
            app.descendants(matching: .any).matching(targetPredicate).firstMatch,
            documents.descendants(matching: .any).matching(targetPredicate).firstMatch
        ]

        var foundArchive: XCUIElement?
        for candidate in candidateArchives {
            if candidate.waitForExistence(timeout: 3) {
                foundArchive = candidate
                break
            }
        }

        if foundArchive == nil {
            let browseCandidates = [
                app.buttons["Browse"].firstMatch,
                documents.buttons["Browse"].firstMatch,
                app.tabBars.buttons["Browse"].firstMatch,
                documents.tabBars.buttons["Browse"].firstMatch,
                app.cells["On My iPad"].firstMatch,
                documents.cells["On My iPad"].firstMatch
            ]
            for browse in browseCandidates {
                if browse.exists {
                    browse.tap()
                    break
                }
            }
            for candidate in candidateArchives {
                if candidate.waitForExistence(timeout: 5) {
                    foundArchive = candidate
                    break
                }
            }
        }

        let targetArchive = foundArchive ?? candidateArchives[0]
        XCTAssertTrue(targetArchive.waitForExistence(timeout: 20), "Staged archive \(archiveName) was absent from Files")
        targetArchive.tap()
    }

    private func closeImportSurfaces() {
        for _ in 0..<2 {
            let done = app.buttons["Done"].firstMatch
            if done.waitForExistence(timeout: 5) { done.tap() }
        }
        ensureAppsAddButton(timeout: 10)
    }

    private func launchInstalledPackage(named packageName: String) {
        let package = app.staticTexts[packageName].firstMatch
        XCTAssertTrue(package.waitForExistence(timeout: 15), "Installed package \(packageName) was unavailable")
        package.tap()
    }

    private func assertNativeScriptCoreUI() {
        XCTAssertTrue(app.buttons["hanlin-nativescript-core-button"].firstMatch.waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["hanlin-nativescript-device-proof"].firstMatch.waitForExistence(timeout: 10))
    }

    private func assertSwiftUIAndRoundTrip() {
        let increment = app.buttons["hanlin-swiftui-increment"].firstMatch
        XCTAssertTrue(increment.waitForExistence(timeout: 30), "SwiftUI provider button was not rendered")
        XCTAssertTrue(app.staticTexts["hanlin-swiftui-title"].firstMatch.waitForExistence(timeout: 10))
        let count = app.staticTexts["hanlin-swiftui-count"].firstMatch
        XCTAssertTrue(count.waitForExistence(timeout: 10))
        XCTAssertEqual(count.label, "SwiftUI count: 0")
        increment.tap()
        XCTAssertTrue(waitUntil(timeout: 10) { count.label == "SwiftUI count: 1" }, "SwiftUI state did not update")
        let event = app.staticTexts["hanlin-swiftui-event-proof"].firstMatch
        XCTAssertTrue(event.waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntil(timeout: 10) { event.label == "NativeScript event count: 1" }, "SwiftUI event did not reach NativeScript")
    }

    private func closeNativeScriptApp() {
        let close = app.buttons["hanlin-script-app-close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        close.tap()
        ensureAppsAddButton(timeout: 15)
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
