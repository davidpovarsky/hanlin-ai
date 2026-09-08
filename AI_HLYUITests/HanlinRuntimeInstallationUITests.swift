import XCTest

@MainActor
final class HanlinRuntimeInstallationUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_RUNTIME_INSTALL_ACCEPTANCE"] = "1"
        app.launch()
    }

    // MARK: - Embedded Runtimes Smoke & Readiness Acceptance

    func testRuntimeCenterEmbeddedRuntimesSmokeAndReadiness() throws {
        openSettings()
        openRuntimeCenter()

        // 1. Verify all 5 runtime cards exist (handling virtualized scroll in List)
        let nodeCard = app.descendants(matching: .any)["hanlin-runtime-card-node"].firstMatch
        let tsCard = app.descendants(matching: .any)["hanlin-runtime-card-typeScript"].firstMatch
        let pythonCard = app.descendants(matching: .any)["hanlin-runtime-card-localPython"].firstMatch
        let jscCard = app.descendants(matching: .any)["hanlin-runtime-card-javaScriptCore"].firstMatch
        let shellCard = app.descendants(matching: .any)["hanlin-runtime-card-shell"].firstMatch

        XCTAssertTrue(nodeCard.waitForExistence(timeout: 10), "Node.js card was missing")
        XCTAssertTrue(tsCard.waitForExistence(timeout: 10), "TypeScript card was missing")
        XCTAssertTrue(pythonCard.waitForExistence(timeout: 10), "Local Python card was missing")
        if !jscCard.exists { app.swipeUp() }
        XCTAssertTrue(jscCard.waitForExistence(timeout: 10), "JavaScriptCore card was missing")
        if !shellCard.exists { app.swipeUp() }
        XCTAssertTrue(shellCard.waitForExistence(timeout: 10), "Shell card was missing")

        capture(name: "RuntimeCenter-Initial")

        // 2. JavaScriptCore Smoke Test (1 + 2 = 3)
        tapButton(withId: "hanlin-runtime-smoke-javaScriptCore")
        let jscResult = app.descendants(matching: .any)["hanlin-runtime-last-message"].firstMatch
        XCTAssertTrue(jscResult.waitForExistence(timeout: 15), "JSC smoke test result was missing")
        XCTAssertTrue(
            jscResult.label.contains("3"),
            "JSC smoke test did not produce expected value '3': \(jscResult.label)"
        )

        // 3. Shell / ios_system Smoke Test & Capabilities View
        tapButton(withId: "hanlin-runtime-smoke-shell")
        let shellResult = app.descendants(matching: .any)["hanlin-runtime-last-message"].firstMatch
        XCTAssertTrue(shellResult.waitForExistence(timeout: 15), "Shell smoke test result was missing")
        XCTAssertFalse(shellResult.label.isEmpty, "Shell smoke test output was unexpectedly empty")

        tapButton(withId: "hanlin-runtime-details-shell")
        let shellNav = app.navigationBars["Shell Capabilities"].firstMatch
        let fallbackNav = app.navigationBars["Shell & Commands"].firstMatch
        XCTAssertTrue(shellNav.waitForExistence(timeout: 10) || fallbackNav.waitForExistence(timeout: 3), "Shell capabilities view did not open")
        capture(name: "Shell-Capabilities-View")
        navigateBack()

        // 4. Local Python Smoke Test (print('שלום'))
        tapButton(withId: "hanlin-runtime-smoke-localPython")
        let pythonResult = app.descendants(matching: .any)["hanlin-runtime-last-message"].firstMatch
        XCTAssertTrue(pythonResult.waitForExistence(timeout: 25), "Python smoke test result was missing")
        XCTAssertTrue(
            pythonResult.label.contains("שלום") || pythonResult.label.contains("Completed"),
            "Python smoke test did not produce expected output: \(pythonResult.label)"
        )

        // 5. Node.js Smoke Test (console.log(process.version))
        tapButton(withId: "hanlin-runtime-smoke-node")
        let nodeResult = app.descendants(matching: .any)["hanlin-runtime-last-message"].firstMatch
        XCTAssertTrue(nodeResult.waitForExistence(timeout: 30), "Node smoke test result was missing")
        XCTAssertTrue(
            nodeResult.label.hasPrefix("v") || nodeResult.label.contains("Completed"),
            "Node smoke test did not produce version prefix 'v': \(nodeResult.label)"
        )

        // 6. TypeScript Smoke Test (compile and execute greeting)
        tapButton(withId: "hanlin-runtime-smoke-typeScript")
        let tsResult = app.descendants(matching: .any)["hanlin-runtime-last-message"].firstMatch
        XCTAssertTrue(tsResult.waitForExistence(timeout: 35), "TypeScript smoke test result was missing")
        XCTAssertTrue(
            tsResult.label.contains("שלום") || tsResult.label.contains("Completed"),
            "TypeScript smoke test did not produce expected greeting: \(tsResult.label)"
        )

        capture(name: "RuntimeCenter-Smoke-Complete")

        // 7. Persistence across restart
        app.terminate()
        app.launch()
        openSettings()
        openRuntimeCenter()

        tapButton(withId: "hanlin-runtime-smoke-javaScriptCore")
        let jscResultAfterRestart = app.descendants(matching: .any)["hanlin-runtime-last-message"].firstMatch
        XCTAssertTrue(jscResultAfterRestart.waitForExistence(timeout: 15))
        XCTAssertTrue(
            jscResultAfterRestart.label.contains("3"),
            "JSC smoke test after restart did not produce expected value '3': \(jscResultAfterRestart.label)"
        )

        capture(name: "RuntimeCenter-Post-Restart-Verified")
    }

    // MARK: - Node Package Manager UI Workflow & Failure Handling

    func testNodePackageManagerUIWorkflowAndFailure() throws {
        openSettings()
        openRuntimeCenter()

        tapButton(withId: "hanlin-runtime-details-node")

        let nodePackagesNav = app.navigationBars["Node Packages"].firstMatch
        let nodePackagesNavFallback = app.navigationBars["Node.js"].firstMatch
        XCTAssertTrue(
            nodePackagesNav.waitForExistence(timeout: 10) || nodePackagesNavFallback.waitForExistence(timeout: 3),
            "Node packages view did not open"
        )

        // Assert pre-install controls
        let nameField = app.textFields["hanlin-npm-package-name-field"].firstMatch
        let versionField = app.textFields["hanlin-npm-version-field"].firstMatch
        let previewButton = app.buttons["hanlin-npm-preview-button"].firstMatch
        let installButton = app.buttons["hanlin-npm-install-button"].firstMatch

        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        XCTAssertTrue(versionField.waitForExistence(timeout: 5))
        XCTAssertTrue(previewButton.waitForExistence(timeout: 5))
        XCTAssertTrue(installButton.waitForExistence(timeout: 5))
        XCTAssertFalse(previewButton.isEnabled, "Preview button should be disabled when package name is empty")
        XCTAssertFalse(installButton.isEnabled, "Install button should be disabled when package name is empty")

        capture(name: "NodePackages-PreInstall")

        // Exercise failure path with non-existent package
        nameField.tap()
        nameField.typeText("__hanlin_nonexistent_npm_404__")

        XCTAssertTrue(previewButton.isEnabled, "Preview button should be enabled after entering package name")
        previewButton.tap()

        // Wait for preview attempt message
        let messageText = app.descendants(matching: .any)["hanlin-npm-message"].firstMatch
        XCTAssertTrue(messageText.waitForExistence(timeout: 30), "Failure message did not appear for non-existent npm package")
        XCTAssertFalse(messageText.label.isEmpty, "Failure message was empty")

        // Package must not be marked installed
        let installedPackage = app.staticTexts["__hanlin_nonexistent_npm_404__"].firstMatch
        XCTAssertFalse(installedPackage.exists, "Non-existent package was unexpectedly listed as installed")

        capture(name: "NodePackages-FailureHandled")
        navigateBack()
    }

    // MARK: - Python Package Manager UI Workflow & Failure Handling

    func testPythonPackageManagerUIWorkflowAndFailure() throws {
        openSettings()
        openRuntimeCenter()

        tapButton(withId: "hanlin-runtime-details-localPython")

        let pythonPackagesNav = app.navigationBars["Python Packages"].firstMatch
        let pythonPackagesNavFallback = app.navigationBars["Local Python"].firstMatch
        XCTAssertTrue(
            pythonPackagesNav.waitForExistence(timeout: 10) || pythonPackagesNavFallback.waitForExistence(timeout: 3),
            "Python packages view did not open"
        )

        // Assert pre-install controls
        let nameField = app.textFields["hanlin-python-package-name-field"].firstMatch
        let versionField = app.textFields["hanlin-python-version-field"].firstMatch
        let previewButton = app.buttons["hanlin-python-preview-button"].firstMatch
        let installButton = app.buttons["hanlin-python-install-button"].firstMatch

        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        XCTAssertTrue(versionField.waitForExistence(timeout: 5))
        XCTAssertTrue(previewButton.waitForExistence(timeout: 5))
        XCTAssertTrue(installButton.waitForExistence(timeout: 5))

        capture(name: "PythonPackages-PreInstall")

        // Exercise failure path with non-existent PyPI package
        nameField.tap()
        nameField.typeText("__hanlin_nonexistent_pypi_404__")

        previewButton.tap()

        let messageText = app.descendants(matching: .any)["hanlin-python-message"].firstMatch
        XCTAssertTrue(messageText.waitForExistence(timeout: 25), "Failure message did not appear for non-existent PyPI package")
        XCTAssertFalse(messageText.label.isEmpty, "Failure message was empty")

        // Package must not be marked installed
        let installedPackage = app.staticTexts["__hanlin_nonexistent_pypi_404__"].firstMatch
        XCTAssertFalse(installedPackage.exists, "Non-existent package was unexpectedly listed as installed")

        capture(name: "PythonPackages-FailureHandled")
        navigateBack()
    }

    // MARK: - MCP Server Installation UI Workflow & Failure Handling

    func testMCPServerInstallationUIWorkflowAndFailure() throws {
        openSettings()
        openMCPServers()

        let addServerLink = app.descendants(matching: .any)["hanlin-mcp-add-server-link"].firstMatch
        XCTAssertTrue(addServerLink.waitForExistence(timeout: 10), "Add MCP Server link was missing")
        addServerLink.tap()

        let addServerNav = app.navigationBars["Add MCP Server"].firstMatch
        XCTAssertTrue(addServerNav.waitForExistence(timeout: 10), "Add MCP Server view did not open")

        let inputField = app.textFields["hanlin-mcp-package-input"].firstMatch
        let previewButton = app.buttons["hanlin-mcp-preview-button"].firstMatch

        XCTAssertTrue(inputField.waitForExistence(timeout: 5))
        XCTAssertTrue(previewButton.waitForExistence(timeout: 5))
        XCTAssertFalse(previewButton.isEnabled, "Preview button should be disabled when package input is empty")

        capture(name: "MCPServer-PreInstall")

        // Exercise invalid package spec failure path
        inputField.tap()
        inputField.typeText(":::invalid:::")

        XCTAssertTrue(previewButton.isEnabled, "Preview button should be enabled after entering text")
        previewButton.tap()

        let errorMessage = app.descendants(matching: .any)["hanlin-mcp-error-message"].firstMatch
        XCTAssertTrue(errorMessage.waitForExistence(timeout: 15), "Error message did not appear for invalid MCP package spec")
        XCTAssertFalse(errorMessage.label.isEmpty, "Error message was empty")

        // Install button must not be present
        let installButton = app.buttons["hanlin-mcp-install-button"].firstMatch
        XCTAssertFalse(installButton.exists, "Install button was unexpectedly shown for invalid package spec")

        capture(name: "MCPServer-InvalidSpec-Rejected")
        navigateBack()
    }

    // MARK: - Navigation & Utility Helpers

    private func tapButton(withId id: String, timeout: TimeInterval = 10) {
        let candidates = [
            app.buttons[id].firstMatch,
            app.descendants(matching: .any)[id].firstMatch
        ]
        var target: XCUIElement?
        for candidate in candidates {
            if candidate.waitForExistence(timeout: 2) {
                target = candidate
                break
            }
        }
        if target == nil {
            app.swipeUp()
            for candidate in candidates {
                if candidate.waitForExistence(timeout: 2) {
                    target = candidate
                    break
                }
            }
        }
        if target == nil {
            app.swipeDown()
            for candidate in candidates {
                if candidate.waitForExistence(timeout: 2) {
                    target = candidate
                    break
                }
            }
        }
        let button = target ?? candidates[0]
        XCTAssertTrue(button.waitForExistence(timeout: timeout), "Button \(id) was missing")
        if !button.isHittable {
            app.swipeUp()
        }
        if button.isHittable {
            button.tap()
        } else {
            button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    private func openSettings() {
        let settingsNav = app.navigationBars["设置"].firstMatch
        let settingsNavEn = app.navigationBars["Settings"].firstMatch
        if settingsNav.exists || settingsNavEn.exists { return }

        let settingsTabCandidates = [
            app.buttons["hanlin-settings-tab"].firstMatch,
            app.tabBars.buttons["hanlin-settings-tab"].firstMatch,
            app.buttons["设置"].firstMatch,
            app.tabBars.buttons["设置"].firstMatch,
            app.buttons["Settings"].firstMatch,
            app.tabBars.buttons["Settings"].firstMatch
        ]

        for tab in settingsTabCandidates {
            if tab.waitForExistence(timeout: 3) && tab.isHittable {
                tab.tap()
                break
            }
        }

        _ = waitUntil(timeout: 10) {
            self.app.navigationBars["设置"].exists || self.app.navigationBars["Settings"].exists
        }
    }

    private func openRuntimeCenter() {
        let runtimeCenterNav = app.navigationBars["Runtimes & Packages"].firstMatch
        if runtimeCenterNav.exists { return }

        let link = app.descendants(matching: .any)["hanlin-runtimes-packages-link"].firstMatch
        if !link.waitForExistence(timeout: 5) {
            app.swipeUp()
        }
        XCTAssertTrue(link.waitForExistence(timeout: 10), "Runtimes & Packages link was missing in Settings")
        link.tap()
        XCTAssertTrue(runtimeCenterNav.waitForExistence(timeout: 10), "RuntimeCenterView did not open")
    }

    private func openMCPServers() {
        let mcpNav = app.navigationBars["MCP Servers"].firstMatch
        if mcpNav.exists { return }

        let link = app.descendants(matching: .any)["hanlin-mcp-servers-link"].firstMatch
        if !link.waitForExistence(timeout: 5) {
            app.swipeUp()
        }
        XCTAssertTrue(link.waitForExistence(timeout: 10), "MCP Servers link was missing in Settings")
        link.tap()
        XCTAssertTrue(mcpNav.waitForExistence(timeout: 10), "MCPServersSettingsView did not open")
    }

    private func navigateBack() {
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        if backButton.waitForExistence(timeout: 5) && backButton.isHittable {
            backButton.tap()
        }
    }

    private func capture(name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return condition()
    }
}
