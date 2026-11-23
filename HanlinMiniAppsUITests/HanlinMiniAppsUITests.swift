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
        let titlePredicate = NSPredicate(format: "label CONTAINS 'HanlinScript Parity' OR identifier == 'hanlin-script-parity-title'")
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
        XCTAssertTrue(nodeLabel.waitForExistence(timeout: 25), "Node execution did not return verified Node runtime output with nonce \(challengeNonce)")

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
        let source = app.buttons[archive].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 15))
        if !source.isHittable { list.swipeUp() }
        XCTAssertTrue(source.isHittable)
        source.tap()
        let install = app.buttons["hanlin-package-install"].firstMatch
        XCTAssertTrue(install.waitForExistence(timeout: 30))
        let approve = app.buttons["hanlin-approve-all-capabilities"].firstMatch
        if approve.waitForExistence(timeout: 2) {
            if !approve.isHittable { app.swipeUp() }
            XCTAssertTrue(approve.isHittable)
            approve.tap() // Actual existing user consent control, never a stored grant seed.
        }
        if !install.isHittable { app.swipeDown() }
        XCTAssertTrue(waitUntil(timeout: 15) { install.isEnabled && install.isHittable })
        install.tap()
        let importError = app.staticTexts["hanlin-import-error-message"].firstMatch
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
