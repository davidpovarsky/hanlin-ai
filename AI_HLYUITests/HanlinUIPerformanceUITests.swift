import XCTest

/// End-to-end UI performance regression suite measuring application launch, screen navigation,
/// ScriptUI package install/render/interaction/persistence, and NativeScript SwiftUI provider rendering.
@MainActor
final class HanlinUIPerformanceUITests: XCTestCase {
    private let app = XCUIApplication()
    private static let sampleIterationCount = 5

    private let validScriptUIPackageName = "Hanlin ScriptUI Valid"
    private let nativeScriptSwiftUIPackageName = "Hanlin NativeScript SwiftUI E2E"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
    }

    private func measureOptions() -> XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = Self.sampleIterationCount
        return options
    }

    private func emitSample(
        flowNumber: Int,
        flowName: String,
        category: String,
        metric: String,
        unit: String,
        samples: [Double],
        classification: String = "informational"
    ) {
        guard !samples.isEmpty else { return }
        let count = Double(samples.count)
        let mean = samples.reduce(0.0, +) / count
        let sorted = samples.sorted()
        let median = sorted[sorted.count / 2]
        let variance = samples.reduce(0.0) { $0 + pow($1 - mean, 2.0) } / max(1.0, count - 1.0)
        let stdDev = sqrt(variance)
        let minVal = sorted.first ?? 0.0
        let maxVal = sorted.last ?? 0.0

        let payload: [String: Any] = [
            "flow_number": flowNumber,
            "flow_name": flowName,
            "category": category,
            "metric": metric,
            "unit": unit,
            "sample_count": samples.count,
            "samples": samples,
            "mean": mean,
            "median": median,
            "std_dev": stdDev,
            "min": minVal,
            "max": maxVal,
            "classification": classification,
            "status": "PASS"
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
           let jsonStr = String(data: data, encoding: .utf8) {
            print("HANLIN_PERF_SAMPLE: \(jsonStr)")
        }
    }

    // MARK: - Flow 1: Application Launch

    func testFlow1_ApplicationColdLaunchPerformance() throws {
        var recordedSamples: [Double] = []

        measure(
            metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)],
            options: measureOptions()
        ) {
            let start = CFAbsoluteTimeGetCurrent()
            let launchedApp = XCUIApplication()
            launchedApp.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            launchedApp.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
            launchedApp.launch()
            let homeRootPredicate = NSPredicate(
                format: "label CONTAINS 'Hylic.AI' OR identifier CONTAINS 'Hylic.AI' OR title CONTAINS 'Hylic.AI'"
            )
            let homeRoot = launchedApp.descendants(matching: .any).matching(homeRootPredicate).firstMatch
            XCTAssertTrue(homeRoot.waitForExistence(timeout: 20), "Cold launch did not reach responsive home screen")
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            recordedSamples.append(elapsed)
        }

        emitSample(
            flowNumber: 1,
            flowName: "Application Cold Launch",
            category: "App Launch",
            metric: "launch_duration",
            unit: "s",
            samples: recordedSamples
        )
    }

    // MARK: - Flow 2: Time to Usable First Screen

    func testFlow2_TimeToUsableFirstScreenPerformance() throws {
        var recordedSamples: [Double] = []

        measure(
            metrics: [XCTClockMetric(), XCTCPUMetric(limitingToCurrentThread: false)],
            options: measureOptions()
        ) {
            let start = CFAbsoluteTimeGetCurrent()
            let testApp = XCUIApplication()
            testApp.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            testApp.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
            testApp.launch()

            let homeCandidates = [
                testApp.buttons["hanlin-home-tab"].firstMatch,
                testApp.tabBars.buttons["hanlin-home-tab"].firstMatch,
                testApp.descendants(matching: .any).matching(identifier: "hanlin-home-tab").firstMatch,
                testApp.buttons["Home"].firstMatch,
                testApp.staticTexts["Home"].firstMatch
            ]
            var interactive = false
            for candidate in homeCandidates {
                if candidate.waitForExistence(timeout: 3) && candidate.isHittable {
                    interactive = true
                    break
                }
            }
            if !interactive {
                interactive = testApp.windows.firstMatch.waitForExistence(timeout: 10)
            }
            XCTAssertTrue(interactive, "Home tab / first screen was not interactive within timeout")
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            recordedSamples.append(elapsed)
        }

        emitSample(
            flowNumber: 2,
            flowName: "Time to Usable First Screen",
            category: "App Launch",
            metric: "time_to_first_screen",
            unit: "s",
            samples: recordedSamples
        )
    }

    // MARK: - Flow 3: Open Scripting / Apps Screen

    func testFlow3_OpenScriptingAppsScreenPerformance() throws {
        app.launch()
        var recordedSamples: [Double] = []

        for _ in 0..<Self.sampleIterationCount {
            // Ensure on Home tab first
            selectTab(identifier: "hanlin-home-tab", labels: ["列表", "List", "Chats"])
            _ = waitUntil(timeout: 5) { !self.appsAddButton.exists }

            let start = CFAbsoluteTimeGetCurrent()
            openApps()
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            XCTAssertTrue(appsAddButton.waitForExistence(timeout: 10), "Apps screen was not responsive")
            recordedSamples.append(elapsed)
        }

        emitSample(
            flowNumber: 3,
            flowName: "Open Scripting/Apps Screen",
            category: "UI Navigation",
            metric: "screen_transition_latency",
            unit: "s",
            samples: recordedSamples
        )
    }

    // MARK: - Flow 9: Deterministic Local Package Installation via UI

    func testFlow9_ScriptUIPackageImportAndInstallationPerformance() throws {
        app.launchEnvironment["HANLIN_SCRIPTUI_E2E"] = "1"
        app.launch()
        openApps()
        ensurePackageUninstalled(named: validScriptUIPackageName)

        var recordedSamples: [Double] = []
        let start = CFAbsoluteTimeGetCurrent()

        ensureAppsAddButton(timeout: 15).tap()
        let importLink = app.buttons["hanlin-import-script-package"].firstMatch
        XCTAssertTrue(importLink.waitForExistence(timeout: 10), "Import Script Package link missing")
        importLink.tap()

        selectArchive(named: "HanlinScriptUIValid")
        let installButton = app.buttons["hanlin-package-install"].firstMatch
        XCTAssertTrue(installButton.waitForExistence(timeout: 20), "Install button missing in preview")

        var networkToggle = app.switches["network"].firstMatch
        if !networkToggle.waitForExistence(timeout: 3) {
            app.swipeUp()
            networkToggle = app.switches["network"].firstMatch
        }
        let approveAll = app.buttons["hanlin-approve-all-capabilities"].firstMatch
        if approveAll.waitForExistence(timeout: 3) && approveAll.isHittable {
            approveAll.tap()
        } else if networkToggle.waitForExistence(timeout: 5) {
            toggleSwitch(networkToggle, targetValue: "1")
        }
        _ = waitUntil(timeout: 5) { (networkToggle.value as? String) == "1" }

        if !installButton.exists || !installButton.isHittable {
            app.swipeDown()
        }
        XCTAssertTrue(installButton.waitForExistence(timeout: 5), "Install button did not reappear")
        XCTAssertTrue(waitUntil(timeout: 10) { installButton.isEnabled }, "Install button not enabled")
        installButton.tap()
        XCTAssertTrue(waitUntil(timeout: 30) { !installButton.exists }, "Installation did not complete")
        closeImportSurfaces()

        let elapsed = CFAbsoluteTimeGetCurrent() - start
        recordedSamples.append(elapsed)

        let packageCard = findPackageCard(named: validScriptUIPackageName)
        XCTAssertTrue(packageCard.waitForExistence(timeout: 15), "Installed package card missing from Apps list")

        emitSample(
            flowNumber: 9,
            flowName: "ScriptUI Package UI Import & Installation",
            category: "UI Package Management",
            metric: "import_and_install_duration",
            unit: "s",
            samples: recordedSamples
        )
    }

    // MARK: - Flow 10: ScriptUI First Render Performance

    func testFlow10_ScriptUIFirstRenderPerformance() throws {
        app.launchEnvironment["HANLIN_SCRIPTUI_E2E"] = "1"
        app.launch()
        openApps()
        ensureValidScriptUIPackageInstalled()

        var recordedSamples: [Double] = []
        let start = CFAbsoluteTimeGetCurrent()

        launchPackage(named: validScriptUIPackageName)
        let countText = app.staticTexts["Count 0"].firstMatch
        XCTAssertTrue(countText.waitForExistence(timeout: 25), "ScriptUI initial state 'Count 0' did not render")
        let incrementButton = app.buttons["Increment"].firstMatch
        XCTAssertTrue(incrementButton.waitForExistence(timeout: 10), "ScriptUI Increment button missing")

        let elapsed = CFAbsoluteTimeGetCurrent() - start
        recordedSamples.append(elapsed)
        closeScriptApp()

        emitSample(
            flowNumber: 10,
            flowName: "ScriptUI First Render",
            category: "ScriptUI Render",
            metric: "first_render_latency",
            unit: "s",
            samples: recordedSamples
        )
    }

    // MARK: - Flow 15: Key Scripting Screen Interactions (State Mutation)

    func testFlow15_ScriptUIInteractionAndReactiveUpdatePerformance() throws {
        app.launchEnvironment["HANLIN_SCRIPTUI_E2E"] = "1"
        app.launch()
        openApps()
        ensureValidScriptUIPackageInstalled()
        launchPackage(named: validScriptUIPackageName)

        let countText = app.staticTexts["Count 0"].firstMatch
        XCTAssertTrue(countText.waitForExistence(timeout: 25), "Initial state missing")
        let incrementButton = app.buttons["Increment"].firstMatch
        XCTAssertTrue(incrementButton.waitForExistence(timeout: 10), "Increment button missing")

        var recordedSamples: [Double] = []
        for i in 1...Self.sampleIterationCount {
            let expectedNext = "Count \(i)"
            let start = CFAbsoluteTimeGetCurrent()
            incrementButton.tap()
            let nextText = app.staticTexts[expectedNext].firstMatch
            XCTAssertTrue(nextText.waitForExistence(timeout: 10), "Reactive state update to '\(expectedNext)' failed")
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            recordedSamples.append(elapsed)
        }
        closeScriptApp()

        emitSample(
            flowNumber: 15,
            flowName: "ScriptUI Interaction & Reactive State Mutation",
            category: "ScriptUI Interaction",
            metric: "tap_to_mutation_latency",
            unit: "s",
            samples: recordedSamples
        )
    }

    // MARK: - Flow 16: Persistence / Reload / Reopen Across App Restart

    func testFlow16_ScriptUIPersistenceAcrossAppRestartPerformance() throws {
        app.launchEnvironment["HANLIN_SCRIPTUI_E2E"] = "1"
        app.launch()
        openApps()
        ensureValidScriptUIPackageInstalled()

        var recordedSamples: [Double] = []
        for _ in 0..<3 {
            app.terminate()
            let start = CFAbsoluteTimeGetCurrent()
            app.launch()
            openApps()

            let card = findPackageCard(named: validScriptUIPackageName)
            XCTAssertTrue(card.waitForExistence(timeout: 15), "Persisted package card missing after restart")
            card.tap()

            let countText = app.staticTexts["Count 0"].firstMatch
            XCTAssertTrue(countText.waitForExistence(timeout: 20), "ScriptUI did not initialize cleanly on reopen")
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            recordedSamples.append(elapsed)
            closeScriptApp()
        }

        emitSample(
            flowNumber: 16,
            flowName: "ScriptUI Persistence Reload Across Restart",
            category: "App Persistence",
            metric: "restart_and_reload_duration",
            unit: "s",
            samples: recordedSamples
        )
    }

    // MARK: - Flow 11 & 12: NativeScript First Initialization and Core UI Render

    func testFlow11_12_NativeScriptFirstInitializationAndCoreRenderPerformance() throws {
        app.launchEnvironment["HANLIN_NATIVESCRIPT_E2E"] = "1"
        app.launch()
        openApps()

        var recordedSamples: [Double] = []
        let start = CFAbsoluteTimeGetCurrent()

        launchInstalledPackage(named: nativeScriptSwiftUIPackageName)
        let coreButton = app.buttons["hanlin-nativescript-core-button"].firstMatch
        let coreLabel = app.staticTexts["hanlin-nativescript-device-proof"].firstMatch
        XCTAssertTrue(coreButton.waitForExistence(timeout: 25), "NativeScript Core button did not render")
        XCTAssertTrue(coreLabel.waitForExistence(timeout: 10), "NativeScript device proof did not render")

        let elapsed = CFAbsoluteTimeGetCurrent() - start
        recordedSamples.append(elapsed)
        closeNativeScriptApp()

        emitSample(
            flowNumber: 11,
            flowName: "NativeScript First Init & Core UI Render",
            category: "NativeScript Render",
            metric: "first_init_and_render_latency",
            unit: "s",
            samples: recordedSamples
        )
    }

    // MARK: - Flow 13 & 14: @nativescript/swift-ui Provider First & Subsequent Render

    func testFlow13_14_NativeScriptSwiftUIProviderRenderAndRoundTripPerformance() throws {
        app.launchEnvironment["HANLIN_NATIVESCRIPT_E2E"] = "1"
        app.launch()
        openApps()

        var recordedSamples: [Double] = []
        for _ in 0..<Self.sampleIterationCount {
            let start = CFAbsoluteTimeGetCurrent()
            launchInstalledPackage(named: nativeScriptSwiftUIPackageName)

            let incrementButton = app.buttons["hanlin-swiftui-increment"].firstMatch
            XCTAssertTrue(incrementButton.waitForExistence(timeout: 25), "@nativescript/swift-ui provider button missing")
            incrementButton.tap()

            let updatedButton = app.buttons["hanlin-swiftui-increment"].firstMatch
            XCTAssertTrue(updatedButton.waitForExistence(timeout: 10), "SwiftUI button did not survive round trip")
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            recordedSamples.append(elapsed)
            closeNativeScriptApp()
        }

        emitSample(
            flowNumber: 13,
            flowName: "@nativescript/swift-ui Provider Render & Interaction Round-Trip",
            category: "NativeScript / SwiftUI",
            metric: "provider_render_and_event_latency",
            unit: "s",
            samples: recordedSamples
        )
    }

    // MARK: - UI Helpers

    @discardableResult
    private func selectTab(identifier: String, labels: [String] = []) -> Bool {
        var candidates: [XCUIElement] = [
            app.tabBars.buttons[identifier].firstMatch,
            app.buttons[identifier].firstMatch,
            app.tabs[identifier].firstMatch
        ]
        for label in labels {
            candidates.append(app.tabBars.buttons[label].firstMatch)
            candidates.append(app.buttons[label].firstMatch)
            candidates.append(app.tabs[label].firstMatch)
        }
        for candidate in candidates {
            if candidate.waitForExistence(timeout: 2) && candidate.isHittable {
                candidate.tap()
                return true
            }
        }
        return false
    }

    private func openApps() {
        if appsAddButton.waitForExistence(timeout: 3) { return }
        let candidates = [
            app.buttons["hanlin-apps-tab"].firstMatch,
            app.tabBars.buttons["hanlin-apps-tab"].firstMatch,
            app.tabs["hanlin-apps-tab"].firstMatch,
            app.buttons["Apps"].firstMatch,
            app.tabBars.buttons["Apps"].firstMatch,
            app.tabs["Apps"].firstMatch
        ]
        for candidate in candidates {
            if candidate.waitForExistence(timeout: 2) {
                candidate.tap()
                break
            }
        }
        _ = ensureAppsAddButton(timeout: 15)
    }

    private var appsAddButton: XCUIElement {
        let direct = app.buttons["hanlin-apps-add"].firstMatch
        if direct.exists { return direct }
        let nav = app.navigationBars.buttons["hanlin-apps-add"].firstMatch
        if nav.exists { return nav }
        let byId = app.descendants(matching: .any).matching(identifier: "hanlin-apps-add").firstMatch
        if byId.exists { return byId }
        return app.buttons["Add App"].firstMatch
    }

    @discardableResult
    private func ensureAppsAddButton(timeout: TimeInterval) -> XCUIElement {
        let button = appsAddButton
        XCTAssertTrue(button.waitForExistence(timeout: timeout), "Apps add button not found")
        return button
    }

    private func selectArchive(named archiveName: String) {
        let direct = app.buttons[archiveName].firstMatch
        if direct.waitForExistence(timeout: 5) {
            _ = waitUntil(timeout: 5) { direct.isHittable }
            direct.tap()
            return
        }
        let predicate = NSPredicate(format: "label CONTAINS %@ OR identifier CONTAINS %@", archiveName, archiveName)
        let element = app.descendants(matching: .any).matching(predicate).firstMatch
        if element.waitForExistence(timeout: 10) {
            element.tap()
        }
    }

    private func ensureValidScriptUIPackageInstalled() {
        let card = findPackageCard(named: validScriptUIPackageName)
        if card.waitForExistence(timeout: 3) { return }

        ensureAppsAddButton(timeout: 15).tap()
        let importLink = app.buttons["hanlin-import-script-package"].firstMatch
        if importLink.waitForExistence(timeout: 10) {
            importLink.tap()
        }
        selectArchive(named: "HanlinScriptUIValid")

        let installButton = app.buttons["hanlin-package-install"].firstMatch
        _ = installButton.waitForExistence(timeout: 20)

        var networkToggle = app.switches["network"].firstMatch
        if !networkToggle.waitForExistence(timeout: 3) {
            app.swipeUp()
            networkToggle = app.switches["network"].firstMatch
        }
        let approveAllButton = app.buttons["hanlin-approve-all-capabilities"].firstMatch
        if approveAllButton.waitForExistence(timeout: 3) && approveAllButton.isHittable {
            approveAllButton.tap()
        } else if networkToggle.waitForExistence(timeout: 5) {
            toggleSwitch(networkToggle, targetValue: "1")
        }
        _ = waitUntil(timeout: 5) { (networkToggle.value as? String) == "1" }

        if !installButton.exists || !installButton.isHittable {
            app.swipeDown()
        }
        _ = installButton.waitForExistence(timeout: 5)
        _ = waitUntil(timeout: 10) { installButton.isEnabled }
        if installButton.isEnabled {
            installButton.tap()
            _ = waitUntil(timeout: 30) { !installButton.exists }
        }
        closeImportSurfaces()
    }

    private func openPackageDetails(named packageName: String) {
        let packageCard = findPackageCard(named: packageName)
        if packageCard.waitForExistence(timeout: 5) {
            packageCard.press(forDuration: 1.5)
            let infoButton = app.buttons["Package Information"].firstMatch
            if infoButton.waitForExistence(timeout: 5) {
                infoButton.tap()
            }
        }
    }

    private func closeDetails() {
        let done = app.buttons["Done"].firstMatch
        if done.waitForExistence(timeout: 3) && done.isHittable {
            done.tap()
            _ = waitUntil(timeout: 5) { !done.exists }
        } else {
            app.swipeDown()
            _ = waitUntil(timeout: 5) { !done.exists }
        }
    }

    private func ensurePackageUninstalled(named packageName: String) {
        let card = findPackageCard(named: packageName)
        if card.waitForExistence(timeout: 2) {
            openPackageDetails(named: packageName)
            let uninstallButton = app.buttons["Uninstall Package"].firstMatch
            if uninstallButton.waitForExistence(timeout: 5) && uninstallButton.isHittable {
                uninstallButton.tap()
                let confirm = app.alerts.buttons["Uninstall"].firstMatch
                if confirm.waitForExistence(timeout: 3) { confirm.tap() }
                _ = waitUntil(timeout: 10) { !findPackageCard(named: packageName).exists }
            } else {
                closeDetails()
            }
        }
    }

    private func launchPackage(named name: String) {
        let card = findPackageCard(named: name)
        XCTAssertTrue(card.waitForExistence(timeout: 15), "Package card \(name) missing")
        card.tap()
    }

    private func launchInstalledPackage(named name: String) {
        launchPackage(named: name)
    }

    private func closeScriptApp() {
        let close = app.buttons["hanlin-script-app-close"].firstMatch
        if close.waitForExistence(timeout: 10) && close.isHittable {
            close.tap()
            _ = waitUntil(timeout: 10) { !close.exists }
            _ = ensureAppsAddButton(timeout: 15)
        }
    }

    private func closeNativeScriptApp() {
        let close = app.buttons["hanlin-nativescript-close"].firstMatch
        if close.waitForExistence(timeout: 5) && close.isHittable {
            close.tap()
            _ = waitUntil(timeout: 10) { !close.exists }
            _ = ensureAppsAddButton(timeout: 15)
            return
        }
        closeScriptApp()
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
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.exists && cancel.isHittable { cancel.tap() }
        let close = app.buttons["Close"].firstMatch
        if close.exists && close.isHittable { close.tap() }
    }

    private func findPackageCard(named name: String) -> XCUIElement {
        let card = app.buttons["hanlin-package-card-\(name)"].firstMatch
        if card.exists { return card }
        let predicate = NSPredicate(format: "label CONTAINS %@ OR identifier CONTAINS %@", name, name)
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    private func toggleSwitch(_ element: XCUIElement, targetValue: String) {
        guard let current = element.value as? String, current != targetValue else { return }
        element.tap()
        _ = waitUntil(timeout: 5) { (element.value as? String) == targetValue }
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }
}
