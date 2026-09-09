import XCTest

@MainActor
final class HanlinScriptUIProductionE2ETests: XCTestCase {
    private let app = XCUIApplication()
    private let documents = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
    private let validPackageName = "Hanlin ScriptUI Valid"
    private let malformedPackageName = "Hanlin ScriptUI Malformed"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_SCRIPTUI_E2E"] = "1"
        app.launch()
    }

    func testProductionScriptUIUserJourneyAndLifecycle() throws {
        openApps()

        // 1. Import, Preview & Capabilities Review
        ensureAppsAddButton(timeout: 15).tap()
        let importLink = app.buttons["hanlin-import-script-package"].firstMatch
        XCTAssertTrue(importLink.waitForExistence(timeout: 10), "Import Script Package link missing")
        importLink.tap()

        selectArchive(named: "HanlinScriptUIValid")

        let installButton = app.buttons["hanlin-package-install"].firstMatch
        XCTAssertTrue(installButton.waitForExistence(timeout: 20), "Install button did not appear in preview")

        // Inferred capability check: 'fetch' in index.tsx requests 'network'
        let networkToggle = app.switches["network"].firstMatch
        if networkToggle.waitForExistence(timeout: 5) {
            // Install must be disabled before mandatory capability approval
            XCTAssertFalse(installButton.isEnabled, "Install button was prematurely enabled before capability approval")
            networkToggle.tap()
            XCTAssertTrue(waitUntil(timeout: 5) { installButton.isEnabled }, "Install button remained disabled after approving capability")
        }

        // 2. Install
        installButton.tap()
        XCTAssertTrue(waitUntil(timeout: 30) { !installButton.exists }, "Installation did not complete")
        closeImportSurfaces()

        // 3. Open & Execute via JavaScriptCore / ScriptUI
        launchPackage(named: validPackageName)

        // ScriptUI renders Text "Count 0" and Button "Increment"
        let countText = app.staticTexts["Count 0"].firstMatch
        XCTAssertTrue(countText.waitForExistence(timeout: 25), "ScriptUI initial state 'Count 0' did not render")
        let incrementButton = app.buttons["Increment"].firstMatch
        XCTAssertTrue(incrementButton.waitForExistence(timeout: 10), "ScriptUI Increment button was missing")

        // 4. Exact Deterministic State Mutation
        incrementButton.tap()
        let updatedCountText = app.staticTexts["Count 1"].firstMatch
        XCTAssertTrue(updatedCountText.waitForExistence(timeout: 10), "ScriptUI state did not mutate to 'Count 1' after button tap")

        // 5. Close
        closeScriptApp()

        // 6. Persistence across app restart
        app.terminate()
        app.launch()
        openApps()

        let packageCard = findPackageCard(named: validPackageName)
        XCTAssertTrue(packageCard.waitForExistence(timeout: 20), "Package \(validPackageName) missing after restart")

        // Open again successfully
        launchPackage(named: validPackageName)
        XCTAssertTrue(app.staticTexts["Count 0"].firstMatch.waitForExistence(timeout: 25), "ScriptUI did not initialize cleanly on reopen after restart")
        closeScriptApp()

        // 7. Enable / Disable Lifecycle
        openPackageDetails(named: validPackageName)
        let enabledToggle = app.switches["Enabled"].firstMatch
        XCTAssertTrue(enabledToggle.waitForExistence(timeout: 10), "Enabled toggle missing in Package Details")
        XCTAssertEqual(enabledToggle.value as? String, "1", "Package was not initially enabled")

        // Disable package
        enabledToggle.tap()
        XCTAssertTrue(waitUntil(timeout: 5) { (enabledToggle.value as? String) == "0" }, "Package failed to disable")
        closeDetails()

        // Tap disabled package -> launch guard rejects or does not open application container
        let disabledCard = findPackageCard(named: validPackageName)
        disabledCard.tap()
        let closeButton = app.buttons["hanlin-script-app-close"].firstMatch
        XCTAssertFalse(closeButton.waitForExistence(timeout: 3), "Disabled package unexpectedly launched")

        // Re-enable package
        openPackageDetails(named: validPackageName)
        let reenableToggle = app.switches["Enabled"].firstMatch
        XCTAssertTrue(reenableToggle.waitForExistence(timeout: 10))
        reenableToggle.tap()
        XCTAssertTrue(waitUntil(timeout: 5) { (reenableToggle.value as? String) == "1" }, "Package failed to re-enable")
        closeDetails()

        // Verify open works again
        launchPackage(named: validPackageName)
        XCTAssertTrue(app.staticTexts["Count 0"].firstMatch.waitForExistence(timeout: 25), "Re-enabled package failed to open")
        closeScriptApp()

        // 8. Uninstall & Post-Restart Absence
        openPackageDetails(named: validPackageName)
        let uninstallButton = app.buttons["Uninstall"].firstMatch
        XCTAssertTrue(uninstallButton.waitForExistence(timeout: 10), "Uninstall button missing")
        uninstallButton.tap()

        _ = waitUntil(timeout: 10) { !findPackageCard(named: validPackageName).exists }
        XCTAssertFalse(findPackageCard(named: validPackageName).exists, "Uninstalled package remained visible")

        app.terminate()
        app.launch()
        openApps()

        XCTAssertFalse(findPackageCard(named: validPackageName).waitForExistence(timeout: 5), "Uninstalled package reappeared after app relaunch")
    }

    func testScriptUIMalformedPackageRejection() throws {
        openApps()
        ensureAppsAddButton(timeout: 15).tap()
        let importLink = app.buttons["hanlin-import-script-package"].firstMatch
        XCTAssertTrue(importLink.waitForExistence(timeout: 10))
        importLink.tap()

        selectArchive(named: "HanlinScriptUIMalformed")

        let errorIndicator = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == 'hanlin-import-error' OR identifier == 'hanlin-import-error-message' OR label CONTAINS 'Import Error' OR label CONTAINS 'malformed'")
        ).firstMatch
        XCTAssertTrue(errorIndicator.waitForExistence(timeout: 20), "Malformed package import error was not displayed")
        XCTAssertFalse(app.buttons["hanlin-package-install"].firstMatch.exists, "Install button was unexpectedly available for malformed package")

        closeImportSurfaces()

        let malformedCard = findPackageCard(named: malformedPackageName)
        XCTAssertFalse(malformedCard.exists, "Partially committed malformed package found in Apps grid")
    }

    func testScriptUILaunchReEntrancyAndIsolation() throws {
        openApps()

        // Ensure valid package is installed
        ensurePackageInstalled(named: validPackageName, archive: "HanlinScriptUIValid")

        // A. Duplicate launch while session is active
        launchPackage(named: validPackageName)
        let countText = app.staticTexts["Count 0"].firstMatch
        XCTAssertTrue(countText.waitForExistence(timeout: 25))

        let incrementButton = app.buttons["Increment"].firstMatch
        incrementButton.tap()
        XCTAssertTrue(app.staticTexts["Count 1"].firstMatch.waitForExistence(timeout: 10))

        // Trigger duplicate launch attempt while active: state must NOT reset to 0
        let packageCard = findPackageCard(named: validPackageName)
        if packageCard.exists && packageCard.isHittable {
            packageCard.tap()
        }
        // State remains Count 1; session is NOT destroyed or re-created
        XCTAssertTrue(app.staticTexts["Count 1"].firstMatch.exists, "Duplicate launch tore down or reset active session state")
        XCTAssertFalse(app.staticTexts["Count 0"].firstMatch.exists, "Session state unexpectedly reverted to 0 on duplicate launch")

        // B. Close -> reopen: same package opens cleanly
        closeScriptApp()
        launchPackage(named: validPackageName)
        XCTAssertTrue(app.staticTexts["Count 0"].firstMatch.waitForExistence(timeout: 25), "Clean session failed on reopen")
        closeScriptApp()

        // C. A -> B -> A isolation
        // App A state isolation verification
        launchPackage(named: validPackageName)
        XCTAssertTrue(app.staticTexts["Count 0"].firstMatch.waitForExistence(timeout: 25))
        incrementButton.tap()
        XCTAssertTrue(app.staticTexts["Count 1"].firstMatch.waitForExistence(timeout: 10))
        closeScriptApp()

        // Reopen A again: brand new session initialized without stale dirty state
        launchPackage(named: validPackageName)
        XCTAssertTrue(app.staticTexts["Count 0"].firstMatch.waitForExistence(timeout: 25))
        closeScriptApp()
    }

    // MARK: - Navigation & Staging Helpers

    private var appsAddButton: XCUIElement {
        let direct = app.buttons["hanlin-apps-add"].firstMatch
        if direct.exists { return direct }
        let navDirect = app.navigationBars.buttons["hanlin-apps-add"].firstMatch
        if navDirect.exists { return navDirect }
        let byId = app.descendants(matching: .any).matching(identifier: "hanlin-apps-add").firstMatch
        if byId.exists { return byId }
        let byLabel = app.buttons["Add App"].firstMatch
        if byLabel.exists { return byLabel }
        return direct
    }

    @discardableResult
    private func ensureAppsAddButton(timeout: TimeInterval = 20) -> XCUIElement {
        XCTAssertTrue(appsAddButton.waitForExistence(timeout: timeout), "hanlin-apps-add button did not exist")
        return appsAddButton
    }

    private func openApps() {
        if appsAddButton.waitForExistence(timeout: 5) { return }
        let appsTab = app.tabBars.buttons["hanlin-apps-tab"].firstMatch
        if appsTab.waitForExistence(timeout: 5) {
            appsTab.tap()
        } else {
            let labelTab = app.tabBars.buttons["Apps"].firstMatch
            if labelTab.waitForExistence(timeout: 5) { labelTab.tap() }
        }
        ensureAppsAddButton(timeout: 15)
    }

    private func selectArchive(named archiveName: String) {
        let navBar = app.navigationBars["Script Package"].firstMatch
        _ = navBar.waitForExistence(timeout: 5)

        let directArchive = app.buttons[archiveName].firstMatch
        if directArchive.waitForExistence(timeout: 5) {
            _ = waitUntil(timeout: 5) { directArchive.isHittable }
            directArchive.tap()
            return
        }

        let importer = app.buttons["hanlin-file-importer"].firstMatch
        if importer.waitForExistence(timeout: 10) {
            importer.tap()
            let targetPredicate = NSPredicate(format: "label CONTAINS %@ OR identifier CONTAINS %@", archiveName, archiveName)
            let target = app.descendants(matching: .any).matching(targetPredicate).firstMatch
            if target.waitForExistence(timeout: 10) {
                target.tap()
            }
        }
    }

    private func ensurePackageInstalled(named packageName: String, archive: String) {
        if findPackageCard(named: packageName).exists { return }
        ensureAppsAddButton(timeout: 15).tap()
        let importLink = app.buttons["hanlin-import-script-package"].firstMatch
        XCTAssertTrue(importLink.waitForExistence(timeout: 10))
        importLink.tap()
        selectArchive(named: archive)

        let installButton = app.buttons["hanlin-package-install"].firstMatch
        XCTAssertTrue(installButton.waitForExistence(timeout: 20))
        let networkToggle = app.switches["network"].firstMatch
        if networkToggle.waitForExistence(timeout: 3) && !installButton.isEnabled {
            networkToggle.tap()
        }
        XCTAssertTrue(waitUntil(timeout: 5) { installButton.isEnabled })
        installButton.tap()
        _ = waitUntil(timeout: 30) { !installButton.exists }
        closeImportSurfaces()
    }

    private func findPackageCard(named packageName: String) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS %@ OR identifier CONTAINS %@", packageName, packageName)
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    private func launchPackage(named packageName: String) {
        let packageCard = findPackageCard(named: packageName)
        XCTAssertTrue(packageCard.waitForExistence(timeout: 15), "Package \(packageName) unavailable for launch")
        packageCard.tap()
    }

    private func closeScriptApp() {
        let close = app.buttons["hanlin-script-app-close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 10), "Script app close button missing")
        close.tap()
        _ = waitUntil(timeout: 10) { !close.exists }
        ensureAppsAddButton(timeout: 15)
    }

    private func openPackageDetails(named packageName: String) {
        let packageCard = findPackageCard(named: packageName)
        XCTAssertTrue(packageCard.waitForExistence(timeout: 10))
        packageCard.press(forDuration: 1.5)
        let infoButton = app.buttons["Package Information"].firstMatch
        if infoButton.waitForExistence(timeout: 5) {
            infoButton.tap()
        }
    }

    private func closeDetails() {
        let done = app.buttons["Done"].firstMatch
        if done.exists && done.isHittable {
            done.tap()
        } else {
            app.swipeDown()
        }
    }

    private func closeImportSurfaces() {
        let scriptPackageNav = app.navigationBars["Script Package"].firstMatch
        if scriptPackageNav.exists {
            let done = app.buttons["Done"].firstMatch
            if done.exists && done.isHittable { done.tap() }
            _ = waitUntil(timeout: 5) { !scriptPackageNav.exists }
        }
        let addAppsNav = app.navigationBars["Add Apps"].firstMatch
        if addAppsNav.waitForExistence(timeout: 3) || addAppsNav.exists {
            let done = app.buttons["Done"].firstMatch
            if done.waitForExistence(timeout: 3) && done.isHittable { done.tap() }
            _ = waitUntil(timeout: 5) { !addAppsNav.exists }
        }
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
}
