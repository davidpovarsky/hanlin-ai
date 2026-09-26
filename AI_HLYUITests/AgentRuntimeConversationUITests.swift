import XCTest

@MainActor
final class AgentRuntimeConversationUITests: XCTestCase {
    func testRealChatUISendsPromptShowsToolActivityAndFinalAnswer() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE"] = "1"
        app.launch()

        // 1. Initial State: Python runtime is OFF + Assistant Python permission is ON
        openRuntimeCenter(in: app)
        let initialPythonToggle = toggleSwitch(for: "localPython", in: app)
        if !initialPythonToggle.waitForExistence(timeout: 5) { app.swipeUp() }
        XCTAssertTrue(initialPythonToggle.waitForExistence(timeout: 10), "Python toggle card was missing in Runtime Center")
        XCTAssertFalse(isToggleOn(initialPythonToggle), "Python toggle should initially be OFF on fresh process")

        let toolPerm = app.switches["hanlin-tool-permission-execute_local_python_code"].firstMatch
        if !toolPerm.exists { app.swipeUp() }
        if toolPerm.exists {
            XCTAssertTrue(isToggleOn(toolPerm), "Assistant Python permission should be ON")
        }

        // 2. Switch to Chat and prompt the Agent to execute Python
        openChat(in: app)

        let input = app.textFields["hanlin-chat-input"].firstMatch
        if !input.waitForExistence(timeout: 5) {
            let chatPredicate = NSPredicate(format: "label CONTAINS 'Agent Acceptance Chat' OR identifier CONTAINS 'Agent Acceptance Chat'")
            let seededChat = app.descendants(matching: .any).matching(chatPredicate).firstMatch
            XCTAssertTrue(seededChat.waitForExistence(timeout: 15), "The deterministic acceptance chat was not listed.")
            seededChat.tap()
        }
        XCTAssertTrue(input.waitForExistence(timeout: 20), "The real chat input did not appear.")
        input.tap()
        input.typeText("Run the local Python acceptance tool and report the result.")

        let send = app.buttons["hanlin-chat-send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 10), "The real chat send button did not appear.")
        send.tap()

        let finalAnswer = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'AGENT_UI_ACCEPTANCE_COMPLETE'")
        ).firstMatch
        XCTAssertTrue(finalAnswer.waitForExistence(timeout: 45), "The deterministic provider's final answer was not rendered.")

        let activitySummary = app.buttons["hanlin-agent-activity-summary"].firstMatch
        XCTAssertTrue(activitySummary.waitForExistence(timeout: 10), "The completed agent activity summary was not rendered.")
        activitySummary.tap()

        let failedActivity = app.buttons["hanlin-agent-tool-failed"].firstMatch
        XCTAssertTrue(failedActivity.waitForExistence(timeout: 10), "The intentional tool failure was not presented truthfully in the real chat UI.")
        XCTAssertTrue(
            failedActivity.label.localizedCaseInsensitiveContains("invalid"),
            "The failed activity did not identify the invalid arguments."
        )

        let toolActivity = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Local Python' OR label CONTAINS[c] 'ui-tool-ok'")
        ).firstMatch
        XCTAssertTrue(toolActivity.waitForExistence(timeout: 45), "Tool activity/result was not rendered in the real chat UI.")

        // 3. Verify Runtime Center reactively shows Python ON after agent execution
        openRuntimeCenter(in: app)
        let postPythonToggle = toggleSwitch(for: "localPython", in: app)
        if !postPythonToggle.waitForExistence(timeout: 5) { app.swipeUp() }
        XCTAssertTrue(
            waitForToggle(postPythonToggle, toBe: true, timeout: 20),
            "Python runtime should auto-start on agent execution and Runtime Center must show Python ON"
        )
    }

    // MARK: - Navigation & Toggle Helpers

    private func selectTab(identifier: String, labels: [String] = [], in app: XCUIApplication) -> Bool {
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

        func findCandidate() -> Bool {
            for candidate in candidates {
                if candidate.waitForExistence(timeout: 2) && candidate.isHittable {
                    candidate.tap()
                    return true
                }
            }
            return false
        }

        // 1. Try directly on current tab page
        if findCandidate() { return true }

        // 2. Try Previous Page (e.g. if we are on later tab page like Settings and want Home)
        let prevPage = app.buttons["Previous Page"].firstMatch
        if prevPage.waitForExistence(timeout: 2) && prevPage.isHittable {
            prevPage.tap()
            if findCandidate() { return true }
        }

        // 3. Try Next Page (e.g. if target tab is on subsequent page)
        let nextPage = app.buttons["Next Page"].firstMatch
        if nextPage.waitForExistence(timeout: 2) && nextPage.isHittable {
            nextPage.tap()
            if findCandidate() { return true }
        }

        // 4. Fallback to broad hierarchy predicate
        let labelClauses = labels.map { "label CONTAINS '\($0)'" }
        let format = (["identifier == '\(identifier)'"] + labelClauses).joined(separator: " OR ")
        let fallback = app.descendants(matching: .any).matching(NSPredicate(format: format)).firstMatch
        if fallback.waitForExistence(timeout: 3) && fallback.isHittable {
            fallback.tap()
            return true
        }

        return false
    }

    private func openSettings(in app: XCUIApplication) {
        let settingsNav = app.navigationBars["设置"].firstMatch
        let settingsNavEn = app.navigationBars["Settings"].firstMatch
        if settingsNav.exists || settingsNavEn.exists { return }
        _ = selectTab(identifier: "hanlin-settings-tab", labels: ["Settings", "设置"], in: app)
        _ = settingsNavEn.waitForExistence(timeout: 5) || settingsNav.waitForExistence(timeout: 5)
    }

    private func openRuntimeCenter(in app: XCUIApplication) {
        openSettings(in: app)
        let runtimeCenterNav = app.navigationBars["Runtimes & Packages"].firstMatch
        if runtimeCenterNav.waitForExistence(timeout: 3) { return }
        let link = app.descendants(matching: .any)["hanlin-runtimes-packages-link"].firstMatch
        if !link.waitForExistence(timeout: 5) {
            app.swipeUp()
        }
        if link.waitForExistence(timeout: 10) {
            if link.isHittable {
                link.tap()
            } else {
                app.swipeUp()
                link.tap()
            }
        }
        _ = runtimeCenterNav.waitForExistence(timeout: 10)
    }

    private func openChat(in app: XCUIApplication) {
        _ = selectTab(identifier: "hanlin-home-tab", labels: ["Chats", "Messages", "Home", "列表"], in: app)
    }

    private func toggleSwitch(for kindRaw: String, in app: XCUIApplication) -> XCUIElement {
        let sw = app.switches["hanlin-runtime-availability-\(kindRaw)"].firstMatch
        if sw.exists { return sw }
        return app.descendants(matching: .switch)["hanlin-runtime-availability-\(kindRaw)"].firstMatch
    }

    private func isToggleOn(_ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        if let valStr = element.value as? String {
            return valStr == "1" || valStr.lowercased() == "on" || valStr.lowercased() == "true"
        }
        if let valInt = element.value as? Int {
            return valInt == 1
        }
        return false
    }

    private func waitForToggle(_ element: XCUIElement, toBe targetState: Bool, timeout: TimeInterval = 15) -> Bool {
        let predicate = NSPredicate { _, _ in
            self.isToggleOn(element) == targetState
        }
        let exp = expectation(for: predicate, evaluatedWith: element)
        let result = XCTWaiter.wait(for: [exp], timeout: timeout)
        return result == .completed
    }
}
