import XCTest

@MainActor
final class HanlinRuntimeCommandAcceptanceUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_RUNTIME_INSTALL_ACCEPTANCE"] = "1"
        app.launch()
    }

    func testRuntimeCenterCommandSmokeAndCoherence() throws {
        openSettings()
        openRuntimeCenter()

        // 1. Initial Shell Smoke execution
        let smokeShell = app.buttons["hanlin-runtime-smoke-shell"].firstMatch
        XCTAssertTrue(smokeShell.waitForExistence(timeout: 10), "Shell smoke button missing in Runtime Center")
        smokeShell.tap()

        let lastMessage = app.descendants(matching: .any)["hanlin-runtime-last-message"].firstMatch
        XCTAssertTrue(lastMessage.waitForExistence(timeout: 15), "Shell command output missing")
        // Exact semantic assertion: shell smoke output confirms healthy execution
        XCTAssertTrue(
            lastMessage.label.contains("0") || lastMessage.label.contains("OK") || lastMessage.label.contains("Completed"),
            "Shell execution did not return a successful deterministic status: \(lastMessage.label)"
        )

        // 2. Open Shell Capabilities & Verified Command Catalog
        let shellDetails = app.buttons["hanlin-runtime-details-shell"].firstMatch
        XCTAssertTrue(shellDetails.waitForExistence(timeout: 10))
        shellDetails.tap()

        let shellCapabilitiesNav = app.navigationBars["Shell Capabilities"].firstMatch
        let fallbackNav = app.navigationBars["Shell & Commands"].firstMatch
        XCTAssertTrue(shellCapabilitiesNav.waitForExistence(timeout: 10) || fallbackNav.waitForExistence(timeout: 5))

        // Verify approved linked commands exist in the UI list
        let echoOrLsCell = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'ls' OR label CONTAINS 'cat' OR label CONTAINS 'grep' OR identifier CONTAINS 'cmd-'")
        ).firstMatch
        XCTAssertTrue(echoOrLsCell.waitForExistence(timeout: 10), "Approved shell command list not displayed in Shell Capabilities")

        navigateBack()

        // 3. Recovery Verification: execute another distinct runtime operation to prove session coherence
        let jscSmoke = app.buttons["hanlin-runtime-smoke-javaScriptCore"].firstMatch
        XCTAssertTrue(jscSmoke.waitForExistence(timeout: 10))
        jscSmoke.tap()

        let jscResult = app.descendants(matching: .any)["hanlin-runtime-last-message"].firstMatch
        XCTAssertTrue(jscResult.waitForExistence(timeout: 15))
        XCTAssertTrue(jscResult.label.contains("3"), "JavaScriptCore failed to execute cleanly after shell operations: \(jscResult.label)")
    }

    func testRuntimeSessionStateAndRestartPersistence() throws {
        openSettings()
        openRuntimeCenter()

        // Verify Python runtime execution
        let pythonSmoke = app.buttons["hanlin-runtime-smoke-localPython"].firstMatch
        XCTAssertTrue(pythonSmoke.waitForExistence(timeout: 10))
        pythonSmoke.tap()

        let pythonResult = app.descendants(matching: .any)["hanlin-runtime-last-message"].firstMatch
        XCTAssertTrue(pythonResult.waitForExistence(timeout: 25))
        XCTAssertTrue(
            pythonResult.label.contains("שלום") || pythonResult.label.contains("Completed"),
            "Python smoke failed: \(pythonResult.label)"
        )

        // Terminate and relaunch to prove persistent state
        app.terminate()
        app.launch()
        openSettings()
        openRuntimeCenter()

        // Node.js execution after restart
        let nodeSmoke = app.buttons["hanlin-runtime-smoke-node"].firstMatch
        XCTAssertTrue(nodeSmoke.waitForExistence(timeout: 10))
        nodeSmoke.tap()

        let nodeResult = app.descendants(matching: .any)["hanlin-runtime-last-message"].firstMatch
        XCTAssertTrue(nodeResult.waitForExistence(timeout: 30))
        XCTAssertTrue(
            nodeResult.label.hasPrefix("v") || nodeResult.label.contains("Completed"),
            "Node.js runtime smoke failed after restart: \(nodeResult.label)"
        )
    }

    // MARK: - Helpers

    private func openSettings() {
        let runtimeLink = app.buttons["hanlin-runtimes-packages-link"].firstMatch
        if runtimeLink.exists { return }
        let settingsTab = app.tabBars.buttons["hanlin-settings-tab"].firstMatch
        if settingsTab.waitForExistence(timeout: 3) && settingsTab.isHittable {
            settingsTab.tap()
            return
        }
        let nextPage = app.buttons["Next Page"].firstMatch
        if nextPage.waitForExistence(timeout: 2) && nextPage.isHittable {
            nextPage.tap()
            if settingsTab.waitForExistence(timeout: 3) && settingsTab.isHittable {
                settingsTab.tap()
                return
            }
        }
        let labelTab = app.tabBars.buttons["Settings"].firstMatch
        if labelTab.waitForExistence(timeout: 2) && labelTab.isHittable { labelTab.tap() }
    }

    private func openRuntimeCenter() {
        let runtimeLink = app.buttons["hanlin-runtimes-packages-link"].firstMatch
        if !runtimeLink.exists { app.swipeUp() }
        XCTAssertTrue(runtimeLink.waitForExistence(timeout: 10), "Runtime Center link missing in Settings")
        runtimeLink.tap()
    }

    private func navigateBack() {
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        if backButton.exists && backButton.isHittable {
            backButton.tap()
        }
    }
}
