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
        let skillCenterLink = app.descendants(matching: .any)["hanlin-skill-center-link"].firstMatch
        if !skillCenterLink.waitForExistence(timeout: 5) {
            app.swipeUp()
        }
        XCTAssertTrue(skillCenterLink.waitForExistence(timeout: 10), "Skill Center link not found in Settings")
        if skillCenterLink.isHittable {
            skillCenterLink.tap()
        } else {
            skillCenterLink.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }

        // 3. Verify Skill Center view loaded
        let navBar = app.navigationBars.matching(NSPredicate(format: "identifier == 'Skill Center' OR identifier == '技能中心' OR title == 'Skill Center' OR title == '技能中心'")).firstMatch
        let filterPicker = app.segmentedControls["hanlin-skill-center-filter-picker"].firstMatch
        XCTAssertTrue(navBar.waitForExistence(timeout: 10) || filterPicker.waitForExistence(timeout: 10), "Skill Center navigation bar or filter picker not found")

        // 4. Test filter picker segments
        if filterPicker.waitForExistence(timeout: 5) {
            let systemButton = filterPicker.buttons.matching(NSPredicate(format: "label CONTAINS 'System' OR label CONTAINS '系统'")).firstMatch
            if systemButton.exists { systemButton.tap() }

            let allButton = filterPicker.buttons.matching(NSPredicate(format: "label CONTAINS 'All' OR label CONTAINS '全部'")).firstMatch
            if allButton.exists { allButton.tap() }
        }

        // 5. Verify toolbar buttons exist
        let importButton = app.buttons["hanlin-skill-center-import-button"].firstMatch
        let createButton = app.buttons["hanlin-skill-center-create-button"].firstMatch
        XCTAssertTrue(importButton.exists, "Import button not found in toolbar")
        XCTAssertTrue(createButton.exists, "Create button not found in toolbar")

        // 6. Tap code skill row to open SkillDetailView
        let codeRow = app.descendants(matching: .any)["hanlin-skill-center-skill-row-code"].firstMatch
        if !codeRow.waitForExistence(timeout: 5) {
            app.swipeUp()
        }
        if codeRow.waitForExistence(timeout: 5) {
            if codeRow.isHittable {
                codeRow.tap()
            } else {
                codeRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }

            // Verify Skill Detail elements
            let enableToggle = app.descendants(matching: .any)["hanlin-skill-detail-enable-toggle"].firstMatch
            XCTAssertTrue(enableToggle.waitForExistence(timeout: 10), "Enable toggle not found in SkillDetailView")

            // Go back to Skill Center
            let backButton = app.navigationBars.buttons.firstMatch
            if backButton.exists && backButton.isHittable {
                backButton.tap()
            }
        }
    }

    private func selectSettingsTab() -> Bool {
        let identifier = "hanlin-settings-tab"
        let labels = ["Settings", "设置"]
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
        if fallback.waitForExistence(timeout: 5) {
            if fallback.isHittable {
                fallback.tap()
                return true
            } else {
                fallback.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                return true
            }
        }
        return false
    }
}
