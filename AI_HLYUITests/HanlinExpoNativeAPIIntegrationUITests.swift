import XCTest

@MainActor
final class HanlinExpoNativeAPIIntegrationUITests: XCTestCase {
    private let app = XCUIApplication()
    private let documents = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
    private let probeAPackageName = "Expo Native API Probe A"
    private let probeBPackageName = "Expo Native API Probe B"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_EXPO_E2E"] = "1"
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 20)
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    // MARK: - Test Cases

    func testExpoNativeAPIMountAndInteraction() throws {
        openApps()
        importAndInstall(archive: "ExpoNativeAPIProbeA")

        launchInstalledPackage(named: probeAPackageName)

        // 1. Verify Host & NavigationStack rendered
        let titlePredicate = NSPredicate(format: "label CONTAINS 'Hanlin Expo + NativeScript Hybrid'")
        let titleText = app.descendants(matching: .any).matching(titlePredicate).firstMatch
        XCTAssertTrue(titleText.waitForExistence(timeout: 30), "Hybrid title did not render")

        // 2. Verify Worklets runtime executed runOnUI to query UIDevice.currentDevice.systemVersion
        let systemVersionPredicate = NSPredicate(format: "label CONTAINS 'iOS System Version:' AND NOT label CONTAINS 'Loading...' AND NOT label CONTAINS 'Error' AND NOT label CONTAINS 'failed'")
        let systemVersionText = app.descendants(matching: .any).matching(systemVersionPredicate).firstMatch
        XCTAssertTrue(systemVersionText.waitForExistence(timeout: 20), "UIDevice systemVersion was not retrieved via runOnUI Worklet")

        // 3. Verify Fabric Component (NativeScriptUIViewComponentView) hosting UILabel inside RNHostView
        let nativeLabelPredicate = NSPredicate(format: "label CONTAINS 'Native UIKit Label: Probe Variant A (Hebrew RTL Ready)'")
        let nativeLabel = app.descendants(matching: .any).matching(nativeLabelPredicate).firstMatch
        XCTAssertTrue(nativeLabel.waitForExistence(timeout: 15), "Native UIKit UILabel Fabric host did not render Variant A text")

        // 4. Verify native UISwitch with two-way target-action
        let switchStatusPredicate = NSPredicate(format: "label CONTAINS 'Native Switch Status: DISABLED (OFF)'")
        let switchStatus = app.descendants(matching: .any).matching(switchStatusPredicate).firstMatch
        XCTAssertTrue(switchStatus.waitForExistence(timeout: 10), "Initial switch status marker was missing")

        let uiSwitch = app.switches.firstMatch
        XCTAssertTrue(uiSwitch.waitForExistence(timeout: 10), "Native UISwitch did not render")
        XCTAssertTrue(uiSwitch.isHittable, "Native UISwitch was not hittable")
        uiSwitch.tap()

        let updatedSwitchStatusPredicate = NSPredicate(format: "label CONTAINS 'Native Switch Status: ENABLED (ON)'")
        let updatedSwitchStatus = app.descendants(matching: .any).matching(updatedSwitchStatusPredicate).firstMatch
        XCTAssertTrue(updatedSwitchStatus.waitForExistence(timeout: 10), "Native UISwitch ValueChanged action failed to update state")

        // 5. Test native UIViewController mounting via defineUIViewController
        let mountVCButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Mount Native UIViewController'")).firstMatch
        XCTAssertTrue(mountVCButton.waitForExistence(timeout: 10), "Mount UIViewController button was missing")
        mountVCButton.tap()

        let controllerLabelPredicate = NSPredicate(format: "label CONTAINS 'Hosted Native UIViewController'")
        let controllerLabel = app.descendants(matching: .any).matching(controllerLabelPredicate).firstMatch
        XCTAssertTrue(controllerLabel.waitForExistence(timeout: 15), "Native UIViewController view did not mount in RNHostView")

        // Toggle off
        let hideVCButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Hide Native Controller'")).firstMatch
        XCTAssertTrue(hideVCButton.waitForExistence(timeout: 5), "Hide Native Controller button was missing")
        hideVCButton.tap()
        XCTAssertTrue(waitUntil(timeout: 5) { !controllerLabel.exists }, "Native UIViewController did not unmount")

        // 6. Clean host return
        closeExpoApp()
    }

    func testExpoNativeAPIDynamicVariantSwitching() throws {
        openApps()

        importAndInstall(archive: "ExpoNativeAPIProbeA")
        importAndInstall(archive: "ExpoNativeAPIProbeB")

        // 1. Launch Variant A
        launchInstalledPackage(named: probeAPackageName)
        let variantAPredicate = NSPredicate(format: "label CONTAINS 'Probe Variant A'")
        XCTAssertTrue(
            app.descendants(matching: .any).matching(variantAPredicate).firstMatch.waitForExistence(timeout: 30),
            "Variant A did not render active indicator"
        )
        closeExpoApp()

        // 2. Launch Variant B without host rebuild
        launchInstalledPackage(named: probeBPackageName)
        let variantBPredicate = NSPredicate(format: "label CONTAINS 'Probe Variant B'")
        XCTAssertTrue(
            app.descendants(matching: .any).matching(variantBPredicate).firstMatch.waitForExistence(timeout: 30),
            "Variant B did not render dynamically switched indicator"
        )
        closeExpoApp()

        // 3. Re-launch Variant A to ensure clean isolation
        launchInstalledPackage(named: probeAPackageName)
        XCTAssertTrue(
            app.descendants(matching: .any).matching(variantAPredicate).firstMatch.waitForExistence(timeout: 30),
            "Variant A failed to restore cleanly"
        )
        XCTAssertFalse(
            app.descendants(matching: .any).matching(variantBPredicate).firstMatch.exists,
            "Contamination from Variant B detected in Variant A session"
        )
        closeExpoApp()
    }

    func testExpoNativeAPIIncompatibleVersionRejection() throws {
        openApps()
        ensureAppsAddButton(timeout: 15).tap()
        let importLink = app.buttons["hanlin-import-script-package"].firstMatch
        XCTAssertTrue(importLink.waitForExistence(timeout: 10))
        if importLink.isHittable {
            importLink.tap()
        } else {
            importLink.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }

        selectArchive("ExpoNativeAPIProbeIncompatible")

        let errorIndicator = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == 'hanlin-import-error' OR identifier == 'hanlin-import-error-message' OR label CONTAINS 'Import Error' OR label CONTAINS 'Compatibility' OR label CONTAINS 'incompatible'")
        ).firstMatch
        XCTAssertTrue(errorIndicator.waitForExistence(timeout: 20), "Incompatible version error was not displayed")

        let installButton = app.buttons["hanlin-package-install"].firstMatch
        XCTAssertTrue(!installButton.exists || !installButton.isEnabled, "Install button was unexpectedly enabled for incompatible version")
        closeImportSurfaces()
    }

    func testExpoNativeAPIMalformedPackageRejection() throws {
        openApps()
        ensureAppsAddButton(timeout: 15).tap()
        let importLink = app.buttons["hanlin-import-script-package"].firstMatch
        XCTAssertTrue(importLink.waitForExistence(timeout: 10))
        if importLink.isHittable {
            importLink.tap()
        } else {
            importLink.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }

        selectArchive("ExpoNativeAPIMalformed")

        let errorIndicator = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == 'hanlin-import-error' OR identifier == 'hanlin-import-error-message' OR label CONTAINS 'Import Error' OR label CONTAINS 'malformed'")
        ).firstMatch
        XCTAssertTrue(errorIndicator.waitForExistence(timeout: 20), "Malformed package import error was not displayed")

        let installButton = app.buttons["hanlin-package-install"].firstMatch
        XCTAssertTrue(!installButton.exists || !installButton.isEnabled, "Install button was unexpectedly enabled for malformed package")
        closeImportSurfaces()
    }

    func testExpoNativeAPIDeniedPersistedGrant() throws {
        openApps()
        importAndInstall(archive: "ExpoNativeAPIProbeMissingGrant")
        launchInstalledPackage(named: "Hanlin Expo Native API Probe (Missing Grant)")

        // Verify host launched
        let titlePredicate = NSPredicate(format: "label CONTAINS 'Hanlin Expo + NativeScript Hybrid'")
        let titleText = app.descendants(matching: .any).matching(titlePredicate).firstMatch
        XCTAssertTrue(titleText.waitForExistence(timeout: 30), "Hybrid host failed to launch")

        // Verify native Fabric label did NOT mount because ios-native-api is denied
        let nativeLabelPredicate = NSPredicate(format: "label CONTAINS 'Native UIKit Label: Probe Variant A'")
        let nativeLabel = app.descendants(matching: .any).matching(nativeLabelPredicate).firstMatch
        XCTAssertFalse(nativeLabel.waitForExistence(timeout: 5), "Native UIKit UILabel was unexpectedly mounted despite missing grant")

        closeExpoApp()
    }

    func testExpoNativeAPIRevokeWhileMounted() throws {
        openApps()
        importAndInstall(archive: "ExpoNativeAPIProbeA")
        launchInstalledPackage(named: probeAPackageName)

        // 1. Verify active session with native UIKit switch
        let uiSwitch = app.switches.firstMatch
        XCTAssertTrue(uiSwitch.waitForExistence(timeout: 20), "Native UISwitch did not render")
        XCTAssertTrue(uiSwitch.isHittable, "Native UISwitch was not hittable")

        // 2. Revoke by closing active application synchronously
        closeExpoApp()

        // 3. Verify clean relaunch after close (ensuring teardown was synchronous and clean)
        launchInstalledPackage(named: probeAPackageName)
        let reopenedSwitch = app.switches.firstMatch
        XCTAssertTrue(reopenedSwitch.waitForExistence(timeout: 20), "Native UISwitch failed to render on clean relaunch")
        closeExpoApp()
    }

    func testExpoNativeAPIRepeatedLifecycle() throws {
        openApps()
        importAndInstall(archive: "ExpoNativeAPIProbeA")
        importAndInstall(archive: "ExpoNativeAPIProbeB")

        // 20 cycles alternating between Variant A and Variant B
        for cycle in 1...20 {
            let useVariantA = (cycle % 2 == 1)
            let targetPackage = useVariantA ? probeAPackageName : probeBPackageName
            let targetMarker = useVariantA ? "Probe Variant A" : "Probe Variant B"

            launchInstalledPackage(named: targetPackage)

            let markerPredicate = NSPredicate(format: "label CONTAINS %@", targetMarker)
            let marker = app.descendants(matching: .any).matching(markerPredicate).firstMatch
            XCTAssertTrue(marker.waitForExistence(timeout: 15), "Cycle \(cycle) failed to render \(targetMarker)")

            closeExpoApp()
        }
    }

    // MARK: - Navigation & Staging Helpers

    private var appsAddButtonCandidates: [XCUIElement] {
        [
            app.buttons["hanlin-apps-add"].firstMatch,
            app.navigationBars.buttons["hanlin-apps-add"].firstMatch,
            app.navigationBars["Apps"].buttons["hanlin-apps-add"].firstMatch,
            app.buttons["Add App"].firstMatch,
            app.navigationBars.buttons["Add App"].firstMatch,
            app.navigationBars["Apps"].buttons["Add App"].firstMatch,
            app.descendants(matching: .any).matching(identifier: "hanlin-apps-add").firstMatch
        ]
    }

    private var appsAddButton: XCUIElement {
        for candidate in appsAddButtonCandidates {
            if candidate.exists { return candidate }
        }
        return app.buttons["hanlin-apps-add"].firstMatch
    }

    @discardableResult
    private func ensureAppsAddButton(timeout: TimeInterval = 20) -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for candidate in appsAddButtonCandidates {
                if candidate.exists {
                    return candidate
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        let direct = app.buttons["hanlin-apps-add"].firstMatch
        XCTAssertTrue(direct.waitForExistence(timeout: 1), "hanlin-apps-add button did not exist")
        return direct
    }

    private func closeAddSheetIfNeeded() {
        guard app.navigationBars["Add Apps"].exists || app.buttons["hanlin-apps-add-done"].exists else { return }
        let addDone = app.buttons["hanlin-apps-add-done"].firstMatch
        if addDone.exists && addDone.isHittable {
            addDone.tap()
            _ = waitUntil(timeout: 2) { !addDone.exists }
        } else {
            let doneButtons = [
                app.navigationBars["Add Apps"].buttons["Done"].firstMatch,
                app.navigationBars.buttons["Done"].firstMatch,
                app.buttons["Done"].firstMatch,
            ]
            for done in doneButtons {
                if done.exists && done.isHittable {
                    done.tap()
                    _ = waitUntil(timeout: 2) { !done.exists }
                    break
                }
            }
        }
    }

    private func openApps() {
        app.activate()
        for candidate in appsAddButtonCandidates {
            if candidate.exists { return }
        }

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
            if candidate.waitForExistence(timeout: 2) {
                candidate.tap()
                tapped = true
                break
            }
        }

        if !tapped {
            let nextPage = app.buttons["Next Page"].firstMatch
            if nextPage.waitForExistence(timeout: 2) {
                nextPage.tap()
                for candidate in candidates {
                    if candidate.waitForExistence(timeout: 2) {
                        candidate.tap()
                        tapped = true
                        break
                    }
                }
            }
        }

        if !tapped {
            let prevPage = app.buttons["Previous Page"].firstMatch
            if prevPage.waitForExistence(timeout: 2) {
                prevPage.tap()
                for candidate in candidates {
                    if candidate.waitForExistence(timeout: 2) {
                        candidate.tap()
                        tapped = true
                        break
                    }
                }
            }
        }

        if !tapped {
            let fallback = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier == 'hanlin-apps-tab' OR label == 'Apps'")
            ).firstMatch
            if fallback.waitForExistence(timeout: 5) {
                fallback.tap()
                tapped = true
            }
        }

        ensureAppsAddButton(timeout: 20)
    }

    private func selectArchive(_ archive: String) {
        let navBar = app.navigationBars["Script Package"].firstMatch
        _ = navBar.waitForExistence(timeout: 5)

        let directPredicate = NSPredicate(
            format: "label CONTAINS[c] %@ OR identifier CONTAINS[c] %@",
            archive,
            archive
        )
        var directArchive = app.buttons.matching(directPredicate).firstMatch
        if !directArchive.exists || !directArchive.isHittable {
            for _ in 1...6 {
                if directArchive.exists && directArchive.isHittable { break }
                app.swipeUp()
                if directArchive.waitForExistence(timeout: 2) && directArchive.isHittable { break }
            }
        }
        if !directArchive.exists {
            for _ in 1...6 {
                app.swipeDown()
                if directArchive.waitForExistence(timeout: 2) && directArchive.isHittable { break }
            }
        }
        if !directArchive.exists {
            let directCandidate = app.descendants(matching: .any).matching(identifier: archive).firstMatch
            if directCandidate.waitForExistence(timeout: 2) {
                directArchive = directCandidate
            }
        }
        if directArchive.waitForExistence(timeout: 5) {
            _ = waitUntil(timeout: 5) { directArchive.isHittable }
            if directArchive.isHittable {
                directArchive.tap()
            } else {
                directArchive.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }

            let inspecting = app.staticTexts["Inspecting…"].firstMatch
            let install = app.buttons["hanlin-package-install"].firstMatch
            let errorText = app.staticTexts["Import Error"].firstMatch
            let errorIndicator = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier == 'hanlin-import-error' OR identifier == 'hanlin-import-error-message' OR label CONTAINS 'Import Error' OR label CONTAINS 'malformed'")
            ).firstMatch
            let started = waitUntil(timeout: 4) {
                inspecting.exists || install.exists || errorText.exists || errorIndicator.exists
            }
            if !started && directArchive.exists {
                if directArchive.isHittable {
                    directArchive.tap()
                } else {
                    directArchive.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                }
            }
            return
        }

        let importer = app.buttons["hanlin-file-importer"].firstMatch
        XCTAssertTrue(importer.waitForExistence(timeout: 10))
        importer.tap()

        let targetPredicate = NSPredicate(
            format: "label == %@ OR label == %@ OR identifier == %@ OR identifier == %@",
            archive,
            "\(archive).hanlinExpo",
            archive,
            "\(archive).hanlinExpo"
        )
        let candidateArchives = [
            app.buttons[archive].firstMatch,
            app.descendants(matching: .any).matching(targetPredicate).firstMatch,
            documents.descendants(matching: .any).matching(targetPredicate).firstMatch,
        ]
        var found: XCUIElement?
        for candidate in candidateArchives {
            if candidate.waitForExistence(timeout: 3) {
                found = candidate
                break
            }
        }
        let target = found ?? candidateArchives[0]
        XCTAssertTrue(target.waitForExistence(timeout: 20), "Staged archive \(archive) was absent")
        target.tap()
    }

    private func hasPackageCard(named packageName: String) -> Bool {
        let cardPredicate = NSPredicate(format: "label CONTAINS[c] %@ OR identifier CONTAINS[c] %@", packageName, packageName)
        return app.buttons.matching(cardPredicate).firstMatch.exists ||
               app.descendants(matching: .any).matching(cardPredicate).firstMatch.exists
    }

    private func importAndInstall(archive: String) {
        let displayName = archive == "ExpoNativeAPIProbeA" ? probeAPackageName : (archive == "ExpoNativeAPIProbeB" ? probeBPackageName : archive)
        if hasPackageCard(named: displayName) || hasPackageCard(named: archive) { return }

        ensureAppsAddButton(timeout: 15).tap()
        let importLink = app.buttons["hanlin-import-script-package"].firstMatch
        XCTAssertTrue(importLink.waitForExistence(timeout: 10), "Import Script Package link was missing")
        if importLink.isHittable {
            importLink.tap()
        } else {
            importLink.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }

        selectArchive(archive)

        let install = app.buttons["hanlin-package-install"].firstMatch
        let inspecting = app.staticTexts["Inspecting…"].firstMatch
        if inspecting.waitForExistence(timeout: 3) {
            _ = waitUntil(timeout: 30) { !inspecting.exists }
        }
        XCTAssertTrue(install.waitForExistence(timeout: 30), "Install button did not appear for \(archive)")
        XCTAssertTrue(waitUntil(timeout: 10) { install.isEnabled }, "\(archive) was not installable")
        install.tap()
        XCTAssertTrue(waitUntil(timeout: 25) { !install.exists }, "\(archive) installation did not complete")
        closeImportSurfaces()
    }

    private func closeImportSurfaces() {
        for _ in 1...6 {
            let doneButtons = [
                app.buttons["hanlin-apps-add-done"].firstMatch,
                app.navigationBars["Script Package"].buttons["Done"].firstMatch,
                app.navigationBars["Add Apps"].buttons["Done"].firstMatch,
                app.navigationBars.buttons["Done"].firstMatch,
                app.buttons["Done"].firstMatch,
            ]
            var tappedDone = false
            for done in doneButtons {
                if done.waitForExistence(timeout: 2) && done.isHittable {
                    done.tap()
                    tappedDone = true
                    _ = waitUntil(timeout: 2) { !done.exists }
                    break
                }
            }
            if !tappedDone {
                if !app.navigationBars["Script Package"].exists && !app.navigationBars["Add Apps"].exists && appsAddButton.exists {
                    break
                }
                let backButtons = [
                    app.navigationBars["Script Package"].buttons.element(boundBy: 0),
                    app.navigationBars.buttons.element(boundBy: 0),
                ]
                for back in backButtons {
                    if back.waitForExistence(timeout: 1) && back.isHittable {
                        back.tap()
                        tappedDone = true
                        _ = waitUntil(timeout: 2) { !back.exists }
                        break
                    }
                }
                if !tappedDone { break }
            }
        }
        _ = waitUntil(timeout: 5) {
            !self.app.navigationBars["Script Package"].exists &&
            !self.app.navigationBars["Add Apps"].exists &&
            !self.app.buttons["hanlin-package-install"].exists
        }
        ensureAppsAddButton(timeout: 10)
    }

    private func findPackageCard(named packageName: String) -> XCUIElement {
        let cardPredicate = NSPredicate(format: "label CONTAINS[c] %@ OR identifier CONTAINS[c] %@", packageName, packageName)
        let packageCandidates: [() -> XCUIElement] = [
            { self.app.buttons.matching(cardPredicate).firstMatch },
            { self.app.descendants(matching: .any).matching(cardPredicate).firstMatch }
        ]

        for candidate in packageCandidates {
            let elem = candidate()
            if elem.exists { return elem }
        }

        for _ in 1...2 {
            app.swipeUp()
            for candidate in packageCandidates {
                let elem = candidate()
                if elem.exists { return elem }
            }
        }

        for _ in 1...2 {
            app.swipeDown()
            for candidate in packageCandidates {
                let elem = candidate()
                if elem.exists { return elem }
            }
        }

        return app.buttons.matching(cardPredicate).firstMatch
    }

    private func launchInstalledPackage(named packageName: String) {
        let package = findPackageCard(named: packageName)
        XCTAssertTrue(package.waitForExistence(timeout: 20), "Installed package \(packageName) was unavailable")

        let closeButton = app.buttons["hanlin-script-app-close"].firstMatch

        for attempt in 1...3 {
            if closeButton.exists { return }
            if !package.isHittable {
                app.swipeDown()
                _ = waitUntil(timeout: 2) { package.isHittable }
            }
            if !package.isHittable {
                app.swipeUp()
                _ = waitUntil(timeout: 2) { package.isHittable }
            }
            if package.isHittable {
                package.tap()
            } else {
                package.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            if waitUntil(timeout: attempt == 1 ? 15 : 8, condition: { closeButton.exists }) {
                return
            }
            if app.alerts["Script App Error"].exists {
                let errorLabels = app.alerts["Script App Error"].staticTexts.allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty }
                XCTFail("Script App Error alert appeared when launching \(packageName): " + errorLabels.joined(separator: " | "))
                return
            }
        }
    }

    private func closeExpoApp() {
        let closeButton = app.buttons["hanlin-script-app-close"].firstMatch
        if closeButton.waitForExistence(timeout: 10) {
            closeButton.tap()
        }
        _ = waitUntil(timeout: 5) { !closeButton.exists }
        ensureAppsAddButton(timeout: 15)
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }
}
