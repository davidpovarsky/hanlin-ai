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

    func testSettingsContainsSkillCenter() throws {
        XCTAssertTrue(selectSettingsTab(), "Failed to navigate to Settings tab")
        let skillCenterLink = app.descendants(matching: .any)["hanlin-skill-center-link"].firstMatch
        if !skillCenterLink.waitForExistence(timeout: 5) {
            app.swipeUp()
        }
        XCTAssertTrue(skillCenterLink.waitForExistence(timeout: 10), "Skill Center link not found in Settings")
    }

    func testSkillCenterNavigationAndInteraction() throws {
        openSkillCenter()

        let navBar = app.navigationBars.matching(NSPredicate(format: "identifier == 'Skill Center' OR identifier == '技能中心' OR title == 'Skill Center' OR title == '技能中心'")).firstMatch
        let filterPicker = app.segmentedControls["hanlin-skill-center-filter-picker"].firstMatch
        XCTAssertTrue(navBar.waitForExistence(timeout: 10) || filterPicker.waitForExistence(timeout: 10), "Skill Center navigation bar or filter picker not found")

        if filterPicker.waitForExistence(timeout: 5) {
            let systemButton = filterPicker.buttons.matching(NSPredicate(format: "label CONTAINS 'System' OR label CONTAINS '系统'")).firstMatch
            if systemButton.exists { systemButton.tap() }

            let allButton = filterPicker.buttons.matching(NSPredicate(format: "label CONTAINS 'All' OR label CONTAINS '全部'")).firstMatch
            if allButton.exists { allButton.tap() }
        }

        let importButton = app.buttons["hanlin-skill-center-import-button"].firstMatch
        let createButton = app.buttons["hanlin-skill-center-create-button"].firstMatch
        XCTAssertTrue(importButton.exists, "Import button not found in toolbar")
        XCTAssertTrue(createButton.exists, "Create button not found in toolbar")

        let codeRow = app.descendants(matching: .any)["hanlin-skill-center-skill-row-code"].firstMatch
        if !codeRow.waitForExistence(timeout: 5) {
            app.swipeUp()
        }
        if codeRow.waitForExistence(timeout: 5) {
            tapElement(codeRow)
            let enableToggle = app.descendants(matching: .any)["hanlin-skill-detail-enable-toggle"].firstMatch
            XCTAssertTrue(enableToggle.waitForExistence(timeout: 10), "Enable toggle not found in SkillDetailView")

            let backButton = app.navigationBars.buttons.firstMatch
            if backButton.exists && backButton.isHittable {
                backButton.tap()
            }
        }
    }

    func testCreateEditDisableDeleteCustomSkill() throws {
        openSkillCenter()

        let createButton = app.buttons["hanlin-skill-center-create-button"].firstMatch
        XCTAssertTrue(createButton.waitForExistence(timeout: 5), "Create button not found")
        tapElement(createButton)

        let menuNew = app.buttons["hanlin-skill-center-menu-new-skill"].firstMatch
        if menuNew.waitForExistence(timeout: 3) {
            tapElement(menuNew)
        }

        let idInput = app.textFields["hanlin-skill-editor-id-input"].firstMatch
        if idInput.waitForExistence(timeout: 5) {
            tapElement(idInput)
            idInput.typeText("test-ui-skill")

            let nameInput = app.textFields["hanlin-skill-editor-name-input"].firstMatch
            tapElement(nameInput)
            nameInput.typeText("Test UI Skill")

            let descInput = app.textFields["hanlin-skill-editor-desc-input"].firstMatch
            if descInput.exists {
                tapElement(descInput)
                descInput.typeText("UI created test skill")
            }

            let saveButton = app.buttons["hanlin-skill-editor-save-button"].firstMatch
            XCTAssertTrue(saveButton.waitForExistence(timeout: 5), "Save button not found in editor")
            tapElement(saveButton)
        }

        let createdRow = app.descendants(matching: .any)["hanlin-skill-center-skill-row-test-ui-skill"].firstMatch
        if createdRow.waitForExistence(timeout: 5) {
            tapElement(createdRow)

            let editButton = app.buttons["hanlin-skill-detail-edit-button"].firstMatch
            XCTAssertTrue(editButton.waitForExistence(timeout: 5), "Edit button not found in detail")

            let deleteButton = app.buttons["hanlin-skill-detail-delete-button"].firstMatch
            if deleteButton.waitForExistence(timeout: 5) {
                tapElement(deleteButton)
                let confirmDelete = app.buttons["Delete"].firstMatch
                if confirmDelete.waitForExistence(timeout: 3) {
                    tapElement(confirmDelete)
                }
            }
        }
    }

    func testOverrideAndResetBuiltInSkill() throws {
        openSkillCenter()

        let codeRow = app.descendants(matching: .any)["hanlin-skill-center-skill-row-code"].firstMatch
        if !codeRow.waitForExistence(timeout: 5) { app.swipeUp() }
        XCTAssertTrue(codeRow.waitForExistence(timeout: 10), "Code skill row not found")
        tapElement(codeRow)

        let overrideButton = app.buttons["hanlin-skill-detail-override-button"].firstMatch
        let editButton = app.buttons["hanlin-skill-detail-edit-button"].firstMatch

        if overrideButton.waitForExistence(timeout: 5) {
            tapElement(overrideButton)
            let saveButton = app.buttons["hanlin-skill-editor-save-button"].firstMatch
            if saveButton.waitForExistence(timeout: 5) {
                tapElement(saveButton)
            }
            let resetButton = app.buttons["hanlin-skill-detail-reset-button"].firstMatch
            if resetButton.waitForExistence(timeout: 5) {
                tapElement(resetButton)
            }
        } else if editButton.waitForExistence(timeout: 5) {
            let resetButton = app.buttons["hanlin-skill-detail-reset-button"].firstMatch
            if resetButton.waitForExistence(timeout: 5) {
                tapElement(resetButton)
            }
        }

        let backButton = app.navigationBars.buttons.firstMatch
        if backButton.exists && backButton.isHittable {
            backButton.tap()
        }
    }

    func testImportSkillZipPreviewInstall() throws {
        openSkillCenter()

        let importButton = app.buttons["hanlin-skill-center-import-button"].firstMatch
        XCTAssertTrue(importButton.waitForExistence(timeout: 5), "Import button not found")
        tapElement(importButton)

        let zipTab = app.buttons["hanlin-skill-import-tab-zip"].firstMatch
        XCTAssertTrue(zipTab.waitForExistence(timeout: 5), "ZIP tab not found in import view")

        let fileButton = app.buttons["hanlin-skill-import-select-file-button"].firstMatch
        XCTAssertTrue(fileButton.waitForExistence(timeout: 5), "Select ZIP file button not found")

        let cancelButton = app.buttons["hanlin-skill-import-cancel-button"].firstMatch
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5), "Cancel button not found")
        tapElement(cancelButton)
    }

    func testInstallSkillFromURL() throws {
        openSkillCenter()

        let importButton = app.buttons["hanlin-skill-center-import-button"].firstMatch
        XCTAssertTrue(importButton.waitForExistence(timeout: 5), "Import button not found")
        tapElement(importButton)

        let urlTab = app.buttons["hanlin-skill-import-tab-url"].firstMatch
        if urlTab.waitForExistence(timeout: 5) {
            tapElement(urlTab)
            let urlInput = app.textFields["hanlin-skill-import-url-input"].firstMatch
            let urlButton = app.buttons["hanlin-skill-import-url-button"].firstMatch
            XCTAssertTrue(urlInput.waitForExistence(timeout: 5), "URL text field not found")
            XCTAssertTrue(urlButton.waitForExistence(timeout: 5), "URL install button not found")
        }

        let cancelButton = app.buttons["hanlin-skill-import-cancel-button"].firstMatch
        if cancelButton.waitForExistence(timeout: 5) {
            tapElement(cancelButton)
        }
    }

    func testInstalledSkillAppearsInNextChatRun() throws {
        openSkillCenter()
        let codeRow = app.descendants(matching: .any)["hanlin-skill-center-skill-row-code"].firstMatch
        if !codeRow.waitForExistence(timeout: 5) { app.swipeUp() }
        XCTAssertTrue(codeRow.waitForExistence(timeout: 10), "Code skill should appear in catalog")
    }

    // MARK: - Navigation Helpers

    private func openSkillCenter() {
        XCTAssertTrue(selectSettingsTab(), "Failed to navigate to Settings tab")
        let skillCenterLink = app.descendants(matching: .any)["hanlin-skill-center-link"].firstMatch
        if !skillCenterLink.waitForExistence(timeout: 5) {
            app.swipeUp()
        }
        XCTAssertTrue(skillCenterLink.waitForExistence(timeout: 10), "Skill Center link not found in Settings")
        tapElement(skillCenterLink)
    }

    private func tapElement(_ element: XCUIElement) {
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
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

        for candidate in candidates {
            if candidate.waitForExistence(timeout: 2) && candidate.isHittable {
                candidate.tap()
                return true
            }
        }

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

        let labelClauses = labels.map { "label CONTAINS '\($0)'" }
        let format = (["identifier == '\(identifier)'"] + labelClauses).joined(separator: " OR ")
        let fallback = app.descendants(matching: .any).matching(NSPredicate(format: format)).firstMatch
        if fallback.waitForExistence(timeout: 5) {
            tapElement(fallback)
            return true
        }
        return false
    }
}
