import XCTest

@MainActor
final class HanlinScriptUIProductionE2ETests: XCTestCase {
    private let app = XCUIApplication()
    private let documents = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
    private let validPackageName = "Hanlin ScriptUI Valid"
    private let malformedPackageName = "Hanlin ScriptUI Malformed"

    private let appBPackageName = "Hanlin ScriptUI App B"

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

        // Assert exact preview metadata from production UI
        let installButton = app.buttons["hanlin-package-install"].firstMatch
        XCTAssertTrue(installButton.waitForExistence(timeout: 20), "Install button did not appear in preview")

        let titlePredicate = NSPredicate(format: "label CONTAINS 'Hanlin ScriptUI Valid' OR value CONTAINS 'Hanlin ScriptUI Valid'")
        XCTAssertTrue(app.descendants(matching: .any).matching(titlePredicate).firstMatch.waitForExistence(timeout: 10), "Preview title missing")
        let versionPredicate = NSPredicate(format: "label CONTAINS '1.0.0' OR value CONTAINS '1.0.0'")
        XCTAssertTrue(app.descendants(matching: .any).matching(versionPredicate).firstMatch.waitForExistence(timeout: 5), "Preview version missing")
        let entrypointPredicate = NSPredicate(format: "label CONTAINS 'index.tsx' OR value CONTAINS 'index.tsx'")
        XCTAssertTrue(app.descendants(matching: .any).matching(entrypointPredicate).firstMatch.waitForExistence(timeout: 5), "Preview entrypoint missing")

        // Mandatory network capability check: 'fetch' in index.tsx requests 'network'
        // Test MUST fail if approval UI is absent.
        var networkToggle = app.switches["network"].firstMatch
        if !networkToggle.waitForExistence(timeout: 3) {
            app.swipeUp()
            networkToggle = app.switches["network"].firstMatch
        }
        XCTAssertTrue(networkToggle.waitForExistence(timeout: 10), "Network capability approval toggle was not rendered in preview")
        XCTAssertFalse(installButton.isEnabled, "Install button was prematurely enabled before capability approval")

        let approveAllButton = app.buttons["hanlin-approve-all-capabilities"].firstMatch
        if approveAllButton.waitForExistence(timeout: 3) && approveAllButton.isHittable {
            approveAllButton.tap()
        } else {
            networkToggle.tap()
            if (networkToggle.value as? String) != "1" {
                networkToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            }
        }
        _ = waitUntil(timeout: 5) { (networkToggle.value as? String) == "1" }
        if !installButton.isHittable {
            app.swipeDown()
        }
        XCTAssertTrue(waitUntil(timeout: 8) { installButton.isEnabled }, "Install button remained disabled after approving capability")

        // 2. Install
        if !installButton.isHittable {
            app.swipeDown()
        }
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

        // 7. Capability Grant / Revoke Lifecycle (app.set_capability_granted)
        openPackageDetails(named: validPackageName)
        let networkPermission = app.switches["network"].firstMatch
        XCTAssertTrue(networkPermission.waitForExistence(timeout: 10), "Network capability toggle missing in Package Details")
        XCTAssertEqual(networkPermission.value as? String, "1", "Network capability was not granted")

        // Revoke network capability
        networkPermission.tap()
        XCTAssertTrue(waitUntil(timeout: 5) { (networkPermission.value as? String) == "0" }, "Failed to revoke network capability")
        closeDetails()

        // Launch must be guarded when required capability is missing
        let packageCardWithoutCap = findPackageCard(named: validPackageName)
        packageCardWithoutCap.tap()
        let closeBtnAfterDenied = app.buttons["hanlin-script-app-close"].firstMatch
        XCTAssertFalse(closeBtnAfterDenied.waitForExistence(timeout: 3), "Package unexpectedly launched with revoked required capability")

        // Re-grant network capability
        openPackageDetails(named: validPackageName)
        let regrantToggle = app.switches["network"].firstMatch
        XCTAssertTrue(regrantToggle.waitForExistence(timeout: 10))
        regrantToggle.tap()
        XCTAssertTrue(waitUntil(timeout: 5) { (regrantToggle.value as? String) == "1" }, "Failed to re-grant network capability")
        closeDetails()

        // 8. Enable / Disable Lifecycle (app.set_enabled)
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

        // 9. Uninstall & Post-Restart Absence (app.uninstall)
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

    func testScriptUIDiscardPreviewLifecycle() throws {
        openApps()
        ensureAppsAddButton(timeout: 15).tap()
        let importLink = app.buttons["hanlin-import-script-package"].firstMatch
        XCTAssertTrue(importLink.waitForExistence(timeout: 10))
        importLink.tap()

        selectArchive(named: "HanlinScriptUIValid")

        // Reach valid Preview
        let discardButton = app.buttons["Discard"].firstMatch
        XCTAssertTrue(discardButton.waitForExistence(timeout: 20), "Discard button missing in preview")
        let titlePredicate = NSPredicate(format: "label CONTAINS 'Hanlin ScriptUI Valid' OR value CONTAINS 'Hanlin ScriptUI Valid'")
        XCTAssertTrue(app.descendants(matching: .any).matching(titlePredicate).firstMatch.waitForExistence(timeout: 10), "Preview title missing")

        // Explicitly Discard preview (app.discard_preview)
        discardButton.tap()
        _ = waitUntil(timeout: 5) { !discardButton.exists }

        // Return to Apps
        closeImportSurfaces()

        // Verify no installed record
        let card = findPackageCard(named: validPackageName)
        XCTAssertFalse(card.exists, "Discarded package was unexpectedly installed")

        // Relaunch and verify it remains absent
        app.terminate()
        app.launch()
        openApps()
        XCTAssertFalse(findPackageCard(named: validPackageName).waitForExistence(timeout: 5), "Discarded package appeared after relaunch")
    }

    func testScriptUIMalformedPackageRejection() throws {
        openApps()
        ensureAppsAddButton(timeout: 15).tap()
        let importLink = app.buttons["hanlin-import-script-package"].firstMatch
        XCTAssertTrue(importLink.waitForExistence(timeout: 10))
        importLink.tap()

        selectArchive(named: "HanlinScriptUIMalformed")

        let errorIndicator = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == 'hanlin-import-error' OR identifier == 'hanlin-import-error-message' OR label CONTAINS 'Import Error' OR label CONTAINS 'malformed' OR label CONTAINS 'entrypoint'")
        ).firstMatch
        if !errorIndicator.waitForExistence(timeout: 5) {
            app.swipeUp()
        }
        XCTAssertTrue(errorIndicator.waitForExistence(timeout: 20), "Malformed package import error was not displayed")

        let installButton = app.buttons["hanlin-package-install"].firstMatch
        XCTAssertTrue(!installButton.exists || !installButton.isEnabled, "Install button was unexpectedly available for malformed package")

        closeImportSurfaces()

        let malformedCard = findPackageCard(named: malformedPackageName)
        XCTAssertFalse(malformedCard.exists, "Partially committed malformed package found in Apps grid")

        // Prove malformed-install rejection cleanup persists after relaunch
        app.terminate()
        app.launch()
        openApps()
        XCTAssertFalse(findPackageCard(named: malformedPackageName).waitForExistence(timeout: 5), "Malformed package unexpectedly present after restart")
    }

    func testScriptUILaunchReEntrancyAndIsolation() throws {
        openApps()

        // Ensure both packages are installed
        ensurePackageInstalled(named: validPackageName, archive: "HanlinScriptUIValid")
        ensurePackageInstalled(named: appBPackageName, archive: "HanlinScriptUIAppB")

        // 1. User-level in-flight re-entrancy protection (guard !isLaunching)
        let packageCard = findPackageCard(named: validPackageName)
        XCTAssertTrue(packageCard.waitForExistence(timeout: 15), "Package card missing before launch")

        // Rapid double tap triggers two immediate launch entries while isLaunching is true
        packageCard.doubleTap()

        let countText = app.staticTexts["Count 0"].firstMatch
        XCTAssertTrue(countText.waitForExistence(timeout: 25), "ScriptUI initial state failed to render")
        let closeButtons = app.buttons.matching(identifier: "hanlin-script-app-close")
        XCTAssertEqual(closeButtons.count, 1, "Double tap caused duplicate container or presentation")

        // First launch establishes state: mutate to Count 1
        let incrementButton = app.buttons["Increment"].firstMatch
        incrementButton.tap()
        XCTAssertTrue(app.staticTexts["Count 1"].firstMatch.waitForExistence(timeout: 10), "State did not mutate to Count 1")

        // Close App A
        closeScriptApp()

        // 3. Reopen App A: proves clean close -> reopen without stale dirty state
        launchPackage(named: validPackageName)
        XCTAssertTrue(app.staticTexts["Count 0"].firstMatch.waitForExistence(timeout: 25), "Clean session failed on reopen")
        closeScriptApp()

        // 4. Real A -> B -> A isolation
        // A -> mutate observable state -> close
        launchPackage(named: validPackageName)
        XCTAssertTrue(app.staticTexts["Count 0"].firstMatch.waitForExistence(timeout: 25))
        app.buttons["Increment"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Count 1"].firstMatch.waitForExistence(timeout: 10))
        closeScriptApp()

        // B -> open and verify its own independent state -> mutate -> close
        launchPackage(named: appBPackageName)
        XCTAssertTrue(app.staticTexts["App B Ready"].firstMatch.waitForExistence(timeout: 25), "App B initial state missing")
        let mutateB = app.buttons["Mutate B"].firstMatch
        XCTAssertTrue(mutateB.waitForExistence(timeout: 10))
        mutateB.tap()
        XCTAssertTrue(app.staticTexts["App B Mutated"].firstMatch.waitForExistence(timeout: 10), "App B state mutation failed")
        closeScriptApp()

        // A -> reopen -> verify clean correct A state and NO B leakage
        launchPackage(named: validPackageName)
        XCTAssertTrue(app.staticTexts["Count 0"].firstMatch.waitForExistence(timeout: 25), "App A did not reopen cleanly")
        XCTAssertFalse(app.staticTexts["App B Ready"].firstMatch.exists, "Leakage from App B state detected in App A")
        XCTAssertFalse(app.staticTexts["App B Mutated"].firstMatch.exists, "Leakage from App B mutated state detected in App A")
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

    private func selectArchive(named archiveName: String) {
        let navBar = app.navigationBars["Script Package"].firstMatch
        _ = navBar.waitForExistence(timeout: 5)

        let directArchive = app.buttons[archiveName].firstMatch
        if directArchive.waitForExistence(timeout: 5) {
            _ = waitUntil(timeout: 5) { directArchive.isHittable }
            directArchive.tap()

            let inspecting = app.staticTexts["Inspecting…"].firstMatch
            let install = app.buttons["hanlin-package-install"].firstMatch
            let errorText = app.staticTexts["Import Error"].firstMatch
            let errorIndicator = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier == 'hanlin-import-error' OR identifier == 'hanlin-import-error-message' OR label CONTAINS 'Import Error'")
            ).firstMatch
            let started = waitUntil(timeout: 4) {
                inspecting.exists || install.exists || errorText.exists || errorIndicator.exists
            }
            if !started && directArchive.exists && directArchive.isHittable {
                directArchive.tap()
            }
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
        var networkToggle = app.switches["network"].firstMatch
        if !networkToggle.waitForExistence(timeout: 3) {
            app.swipeUp()
            networkToggle = app.switches["network"].firstMatch
        }
        let approveAllButton = app.buttons["hanlin-approve-all-capabilities"].firstMatch
        if approveAllButton.waitForExistence(timeout: 2) && approveAllButton.isHittable {
            approveAllButton.tap()
        } else if networkToggle.waitForExistence(timeout: 5) && !installButton.isEnabled {
            networkToggle.tap()
            if (networkToggle.value as? String) != "1" {
                networkToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            }
            _ = waitUntil(timeout: 5) { (networkToggle.value as? String) == "1" }
        }
        if !installButton.isHittable {
            app.swipeDown()
        }
        XCTAssertTrue(waitUntil(timeout: 8) { installButton.isEnabled })
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
        if done.waitForExistence(timeout: 3) && done.isHittable {
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
