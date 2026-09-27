import XCTest

@MainActor
final class HanlinSkillCenterUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launch()
    }

    func testSkillCenterNavigationAndInteraction() throws {
        // 1. Navigate to Settings
        XCTAssertTrue(selectSettingsTab(), "Failed to navigate to Settings tab")

        // 2. Open Skill Center under Tools
        let skillCenterLink = app.buttons["hanlin-skill-center-link"].firstMatch
        if !skillCenterLink.waitForExistence(timeout: 5) {
            app.swipeUp()
        }
        XCTAssertTrue(skillCenterLink.waitForExistence(timeout: 10), "Skill Center link not found in Settings")
        skillCenterLink.tap()

        // 3. Verify Skill Center view loaded
        let navBar = app.navigationBars["Skill Center"].firstMatch
        XCTAssertTrue(navBar.waitForExistence(timeout: 10), "Skill Center navigation bar not found")

        // 4. Test filter picker segments
        let filterPicker = app.segmentedControls["hanlin-skill-center-filter-picker"].firstMatch
        if filterPicker.waitForExistence(timeout: 5) {
            let systemButton = filterPicker.buttons["System"].firstMatch
            if systemButton.exists { systemButton.tap() }

            let allButton = filterPicker.buttons["All"].firstMatch
            if allButton.exists { allButton.tap() }
        }

        // 5. Verify toolbar buttons exist
        let importButton = app.buttons["hanlin-skill-center-import-button"].firstMatch
        let createButton = app.buttons["hanlin-skill-center-create-button"].firstMatch
        XCTAssertTrue(importButton.exists, "Import button not found in toolbar")
        XCTAssertTrue(createButton.exists, "Create button not found in toolbar")

        // 6. Tap code skill row to open SkillDetailView
        let codeRow = app.buttons["hanlin-skill-center-skill-row-code"].firstMatch
        if !codeRow.waitForExistence(timeout: 5) {
            app.swipeUp()
        }
        if codeRow.waitForExistence(timeout: 5) {
            codeRow.tap()

            // Verify Skill Detail elements
            let enableToggle = app.switches["hanlin-skill-detail-enable-toggle"].firstMatch
            XCTAssertTrue(enableToggle.waitForExistence(timeout: 10), "Enable toggle not found in SkillDetailView")

            // Go back to Skill Center
            let backButton = app.navigationBars.buttons.firstMatch
            if backButton.exists {
                backButton.tap()
            }
        }
    }

    private func selectSettingsTab() -> Bool {
        var candidates: [XCUIElement] = [
            app.tabBars.buttons["hanlin-settings-tab"].firstMatch,
            app.buttons["hanlin-settings-tab"].firstMatch,
            app.tabs["hanlin-settings-tab"].firstMatch,
            app.tabBars.buttons["Settings"].firstMatch,
            app.buttons["Settings"].firstMatch
        ]
        for candidate in candidates {
            if candidate.waitForExistence(timeout: 2) && candidate.isHittable {
                candidate.tap()
                return true
            }
        }
        let fallback = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'hanlin-settings-tab' OR label CONTAINS 'Settings' OR label CONTAINS '设置'")).firstMatch
        if fallback.waitForExistence(timeout: 5) && fallback.isHittable {
            fallback.tap()
            return true
        }
        return false
    }
}
