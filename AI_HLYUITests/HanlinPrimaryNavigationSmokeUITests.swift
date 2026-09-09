import XCTest

@MainActor
final class HanlinPrimaryNavigationSmokeUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launch()
    }

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

        // 1. Try directly on current tab page
        for candidate in candidates {
            if candidate.waitForExistence(timeout: 2) && candidate.isHittable {
                candidate.tap()
                return true
            }
        }

        // 2. If tab bar is paged (e.g. iPad mini floating tab bar with Next Page / Previous Page)
        let nextPage = app.buttons["Next Page"].firstMatch
        if nextPage.waitForExistence(timeout: 2) && nextPage.isHittable {
            nextPage.tap()
            for candidate in candidates {
                if candidate.waitForExistence(timeout: 3) && candidate.isHittable {
                    candidate.tap()
                    return true
                }
            }
        }

        let prevPage = app.buttons["Previous Page"].firstMatch
        if prevPage.waitForExistence(timeout: 2) && prevPage.isHittable {
            prevPage.tap()
            for candidate in candidates {
                if candidate.waitForExistence(timeout: 3) && candidate.isHittable {
                    candidate.tap()
                    return true
                }
            }
        }

        // 3. Fallback to broad hierarchy predicate
        let labelClauses = labels.map { "label CONTAINS '\($0)'" }
        let format = (["identifier == '\(identifier)'"] + labelClauses).joined(separator: " OR ")
        let fallback = app.descendants(matching: .any).matching(NSPredicate(format: format)).firstMatch
        if fallback.waitForExistence(timeout: 5) && fallback.isHittable {
            fallback.tap()
            return true
        }
        return false
    }

    func testWholeAppPrimaryNavigationSmoke() throws {
        // 1. Root: Home / Chat List (Tab 0)
        XCTAssertTrue(selectTab(identifier: "hanlin-home-tab", labels: ["列表", "List", "Chats"]), "Home tab button was absent")
        let homeRootPredicate = NSPredicate(format: "label CONTAINS 'Hylic.AI' OR identifier CONTAINS 'Hylic.AI' OR title CONTAINS 'Hylic.AI'")
        let homeRoot = app.descendants(matching: .any).matching(homeRootPredicate).firstMatch
        XCTAssertTrue(homeRoot.waitForExistence(timeout: 15), "Primary navigation to Home/ChatList failed: root 'Hylic.AI' was absent")

        // 2. Vision View (Tab 1)
        XCTAssertTrue(selectTab(identifier: "hanlin-vision-tab", labels: ["视觉", "Vision"]), "Vision tab button was absent")
        let alert = app.alerts.firstMatch
        let visionReturnPredicate = NSPredicate(format: "label CONTAINS 'chevron.down.circle.fill' OR identifier CONTAINS 'chevron.down.circle.fill'")
        let visionReturnButton = app.descendants(matching: .any).matching(visionReturnPredicate).firstMatch

        if alert.waitForExistence(timeout: 5) {
            let dismissAlert = alert.buttons.firstMatch
            if dismissAlert.exists {
                dismissAlert.tap()
            }
        } else if visionReturnButton.waitForExistence(timeout: 10) {
            visionReturnButton.tap()
        }
        XCTAssertTrue(homeRoot.waitForExistence(timeout: 15), "Return navigation from Vision to Home failed")

        // 3. Knowledge Base / Backpack (Tab 2)
        XCTAssertTrue(selectTab(identifier: "hanlin-knowledge-tab", labels: ["知识库", "Knowledge"]), "Knowledge tab button was absent")
        let knowledgePredicate = NSPredicate(format: "label CONTAINS 'Knowledge' OR label CONTAINS '知识'")
        let knowledgeRoot = app.descendants(matching: .any).matching(knowledgePredicate).firstMatch
        XCTAssertTrue(knowledgeRoot.waitForExistence(timeout: 15), "Primary navigation to Knowledge failed: root was absent")

        // 4. Models / Agents (Tab 3)
        XCTAssertTrue(selectTab(identifier: "hanlin-models-tab", labels: ["模型", "Models", "智能体"]), "Models tab button was absent")
        let modelsPredicate = NSPredicate(format: "label CONTAINS 'Models' OR label CONTAINS '模型' OR label CONTAINS '智能体'")
        let modelsRoot = app.descendants(matching: .any).matching(modelsPredicate).firstMatch
        XCTAssertTrue(modelsRoot.waitForExistence(timeout: 15), "Primary navigation to Models failed: root was absent")

        // 5. Apps Hub (Tab 4)
        XCTAssertTrue(selectTab(identifier: "hanlin-apps-tab", labels: ["Apps"]), "Apps tab button was absent")
        let appsRoot = app.navigationBars["Apps"].firstMatch
        let addAppButton = app.buttons["hanlin-apps-add"].firstMatch
        XCTAssertTrue(appsRoot.waitForExistence(timeout: 15) || addAppButton.waitForExistence(timeout: 15), "Primary navigation to Apps failed: Apps root was absent")

        // 6. Settings (Tab 5)
        XCTAssertTrue(selectTab(identifier: "hanlin-settings-tab", labels: ["设置", "Settings"]), "Settings tab button was absent")
        let settingsPredicate = NSPredicate(format: "label CONTAINS 'Settings' OR label CONTAINS '设置'")
        let settingsRoot = app.descendants(matching: .any).matching(settingsPredicate).firstMatch
        XCTAssertTrue(settingsRoot.waitForExistence(timeout: 15), "Primary navigation to Settings failed: Settings root was absent")

        // 7. Return to Apps Hub (proving full navigation cycle)
        XCTAssertTrue(selectTab(identifier: "hanlin-apps-tab", labels: ["Apps"]), "Return to Apps tab button was absent")
        XCTAssertTrue(appsRoot.waitForExistence(timeout: 15) || addAppButton.waitForExistence(timeout: 15), "Return navigation to Apps failed")
    }
}
