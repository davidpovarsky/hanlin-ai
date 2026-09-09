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

    func testWholeAppPrimaryNavigationSmoke() throws {
        // 1. Root: Home / Chat List (Tab 0)
        let homeTab = app.tabBars.buttons["hanlin-home-tab"].firstMatch
        if homeTab.waitForExistence(timeout: 10) {
            homeTab.tap()
        }
        let homeRoot = app.navigationBars["Hylic.AI"].firstMatch
        XCTAssertTrue(homeRoot.waitForExistence(timeout: 15), "Primary navigation to Home/ChatList failed: root navigation bar 'Hylic.AI' was absent")

        // 2. Knowledge Base / Backpack (Tab 2)
        let knowledgeTab = app.tabBars.buttons["hanlin-knowledge-tab"].firstMatch
        XCTAssertTrue(knowledgeTab.waitForExistence(timeout: 10), "Knowledge tab button 'hanlin-knowledge-tab' was absent")
        knowledgeTab.tap()

        let knowledgePredicate = NSPredicate(format: "label CONTAINS 'Knowledge' OR label CONTAINS '知识'")
        let knowledgeRoot = app.navigationBars.matching(knowledgePredicate).firstMatch
        XCTAssertTrue(knowledgeRoot.waitForExistence(timeout: 15), "Primary navigation to Knowledge failed: root navigation bar was absent")

        // 3. Models / Agents (Tab 3)
        let modelsTab = app.tabBars.buttons["hanlin-models-tab"].firstMatch
        XCTAssertTrue(modelsTab.waitForExistence(timeout: 10), "Models tab button 'hanlin-models-tab' was absent")
        modelsTab.tap()

        let modelsPredicate = NSPredicate(format: "label CONTAINS 'Models' OR label CONTAINS '模型' OR label CONTAINS '智能体'")
        let modelsRoot = app.navigationBars.matching(modelsPredicate).firstMatch
        XCTAssertTrue(modelsRoot.waitForExistence(timeout: 15), "Primary navigation to Models failed: root navigation bar was absent")

        // 4. Apps Hub (Tab 4)
        let appsTab = app.tabBars.buttons["hanlin-apps-tab"].firstMatch
        XCTAssertTrue(appsTab.waitForExistence(timeout: 10), "Apps tab button 'hanlin-apps-tab' was absent")
        appsTab.tap()

        let appsRoot = app.navigationBars["Apps"].firstMatch
        let addAppButton = app.buttons["hanlin-apps-add"].firstMatch
        XCTAssertTrue(appsRoot.waitForExistence(timeout: 15) || addAppButton.waitForExistence(timeout: 15), "Primary navigation to Apps failed: Apps root was absent")

        // 5. Settings (Tab 5)
        let settingsTab = app.tabBars.buttons["hanlin-settings-tab"].firstMatch
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 10), "Settings tab button 'hanlin-settings-tab' was absent")
        settingsTab.tap()

        let settingsPredicate = NSPredicate(format: "label CONTAINS 'Settings' OR label CONTAINS '设置'")
        let settingsRoot = app.navigationBars.matching(settingsPredicate).firstMatch
        XCTAssertTrue(settingsRoot.waitForExistence(timeout: 15), "Primary navigation to Settings failed: Settings root was absent")

        // 6. Return to Apps Hub (proving full navigation cycle)
        let returnAppsTab = app.tabBars.buttons["hanlin-apps-tab"].firstMatch
        XCTAssertTrue(returnAppsTab.waitForExistence(timeout: 10))
        returnAppsTab.tap()

        XCTAssertTrue(appsRoot.waitForExistence(timeout: 15) || addAppButton.waitForExistence(timeout: 15), "Return navigation to Apps failed")
    }
}
