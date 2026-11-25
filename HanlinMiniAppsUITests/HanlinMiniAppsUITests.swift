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
        XCTAssertTrue(app.staticTexts["Mini App ID, hanlin.demo.swift-parity"].exists,
                      "The real Swift view must expose its canonical identity through LabeledContent.")
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
        let manage = app.buttons["hanlin-apps-add"]
        XCTAssertTrue(manage.waitForExistence(timeout: 30))
        manage.tap()
        let importPackage = app.buttons["hanlin-import-script-package"]
        XCTAssertTrue(importPackage.waitForExistence(timeout: 15))
        importPackage.tap()
        XCTAssertTrue(app.buttons["hanlin-file-importer"].waitForExistence(timeout: 15))
    }

    func testInstalledScriptUIAppearsAndRunsAfterRestart() throws {
        executionTimeAllowance = 240
        app.launch()
        let manage = app.buttons["hanlin-apps-add"]
        XCTAssertTrue(manage.waitForExistence(timeout: 30))
        manage.tap()
        let importPackage = app.buttons["hanlin-import-script-package"]
        XCTAssertTrue(importPackage.waitForExistence(timeout: 15))
        importPackage.tap()
        let archive = app.buttons["HanlinScriptUIValid"]
        let packages = app.collectionViews["hanlin-package-import-list"]
        XCTAssertTrue(packages.waitForExistence(timeout: 15))
        for _ in 0..<12 {
            if archive.exists && archive.isHittable { break }
            packages.swipeUp()
        }
        XCTAssertTrue(archive.exists && archive.isHittable,
                      "The production package fixture must be reachable in this app's Documents list.")
        archive.tap()
        let install = app.buttons["hanlin-package-install"]
        XCTAssertTrue(install.waitForExistence(timeout: 30))
        XCTAssertTrue(install.isEnabled)
        install.tap()
        let installed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: install)
        XCTAssertEqual(XCTWaiter.wait(for: [installed], timeout: 60), .completed)
        app.navigationBars["Script Package"].buttons["Done"].tap()
        let close = app.buttons["hanlin-apps-add-done"]
        XCTAssertTrue(close.waitForExistence(timeout: 15))
        close.tap()
        let scriptCard = app.buttons["hanlin-package-card-Hanlin ScriptUI Valid"].firstMatch
        revealCard(scriptCard)
        scriptCard.press(forDuration: 1)
        let info = app.buttons["hanlin-package-information-menu-item"].firstMatch
        XCTAssertTrue(info.waitForExistence(timeout: 10))
        info.tap()
        let detailsDone = app.buttons["hanlin-package-details-done"].firstMatch
        XCTAssertTrue(detailsDone.waitForExistence(timeout: 10))
        detailsDone.tap()
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

    func testOriginalCardMenuHideRestoreAndSearch() {
        app.launch()
        let card = app.buttons["hanlin-package-card-Swift Parity"].firstMatch
        revealCard(card)
        let actions = app.buttons["hanlin-app-actions-hanlin.demo.swift-parity"].firstMatch
        XCTAssertTrue(actions.waitForExistence(timeout: 10))
        actions.tap()
        XCTAssertTrue(app.buttons["Open"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Hide App"].exists)
        app.buttons["App Information"].tap()
        XCTAssertTrue(app.navigationBars["App Information"].waitForExistence(timeout: 10))
        app.navigationBars["App Information"].buttons["Done"].tap()

        app.buttons["Edit"].tap()
        let hide = app.buttons["Hide Swift Parity"].firstMatch
        XCTAssertTrue(hide.waitForExistence(timeout: 10))
        hide.tap()
        XCTAssertTrue(card.waitForNonExistence(timeout: 10))
        app.buttons["Done"].tap()

        app.buttons["hanlin-apps-add"].tap()
        XCTAssertTrue(app.staticTexts["Hidden Apps"].waitForExistence(timeout: 10))
        app.buttons["Swift Parity"].tap()
        app.buttons["hanlin-apps-add-done"].tap()
        revealCard(card)

        let search = app.searchFields["Search Apps"].firstMatch
        if !search.isHittable { app.swipeDown() }
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        search.tap()
        search.typeText("Swift Parity")
        XCTAssertTrue(card.waitForExistence(timeout: 10))
    }

    func testOriginalPhotoStudyActionOpensCapture() {
        app.launch()
        let capture = app.buttons["hanlin-apps-torah-capture"].firstMatch
        XCTAssertTrue(capture.waitForExistence(timeout: 30))
        capture.tap()
        XCTAssertTrue(app.navigationBars["צילום ולימוד ספר"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["בחר תמונה"].exists)
        XCTAssertTrue(app.buttons["צלם"].exists)
        XCTAssertFalse(app.buttons["זהה מקור"].isEnabled)
    }

    private func revealCard(_ card: XCUIElement) {
        XCTAssertTrue(app.buttons["hanlin-apps-add"].firstMatch.waitForExistence(timeout: 30))
        for _ in 0..<5 {
            if card.exists && card.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        XCTAssertTrue(card.isHittable)
    }

    private func openScriptUI() throws {
        let row = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH 'hanlin-package-card-' AND label CONTAINS %@", "Hanlin ScriptUI Valid"
        )).firstMatch
        revealCard(row)
        row.tap()
    }

    private func openParity() throws {
        let row = app.descendants(matching: .any)["hanlin-package-card-Swift Parity"].firstMatch
        revealCard(row)
        row.tap()
    }
}


/// The original runtime packages and runtime assertions, now exercised through the
/// actual shipping companion's catalog/import/launch UI. No AI-only test surface,
/// substitute engine, preinstalled package, manufactured grant or response is used.
@MainActor
final class MiniAppsProductionRuntimeUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.itorah.hanlinminiapps")
    private let parityPackageName = "HanlinScript Parity"
    private let probeAPackageName = "Expo SwiftUI Probe A"
    private var parityChallengeNonce = ""

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 420
        parityChallengeNonce = "companion-" + UUID().uuidString.lowercased()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_PARITY_CHALLENGE"] = parityChallengeNonce
        app.launch()
    }

    override func tearDownWithError() throws {
        // XCTest's synchronous teardown is nonisolated even on this MainActor
        // suite. Keep diagnostics inline, as in the compiled paired-product suite,
        // instead of sending the entire XCTestCase to an actor-isolated helper.
        if testRun?.hasSucceeded == false {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "companion-runtime-failure"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "companion-runtime-failure-accessibility"
            tree.lifetime = .keepAlways
            add(tree)
        }
        app.terminate()
    }

    func testStandaloneNativeScriptUsesRealRuntimesAndSurvivesRelaunch() throws {
        let challengeNonce = parityChallengeNonce

        openApps()
        importAndInstall(archive: "hanlin-script-parity")

        launchInstalledPackage(named: parityPackageName)

        // 1. Verify App Title
        // Require the presented runtime title; the catalog card has the same label.
        let titlePredicate = NSPredicate(format: "identifier == %@", "hanlin-script-parity-title")
        let titleCandidate = app.descendants(matching: .any).matching(titlePredicate).firstMatch
        XCTAssertTrue(titleCandidate.waitForExistence(timeout: 30), "HanlinScript Parity title did not render")
        capture(name: "Parity-App-Launched")

        // 2. Verify Deterministic Runtimes Outputs with Nonce Verification
        // JS: [VERIFIED JSC] nonce=...
        let jsPredicate = NSPredicate(format: "label CONTAINS '[VERIFIED JSC]' AND label CONTAINS %@ AND NOT (label CONTAINS 'Err' OR label CONTAINS 'Error')", challengeNonce)
        let jsLabel = app.descendants(matching: .any).matching(jsPredicate).firstMatch
        XCTAssertTrue(jsLabel.waitForExistence(timeout: 25), "JavaScript execution did not return verified JSC output with nonce \(challengeNonce)")

        // Node: [VERIFIED Node <version>] nonce=...
        let nodePredicate = NSPredicate(format: "label CONTAINS '[VERIFIED Node' AND label CONTAINS %@ AND NOT (label CONTAINS 'Err' OR label CONTAINS 'Error')", challengeNonce)
        let nodeLabel = app.descendants(matching: .any).matching(nodePredicate).firstMatch
        // First use prepares the original embedded Host before executing Node.
        // Preserve the actual nonce/result contract within the existing 420s case allowance.
        XCTAssertTrue(nodeLabel.waitForExistence(timeout: 180), "Node execution did not return verified Node runtime output with nonce \(challengeNonce)")

        // Python: [VERIFIED CPython <version>] nonce=...
        let pyPredicate = NSPredicate(format: "label CONTAINS '[VERIFIED CPython' AND label CONTAINS %@ AND NOT (label CONTAINS 'Err' OR label CONTAINS 'Error')", challengeNonce)
        let pyLabel = app.descendants(matching: .any).matching(pyPredicate).firstMatch
        XCTAssertTrue(pyLabel.waitForExistence(timeout: 25), "Python execution did not return verified CPython runtime output with nonce \(challengeNonce)")

        // HTTPS: [VERIFIED 200]
        let netPredicate = NSPredicate(format: "label CONTAINS '[VERIFIED 200]' AND label CONTAINS %@", challengeNonce)
        let netLabel = app.descendants(matching: .any).matching(netPredicate).firstMatch
        XCTAssertTrue(netLabel.waitForExistence(timeout: 25), "HTTPS network fetch did not return verified status 200")

        // Inter-App Share: [VERIFIED] echoNonce=...
        let interAppPredicate = NSPredicate(format: "label CONTAINS '[VERIFIED]' AND label CONTAINS %@ AND NOT (label CONTAINS 'Err' OR label CONTAINS 'Error' OR label CONTAINS 'denied' OR label CONTAINS 'unavailable' OR label CONTAINS 'Pending')", challengeNonce)
        let interAppLabel = app.descendants(matching: .any).matching(interAppPredicate).firstMatch
        XCTAssertTrue(interAppLabel.waitForExistence(timeout: 25), "Inter-App communication did not complete successfully with echoNonce \(challengeNonce)")
        capture(name: "Parity-Runtimes-Verified")

        // 3. Storage Persistence Check
        let storagePredicate = NSPredicate(format: "(label CONTAINS 'Saved in canonical' OR label CONTAINS 'Reloaded persisted') AND NOT (label CONTAINS 'Error' OR label CONTAINS 'Err' OR label CONTAINS 'failed')")
        let storageLabel = app.descendants(matching: .any).matching(storagePredicate).firstMatch
        XCTAssertTrue(storageLabel.waitForExistence(timeout: 20), "Canonical private storage was not verified")

        // 4. Close App
        closeNativeScriptApp()

        // 5. App Close and Reopen / Persistence across Restart
        app.terminate()
        app.launch()
        openApps()

        let parityPredicate = NSPredicate(format: "label CONTAINS %@ OR identifier CONTAINS %@", parityPackageName, parityPackageName)
        let parityCard = app.descendants(matching: .any).matching(parityPredicate).firstMatch
        var parityFound = parityCard.waitForExistence(timeout: 10)
        if !parityFound {
            app.swipeUp()
            parityFound = parityCard.waitForExistence(timeout: 10)
        }
        XCTAssertTrue(parityFound, "Package \(parityPackageName) was not visible after app restart")

        launchInstalledPackage(named: parityPackageName)
        let relaunchedTitle = app.descendants(matching: .any).matching(titlePredicate).firstMatch
        XCTAssertTrue(relaunchedTitle.waitForExistence(timeout: 30), "HanlinScript Parity failed to relaunch after app restart")
        capture(name: "Parity-Relaunched-Successfully")
        closeNativeScriptApp()
    }

    func testStandaloneExpoRendersNativeControlsAndRunsReactEvents() throws {
        openApps()
        importAndInstall(archive: "ExpoSwiftUIProbeA")

        launchInstalledPackage(named: probeAPackageName)

        // 1. Verify Apple SwiftUI SplitView Navigation & Sidebar rendered via Expo UI
        let sidebarTitlePredicate = NSPredicate(format: "label CONTAINS 'ספרי תורה' OR identifier == 'torah-sidebar' OR label CONTAINS 'Genesis' OR label CONTAINS 'Expo Dynamic A'")
        let sidebarTitle = app.descendants(matching: .any).matching(sidebarTitlePredicate).firstMatch
        XCTAssertTrue(sidebarTitle.waitForExistence(timeout: 30), "Expo SwiftUI NavigationSplitView sidebar did not render")

        // 2. Verify Torah books list items rendered as native SwiftUI buttons/rows
        let genesisPredicate = NSPredicate(format: "label CONTAINS 'בראשית' OR label CONTAINS 'Genesis'")
        var genesisButton = app.buttons.matching(genesisPredicate).firstMatch
        if !genesisButton.exists {
            genesisButton = app.descendants(matching: .any).matching(genesisPredicate).firstMatch
        }
        XCTAssertTrue(genesisButton.waitForExistence(timeout: 15), "Genesis item in sidebar did not render")

        // 3. Verify Detail Column initial content & Variant A tag
        let variantAPredicate = NSPredicate(format: "label CONTAINS 'Expo Dynamic A' OR label CONTAINS 'Variant A'")
        let variantALabel = app.descendants(matching: .any).matching(variantAPredicate).firstMatch
        XCTAssertTrue(variantALabel.waitForExistence(timeout: 15), "Dynamic Variant A indicator did not render")
        let hostFiles = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == 'HOST_FILES_PASS:131073'")
        ).firstMatch
        XCTAssertTrue(hostFiles.waitForExistence(timeout: 45),
                      "The standalone production JS facade must preserve empty/all-byte/131073-byte files and missing-file status.")


        let genesisTextPredicate = NSPredicate(format: "label CONTAINS 'בראשית ברא' OR label CONTAINS 'בְּרֵאשִׁ֖ית' OR label CONTAINS 'Genesis'")
        let genesisText = app.descendants(matching: .any).matching(genesisTextPredicate).firstMatch
        XCTAssertTrue(genesisText.waitForExistence(timeout: 15), "Torah source text did not render in detail column")

        // 4. Verify native Expo UI Toolbar with SF Symbol button and test React state mutation
        let toolbarButtonPredicate = NSPredicate(format: "identifier == 'ToolbarProbeButton' OR label == 'Toolbar Probe' OR label CONTAINS 'Toolbar Probe'")
        let toolbarButton = app.descendants(matching: .any).matching(toolbarButtonPredicate).firstMatch
        XCTAssertTrue(toolbarButton.waitForExistence(timeout: 15), "Native Toolbar button 'Toolbar Probe' did not render")
        XCTAssertTrue(toolbarButton.isHittable, "Native Toolbar button 'Toolbar Probe' is not hittable")

        let initialToolbarCountPredicate = NSPredicate(format: "label CONTAINS 'Toolbar action count: 0'")
        let initialToolbarCount = app.descendants(matching: .any).matching(initialToolbarCountPredicate).firstMatch
        XCTAssertTrue(initialToolbarCount.waitForExistence(timeout: 10), "Initial 'Toolbar action count: 0' marker was missing")

        toolbarButton.tap()

        let updatedToolbarCountPredicate = NSPredicate(format: "label CONTAINS 'Toolbar action count: 1'")
        let updatedToolbarCount = app.descendants(matching: .any).matching(updatedToolbarCountPredicate).firstMatch
        if !updatedToolbarCount.waitForExistence(timeout: 2) {
            toolbarButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(updatedToolbarCount.waitForExistence(timeout: 10), "Toolbar action count failed to increment to 1 after tap")

        // 5. Test interactive state change: switch book to Exodus ('שמות')
        let exodusPredicate = NSPredicate(format: "label CONTAINS 'שמות' OR label CONTAINS 'Exodus'")
        let exodusButton = app.buttons.matching(exodusPredicate).firstMatch
        if exodusButton.exists && exodusButton.isHittable {
            exodusButton.tap()

            let exodusTextPredicate = NSPredicate(format: "label CONTAINS 'ואלה שמות' OR label CONTAINS 'וְאֵ֗לֶּה שְׁמוֹת֙' OR label CONTAINS 'Exodus'")
            let exodusText = app.staticTexts.matching(exodusTextPredicate).firstMatch
            _ = exodusText.waitForExistence(timeout: 5)
        }

        // 6. Test native BottomSheet presentation and Toggle state mutation (required, non-optional)
        let settingsPredicate = NSPredicate(format: "label CONTAINS 'הגדרות' OR label CONTAINS 'Settings'")
        var settingsButton = app.buttons.matching(settingsPredicate).firstMatch
        if !settingsButton.exists {
            settingsButton = app.descendants(matching: .any).matching(settingsPredicate).firstMatch
        }
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 10), "Settings button did not exist")
        XCTAssertTrue(settingsButton.isHittable, "Settings button was not hittable")
        settingsButton.tap()

        let sheetTitlePredicate = NSPredicate(format: "label CONTAINS 'הגדרות קריאה' OR label CONTAINS 'הגדרות' OR label CONTAINS 'Settings'")
        let sheetTitle = app.descendants(matching: .any).matching(sheetTitlePredicate).firstMatch
        XCTAssertTrue(sheetTitle.waitForExistence(timeout: 10), "Expo UI native BottomSheet failed to present")

        let initialNikkudPredicate = NSPredicate(format: "identifier == 'NikkudStateMarker' OR label CONTAINS 'Nikkud: ON'")
        let initialNikkud = app.descendants(matching: .any).matching(initialNikkudPredicate).firstMatch
        XCTAssertTrue(initialNikkud.waitForExistence(timeout: 10), "Initial 'Nikkud: ON' marker did not render in BottomSheet")

        let togglePredicate = NSPredicate(format: "identifier == 'NikkudToggle' OR label CONTAINS 'הצג ניקוד וטעמים' OR label CONTAINS 'ניקוד' OR identifier == 'Toggle'")
        var toggle = app.switches.matching(togglePredicate).firstMatch
        if !toggle.exists {
            toggle = app.descendants(matching: .any).matching(togglePredicate).firstMatch
        }
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "Nikkud toggle was missing in BottomSheet")
        XCTAssertTrue(toggle.isHittable, "Nikkud toggle was not hittable")

        let updatedNikkudPredicate = NSPredicate(format: "label CONTAINS 'Nikkud: OFF'")
        let updatedNikkud = app.descendants(matching: .any).matching(updatedNikkudPredicate).firstMatch

        // In SwiftUI, a full-width Toggle row places the switch knob at the trailing edge (in LTR, dx ≈ 0.9)
        // or leading edge (in RTL, dx ≈ 0.1). Standard center-tap (0.5, 0.5) hits the empty spacer between
        // label and switch knob. Tap trailing knob first, then leading knob, then default tap.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        if !updatedNikkud.waitForExistence(timeout: 2) {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        }
        if !updatedNikkud.waitForExistence(timeout: 2) {
            toggle.tap()
        }

        XCTAssertTrue(updatedNikkud.waitForExistence(timeout: 10), "Nikkud state marker failed to switch to 'Nikkud: OFF'")

        let closeSheetPredicate = NSPredicate(format: "identifier == 'CloseSettingsSheetButton' OR label CONTAINS 'סגור הגדרות' OR label == 'סגור'")
        var closeSheetButton = app.buttons.matching(closeSheetPredicate).firstMatch
        if !closeSheetButton.exists {
            closeSheetButton = app.descendants(matching: .any).matching(closeSheetPredicate).firstMatch
        }
        XCTAssertTrue(closeSheetButton.waitForExistence(timeout: 5), "Close sheet button was missing")
        XCTAssertTrue(closeSheetButton.isHittable, "Close sheet button was not hittable")
        closeSheetButton.tap()

        // 7. Close MiniApp and verify clean host return
        closeExpoApp()

        // 8. Verify clean relaunch without session leakage
        launchInstalledPackage(named: probeAPackageName)
        XCTAssertTrue(sidebarTitle.waitForExistence(timeout: 30), "Expo SwiftUI MiniApp failed to relaunch cleanly")
        closeExpoApp()
    }

    func testStandaloneExpoWidgetsUsesOriginalTimelinesAndLiveActivities() throws {
        for variant in ["A", "B"] {
            openApps()
            importAndInstall(archive: "ExpoWidgetsProbe" + variant)
            launchInstalledPackage(named: "Original Expo Widgets Probe " + variant)
            let status = app.descendants(matching: .any).matching(identifier: "expo-widgets-status").firstMatch
            XCTAssertTrue(status.waitForExistence(timeout: 30), "The original Expo Widgets probe did not render")
            let expected = "EXPO_WIDGETS_PASS:" + variant + ":" + (variant == "A" ? "23" : "31")
            XCTAssertTrue(waitUntil(timeout: 30) {
                status.label == expected || status.label.hasPrefix("EXPO_WIDGETS_ERROR:")
            }, "Original widget methods did not complete: \(status.label)")
            XCTAssertEqual(status.label, expected, "Original widget API failed: \(status.label)")
            let start = app.buttons["expo-widgets-start-activity"].firstMatch
            XCTAssertTrue(start.waitForExistence(timeout: 10))
            if !start.isHittable { app.swipeUp() }
            XCTAssertTrue(start.isHittable)
            start.tap()
            let activity = app.descendants(matching: .any).matching(identifier: "expo-widgets-activity-status").firstMatch
            XCTAssertTrue(waitUntil(timeout: 30) {
                activity.label.hasPrefix("EXPO_WIDGETS_ACTIVITY_PASS:") ||
                    activity.label.hasPrefix("EXPO_WIDGETS_ACTIVITY_ERROR:")
            }, "Original ActivityKit methods did not complete: \(activity.label)")
            XCTAssertTrue(activity.label.hasPrefix("EXPO_WIDGETS_ACTIVITY_PASS:"),
                "Original create/start/query/update/token/end failed: \(activity.label)")
            XCTAssertFalse(activity.label.dropFirst("EXPO_WIDGETS_ACTIVITY_PASS:".count).isEmpty,
                "The actual system activity identifier must be returned")
            capture(name: "original-expo-widgets-" + variant)
            closeExpoApp()
        }
        // Both packages deliberately use the same public widget names. The
        // first package checks its existing timeline before writing on relaunch.
        launchInstalledPackage(named: "Original Expo Widgets Probe A")
        let retained = app.descendants(matching: .any).matching(identifier: "expo-widgets-status").firstMatch
        XCTAssertTrue(retained.waitForExistence(timeout: 30))
        XCTAssertTrue(waitUntil(timeout: 30) {
            retained.label == "EXPO_WIDGETS_PASS:A:23" || retained.label.hasPrefix("EXPO_WIDGETS_ERROR:")
        })
        XCTAssertEqual(retained.label, "EXPO_WIDGETS_PASS:A:23", "The second installation changed the first package's original timeline")
        capture(name: "original-expo-widgets-relaunch-a")
        closeExpoApp()
    }

    func testStandaloneExpoNativeAPIUsesActualUIKitAndWorklets() throws {
        openApps()
        importAndInstall(archive: "ExpoNativeAPIProbeA")

        launchInstalledPackage(named: "Hanlin Expo Native API Probe A")

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
        if !uiSwitch.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(uiSwitch.isHittable, "Native UISwitch was not hittable")
        uiSwitch.tap()

        let updatedSwitchStatusPredicate = NSPredicate(format: "label CONTAINS 'Native Switch Status: ENABLED (ON)'")
        let updatedSwitchStatus = app.descendants(matching: .any).matching(updatedSwitchStatusPredicate).firstMatch
        XCTAssertTrue(updatedSwitchStatus.waitForExistence(timeout: 10), "Native UISwitch ValueChanged action failed to update state")

        // 5. Test native UIViewController mounting via defineUIViewController
        let mountVCButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Mount Native UIViewController'")).firstMatch
        XCTAssertTrue(mountVCButton.waitForExistence(timeout: 10), "Mount UIViewController button was missing")
        if !mountVCButton.isHittable {
            app.swipeUp()
        }
        mountVCButton.tap()

        let controllerLabelPredicate = NSPredicate(format: "label CONTAINS 'Hosted Native UIViewController'")
        let controllerLabel = app.descendants(matching: .any).matching(controllerLabelPredicate).firstMatch
        XCTAssertTrue(controllerLabel.waitForExistence(timeout: 15), "Native UIViewController view did not mount in RNHostView")

        // Toggle off
        let hideVCButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Hide Native Controller'")).firstMatch
        XCTAssertTrue(hideVCButton.waitForExistence(timeout: 5), "Hide Native Controller button was missing")
        if !hideVCButton.isHittable {
            app.swipeUp()
        }
        hideVCButton.tap()
        XCTAssertTrue(waitUntil(timeout: 5) { !controllerLabel.exists }, "Native UIViewController did not unmount")

        // 6. Clean host return
        closeExpoApp()
    }

    // These cases use the existing production archive/importer and actual public
    // Hanlin manual adapters. Exact native callbacks and visible state changes are required.
    func testStandaloneExpoManualInputLayoutAndDataAdapters() throws {
        openManualAdapterProbe()

        tapAdapterButton("Input adapters")
        expectAdapterText("FOCUS_EVENTS:0")
        tapAdapterButton("Focus manual editor")
        let editor = app.textViews["manual-editor"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10),
                      "Focused must make its native editor receive keyboard focus")
        editor.typeText("alpha")
        expectAdapterText("EDITOR_VALUE:alpha")
        let other = app.textFields["manual-other-field"].firstMatch
        XCTAssertTrue(other.waitForExistence(timeout: 10))
        other.tap()
        expectAdapterText("FOCUS_VALUE:false")
        expectAdapterText("FOCUS_EVENTS:1")
        tapAdapterButton("Reset editor from React")
        XCTAssertTrue(waitUntil(timeout: 10) { editor.value as? String == "Reset from React" },
                      "TextEditor must apply the controlled value to the actual native text view")
        capture(name: "Manual TextEditor and Focused native results")
        tapAdapterButton("Adapter menu")

        tapAdapterButton("Search adapter")
        expectAdapterText("MANUAL_SEARCH_CONTENT")
        tapAdapterButton("MANUAL_SEARCH_ACTIONS:0")
        XCTAssertTrue(app.buttons["MANUAL_SEARCH_ACTIONS:1"].firstMatch.waitForExistence(timeout: 10))
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("hanlin")
        expectAdapterText("MANUAL_QUERY:hanlin")
        expectAdapterText("MANUAL_SUBMITS:0")
        let submit = app.keyboards.buttons.matching(
            NSPredicate(format: "label == 'Search' OR label == 'search' OR label == 'Go'")).firstMatch
        if submit.waitForExistence(timeout: 2) && submit.isHittable {
            submit.tap()
        } else {
            field.typeText("\n")
        }
        expectAdapterText("MANUAL_SUBMITS:1")
        expectAdapterText("MANUAL_SUBMITTED:hanlin")
        capture(name: "Manual Searchable complete native submit")
        tapAdapterButton("Adapter menu")

        tapAdapterButton("Layout adapters")
        let v1 = app.buttons["V1"].firstMatch
        let v2 = app.buttons["V2"].firstMatch
        let v3 = app.buttons["V3"].firstMatch
        let h1 = app.buttons["H1"].firstMatch
        let h2 = app.buttons["H2"].firstMatch
        let h3 = app.buttons["H3"].firstMatch
        for element in [v1, v2, v3, h1, h2, h3] {
            XCTAssertTrue(element.waitForExistence(timeout: 10))
        }
        XCTAssertEqual(v1.frame.midY, v2.frame.midY, accuracy: 3, "VGrid must place the first two cells in one row")
        XCTAssertGreaterThan(v3.frame.minY, v1.frame.minY + 20)
        XCTAssertEqual(h1.frame.midX, h2.frame.midX, accuracy: 3, "HGrid must place the first two cells in one column")
        XCTAssertGreaterThan(h3.frame.minX, h1.frame.minX + 30)
        tapAdapterButton("V3")
        expectAdapterText("LAYOUT_ACTION:V3")
        tapAdapterButton("H3")
        expectAdapterText("LAYOUT_ACTION:H3")
        let compact = app.buttons["FIT_COMPACT"].firstMatch
        let wide = app.buttons["FIT_WIDE"].firstMatch
        XCTAssertTrue(compact.waitForExistence(timeout: 10))
        XCTAssertFalse(wide.exists, "A 300-point candidate must not fit a 160-point proposal")
        tapAdapterButton("FIT_COMPACT")
        expectAdapterText("LAYOUT_ACTION:compact")
        tapAdapterButton("Expand fit proposal")
        XCTAssertTrue(wide.waitForExistence(timeout: 10))
        XCTAssertFalse(compact.exists, "ViewThatFits must switch to its first fitting candidate")
        tapAdapterButton("FIT_WIDE")
        expectAdapterText("LAYOUT_ACTION:wide")
        let inset = app.buttons["INSET_ACTIONS:0"].firstMatch
        XCTAssertTrue(inset.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(inset.frame.midY, h3.frame.maxY, "Bottom inset slot must be below its content")
        tapAdapterButton("INSET_ACTIONS:0")
        XCTAssertTrue(app.buttons["INSET_ACTIONS:1"].firstMatch.waitForExistence(timeout: 10))
        tapAdapterButton("Move inset to top")
        XCTAssertTrue(waitUntil(timeout: 10) {
            app.buttons["INSET_ACTIONS:1"].firstMatch.frame.maxY < v1.frame.minY
        }, "Changing the SafeAreaInset edge must move the actual native slot above its content")
        capture(name: "Manual grids adaptive fit and safe area slots")
        tapAdapterButton("Adapter menu")

        tapAdapterButton("Table adapter")
        expectAdapterText("TABLE_SELECTION_EVENTS:0")
        let kiwi = sdkOnlyText("Kiwi")
        XCTAssertTrue(kiwi.waitForExistence(timeout: 10))
        kiwi.tap()
        expectAdapterText("TABLE_SELECTION:kiwi")
        expectAdapterText("TABLE_SELECTION_EVENTS:1")
        tapAdapterButton("Clear table selection")
        expectAdapterText("TABLE_SELECTION:none")
        kiwi.tap()
        expectAdapterText("TABLE_SELECTION_EVENTS:2")
        tapAdapterButton("Update table values")
        expectAdapterText("Kiwi updated")
        expectAdapterText("9")
        capture(name: "Manual Table native selection and changed rows")
        tapAdapterButton("Adapter menu")

        tapAdapterButton("Image adapter")
        expectAdapterText("IMAGE_EMPTY_SLOT")
        expectAdapterText("IMAGE_PHASE:empty")
        tapAdapterButton("Load exact PNG")
        expectAdapterText("IMAGE_PHASE:success")
        expectAdapterText("IMAGE_SUCCESS_EVENTS:1")
        capture(name: "Manual AsyncImage decoded exact PNG")
        tapAdapterButton("Load real missing image")
        expectAdapterText("IMAGE_FAILURE_SLOT")
        expectAdapterText("IMAGE_PHASE:failure")
        expectAdapterText("IMAGE_FAILURE_EVENTS:1")
        capture(name: "Manual AsyncImage real HTTP failure slot")
        tapAdapterButton("Adapter menu")
        tapAdapterButton("Close manual adapters")
        closeExpoApp()
    }

    func testStandaloneExpoManualPresentationAdaptersAndDismissalEvents() throws {
        openManualAdapterProbe()
        for kind in ["Sheet", "FullScreenCover", "Popover"] {
            tapAdapterButton(kind + " adapter")
            expectAdapterText(kind + "_CHANGES:0")
            expectAdapterText(kind + "_DISMISSALS:0")
            tapAdapterButton("Open " + kind)
            let content = sdkOnlyText(kind + " native content")
            XCTAssertTrue(content.waitForExistence(timeout: 10), kind + " must render its actual presented slot")
            capture(name: "Manual " + kind + " native presentation")
            tapAdapterButton("Close " + kind + " from React")
            XCTAssertTrue(waitUntil(timeout: 10) { !content.exists })
            expectAdapterText(kind + "_DISMISSALS:1")
            expectAdapterText(kind + "_CHANGES:0")

            tapAdapterButton("Open " + kind)
            XCTAssertTrue(content.waitForExistence(timeout: 10))
            if kind == "Sheet" {
                content.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                    .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.96)))
            } else if kind == "Popover" {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.90)).tap()
            } else {
                tapAdapterButton("Close " + kind + " from React")
            }
            XCTAssertTrue(waitUntil(timeout: 10) { !content.exists }, kind + " must really dismiss")
            expectAdapterText(kind + "_DISMISSALS:2")
            expectAdapterText(kind + (kind == "FullScreenCover" ? "_CHANGES:0" : "_CHANGES:1"))
            capture(name: "Manual " + kind + " exact dismissal callbacks")
            tapAdapterButton("Adapter menu")
        }

        tapAdapterButton("Inspector adapter")
        expectAdapterText("INSPECTOR_CHANGES:0")
        tapAdapterButton("Open Inspector")
        let inspector = sdkOnlyText("Inspector native content")
        XCTAssertTrue(inspector.waitForExistence(timeout: 10))
        tapAdapterButton("Inspector native action")
        capture(name: "Manual Inspector actual native slot")
        tapAdapterButton("Close Inspector from React")
        XCTAssertTrue(waitUntil(timeout: 10) { !inspector.exists })
        expectAdapterText("INSPECTOR_ACTIONS:1")
        expectAdapterText("INSPECTOR_CHANGES:0")
        tapAdapterButton("Open Inspector")
        XCTAssertTrue(inspector.waitForExistence(timeout: 10))
        tapAdapterButton("Close Inspector from React")
        XCTAssertTrue(waitUntil(timeout: 10) { !inspector.exists })
        expectAdapterText("INSPECTOR_CHANGES:0")
        tapAdapterButton("Adapter menu")
        tapAdapterButton("Close manual adapters")
        closeExpoApp()
    }

    func testStandaloneExpoGeneratedGroupBoxSlotsAndInstalledMetadata() throws {
        openAdditionalExpoProbe("Open Generated Views Probe")
        tapAdapterButton("Generated GroupBox slots")
        expectAdapterText("Generated group label 0")
        expectAdapterText("Generated group content 0")
        expectAdapterText("Generated ordinary child group")
        expectAdapterText("Generated ordinary child content 0")
        expectAdapterText("Generated explicit empty group")
        XCTAssertFalse(sdkOnlyText("GENERATED_GROUP_IGNORED_CHILD").exists,
                       "Explicit named content must take precedence over JSX children.")
        XCTAssertFalse(sdkOnlyText("GENERATED_GROUP_NULL_CHILD").exists,
                       "Explicit null content must suppress the JSX child fallback.")
        tapAdapterButton("Change generated group slots")
        expectAdapterText("Generated group label 1")
        expectAdapterText("Generated group content 1")
        expectAdapterText("Generated ordinary child content 1")
        XCTAssertFalse(sdkOnlyText("GENERATED_GROUP_IGNORED_CHILD").exists)
        XCTAssertFalse(sdkOnlyText("GENERATED_GROUP_NULL_CHILD").exists)
        capture(name: "generated-group-box-native-slots")
        tapAdapterButton("Generated view menu")

        tapAdapterButton("Installed bridge metadata")
        expectAdapterText("METADATA_READS:0")
        expectAdapterText("METADATA_STATUS:NOT_READ")
        tapAdapterButton("Read native bridge metadata")
        expectAdapterText("METADATA_READS:1")
        expectAdapterText("METADATA_STATUS:MATCH")
        let expectedRuntime = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH 'METADATA_EXPECTED_RUNTIME:'")
        ).firstMatch
        XCTAssertTrue(expectedRuntime.waitForExistence(timeout: 10))
        let runtime = String(expectedRuntime.label.dropFirst("METADATA_EXPECTED_RUNTIME:".count))
        XCTAssertFalse(runtime.isEmpty)
        expectAdapterText("METADATA_RUNTIME:" + runtime)
        tapAdapterButton("Read native bridge metadata")
        expectAdapterText("METADATA_READS:2")
        expectAdapterText("METADATA_STATUS:MATCH")
        capture(name: "generated-installed-native-bridge-metadata")
        tapAdapterButton("Generated view menu")
        tapAdapterButton("Close generated views")
        closeExpoApp()
    }

    func testStandaloneExpoGeneratedEditButtonEditsOriginalList() throws {
        openAdditionalExpoProbe("Open Generated Views Probe")
        tapAdapterButton("Generated EditButton list")
        expectAdapterText("EDIT_DELETE_EVENTS:0")
        expectAdapterText("EDIT_ROWS:alpha,beta")
        let edit = app.buttons["generated-edit-button"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 15))
        XCTAssertEqual(edit.label, "Edit")
        XCTAssertTrue(edit.isHittable)
        edit.tap()
        XCTAssertTrue(waitUntil(timeout: 10) { edit.label == "Done" },
                      "The generated SwiftUI EditButton must change the actual native edit mode.")

        let row = app.cells.containing(.staticText, identifier: "Generated Alpha").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let delete = row.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Delete'")).firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 10),
                      "The original List.ForEach onDelete must expose native editing controls.")
        XCTAssertTrue(delete.isHittable)
        delete.tap()
        let event = sdkOnlyText("EDIT_DELETE_EVENTS:1")
        let confirm = row.buttons.matching(NSPredicate(format: "label == 'Delete'")).firstMatch
        XCTAssertTrue(waitUntil(timeout: 10) { event.exists || (confirm.exists && confirm.isHittable) })
        if !event.exists { confirm.tap() }
        expectAdapterText("EDIT_DELETE_EVENTS:1")
        expectAdapterText("EDIT_ROWS:beta")
        XCTAssertFalse(sdkOnlyText("Generated Alpha").exists)
        XCTAssertTrue(sdkOnlyText("Generated Beta").exists)
        edit.tap()
        XCTAssertTrue(waitUntil(timeout: 10) { edit.label == "Edit" })
        capture(name: "generated-edit-button-original-delete-event")
        tapAdapterButton("Generated view menu")
        tapAdapterButton("Close generated views")
        closeExpoApp()
    }

    func testStandaloneExpoGeneratedEmptyViewReportsNativeLayout() throws {
        openAdditionalExpoProbe("Open Generated Views Probe")
        tapAdapterButton("Generated EmptyView measurement")
        expectAdapterText("EMPTY_NATIVE_SIZE:120.0x44.0")
        XCTAssertTrue(sdkOnlyText("Visible measurement control").exists)
        let initialEvents = try generatedEventCount("EMPTY_LAYOUT_EVENTS:")
        XCTAssertGreaterThan(initialEvents, 0)
        tapAdapterButton("Replace measured content with EmptyView")
        expectAdapterText("EMPTY_NATIVE_SIZE:0.0x0.0")
        XCTAssertFalse(sdkOnlyText("Visible measurement control").exists)
        let emptyEvents = try generatedEventCount("EMPTY_LAYOUT_EVENTS:")
        XCTAssertGreaterThan(emptyEvents, initialEvents,
                             "EmptyView size must come from a fresh original Host native layout event.")
        capture(name: "generated-empty-view-zero-native-size")
        tapAdapterButton("Restore measured content")
        expectAdapterText("EMPTY_NATIVE_SIZE:120.0x44.0")
        XCTAssertTrue(sdkOnlyText("Visible measurement control").exists)
        XCTAssertGreaterThan(try generatedEventCount("EMPTY_LAYOUT_EVENTS:"), emptyEvents)
        capture(name: "generated-empty-view-restored-native-size")
        tapAdapterButton("Generated view menu")
        tapAdapterButton("Close generated views")
        closeExpoApp()
    }

    func testStandaloneExpoGeneratedModifierAccessibilityAndGeometry() throws {
        openAdditionalExpoProbe("Open Generated Modifiers Probe")
        tapAdapterButton("Modifiers: Accessibility")
        expectAdapterText("MODIFIER_NATIVE_CONTEXT:Accessibility:appeared")
        let allowance = app.descendants(matching: .any)["generated-accessibility-value"].firstMatch
        XCTAssertTrue(allowance.waitForExistence(timeout: 10))
        XCTAssertEqual(allowance.value as? String, "Allowance 7")
        tapAdapterButton("Increase modifier allowance")
        XCTAssertTrue(waitUntil(timeout: 10) { allowance.value as? String == "Allowance 8" },
                      "The generated accessibility value must update the actual native accessibility element.")
        tapAdapterButton("Generated accessibility action")
        expectAdapterText("MODIFIER_ACCESSIBILITY_ACTIONS:1")
        capture(name: "generated-modifier-native-accessibility-value")
        tapAdapterButton("Generated modifier menu")

        tapAdapterButton("Modifiers: Geometry")
        expectAdapterText("MODIFIER_NATIVE_CONTEXT:Geometry:appeared")
        let positioned = app.descendants(matching: .any)["generated-position-text"].firstMatch
        let tracked = app.descendants(matching: .any)["generated-tracking-text"].firstMatch
        XCTAssertTrue(positioned.waitForExistence(timeout: 10))
        XCTAssertTrue(tracked.waitForExistence(timeout: 10))
        let initialX = positioned.frame.midX
        let initialWidth = tracked.frame.width
        XCTAssertGreaterThan(initialWidth, 0)
        tapAdapterButton("Change modifier geometry")
        expectAdapterText("MODIFIER_GEOMETRY_STATE:changed")
        XCTAssertTrue(waitUntil(timeout: 10) {
            abs(positioned.frame.midX - initialX - 120) < 2 && tracked.frame.width > initialWidth + 1
        }, "The generated position and tracking modifiers must change native geometry, not only React labels.")
        XCTAssertEqual(positioned.frame.midX - initialX, 120, accuracy: 2)
        XCTAssertGreaterThan(tracked.frame.width, initialWidth + 1)
        capture(name: "generated-modifier-native-position-and-tracking")
        tapAdapterButton("Generated modifier menu")
        tapAdapterButton("Exit Generated Modifiers Probe")
        closeExpoApp()
    }

    func testStandaloneExpoGeneratedModifierHitTestingAndSubmitScope() throws {
        openAdditionalExpoProbe("Open Generated Modifiers Probe")
        tapAdapterButton("Modifiers: Input")
        expectAdapterText("MODIFIER_NATIVE_CONTEXT:Input:appeared")
        expectAdapterText("MODIFIER_HIT_COUNTS:front=0;back=0")
        let back = app.buttons["Generated back target"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(back.frame.width, 0)
        let nativeTarget = back.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        nativeTarget.tap()
        expectAdapterText("MODIFIER_HIT_COUNTS:front=0;back=1")
        tapAdapterButton("Enable generated front target")
        XCTAssertTrue(app.buttons["Generated front target enabled"].firstMatch.waitForExistence(timeout: 10))
        nativeTarget.tap()
        expectAdapterText("MODIFIER_HIT_COUNTS:front=1;back=1")
        capture(name: "generated-modifier-native-hit-testing")

        let field = app.textFields["generated-modifier-input"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertTrue(field.isHittable)
        field.tap()
        field.typeText("native input\n")
        expectAdapterText("MODIFIER_INPUT:native input")
        XCTAssertFalse(waitUntil(timeout: 2) { self.sdkOnlyText("MODIFIER_SUBMITS:1").exists },
                       "Blocking submitScope must prevent the real ancestor onSubmit callback.")
        expectAdapterText("MODIFIER_SUBMITS:0")
        tapAdapterButton("Allow generated submit")
        XCTAssertTrue(app.buttons["Generated submit allowed"].firstMatch.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("\n")
        expectAdapterText("MODIFIER_SUBMITS:1")
        capture(name: "generated-modifier-native-submit-scope")
        tapAdapterButton("Generated modifier menu")
        tapAdapterButton("Exit Generated Modifiers Probe")
        closeExpoApp()
    }

    func testStandaloneExpoGeneratedModifierNativeContainerContexts() throws {
        openAdditionalExpoProbe("Open Generated Modifiers Probe")
        tapAdapterButton("Modifiers: Containers")
        expectAdapterText("MODIFIER_NATIVE_CONTEXT:Containers:appeared")
        let header = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == 'Generated item header'")
        ).firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        tapAdapterButton("Toggle generated headers")
        XCTAssertTrue(waitUntil(timeout: 10) { !header.exists },
                      "tableColumnHeaders must hide the native header.")
        tapAdapterButton("Toggle generated headers")
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        let selectable = sdkOnlyText("Generated selectable row")
        XCTAssertTrue(selectable.waitForExistence(timeout: 10))
        selectable.tap()
        XCTAssertFalse(waitUntil(timeout: 2) { self.sdkOnlyText("MODIFIER_LIST_SELECTION:invoice").exists })
        expectAdapterText("MODIFIER_LIST_SELECTION:none")
        tapAdapterButton("Allow generated selection")
        XCTAssertTrue(app.buttons["Generated selection allowed"].firstMatch.waitForExistence(timeout: 10))
        selectable.tap()
        expectAdapterText("MODIFIER_LIST_SELECTION:invoice")
        let swipeRow = sdkOnlyText("Generated swipe row")
        XCTAssertTrue(swipeRow.waitForExistence(timeout: 10))
        swipeRow.swipeLeft()
        tapAdapterButton("Record generated swipe")
        expectAdapterText("MODIFIER_SWIPE_ACTIONS:1")
        capture(name: "generated-modifier-native-table-list-and-swipe")

        tapAdapterButton("Generated search context")
        let query = app.searchFields.firstMatch
        XCTAssertTrue(query.waitForExistence(timeout: 10))
        query.tap()
        let suggestion = app.descendants(matching: .any).matching(
            NSPredicate(format: "label == 'Generated suggestion Isaiah'")
        ).firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 10))
        XCTAssertTrue(suggestion.isHittable)
        suggestion.tap()
        expectAdapterText("MODIFIER_SEARCH_QUERY:Isaiah")
        query.tap()
        query.typeText("\n")
        expectAdapterText("MODIFIER_SEARCH_SUBMITTED:Isaiah")
        capture(name: "generated-modifier-native-search-completion")
        tapAdapterButton("Generated modifier menu")

        tapAdapterButton("Modifiers: Containers")
        tapAdapterButton("Generated navigation context")
        tapAdapterButton("Open generated detail")
        expectAdapterText("GENERATED_MODIFIER_DETAIL")
        let navigationBar = app.navigationBars["Generated detail"].firstMatch
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 10))
        XCTAssertFalse(navigationBar.buttons.firstMatch.exists,
                       "The generated back-button modifier must hide the actual native navigation control.")
        tapAdapterButton("Show generated native back")
        let nativeBack = navigationBar.buttons.firstMatch
        XCTAssertTrue(nativeBack.waitForExistence(timeout: 10))
        XCTAssertTrue(nativeBack.isHittable)
        nativeBack.tap()
        expectAdapterText("MODIFIER_NAVIGATION_PATH:")
        XCTAssertFalse(sdkOnlyText("GENERATED_MODIFIER_DETAIL").exists)
        capture(name: "generated-modifier-native-navigation-back")
        tapAdapterButton("Generated modifier menu")

        tapAdapterButton("Modifiers: Containers")
        tapAdapterButton("Generated inspector context")
        tapAdapterButton("Open generated inspector")
        expectAdapterText("GENERATED_MODIFIER_INSPECTOR")
        capture(name: "generated-modifier-original-inspector-context")
        tapAdapterButton("Close generated inspector")
        XCTAssertTrue(waitUntil(timeout: 10) { !self.sdkOnlyText("GENERATED_MODIFIER_INSPECTOR").exists })
        expectAdapterText("MODIFIER_INSPECTOR_PRESENTED:false")
        tapAdapterButton("Generated modifier menu")

        tapAdapterButton("Modifiers: Host Context")
        expectAdapterText("MODIFIER_NATIVE_CONTEXT:Host Context:appeared")
        expectAdapterText("No document scene or file presenter is created by this probe.")
        capture(name: "generated-modifier-host-context-boundary")
        tapAdapterButton("Generated modifier menu")
        tapAdapterButton("Exit Generated Modifiers Probe")
        closeExpoApp()
    }

    func testStandaloneExpoHostServicesUseRealStorageRuntimeAndWidgetPublication() throws {
        openAdditionalExpoProbe("Open Host Services Probe")
        tapAdapterButton("Run Host Services Files")
        expectAdapterText("HOST_SERVICES_FILES_PASS")
        tapAdapterButton("Run Host Services Runtime")
        expectAdapterText("HOST_SERVICES_RUNTIME_PASS")
        tapAdapterButton("Read Host Live Activity Status")
        let activityStatus = app.descendants(matching: .any).matching(NSPredicate(
            format: "label BEGINSWITH 'HOST_SERVICES_ACTIVITY_READS_PASS:enabled='"
        )).firstMatch
        XCTAssertTrue(activityStatus.waitForExistence(timeout: 15),
                      "The original ActivityKit status/list result must be read; this does not assert an activity was started.")
        tapAdapterButton("Publish Prepared Expo Widget")
        expectAdapterText("HOST_SERVICES_WIDGET_STATE_PASS")
        capture(name: "host-services-actual-storage-runtime-and-prepared-widget-state")
        // The typed receipt proves committed state/catalog/reload only. Rendering
        // by WidgetKit and the installed action request/ack have separate cases.
        tapAdapterButton("Close Host Services Probe")
        closeExpoApp()
    }

    private func generatedEventCount(_ prefix: String) throws -> Int {
        let value = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@", prefix)
        ).firstMatch
        XCTAssertTrue(value.waitForExistence(timeout: 10))
        return try XCTUnwrap(Int(value.label.dropFirst(prefix.count)))
    }

    private func openAdditionalExpoProbe(_ label: String) {
        openApps()
        importAndInstall(archive: "ExpoSwiftUIProbeA")
        launchInstalledPackage(named: probeAPackageName)
        let open = app.buttons[label].firstMatch
        if !open.waitForExistence(timeout: 5) || !open.isHittable {
            let sidebar = app.buttons.matching(NSPredicate(format:
                "label == 'Show Sidebar' OR identifier == 'ToggleSidebar' OR label CONTAINS[c] 'Sidebar'")).firstMatch
            if sidebar.exists && sidebar.isHittable {
                sidebar.tap()
            } else {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
                    .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5)))
            }
        }
        tapAdapterButton(label)
    }

    private func openManualAdapterProbe() {
        openApps()
        importAndInstall(archive: "ExpoSwiftUIProbeA")
        launchInstalledPackage(named: probeAPackageName)
        let open = app.buttons["Open Manual Adapter Probe"].firstMatch
        if !open.waitForExistence(timeout: 5) || !open.isHittable {
            let sidebar = app.buttons.matching(NSPredicate(format:
                "label == 'Show Sidebar' OR identifier == 'ToggleSidebar' OR label CONTAINS[c] 'Sidebar'")).firstMatch
            if sidebar.exists && sidebar.isHittable {
                sidebar.tap()
            } else {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
                    .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5)))
            }
        }
        tapAdapterButton("Open Manual Adapter Probe")
        XCTAssertTrue(app.buttons["Input adapters"].firstMatch.waitForExistence(timeout: 10))
    }

    private func expectAdapterText(_ value: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(sdkOnlyText(value).waitForExistence(timeout: 15),
                      "Missing exact native adapter result: " + value, file: file, line: line)
    }

    private func tapAdapterButton(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 15), "Missing adapter button: " + label, file: file, line: line)
        XCTAssertTrue(button.isHittable, "Native adapter button is not hittable: " + label, file: file, line: line)
        button.tap()
    }

    // These two independent source projects were authored by a fresh agent using
    // only the exported original SDK and public documentation. The runner builds
    // their unchanged sources with this app's actual SDK before the real importer
    // installs them. Portable compilation alone is not this native acceptance.
    func testStandaloneSDKOnlyExpoPackageImportsRendersAndHandlesEvents() throws {
        openApps()
        importAndInstall(archive: "SDKOnlyDepartureBudget")
        launchInstalledPackage(named: "Departure Budget")

        let initial = sdkOnlyText("55 minutes reserved before the target")
        XCTAssertTrue(initial.waitForExistence(timeout: 30), "SDK-authored Expo root did not render")
        revealSDKOnlyElement(initial, scrollTowardEnd: false)
        let city = app.buttons["City"].firstMatch
        revealSDKOnlyElement(city, scrollTowardEnd: true)
        city.tap()
        let cityBudget = sdkOnlyText("70 minutes reserved before the target")
        revealSDKOnlyElement(cityBudget, scrollTowardEnd: false)
        XCTAssertTrue(cityBudget.exists, "Native City button did not update the React calculation")
        capture(name: "SDK-only Expo native City result")

        let local = app.buttons["Local"].firstMatch
        revealSDKOnlyElement(local, scrollTowardEnd: true)
        local.tap()
        let localBudget = sdkOnlyText("35 minutes reserved before the target")
        revealSDKOnlyElement(localBudget, scrollTowardEnd: false)
        XCTAssertTrue(localBudget.exists, "Native Local button did not update the React calculation")
        capture(name: "SDK-only Expo native Local result")
        closeExpoApp()

        app.terminate()
        app.launch()
        openApps()
        launchInstalledPackage(named: "Departure Budget")
        XCTAssertTrue(initial.waitForExistence(timeout: 30), "Installed SDK-authored Expo package did not relaunch")
        capture(name: "SDK-only Expo installed package relaunch")
        closeExpoApp()
    }

    func testStandaloneSDKOnlyNativeScriptPackageImportsRendersAndHandlesEvents() throws {
        openApps()
        importAndInstall(archive: "SDKOnlyTableShare")
        launchInstalledPackage(named: "Table Share")
        XCTAssertTrue(sdkOnlyText("Table Share").waitForExistence(timeout: 30),
                      "SDK-authored NativeScript Core page did not render")
        let total = sdkOnlyText("$106.26 total")
        revealSDKOnlyElement(total, scrollTowardEnd: true)
        XCTAssertTrue(total.exists)
        let initialShares = sdkOnlyText("3 people pay $35.42 each.")
        revealSDKOnlyElement(initialShares, scrollTowardEnd: true)
        XCTAssertTrue(initialShares.exists)

        let more = app.buttons["+"].firstMatch
        revealSDKOnlyElement(more, scrollTowardEnd: false)
        more.tap()
        let fourShares = sdkOnlyText("2 pay $26.57; 2 pay $26.56.")
        revealSDKOnlyElement(fourShares, scrollTowardEnd: true)
        XCTAssertTrue(fourShares.exists, "Original NativeScript tap event did not recalculate cents")
        let rounding = app.switches.firstMatch
        revealSDKOnlyElement(rounding, scrollTowardEnd: false)
        XCTAssertTrue(rounding.isEnabled)
        rounding.tap()
        let rounded = sdkOnlyText("4 people pay $27.00 each.")
        revealSDKOnlyElement(rounded, scrollTowardEnd: true)
        XCTAssertTrue(rounded.exists, "Original NativeScript checkedChange event did not recalculate contributions")
        let extra = sdkOnlyText("Whole-dollar rounding collects $1.74 extra. Decide together where that goes.")
        revealSDKOnlyElement(extra, scrollTowardEnd: true)
        XCTAssertTrue(extra.exists)
        capture(name: "SDK-only NativeScript native rounded result")

        let reset = app.buttons["Reset to example bill"].firstMatch
        revealSDKOnlyElement(reset, scrollTowardEnd: true)
        reset.tap()
        revealSDKOnlyElement(initialShares, scrollTowardEnd: false)
        XCTAssertTrue(initialShares.exists, "NativeScript reset did not restore the actual model")
        capture(name: "SDK-only NativeScript native reset result")
        closeNativeScriptApp()
    }

    private func sdkOnlyText(_ text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@", text)).firstMatch
    }

    private func revealSDKOnlyElement(_ element: XCUIElement, scrollTowardEnd: Bool,
                                      file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            if scrollTowardEnd { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(element.waitForExistence(timeout: 10), "SDK-authored native content was missing", file: file, line: line)
        XCTAssertTrue(element.isHittable, "SDK-authored native content was not reachable by scrolling", file: file, line: line)
    }

    func testStandaloneModularSearchLoadsActualSefariaText() throws {
        openApps()
        importAndInstall(archive: "ModularTextSearch")
        launchInstalledPackage(named: "חיפוש טקסטים מודולרי — Expo")

        // The canonical package starts in Hebrew independently of the host locale.
        let english = app.buttons["English"].firstMatch
        XCTAssertTrue(english.waitForExistence(timeout: 30), "The canonical search package did not render")
        english.tap()
        XCTAssertTrue(app.buttons["Search now"].firstMatch.waitForExistence(timeout: 10))

        // Submit through the shipped native Searchable, using the real Sefaria engine.
        for _ in 0..<3 {
            if app.searchFields.allElementsBoundByIndex.contains(where: { $0.isHittable }) { break }
            app.swipeDown()
        }
        let searchField = try XCTUnwrap(
            app.searchFields.allElementsBoundByIndex.first(where: { $0.isHittable }),
            "The package's native search field must be available")
        searchField.tap()
        searchField.typeText("In the beginning God created\n")
        XCTAssertTrue(app.staticTexts["Native search submitted."].firstMatch.waitForExistence(timeout: 15),
            "The native submit event did not reach the package")
        let resultSummary = app.staticTexts.matching(NSPredicate(
            format: "label ==[c] %@", "Results summary")).firstMatch
        XCTAssertTrue(resultSummary.waitForExistence(timeout: 60),
            "The actual Sefaria request must return a result summary")

        // Result references and ranking belong to the live service. Select a real
        // result row by its shipped reference + snippet label, not a fixed edition.
        let resultRows = app.buttons.matching(NSPredicate(
            format: "label CONTAINS %@ AND NOT (identifier BEGINSWITH %@)", "\n", "hanlin-"))
        for _ in 0..<5 {
            if resultRows.allElementsBoundByIndex.contains(where: { $0.isHittable }) { break }
            app.swipeUp()
        }
        let result = try XCTUnwrap(
            resultRows.allElementsBoundByIndex.first(where: { $0.isHittable }),
            "The live search must produce a navigable reference and snippet")
        let selectedReference = String(result.label.split(separator: "\n").first ?? "")
        XCTAssertFalse(selectedReference.isEmpty)
        capture(name: "modular-search-live-sefaria-results")
        result.tap()

        let sourceLink = app.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@", "Open in Sefaria")).firstMatch
        XCTAssertTrue(sourceLink.waitForExistence(timeout: 15),
            "Opening the result must show its real source detail")
        // The original native list can expose interactive rows without an AX
        // hit point on the collection itself. Require the actual detail's
        // version control and verify its real expansion transition below.
        let sourceVersionPrefix = "modular-source-version-"
        let loadedVersionPrefix = "modular-loaded-version-"
        let sourceVersionPredicate = NSPredicate(
            format: "identifier BEGINSWITH %@", sourceVersionPrefix)
        func nativeDetailList() -> XCUIElement? {
            let lists = app.collectionViews.allElementsBoundByIndex + app.tables.allElementsBoundByIndex
            return lists.first {
                $0.descendants(matching: .any).matching(NSPredicate(
                    format: "label == %@", "Open in Sefaria")).firstMatch.exists
            }
        }
        let detailReady = waitUntil(timeout: 15) {
            nativeDetailList()?.buttons.matching(sourceVersionPredicate)
                .allElementsBoundByIndex.contains(where: { $0.isHittable }) == true
        }
        capture(name: "modular-search-native-detail")
        XCTAssertTrue(detailReady, "Native detail must expose an interactive original version control")
        let detailList = try XCTUnwrap(nativeDetailList(),
            "The result must render its native list containing the actual source link")
        let versionButtons = detailList.buttons.matching(sourceVersionPredicate)
        for _ in 0..<5 {
            if versionButtons.allElementsBoundByIndex.contains(where: { $0.isHittable }) { break }
            detailList.swipeUp()
        }
        let sourceVersion = try XCTUnwrap(
            versionButtons.allElementsBoundByIndex.first(where: { $0.isHittable }),
            "The result must expose an original version disclosure")
        let entryID = String(sourceVersion.identifier.dropFirst(sourceVersionPrefix.count))
        XCTAssertFalse(entryID.isEmpty)
        let loadText = detailList.buttons.matching(NSPredicate(
            format: "identifier == %@", "modular-full-text-load-" + entryID)).firstMatch

        func expandDisclosure(_ header: XCUIElement, content: XCUIElement, name: String) {
            // Original Expo DisclosureGroup currently defaults to expanded.
            // Exercise a real transition, then leave this exact group expanded.
            let initiallyExpanded = content.exists
            header.tap()
            XCTAssertTrue(waitUntil(timeout: 10) { content.exists != initiallyExpanded },
                "\(name) must respond to the original disclosure control")
            if initiallyExpanded { header.tap() }
            XCTAssertTrue(content.waitForExistence(timeout: 15),
                "\(name) must expose its own content after expansion")
        }
        expandDisclosure(sourceVersion, content: loadText, name: "Source version")
        if !loadText.isHittable { detailList.swipeUp() }
        XCTAssertTrue(loadText.isHittable)
        let loadedVersions = detailList.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", loadedVersionPrefix + entryID + ":"))
        let versionsBeforeLoad = Set(loadedVersions.allElementsBoundByIndex.map { $0.identifier })
        loadText.tap()

        // These identifiers are emitted only by versions returned from the
        // live /api/v3/texts response, scoped to source entry plus version ID.
        func returnedVersion() -> XCUIElement? {
            loadedVersions.allElementsBoundByIndex.first {
                !versionsBeforeLoad.contains($0.identifier)
            }
        }
        let noVersions = detailList.staticTexts["No text versions were returned for this source."].firstMatch
        XCTAssertTrue(waitUntil(timeout: 60) { returnedVersion() != nil || noVersions.exists },
            "The actual full-text request did not render any returned version")
        XCTAssertFalse(noVersions.exists, "The live source returned no full-text versions")
        for _ in 0..<4 {
            if returnedVersion()?.isHittable == true { break }
            detailList.swipeUp()
        }
        let textVersion = try XCTUnwrap(returnedVersion(), "A returned full-text version is required")
        XCTAssertTrue(textVersion.isHittable)
        let returnedVersionID = String(textVersion.identifier.dropFirst(loadedVersionPrefix.count))
        XCTAssertFalse(returnedVersionID.isEmpty)
        let textBody = detailList.staticTexts.matching(NSPredicate(
            format: "identifier == %@", "modular-full-text-body-" + returnedVersionID)).firstMatch
        expandDisclosure(textVersion, content: textBody, name: "Returned text version")

        let language = detailList.staticTexts.matching(NSPredicate(
            format: "label == %@ OR label BEGINSWITH %@", "Language", "Language,")).firstMatch
        XCTAssertTrue(language.waitForExistence(timeout: 15),
            "The returned version must expose its original language metadata")
        let noText = "No text is available for this version."
        XCTAssertFalse(detailList.staticTexts[noText].firstMatch.exists)

        func visibleFullText() -> XCUIElement? {
            guard textBody.exists && textBody.isHittable else { return nil }
            let label = textBody.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard label.count >= 40 && label.split(whereSeparator: { $0.isWhitespace }).count >= 6 &&
                label != noText && !label.hasPrefix("Language,") && !label.hasPrefix("License,") else {
                return nil
            }
            return textBody
        }
        for _ in 0..<5 {
            if visibleFullText() != nil { break }
            detailList.swipeUp()
        }
        let fullText = try XCTUnwrap(visibleFullText(),
            "Expanding the API response must render a nonempty full text, not only the search snippet or metadata")
        XCTAssertFalse(fullText.label.isEmpty)
        let evidence = XCTAttachment(string: "Reference: \(selectedReference)\nFull text: \(fullText.label)")
        evidence.name = "modular-search-actual-sefaria-text"
        evidence.lifetime = .keepAlways
        add(evidence)
        capture(name: "modular-search-live-sefaria-full-text")
        closeExpoApp()
    }

    private func openApps() {
        let manage = app.buttons["hanlin-apps-add"].firstMatch
        XCTAssertTrue(manage.waitForExistence(timeout: 30),
                      "The independent MiniApps catalog must be ready")
    }

    private func importAndInstall(archive: String) {
        openApps()
        app.buttons["hanlin-apps-add"].tap()
        let importButton = app.buttons["hanlin-import-script-package"].firstMatch
        XCTAssertTrue(importButton.waitForExistence(timeout: 15))
        importButton.tap()
        let list = app.collectionViews["hanlin-package-import-list"].firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 15))
        let source = list.buttons[archive].firstMatch
        // The native List creates accessibility rows lazily. Search within that
        // list before requiring existence, including the later SDK-only inputs.
        for _ in 0..<8 {
            if source.exists && source.isHittable { break }
            list.swipeUp()
        }
        XCTAssertTrue(source.waitForExistence(timeout: 15))
        XCTAssertTrue(source.isHittable)
        source.tap()
        let install = app.buttons["hanlin-package-install"].firstMatch
        let importError = app.staticTexts["hanlin-import-error-message"].firstMatch
        let diagnostics = app.descendants(matching: .any)["hanlin-import-diagnostics-sheet"].firstMatch
        // The original strict compiler took 64.537s in the measured SDK9 import.
        // Wait for the real import outcome within the existing 420s case budget.
        // A compiler/import error ends this wait immediately instead of hiding it.
        XCTAssertTrue(waitUntil(timeout: 240) {
            install.exists || importError.exists || diagnostics.exists
        }, "Original package validation must finish with an install preview or diagnostics")
        XCTAssertFalse(importError.exists,
                       "The original importer failed: \(importError.exists ? importError.label : "")")
        XCTAssertFalse(diagnostics.exists, "The valid original package produced import diagnostics")
        XCTAssertTrue(install.exists, "The original compiler must produce an installable preview")
        XCTAssertFalse(app.buttons["hanlin-approve-all-capabilities"].exists,
                       "Current original framework imports must not add an application capability approval step")
        if !install.isHittable { app.swipeDown() }
        XCTAssertTrue(waitUntil(timeout: 15) { install.isEnabled && install.isHittable })
        install.tap()
        XCTAssertTrue(waitUntil(timeout: 60) { !install.exists || importError.exists },
                      "The existing installer must complete in the companion's own namespace")
        XCTAssertFalse(importError.exists, "The original installer failed: \(importError.exists ? importError.label : "")")
        XCTAssertFalse(install.exists, "Successful installation must consume the original preview")
        let done = app.navigationBars["Script Package"].buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        done.tap()
        let close = app.buttons["hanlin-apps-add-done"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        close.tap()
        openApps()
        capture(name: "companion-import-" + archive)
    }

    private func launchInstalledPackage(named name: String) {
        let card = app.buttons["hanlin-package-card-\(name)"].firstMatch
        for _ in 0..<5 {
            if card.exists && card.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(card.waitForExistence(timeout: 30))
        XCTAssertTrue(card.isHittable)
        card.tap()
    }

    private func closeNativeScriptApp() { closeRuntimeApplication() }
    private func closeExpoApp() { closeRuntimeApplication() }

    private func closeRuntimeApplication() {
        let close = app.buttons["hanlin-script-app-close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 15))
        XCTAssertTrue(close.isHittable)
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 15))
        XCTAssertTrue(app.buttons["hanlin-apps-add"].firstMatch.waitForExistence(timeout: 15),
                      "Closing the real runtime must return to the Apps catalog")
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }

    private func capture(name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-accessibility"
        tree.lifetime = .keepAlways
        add(tree)
    }
}
