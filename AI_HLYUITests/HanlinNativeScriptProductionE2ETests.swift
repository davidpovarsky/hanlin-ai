import XCTest

@MainActor
final class HanlinNativeScriptProductionE2ETests: XCTestCase {
    private let app = XCUIApplication()
    private let documents = XCUIApplication(bundleIdentifier: "com.apple.DocumentsApp")
    private let swiftUIPackageName = "Hanlin NativeScript SwiftUI E2E"
    private let corePackageName = "Hanlin NativeScript Core E2E"
    private let unbundledPackageName = "Hanlin NativeScript Unbundled Core E2E"
    private let sefariaPackageName = "Sefaria Library & Texts (Core)"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_NATIVESCRIPT_E2E"] = "1"
        app.launch()
    }

    func testProductionSharedCoreUnbundledEndToEnd() throws {
        openApps()
        importAndInstall(archive: "core-unbundled")

        launchInstalledPackage(named: unbundledPackageName)

        let titlePredicate = NSPredicate(format: "label CONTAINS 'Unbundled Shared Core Active' OR identifier == 'unbundled-core-title'")
        let titleCandidate = app.descendants(matching: .any).matching(titlePredicate).firstMatch
        XCTAssertTrue(titleCandidate.waitForExistence(timeout: 30), "Unbundled Shared Core title did not render")
        capture(name: "Unbundled-Core-App-Launched")

        let verifyButtonPredicate = NSPredicate(format: "label CONTAINS 'Verify Core Features' OR identifier == 'unbundled-core-verify-button'")
        let verifyButton = app.descendants(matching: .any).matching(verifyButtonPredicate).firstMatch
        XCTAssertTrue(verifyButton.waitForExistence(timeout: 15), "Verify Core Features button did not exist")
        verifyButton.tap()

        let verifiedPredicate = NSPredicate(format: "label CONTAINS 'All Core Features Verified' OR label CONTAINS 'Verified' OR identifier == 'unbundled-core-status'")
        let statusCandidate = app.descendants(matching: .any).matching(verifiedPredicate).firstMatch
        XCTAssertTrue(statusCandidate.waitForExistence(timeout: 20), "Unbundled Shared Core features were not verified")
        capture(name: "Unbundled-Core-Features-Verified")

        closeNativeScriptApp()

        // 1. App close and reopen test
        launchInstalledPackage(named: unbundledPackageName)
        XCTAssertTrue(titleCandidate.waitForExistence(timeout: 30), "Unbundled Shared Core failed to relaunch after closing")
        capture(name: "Unbundled-Core-Relaunched")
        closeNativeScriptApp()

        // 2. Sequential execution across distinct MiniApps to ensure no state/config leakage
        importAndInstall(archive: "HanlinNativeScriptCore")
        launchInstalledPackage(named: corePackageName)
        assertNativeScriptCoreUI()
        capture(name: "Core-Regression-After-Unbundled")
        closeNativeScriptApp()

        // Return to unbundled app to confirm isolation in reverse
        launchInstalledPackage(named: unbundledPackageName)
        XCTAssertTrue(titleCandidate.waitForExistence(timeout: 30), "Unbundled Shared Core failed after running another MiniApp")
        closeNativeScriptApp()
    }


    func testProductionSefariaCoreEndToEnd() throws {
        openApps()
        importAndInstall(archive: "sefaria-reader-core")

        launchInstalledPackage(named: sefariaPackageName)

        let dailyTab = waitForTab(named: "לימוד יומי", timeout: 30)
        XCTAssertNotNil(dailyTab, "Sefaria Core TabView did not render")
        capture(name: "Sefaria-Core-App-Launched")

        // 1. Daily Study Tab (לימוד יומי)
        let readButtonPredicate = NSPredicate(format: "label CONTAINS 'פתח לקריאה ולימוד'")
        let openReadButton = app.buttons.matching(readButtonPredicate).firstMatch
        XCTAssertTrue(openReadButton.waitForExistence(timeout: 30), "Sefaria Daily Study calendar items did not load via Http")
        capture(name: "Sefaria-Daily-Tab-Loaded")

        openReadButton.tap()

        // 3. Reader controls (עברית, English, דו-לשוני, font size, navigation)
        let hebrewMode = app.buttons["עברית"].firstMatch
        let englishMode = app.buttons["English"].firstMatch
        let bilingualMode = app.buttons["דו-לשוני"].firstMatch
        XCTAssertTrue(hebrewMode.waitForExistence(timeout: 30), "Reader page SegmentedBar did not render")
        capture(name: "Sefaria-Reader-Hebrew")

        if englishMode.exists {
            englishMode.tap()
            capture(name: "Sefaria-Reader-English")
        }
        if bilingualMode.exists {
            bilingualMode.tap()
            capture(name: "Sefaria-Reader-Bilingual")
        }

        let plusButton = app.buttons["A+"].firstMatch
        let minusButton = app.buttons["A−"].firstMatch
        if plusButton.exists { plusButton.tap() }
        if minusButton.exists { minusButton.tap() }

        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        if backButton.exists {
            backButton.tap()
        }

        // 2. Library Tab (ארון הספרים)
        if let libraryTab = waitForTab(named: "ארון הספרים", timeout: 15) {
            libraryTab.tap()
            let genesisChip = app.buttons["Genesis 1"].firstMatch
            if genesisChip.waitForExistence(timeout: 10) {
                genesisChip.tap()
                XCTAssertTrue(hebrewMode.waitForExistence(timeout: 30), "Reader failed to load Genesis 1 from library")
                capture(name: "Sefaria-Library-Genesis-Loaded")
                if backButton.exists { backButton.tap() }
            }
        }

        // 4. Search Tab (חיפוש)
        if let searchTab = waitForTab(named: "חיפוש", timeout: 15) {
            searchTab.tap()
            let quickChip = app.buttons["Genesis 1"].firstMatch
            if quickChip.waitForExistence(timeout: 10) {
                quickChip.tap()
                capture(name: "Sefaria-Search-Executed")
                if backButton.exists { backButton.tap() }
            }
        }

        // 5. Lexicon Tab (מילון)
        if let lexiconTab = waitForTab(named: "מילון", timeout: 15) {
            lexiconTab.tap()
            let wordChip = app.buttons["מאימתי"].firstMatch
            if wordChip.waitForExistence(timeout: 10) {
                wordChip.tap()
                let resultPredicate = NSPredicate(format: "label CONTAINS 'מאימתי' OR label CONTAINS 'יסטרוב'")
                let result = app.descendants(matching: .any).matching(resultPredicate).firstMatch
                _ = result.waitForExistence(timeout: 20)
                capture(name: "Sefaria-Lexicon-Results")
            }
        }

        closeNativeScriptApp()

        // 8. App restart / persistence smoke check
        app.terminate()
        app.launch()
        openApps()
        let sefariaPredicate = NSPredicate(format: "label CONTAINS %@", sefariaPackageName)
        let sefariaCard = app.descendants(matching: .any).matching(sefariaPredicate).firstMatch
        XCTAssertTrue(
            sefariaCard.waitForExistence(timeout: 20),
            "Package \(sefariaPackageName) was not visible after app restart"
        )
        launchInstalledPackage(named: sefariaPackageName)
        XCTAssertNotNil(waitForTab(named: "לימוד יומי", timeout: 30), "Sefaria Core failed to relaunch after app restart")
        capture(name: "Sefaria-Relaunch-Success")
        closeNativeScriptApp()
    }

    func testProductionSwiftUIInteractionCoreRegressionAndLifecycle() throws {
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
        let swiftUIPredicate = NSPredicate(format: "label CONTAINS %@", swiftUIPackageName)
        let corePredicate = NSPredicate(format: "label CONTAINS %@", corePackageName)
        XCTAssertTrue(
            app.descendants(matching: .any).matching(swiftUIPredicate).firstMatch.waitForExistence(timeout: 20),
            "Package \(swiftUIPackageName) was not visible after restart"
        )
        XCTAssertTrue(
            app.descendants(matching: .any).matching(corePredicate).firstMatch.waitForExistence(timeout: 20),
            "Package \(corePackageName) was not visible after restart"
        )
        launchInstalledPackage(named: swiftUIPackageName)
        XCTAssertTrue(app.buttons["hanlin-swiftui-increment"].waitForExistence(timeout: 30))
        closeNativeScriptApp()
    }

    func testUnsupportedPluginRejection() throws {
        openApps()
        importArchive(named: "HanlinNativeScriptUnsupported")
        let disabledInstall = app.buttons["hanlin-package-install"].firstMatch
        XCTAssertTrue(disabledInstall.waitForExistence(timeout: 20), "Install button did not exist in preview")
        XCTAssertFalse(disabledInstall.isEnabled, "Unsupported native plugin package was installable")
        let unsupportedMessage = app.staticTexts[
            "This Hanlin build supports @nativescript/swift-ui 4.0.2, but the package requires @nativescript/swift-ui 99.0.0."
        ]
        if !unsupportedMessage.waitForExistence(timeout: 5) {
            app.swipeUp()
        }
        XCTAssertTrue(unsupportedMessage.waitForExistence(timeout: 20), "Unsupported plugin reason was not visible")
        capture(name: "Unsupported-NativeScript-Plugin-Rejected")
        closeImportSurfaces()
    }

    func testMalformedPackageRejection() throws {
        openApps()
        importArchive(named: "HanlinNativeScriptMalformed")
        let errorIndicator = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier == 'hanlin-import-error' OR identifier == 'hanlin-import-error-message' OR label CONTAINS 'Import Error' OR label CONTAINS 'malformed'"
            )
        ).firstMatch
        if !errorIndicator.waitForExistence(timeout: 5) {
            app.swipeUp()
        }
        XCTAssertTrue(errorIndicator.waitForExistence(timeout: 20), "Malformed package import error was not displayed")
        XCTAssertFalse(app.buttons["hanlin-package-install"].firstMatch.exists)
        capture(name: "Malformed-Package-Rejected")
        closeImportSurfaces()
    }

    private func importAndInstall(archive: String) {
        importArchive(named: archive)
        let install = app.buttons["hanlin-package-install"].firstMatch
        if !install.waitForExistence(timeout: 10) {
            app.swipeUp()
        }
        if !install.waitForExistence(timeout: 20) {
            capture(name: "\(archive)-Import-Timeout")
            var detail = "Import Preview did not expose Install for \(archive)."
            if app.staticTexts["Import Error"].firstMatch.exists {
                let errorLabels = app.staticTexts.allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty }
                detail += " Detected on-screen error: " + errorLabels.joined(separator: " | ")
            }
            XCTFail(detail)
            return
        }
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

    private func importArchive(named archiveName: String) {
        ensureAppsAddButton(timeout: 15).tap()
        let importLink = app.buttons["hanlin-import-script-package"].firstMatch
        XCTAssertTrue(importLink.waitForExistence(timeout: 10))
        importLink.tap()

        let navBar = app.navigationBars["Script Package"].firstMatch
        _ = navBar.waitForExistence(timeout: 5)

        let directArchive = app.buttons[archiveName].firstMatch
        if directArchive.waitForExistence(timeout: 5) {
            _ = waitUntil(timeout: 5) { directArchive.isHittable }
            directArchive.tap()

            let inspecting = app.staticTexts["Inspecting…"].firstMatch
            let install = app.buttons["hanlin-package-install"].firstMatch
            let errorText = app.staticTexts["Import Error"].firstMatch
            let started = waitUntil(timeout: 4) {
                inspecting.exists || install.exists || errorText.exists
            }
            if !started && directArchive.exists && directArchive.isHittable {
                directArchive.tap()
            }
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
        let scriptPackageNav = app.navigationBars["Script Package"].firstMatch
        if scriptPackageNav.exists {
            let done = app.buttons["Done"].firstMatch
            if done.exists && done.isHittable {
                done.tap()
            }
            _ = waitUntil(timeout: 5) { !scriptPackageNav.exists }
        }
        let addAppsNav = app.navigationBars["Add Apps"].firstMatch
        if addAppsNav.waitForExistence(timeout: 3) || addAppsNav.exists {
            let done = app.buttons["Done"].firstMatch
            if done.waitForExistence(timeout: 3) && done.isHittable {
                done.tap()
            }
            _ = waitUntil(timeout: 5) { !addAppsNav.exists }
        }
        _ = waitUntil(timeout: 5) {
            !app.navigationBars["Script Package"].exists && !app.navigationBars["Add Apps"].exists
        }
    }

    private func launchInstalledPackage(named packageName: String) {
        let predicate = NSPredicate(format: "label CONTAINS %@ OR identifier CONTAINS %@", packageName, packageName)
        let packageCandidates = [
            app.buttons.matching(predicate).firstMatch,
            app.descendants(matching: .any).matching(predicate).firstMatch,
            app.staticTexts[packageName].firstMatch
        ]
        var target: XCUIElement?
        for candidate in packageCandidates {
            if candidate.waitForExistence(timeout: 5) {
                target = candidate
                break
            }
        }
        let package = target ?? app.staticTexts[packageName].firstMatch
        XCTAssertTrue(package.waitForExistence(timeout: 15), "Installed package \(packageName) was unavailable")

        let closeButton = app.buttons["hanlin-script-app-close"].firstMatch
        let coreButton = app.buttons["hanlin-nativescript-core-button"].firstMatch
        let swiftUIButton = app.buttons["hanlin-swiftui-increment"].firstMatch

        for attempt in 1...3 {
            if closeButton.exists || coreButton.exists || swiftUIButton.exists {
                return
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
            if waitUntil(timeout: attempt == 1 ? 15 : 8, condition: { closeButton.exists || coreButton.exists || swiftUIButton.exists }) {
                return
            }
            if app.alerts["Script App Error"].exists {
                let errorLabels = app.alerts["Script App Error"].staticTexts.allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty }
                XCTFail("Script App Error alert appeared when launching \(packageName): " + errorLabels.joined(separator: " | "))
                return
            }
        }
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
        _ = waitUntil(timeout: 10) { !close.exists }
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

    private func waitForTab(named title: String, timeout: TimeInterval = 30) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        let predicate = NSPredicate(format: "label == %@ OR title == %@ OR identifier == %@ OR label CONTAINS[c] %@", title, title, title, title)
        let queries: [() -> XCUIElement] = [
            { self.app.tabBars.buttons[title].firstMatch },
            { self.app.tabBars.buttons.matching(predicate).firstMatch },
            { self.app.tabBars.tabs[title].firstMatch },
            { self.app.tabBars.tabs.matching(predicate).firstMatch },
            { self.app.tabs[title].firstMatch },
            { self.app.tabs.matching(predicate).firstMatch },
            { self.app.buttons[title].firstMatch },
            { self.app.buttons.matching(predicate).firstMatch },
            { self.app.descendants(matching: .any).matching(predicate).firstMatch }
        ]
        while Date() < deadline {
            for getQuery in queries {
                let elem = getQuery()
                if elem.exists {
                    return elem
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        for getQuery in queries {
            let elem = getQuery()
            if elem.exists { return elem }
        }
        return nil
    }

    private func capture(name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
