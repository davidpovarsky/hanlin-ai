import XCTest

@MainActor
final class HanlinSkillCenterUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_AGENT_SKILLS_EMBEDDED_ACCEPTANCE"] = "1"
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
            let enableToggle = skillDetailToggle()
            XCTAssertTrue(enableToggle.waitForExistence(timeout: 10), "Enable toggle not found in SkillDetailView")

            let backButton = app.navigationBars.buttons.firstMatch
            if backButton.exists && backButton.isHittable {
                backButton.tap()
            }
        }
    }

    private func replaceText(in element: XCUIElement, with newText: String) {
        tapElement(element)
        if let existing = element.value as? String, !existing.isEmpty {
            let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count + 5)
            element.typeText(deleteString)
        }
        element.typeText(newText)
    }

    private func isToggleOn(_ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        let target = element.elementType == .switch ? element : (element.switches.firstMatch.exists ? element.switches.firstMatch : element)
        if let valStr = target.value as? String {
            return valStr == "1" || valStr.lowercased() == "on" || valStr.lowercased() == "true"
        }
        if let valInt = target.value as? Int {
            return valInt == 1
        }
        return false
    }

    private func skillDetailToggle() -> XCUIElement {
        let sw = app.switches["hanlin-skill-detail-enable-toggle"].firstMatch
        if sw.waitForExistence(timeout: 2) { return sw }
        let descendantSwitch = app.descendants(matching: .switch)["hanlin-skill-detail-enable-toggle"].firstMatch
        if descendantSwitch.waitForExistence(timeout: 2) { return descendantSwitch }
        return app.descendants(matching: .any)["hanlin-skill-detail-enable-toggle"].firstMatch
    }

    private func tapToggle(_ element: XCUIElement) {
        if element.elementType == .switch {
            if element.isHittable {
                element.tap()
            } else {
                element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
        } else if element.switches.firstMatch.exists {
            let sw = element.switches.firstMatch
            if sw.isHittable {
                sw.tap()
            } else {
                sw.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
        } else {
            tapElement(element)
        }
    }

    @discardableResult
    private func waitForToggle(_ element: XCUIElement, toBe targetState: Bool, timeout: TimeInterval = 10) -> Bool {
        let predicate = NSPredicate { _, _ in
            self.isToggleOn(element) == targetState
        }
        let exp = expectation(for: predicate, evaluatedWith: element)
        let result = XCTWaiter.wait(for: [exp], timeout: timeout)
        return result == .completed
    }

    func testCreateEditDisableDeleteCustomSkill() throws {
        openSkillCenter()

        let createButton = app.buttons["hanlin-skill-center-create-button"].firstMatch
        XCTAssertTrue(createButton.waitForExistence(timeout: 10), "Create button not found")
        tapElement(createButton)

        let menuNew = app.buttons["hanlin-skill-center-menu-new-skill"].firstMatch
        XCTAssertTrue(menuNew.waitForExistence(timeout: 5), "New skill menu option not found")
        tapElement(menuNew)

        let idInput = app.textFields["hanlin-skill-editor-id-input"].firstMatch
        XCTAssertTrue(idInput.waitForExistence(timeout: 10), "Skill ID input field not found")
        tapElement(idInput)
        idInput.typeText("test-ui-skill")

        let nameInput = app.textFields["hanlin-skill-editor-name-input"].firstMatch
        XCTAssertTrue(nameInput.waitForExistence(timeout: 5), "Skill Name input field not found")
        tapElement(nameInput)
        nameInput.typeText("Test UI Skill")

        let descInput = app.textFields["hanlin-skill-editor-desc-input"].firstMatch
        XCTAssertTrue(descInput.waitForExistence(timeout: 5), "Skill description input field not found")
        tapElement(descInput)
        descInput.typeText("UI created test skill")

        let bodyInput = app.textViews["hanlin-skill-editor-instructions-input"].firstMatch
        XCTAssertTrue(bodyInput.waitForExistence(timeout: 5), "Instructions input not found")
        tapElement(bodyInput)
        bodyInput.typeText("Instructions for test-ui-skill")

        let saveButton = app.buttons["hanlin-skill-editor-save-button"].firstMatch
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5), "Save button not found in editor")
        tapElement(saveButton)

        // 1. Verify row exists in list
        let createdRow = app.descendants(matching: .any)["hanlin-skill-center-skill-row-test-ui-skill"].firstMatch
        if !createdRow.waitForExistence(timeout: 5) { app.swipeUp() }
        XCTAssertTrue(createdRow.waitForExistence(timeout: 10), "Created skill row not found in list")

        // 2. Open detail
        tapElement(createdRow)

        // 3. Disable
        let enableToggle = skillDetailToggle()
        XCTAssertTrue(enableToggle.waitForExistence(timeout: 10), "Enable toggle not found in detail view")
        XCTAssertTrue(isToggleOn(enableToggle), "Skill should initially be enabled")
        tapToggle(enableToggle)
        XCTAssertTrue(waitForToggle(enableToggle, toBe: false, timeout: 10), "Skill should be toggled off")

        // 4. Leave and reopen to assert disabled persisted
        let backButton = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 5), "Back button not found")
        tapElement(backButton)

        XCTAssertTrue(createdRow.waitForExistence(timeout: 10), "Created skill row not found after navigating back")
        tapElement(createdRow)

        let reopenedToggle = skillDetailToggle()
        XCTAssertTrue(reopenedToggle.waitForExistence(timeout: 10), "Enable toggle not found on reopen")
        XCTAssertTrue(waitForToggle(reopenedToggle, toBe: false, timeout: 10), "Disabled state should persist across navigation")

        // 5. Re-enable
        tapToggle(reopenedToggle)
        XCTAssertTrue(waitForToggle(reopenedToggle, toBe: true, timeout: 10), "Skill should be re-enabled")

        // 6. Edit
        let editButton = app.buttons["hanlin-skill-detail-edit-button"].firstMatch
        XCTAssertTrue(editButton.waitForExistence(timeout: 5), "Edit button not found in detail view")
        tapElement(editButton)

        let editNameInput = app.textFields["hanlin-skill-editor-name-input"].firstMatch
        XCTAssertTrue(editNameInput.waitForExistence(timeout: 5), "Name input not found in edit mode")
        replaceText(in: editNameInput, with: "Test UI Skill Edited")

        let editInstructionsInput = app.textViews["hanlin-skill-editor-instructions-input"].firstMatch
        XCTAssertTrue(editInstructionsInput.waitForExistence(timeout: 5), "Instructions input not found in edit mode")
        replaceText(in: editInstructionsInput, with: "EDITED_UI_SKILL_INSTRUCTIONS")

        let editSaveButton = app.buttons["hanlin-skill-editor-save-button"].firstMatch
        XCTAssertTrue(editSaveButton.waitForExistence(timeout: 5), "Save button not found in edit mode")
        tapElement(editSaveButton)

        // 7. Leave and reopen, assert edited title and instructions visible/persisted
        let backAfterEdit = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(backAfterEdit.waitForExistence(timeout: 5), "Back button not found after edit")
        tapElement(backAfterEdit)

        XCTAssertTrue(createdRow.waitForExistence(timeout: 10), "Skill row not found after editing")
        tapElement(createdRow)

        let editedTitle = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Test UI Skill Edited'")).firstMatch
        XCTAssertTrue(editedTitle.waitForExistence(timeout: 10), "Edited title was not visible in detail view")

        let editedInstructions = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'EDITED_UI_SKILL_INSTRUCTIONS'")).firstMatch
        XCTAssertTrue(editedInstructions.waitForExistence(timeout: 10), "Edited instructions were not visible in detail view")

        // 8. Delete
        let deleteButton = app.buttons["hanlin-skill-detail-delete-button"].firstMatch
        if !deleteButton.waitForExistence(timeout: 3) {
            app.swipeUp()
        }
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5), "Delete button not found in detail view")
        tapElement(deleteButton)

        let confirmDelete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5), "Delete confirmation button not found")
        tapElement(confirmDelete)

        // 9. Assert row absent
        XCTAssertFalse(createdRow.waitForExistence(timeout: 5), "Skill row should no longer exist after deletion")
    }

    func testOverrideAndResetBuiltInSkill() throws {
        openSkillCenter()

        let codeRow = app.descendants(matching: .any)["hanlin-skill-center-skill-row-code"].firstMatch
        if !codeRow.waitForExistence(timeout: 5) { app.swipeUp() }
        XCTAssertTrue(codeRow.waitForExistence(timeout: 10), "Code skill row not found")
        tapElement(codeRow)

        // 1. Clear pre-existing override if fixture contamination exists
        let initialResetButton = app.buttons["hanlin-skill-detail-reset-button"].firstMatch
        if !initialResetButton.waitForExistence(timeout: 2) {
            app.swipeUp()
        }
        if initialResetButton.exists {
            tapElement(initialResetButton)
            let confirm = app.buttons["Reset"].firstMatch
            if confirm.waitForExistence(timeout: 2) { tapElement(confirm) }
            app.swipeDown()
        }

        // 2. Create override
        let overrideButton = app.buttons["hanlin-skill-detail-override-button"].firstMatch
        let editButton = app.buttons["hanlin-skill-detail-edit-button"].firstMatch
        if !overrideButton.waitForExistence(timeout: 2) && !editButton.waitForExistence(timeout: 2) {
            app.swipeUp()
        }
        XCTAssertTrue(overrideButton.waitForExistence(timeout: 5) || editButton.waitForExistence(timeout: 5), "Neither override nor edit button found")
        if overrideButton.exists {
            tapElement(overrideButton)
        } else {
            tapElement(editButton)
        }

        let instructionsField = app.textViews["hanlin-skill-editor-instructions-input"].firstMatch
        XCTAssertTrue(instructionsField.waitForExistence(timeout: 5), "Instructions input not found in editor")
        tapElement(instructionsField)
        instructionsField.typeText("\nUI_OVERRIDE_MARKER")

        let saveButton = app.buttons["hanlin-skill-editor-save-button"].firstMatch
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5), "Save button not found in editor")
        tapElement(saveButton)

        // 3. Leave and reopen to assert UI_OVERRIDE_MARKER is actually persisted
        let backButton = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 5), "Back button not found")
        tapElement(backButton)

        XCTAssertTrue(codeRow.waitForExistence(timeout: 10), "Code skill row not found after override")
        tapElement(codeRow)

        let markerText = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'UI_OVERRIDE_MARKER'")).firstMatch
        XCTAssertTrue(markerText.waitForExistence(timeout: 10), "UI_OVERRIDE_MARKER was not persisted in instructions")

        let activeResetButton = app.buttons["hanlin-skill-detail-reset-button"].firstMatch
        if !activeResetButton.waitForExistence(timeout: 3) {
            app.swipeUp()
        }
        if !activeResetButton.waitForExistence(timeout: 3) {
            app.swipeUp()
        }
        XCTAssertTrue(activeResetButton.waitForExistence(timeout: 10), "Reset button not found after customizing skill")

        // 4. Reset override
        tapElement(activeResetButton)
        let confirmReset = app.buttons["Reset"].firstMatch
        if confirmReset.waitForExistence(timeout: 2) {
            tapElement(confirmReset)
        }

        // 5. Leave and reopen to assert override is removed
        let backAfterReset = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(backAfterReset.waitForExistence(timeout: 5), "Back button not found after reset")
        tapElement(backAfterReset)

        XCTAssertTrue(codeRow.waitForExistence(timeout: 10), "Code skill row not found after reset")
        tapElement(codeRow)

        XCTAssertFalse(markerText.waitForExistence(timeout: 3), "UI_OVERRIDE_MARKER should be gone after reset")

        let baseInstructions = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'execute_local_python_code'")).firstMatch
        XCTAssertTrue(baseInstructions.waitForExistence(timeout: 10), "Base instructions should be restored after reset")

        let restoredOverrideButton = app.buttons["hanlin-skill-detail-override-button"].firstMatch
        if !restoredOverrideButton.waitForExistence(timeout: 3) {
            app.swipeUp()
        }
        if !restoredOverrideButton.waitForExistence(timeout: 3) {
            app.swipeUp()
        }
        XCTAssertTrue(restoredOverrideButton.waitForExistence(timeout: 10), "Override button should be visible again after reset to default")

        let finalBack = app.navigationBars.buttons.firstMatch
        if finalBack.exists && finalBack.isHittable {
            finalBack.tap()
        }
    }

    func testImportSkillZipPreviewInstall() throws {
        openSkillCenter()

        let importButton = app.buttons["hanlin-skill-center-import-button"].firstMatch
        XCTAssertTrue(importButton.waitForExistence(timeout: 5), "Import button not found")
        tapElement(importButton)

        let zipTab = app.buttons["hanlin-skill-import-tab-zip"].firstMatch
        XCTAssertTrue(zipTab.waitForExistence(timeout: 5), "ZIP tab not found in import view")
        tapElement(zipTab)

        // Tap deterministic fixture ZIP import button
        let fixtureButton = app.buttons["hanlin-skill-import-fixture-button"].firstMatch
        XCTAssertTrue(fixtureButton.waitForExistence(timeout: 5), "Fixture button not found in import view")
        tapElement(fixtureButton)

        // Verify preview shows title, ID, SHA-256
        let previewTitle = app.descendants(matching: .any)["hanlin-skill-import-preview-title"].firstMatch
        XCTAssertTrue(previewTitle.waitForExistence(timeout: 10), "Preview title not found")

        let originSHA = app.descendants(matching: .any)["hanlin-skill-import-sha256"].firstMatch
        XCTAssertTrue(originSHA.waitForExistence(timeout: 5), "SHA-256 not found in preview")

        let installButton = app.buttons["hanlin-skill-import-install-button"].firstMatch
        XCTAssertTrue(installButton.waitForExistence(timeout: 5), "Install button not found in preview")
        tapElement(installButton)

        // Verify imported skill appears in skill center list
        let importedRow = app.descendants(matching: .any)["hanlin-skill-center-skill-row-ui-import-skill"].firstMatch
        if !importedRow.waitForExistence(timeout: 5) { app.swipeUp() }
        XCTAssertTrue(importedRow.waitForExistence(timeout: 10), "Imported skill row not found in catalog")
    }

    func testInstallSkillFromURL() throws {
        openSkillCenter()

        let importButton = app.buttons["hanlin-skill-center-import-button"].firstMatch
        XCTAssertTrue(importButton.waitForExistence(timeout: 5), "Import button not found")
        tapElement(importButton)

        let urlTab = app.buttons["hanlin-skill-import-tab-url"].firstMatch
        XCTAssertTrue(urlTab.waitForExistence(timeout: 5), "URL tab not found in import view")
        tapElement(urlTab)

        let urlInput = app.textFields["hanlin-skill-import-url-input"].firstMatch
        XCTAssertTrue(urlInput.waitForExistence(timeout: 5), "URL text field not found")
        tapElement(urlInput)
        urlInput.typeText("https://skills.acceptance/ui-url-skill.zip")

        let downloadButton = app.buttons["hanlin-skill-import-url-button"].firstMatch
        XCTAssertTrue(downloadButton.waitForExistence(timeout: 5), "Download & Inspect button not found")
        tapElement(downloadButton)

        // Verify preview
        let previewTitle = app.descendants(matching: .any)["hanlin-skill-import-preview-title"].firstMatch
        XCTAssertTrue(previewTitle.waitForExistence(timeout: 15), "Preview title not found after URL download")

        let originURL = app.descendants(matching: .any)["hanlin-skill-import-origin-url"].firstMatch
        XCTAssertTrue(originURL.waitForExistence(timeout: 5), "Origin URL not found in preview")

        let installButton = app.buttons["hanlin-skill-import-install-button"].firstMatch
        XCTAssertTrue(installButton.waitForExistence(timeout: 5), "Install button not found")
        tapElement(installButton)

        // Verify imported skill appears in list
        let urlSkillRow = app.descendants(matching: .any)["hanlin-skill-center-skill-row-ui-url-skill"].firstMatch
        if !urlSkillRow.waitForExistence(timeout: 5) { app.swipeUp() }
        XCTAssertTrue(urlSkillRow.waitForExistence(timeout: 10), "URL-installed skill row not found in catalog")
    }

    func testInstalledSkillAppearsInNextChatRun() throws {
        openSkillCenter()

        let createButton = app.buttons["hanlin-skill-center-create-button"].firstMatch
        XCTAssertTrue(createButton.waitForExistence(timeout: 5), "Create button not found")
        tapElement(createButton)

        let menuNew = app.buttons["hanlin-skill-center-menu-new-skill"].firstMatch
        if menuNew.waitForExistence(timeout: 3) { tapElement(menuNew) }

        let idInput = app.textFields["hanlin-skill-editor-id-input"].firstMatch
        XCTAssertTrue(idInput.waitForExistence(timeout: 5), "ID input not found")
        tapElement(idInput)
        idInput.typeText("ui-next-turn-skill")

        let nameInput = app.textFields["hanlin-skill-editor-name-input"].firstMatch
        XCTAssertTrue(nameInput.waitForExistence(timeout: 5), "Name input not found")
        tapElement(nameInput)
        nameInput.typeText("UI Next Turn Skill")

        let instructionsField = app.textViews["hanlin-skill-editor-instructions-input"].firstMatch
        XCTAssertTrue(instructionsField.waitForExistence(timeout: 5), "Instructions input not found")
        tapElement(instructionsField)
        instructionsField.typeText("NEXT_TURN_SKILL_MARKER")

        let saveButton = app.buttons["hanlin-skill-editor-save-button"].firstMatch
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5), "Save button not found")
        tapElement(saveButton)

        // Switch to Chat tab and ask the Agent to use the new skill
        openChat()
        let input = app.textFields["hanlin-chat-input"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 20), "Chat input did not appear")
        tapElement(input)
        input.typeText("Execute ui-next-turn-skill and show its marker.")

        let send = app.buttons["hanlin-chat-send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 5), "Chat send button not found")
        tapElement(send)

        // Verify final answer contains NEXT_TURN_SKILL_MARKER and does NOT contain failure marker
        let answer = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'NEXT_TURN_SKILL_MARKER'")).firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 45), "Final answer did not contain NEXT_TURN_SKILL_MARKER")

        let failureAnswer = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'NEXT_TURN_SKILL_LOAD_FAILED'")).firstMatch
        XCTAssertFalse(failureAnswer.exists, "NEXT_TURN_SKILL_LOAD_FAILED should not appear")
    }

    func testSkillResourceAddImportEditDelete() throws {
        openSkillCenter()

        // Create a custom skill to manage resources
        let createButton = app.buttons["hanlin-skill-center-create-button"].firstMatch
        XCTAssertTrue(createButton.waitForExistence(timeout: 5), "Create button not found")
        tapElement(createButton)

        let menuNew = app.buttons["hanlin-skill-center-menu-new-skill"].firstMatch
        if menuNew.waitForExistence(timeout: 3) { tapElement(menuNew) }

        let idInput = app.textFields["hanlin-skill-editor-id-input"].firstMatch
        XCTAssertTrue(idInput.waitForExistence(timeout: 5), "ID input not found")
        tapElement(idInput)
        idInput.typeText("res-crud-skill")

        let nameInput = app.textFields["hanlin-skill-editor-name-input"].firstMatch
        XCTAssertTrue(nameInput.waitForExistence(timeout: 5), "Name input not found")
        tapElement(nameInput)
        nameInput.typeText("Resource CRUD Skill")

        let descInput = app.textFields["hanlin-skill-editor-desc-input"].firstMatch
        if descInput.waitForExistence(timeout: 3) {
            tapElement(descInput)
            descInput.typeText("Resource CRUD Skill Description")
        }

        let saveButton = app.buttons["hanlin-skill-editor-save-button"].firstMatch
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5), "Save button not found")
        tapElement(saveButton)

        // Open detail
        let row = app.descendants(matching: .any)["hanlin-skill-center-skill-row-res-crud-skill"].firstMatch
        if !row.waitForExistence(timeout: 5) { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Skill row not found")
        tapElement(row)

        // 1. Add text resource
        let addResButton = app.buttons["hanlin-skill-detail-add-resource-button"].firstMatch
        XCTAssertTrue(addResButton.waitForExistence(timeout: 10), "Add Resource button not found")
        tapElement(addResButton)

        let resPathInput = app.textFields["hanlin-skill-resource-path-input"].firstMatch
        XCTAssertTrue(resPathInput.waitForExistence(timeout: 5), "Resource path input not found")
        tapElement(resPathInput)
        resPathInput.typeText("references/doc.md")

        let resContentInput = app.textViews["hanlin-skill-resource-content-input"].firstMatch
        XCTAssertTrue(resContentInput.waitForExistence(timeout: 5), "Resource content input not found")
        tapElement(resContentInput)
        resContentInput.typeText("Initial Document Content")

        let saveResButton = app.buttons["hanlin-skill-resource-save-button"].firstMatch
        XCTAssertTrue(saveResButton.waitForExistence(timeout: 5), "Save resource button not found")
        tapElement(saveResButton)

        // 2. Import fixture resource
        let importFixtureBtn = app.buttons["hanlin-skill-detail-import-fixture-resource-button"].firstMatch
        XCTAssertTrue(importFixtureBtn.waitForExistence(timeout: 5), "Import fixture resource button not found")
        tapElement(importFixtureBtn)

        // 3. Edit text resource
        let editResBtn = app.buttons["hanlin-skill-detail-edit-resource-references/doc.md"].firstMatch
        XCTAssertTrue(editResBtn.waitForExistence(timeout: 5), "Edit resource button not found")
        tapElement(editResBtn)
        let editContent = app.textViews["hanlin-skill-resource-edit-content-input"].firstMatch
        XCTAssertTrue(editContent.waitForExistence(timeout: 5), "Edit resource content input not found")
        tapElement(editContent)
        editContent.typeText("\nUpdated Extra Line")
        let saveEditBtn = app.buttons["hanlin-skill-detail-save-edit-resource-button"].firstMatch
        XCTAssertTrue(saveEditBtn.waitForExistence(timeout: 5), "Save edit resource button not found")
        tapElement(saveEditBtn)

        // 4. Delete resource
        let deleteResBtn = app.buttons["hanlin-skill-detail-delete-resource-references/doc.md"].firstMatch
        XCTAssertTrue(deleteResBtn.waitForExistence(timeout: 5), "Delete resource button not found")
        tapElement(deleteResBtn)
        let confirm = app.buttons["Delete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Delete resource confirm button not found")
        tapElement(confirm)
        XCTAssertFalse(deleteResBtn.waitForExistence(timeout: 5), "Resource should be deleted")

        // Clean up skill
        let deleteSkill = app.buttons["hanlin-skill-detail-delete-button"].firstMatch
        XCTAssertTrue(deleteSkill.waitForExistence(timeout: 5), "Delete skill button not found")
        tapElement(deleteSkill)
        let confirmDelete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5), "Delete skill confirm button not found")
        tapElement(confirmDelete)
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

    private func navigateBackToSettingsRoot() {
        while !app.navigationBars["Settings"].exists && !app.navigationBars["设置"].exists && app.navigationBars.buttons.count > 0 {
            let backButton = app.navigationBars.buttons.element(boundBy: 0)
            if backButton.waitForExistence(timeout: 2) && backButton.isHittable {
                backButton.tap()
            } else {
                break
            }
        }
    }

    private func openChat() {
        navigateBackToSettingsRoot()
        _ = selectTab(identifier: "hanlin-home-tab", labels: ["Chats", "Messages", "Home", "列表"])

        let input = app.textFields["hanlin-chat-input"].firstMatch
        if !input.waitForExistence(timeout: 5) {
            let chatPredicate = NSPredicate(format: "label CONTAINS 'Agent Acceptance Chat' OR identifier CONTAINS 'Agent Acceptance Chat'")
            let seededChat = app.descendants(matching: .any).matching(chatPredicate).firstMatch
            if seededChat.waitForExistence(timeout: 15) {
                tapElement(seededChat)
            }
        }
    }

    private func tapElement(_ element: XCUIElement) {
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

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

        func findCandidate() -> Bool {
            for candidate in candidates {
                if candidate.waitForExistence(timeout: 2) && candidate.isHittable {
                    candidate.tap()
                    return true
                }
            }
            return false
        }

        if findCandidate() { return true }

        let prevPage = app.buttons["Previous Page"].firstMatch
        if prevPage.waitForExistence(timeout: 2) && prevPage.isHittable {
            prevPage.tap()
            if findCandidate() { return true }
        }

        let nextPage = app.buttons["Next Page"].firstMatch
        if nextPage.waitForExistence(timeout: 2) && nextPage.isHittable {
            nextPage.tap()
            if findCandidate() { return true }
        }

        let labelClauses = labels.map { "label CONTAINS '\($0)'" }
        let format = (["identifier == '\(identifier)'"] + labelClauses).joined(separator: " OR ")
        let fallback = app.descendants(matching: .any).matching(NSPredicate(format: format)).firstMatch
        if fallback.waitForExistence(timeout: 5) && fallback.isHittable {
            tapElement(fallback)
            return true
        }
        return false
    }

    private func selectSettingsTab() -> Bool {
        selectTab(identifier: "hanlin-settings-tab", labels: ["Settings", "设置"])
    }
}
