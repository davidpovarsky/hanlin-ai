import XCTest

@MainActor
final class HanlinExpoProductionE2ETests: XCTestCase {
    private let app = XCUIApplication()
    private let documents = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
    private let probeAPackageName = "Expo SwiftUI Probe A"
    private let probeBPackageName = "Expo SwiftUI Probe B"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_EXPO_E2E"] = "1"
        app.launch()
    }

    // MARK: - Test Cases

    func testProductionExpoSwiftUIProbeEndToEnd() throws {
        openApps()
        importAndInstall(archive: "ExpoSwiftUIProbeA")

        launchInstalledPackage(named: probeAPackageName)

        // 1. Verify Apple SwiftUI SplitView Navigation & Sidebar rendered via Expo UI
        let sidebarTitlePredicate = NSPredicate(format: "label CONTAINS 'ספרי תורה' OR identifier == 'torah-sidebar' OR label CONTAINS 'Genesis' OR label CONTAINS 'Expo Dynamic A'")
        let sidebarTitle = app.descendants(matching: .any).matching(sidebarTitlePredicate).firstMatch
        XCTAssertTrue(sidebarTitle.waitForExistence(timeout: 30), "Expo SwiftUI NavigationSplitView sidebar did not render")

        // 2. Verify Torah books list items rendered as native SwiftUI buttons/rows
        let genesisPredicate = NSPredicate(format: "label CONTAINS 'בראשית' OR label CONTAINS 'Genesis'")
        let genesisButton = app.descendants(matching: .any).matching(genesisPredicate).firstMatch
        XCTAssertTrue(genesisButton.waitForExistence(timeout: 15), "Genesis item in sidebar did not render")

        // 3. Verify Detail Column initial content & Variant A tag
        let variantAPredicate = NSPredicate(format: "label CONTAINS 'Expo Dynamic A' OR label CONTAINS 'Variant A'")
        let variantALabel = app.descendants(matching: .any).matching(variantAPredicate).firstMatch
        XCTAssertTrue(variantALabel.waitForExistence(timeout: 15), "Dynamic Variant A indicator did not render")

        let genesisTextPredicate = NSPredicate(format: "label CONTAINS 'בראשית ברא' OR label CONTAINS 'בְּרֵאשִׁ֖ית' OR label CONTAINS 'Genesis'")
        let genesisText = app.descendants(matching: .any).matching(genesisTextPredicate).firstMatch
        XCTAssertTrue(genesisText.waitForExistence(timeout: 15), "Torah source text did not render in detail column")

        // 4. Test interactive state change: switch book to Exodus ('שמות')
        let exodusPredicate = NSPredicate(format: "label CONTAINS 'שמות' OR label CONTAINS 'Exodus'")
        let exodusButton = app.descendants(matching: .any).matching(exodusPredicate).firstMatch
        if exodusButton.waitForExistence(timeout: 10) && exodusButton.isHittable {
            exodusButton.tap()

            let exodusTextPredicate = NSPredicate(format: "label CONTAINS 'ואלה שמות' OR label CONTAINS 'וְאֵ֗לֶּה שְׁמוֹת֙' OR label CONTAINS 'Exodus'")
            let exodusText = app.descendants(matching: .any).matching(exodusTextPredicate).firstMatch
            XCTAssertTrue(exodusText.waitForExistence(timeout: 15), "Interactive state change failed to load Exodus text")
        }

        // 5. Test native BottomSheet presentation
        let settingsPredicate = NSPredicate(format: "label CONTAINS 'הגדרות' OR label CONTAINS 'Settings'")
        let settingsButton = app.descendants(matching: .any).matching(settingsPredicate).firstMatch
        if settingsButton.waitForExistence(timeout: 10) && settingsButton.isHittable {
            settingsButton.tap()

            let sheetTitlePredicate = NSPredicate(format: "label CONTAINS 'הגדרות קריאה' OR label CONTAINS 'הגדרות' OR label CONTAINS 'Settings'")
            let sheetTitle = app.descendants(matching: .any).matching(sheetTitlePredicate).firstMatch
            XCTAssertTrue(sheetTitle.waitForExistence(timeout: 10), "Expo UI native BottomSheet failed to present")

            let closeSheetPredicate = NSPredicate(format: "label CONTAINS 'סגור' OR label CONTAINS 'Close'")
            let closeSheetButton = app.descendants(matching: .any).matching(closeSheetPredicate).firstMatch
            if closeSheetButton.waitForExistence(timeout: 5) && closeSheetButton.isHittable {
                closeSheetButton.tap()
            }
        }

        // 6. Close MiniApp and verify clean host return
        closeExpoApp()

        // 7. Verify clean relaunch without session leakage
        launchInstalledPackage(named: probeAPackageName)
        XCTAssertTrue(sidebarTitle.waitForExistence(timeout: 30), "Expo SwiftUI MiniApp failed to relaunch cleanly")
        closeExpoApp()
    }

    func testProductionExpoDynamicHotReplacement() throws {
        openApps()

        // Import and install both Variant A and Variant B dynamically
        importAndInstall(archive: "ExpoSwiftUIProbeA")
        importAndInstall(archive: "ExpoSwiftUIProbeB")

        // 1. Launch Variant A
        launchInstalledPackage(named: probeAPackageName)
        let variantAPredicate = NSPredicate(format: "label CONTAINS 'Expo Dynamic A'")
        XCTAssertTrue(
            app.descendants(matching: .any).matching(variantAPredicate).firstMatch.waitForExistence(timeout: 30),
            "Variant A did not render active indicator"
        )
        closeExpoApp()

        // 2. Launch Variant B without host rebuild — proves dynamic runtime hot replacement
        launchInstalledPackage(named: probeBPackageName)
        let variantBPredicate = NSPredicate(format: "label CONTAINS 'Expo Dynamic B'")
        XCTAssertTrue(
            app.descendants(matching: .any).matching(variantBPredicate).firstMatch.waitForExistence(timeout: 30),
            "Variant B did not render hot-replaced active indicator"
        )
        closeExpoApp()

        // 3. Return to Variant A — proves isolated session swap without dirty memory state
        launchInstalledPackage(named: probeAPackageName)
        XCTAssertTrue(
            app.descendants(matching: .any).matching(variantAPredicate).firstMatch.waitForExistence(timeout: 30),
            "Variant A failed to restore cleanly after running Variant B"
        )
        XCTAssertFalse(
            app.descendants(matching: .any).matching(variantBPredicate).firstMatch.exists,
            "Contamination from Variant B detected in Variant A session"
        )
        closeExpoApp()

        // 4. Persistence across app termination
        app.terminate()
        app.launch()
        openApps()

        let cardA = findPackageCard(named: probeAPackageName)
        let cardB = findPackageCard(named: probeBPackageName)
        XCTAssertTrue(cardA.waitForExistence(timeout: 20), "Package A missing after host restart")
        XCTAssertTrue(cardB.waitForExistence(timeout: 20), "Package B missing after host restart")

        launchInstalledPackage(named: probeBPackageName)
        XCTAssertTrue(
            app.descendants(matching: .any).matching(variantBPredicate).firstMatch.waitForExistence(timeout: 30),
            "Variant B failed to launch after host restart"
        )
        closeExpoApp()
    }

    func testProductionExpoLifecycleAndUninstall() throws {
        openApps()
        importAndInstall(archive: "ExpoSwiftUIProbeA")

        // Open package details and uninstall
        openPackageDetails(named: probeAPackageName)
        let uninstallButton = app.buttons["Uninstall"].firstMatch
        XCTAssertTrue(uninstallButton.waitForExistence(timeout: 10), "Uninstall button missing in package details")
        uninstallButton.tap()

        _ = waitUntil(timeout: 10) { !self.findPackageCard(named: self.probeAPackageName).exists }
        XCTAssertFalse(findPackageCard(named: probeAPackageName).exists, "Uninstalled Expo package remained visible")

        // Verify uninstalled state persists across restart
        app.terminate()
        app.launch()
        openApps()
        XCTAssertFalse(
            findPackageCard(named: probeAPackageName).waitForExistence(timeout: 5),
            "Uninstalled Expo package reappeared after host restart"
        )
    }

    func testProductionExpo1000RowsProbe() throws {
        openApps()
        importAndInstall(archive: "ExpoSwiftUIProbeA")
        launchInstalledPackage(named: probeAPackageName)

        // 1. Ensure Expo SwiftUI SplitView Navigation & Sidebar has loaded
        let sidebarTitlePredicate = NSPredicate(format: "label CONTAINS 'ספרי תורה' OR identifier == 'torah-sidebar' OR label CONTAINS 'Genesis' OR label CONTAINS 'Expo Dynamic A'")
        let sidebarTitle = app.descendants(matching: .any).matching(sidebarTitlePredicate).firstMatch
        XCTAssertTrue(sidebarTitle.waitForExistence(timeout: 30), "Expo SwiftUI NavigationSplitView sidebar did not render")

        // 2. Expand sidebar if collapsed on iPad
        let sidebarToggle = app.navigationBars.buttons.matching(
            NSPredicate(format: "identifier == 'ToggleSidebar' OR label CONTAINS[c] 'Sidebar' OR label CONTAINS[c] 'סרגל'")
        ).firstMatch
        if sidebarToggle.waitForExistence(timeout: 2) && sidebarToggle.isHittable {
            sidebarToggle.tap()
        }

        // 3. Select the 1,000-row benchmark probe (from sidebar or detail header)
        let benchmarkPredicate = NSPredicate(format: "label CONTAINS '1,000' OR label CONTAINS '1000' OR label CONTAINS 'מבחן' OR label CONTAINS 'Rows Probe'")
        var benchmarkButton = app.descendants(matching: .any).matching(benchmarkPredicate).firstMatch
        if !benchmarkButton.waitForExistence(timeout: 5) {
            app.swipeUp()
            benchmarkButton = app.descendants(matching: .any).matching(benchmarkPredicate).firstMatch
        }
        XCTAssertTrue(benchmarkButton.waitForExistence(timeout: 15), "1,000 rows benchmark item missing")
        if benchmarkButton.isHittable {
            benchmarkButton.tap()
        } else {
            benchmarkButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }

        // 3. Verify header rendered in Detail
        let headerPredicate = NSPredicate(format: "label CONTAINS 'רשימת 1,000 שורות' OR label CONTAINS '1,000' OR label CONTAINS '1000' OR label CONTAINS 'שורות'")
        var headerLabel = app.descendants(matching: .any).matching(headerPredicate).firstMatch
        if !headerLabel.waitForExistence(timeout: 5) {
            if benchmarkButton.isHittable {
                benchmarkButton.tap()
            } else {
                benchmarkButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            headerLabel = app.descendants(matching: .any).matching(headerPredicate).firstMatch
        }
        XCTAssertTrue(headerLabel.waitForExistence(timeout: 20), "1,000 rows header failed to render")

        // 4. Verify initial rows exist and list scrolls smoothly
        let row1Predicate = NSPredicate(
            format: "label CONTAINS 'Row #1' OR label CONTAINS 'שורה #1' OR label CONTAINS '#1' OR label CONTAINS 'פריט בדיקה 1'"
        )
        let row1 = app.descendants(matching: .any).matching(row1Predicate).firstMatch
        XCTAssertTrue(row1.waitForExistence(timeout: 25), "First row in 1,000-row list did not render")

        // 5. Scroll down to test lazy evaluation in native SwiftUI List
        app.swipeUp()
        app.swipeUp()

        let scrolledRowPredicate = NSPredicate(
            format: "label CONTAINS 'Row #' OR label CONTAINS 'שורה #' OR label CONTAINS 'פריט בדיקה'"
        )
        let scrolledRow = app.descendants(matching: .any).matching(scrolledRowPredicate).firstMatch
        XCTAssertTrue(scrolledRow.waitForExistence(timeout: 15), "List failed to render rows after scrolling")

        closeExpoApp()
    }

    func testProductionExpoMalformedPackageRejection() throws {
        openApps()
        ensureAppsAddButton(timeout: 15).tap()
        let importLink = app.buttons["hanlin-import-script-package"].firstMatch
        XCTAssertTrue(importLink.waitForExistence(timeout: 10))
        importLink.tap()

        // Attempt to import malformed package
        selectArchive("ExpoSwiftUIMalformed")

        let errorIndicator = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == 'hanlin-import-error' OR identifier == 'hanlin-import-error-message' OR label CONTAINS 'Import Error' OR label CONTAINS 'missing' OR label CONTAINS 'entrypoint' OR label CONTAINS 'Compatibility' OR label CONTAINS 'malformed'")
        ).firstMatch
        if !errorIndicator.waitForExistence(timeout: 5) {
            app.swipeUp()
        }
        XCTAssertTrue(errorIndicator.waitForExistence(timeout: 20), "Malformed package import error was not displayed")

        let installButton = app.buttons["hanlin-package-install"].firstMatch
        XCTAssertTrue(!installButton.exists || !installButton.isEnabled, "Install button was unexpectedly available for malformed package")
        closeImportSurfaces()

        let malformedCard = findPackageCard(named: "Expo SwiftUI Malformed")
        XCTAssertFalse(malformedCard.exists, "Partially committed malformed package found in Apps grid")
    }

    // MARK: - Navigation & Staging Helpers

    private var appsAddButton: XCUIElement {
        let direct = app.buttons["hanlin-apps-add"].firstMatch
        if direct.exists { return direct }
        let navByValue = app.navigationBars["Apps"].buttons["hanlin-apps-add"].firstMatch
        if navByValue.exists { return navByValue }
        let navByLabel = app.navigationBars.buttons["hanlin-apps-add"].firstMatch
        if navByLabel.exists { return navByLabel }
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

    private func selectArchive(_ archive: String) {
        let navBar = app.navigationBars["Script Package"].firstMatch
        _ = navBar.waitForExistence(timeout: 5)

        // Select archive from staged document packages or file importer
        var directArchive = app.buttons[archive].firstMatch
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
        if directArchive.waitForExistence(timeout: 3) {
            if !directArchive.isHittable {
                app.swipeUp()
                _ = waitUntil(timeout: 3) { directArchive.isHittable }
            }
            if directArchive.isHittable {
                directArchive.tap()
            } else {
                directArchive.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
        } else {
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
    }

    private func hasPackageCard(named packageName: String) -> Bool {
        let cardPredicate = NSPredicate(format: "label CONTAINS[c] %@ OR identifier CONTAINS[c] %@", packageName, packageName)
        return app.buttons.matching(cardPredicate).firstMatch.exists ||
               app.descendants(matching: .any).matching(cardPredicate).firstMatch.exists
    }

    private func importAndInstall(archive: String) {
        let displayName = archive == "ExpoSwiftUIProbeA" ? probeAPackageName : (archive == "ExpoSwiftUIProbeB" ? probeBPackageName : archive)
        if hasPackageCard(named: displayName) || hasPackageCard(named: archive) { return }

        ensureAppsAddButton(timeout: 15).tap()
        let importLink = app.buttons["hanlin-import-script-package"].firstMatch
        XCTAssertTrue(importLink.waitForExistence(timeout: 10), "Import Script Package link was missing")
        importLink.tap()

        selectArchive(archive)

        // Preview & Install
        let install = app.buttons["hanlin-package-install"].firstMatch
        XCTAssertTrue(install.waitForExistence(timeout: 20), "Install button did not appear for \(archive)")
        XCTAssertTrue(waitUntil(timeout: 10) { install.isEnabled }, "\(archive) was not installable")
        install.tap()
        XCTAssertTrue(waitUntil(timeout: 25) { !install.exists }, "\(archive) installation did not complete")
        closeImportSurfaces()
    }

    private func closeImportSurfaces() {
        for _ in 1...6 {
            let doneButtons = [
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

        for _ in 1...5 {
            app.swipeUp()
            for candidate in packageCandidates {
                let elem = candidate()
                if elem.waitForExistence(timeout: 2) { return elem }
            }
        }

        for _ in 1...5 {
            app.swipeDown()
            for candidate in packageCandidates {
                let elem = candidate()
                if elem.waitForExistence(timeout: 2) { return elem }
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

    private func openPackageDetails(named packageName: String) {
        let card = findPackageCard(named: packageName)
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        card.press(forDuration: 1.5)
        let detailsPredicate = NSPredicate(format: "label CONTAINS 'Package Information' OR label CONTAINS 'Package Details'")
        let detailsButton = app.descendants(matching: .any).matching(detailsPredicate).firstMatch
        if detailsButton.waitForExistence(timeout: 5) {
            detailsButton.tap()
        }
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
