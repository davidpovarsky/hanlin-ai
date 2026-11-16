import XCTest

@MainActor
final class HanlinSkillCenterUITests: XCTestCase {
    private let app = XCUIApplication()
    private let markdownFixtureID = "ui-md-\(UUID().uuidString.lowercased())"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_AGENT_SKILLS_EMBEDDED_ACCEPTANCE"] = "1"
        app.launchEnvironment["HANLIN_SKILL_MARKDOWN_FIXTURE_ID"] = markdownFixtureID
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
        XCTAssertTrue(codeRow.waitForExistence(timeout: 5), "System skill must be present; do not silently skip detail acceptance")
        tapElement(codeRow)
        assertUnknownCompatibility(scope: "detail")
        let enableToggle = skillDetailToggle()
        XCTAssertTrue(enableToggle.waitForExistence(timeout: 10), "Enable toggle not found in SkillDetailView")

        let backButton = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 5))
        tapElement(backButton)
    }

    private func replaceText(in element: XCUIElement, with newText: String) {
        tapElement(element)
        if let existing = element.value as? String, !existing.isEmpty {
            let deleteString = String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count + 5)
            element.typeText(deleteString)
        }
        element.typeText(newText)
    }

    private func toggleState(_ element: XCUIElement) -> Bool? {
        guard element.exists else { return nil }
        if let value = element.value as? String {
            switch value.lowercased() {
            case "1", "on", "true": return true
            case "0", "off", "false": return false
            default: return nil
            }
        }
        if let value = element.value as? Int, value == 0 || value == 1 { return value == 1 }
        return nil
    }

    private func isToggleOn(_ element: XCUIElement) -> Bool {
        toggleState(element) == true
    }

    private func skillDetailToggle() -> XCUIElement {
        let sw = app.switches["hanlin-skill-detail-enable-toggle"].firstMatch
        if sw.waitForExistence(timeout: 3) { return sw }
        let descendantSwitch = app.descendants(matching: .switch)["hanlin-skill-detail-enable-toggle"].firstMatch
        if descendantSwitch.waitForExistence(timeout: 2) { return descendantSwitch }
        return app.descendants(matching: .any)["hanlin-skill-detail-enable-toggle"].firstMatch
    }

    private func tapToggle(_ element: XCUIElement) {
        tapElement(element)
    }

    @discardableResult
    private func waitForToggle(_ element: XCUIElement, toBe targetState: Bool, timeout: TimeInterval = 10) -> Bool {
        let predicate = NSPredicate { _, _ in
            self.toggleState(element) == targetState
        }
        let exp = expectation(for: predicate, evaluatedWith: element)
        let result = XCTWaiter.wait(for: [exp], timeout: timeout)
        return result == .completed
    }

    private func assertUnknownCompatibility(scope: String, expectedStatus: String = "Unknown", file: StaticString = #filePath, line: UInt = #line) {
        let status = app.descendants(matching: .any)["hanlin-skill-\(scope)-compatibility-status"].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 5), file: file, line: line)
        let unknown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expectedStatus), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [unknown], timeout: 5), .completed, file: file, line: line)
        let lastTested = app.descendants(matching: .any)["hanlin-skill-\(scope)-compatibility-last-tested"].firstMatch
        XCTAssertTrue(lastTested.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertEqual(lastTested.value as? String, "Not recorded", file: file, line: line)
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
        assertUnknownCompatibility(scope: "detail", expectedStatus: "PARSE_ONLY")
        let enableToggle = skillDetailToggle()
        XCTAssertTrue(enableToggle.waitForExistence(timeout: 10), "Enable toggle not found in detail view")
        XCTAssertTrue(isToggleOn(enableToggle), "Skill should initially be enabled")
        tapToggle(enableToggle)
        XCTAssertTrue(waitForToggle(enableToggle, toBe: false, timeout: 10), "Skill should be toggled off")
        assertUnknownCompatibility(scope: "detail", expectedStatus: "DISABLED")

        // 4. Leave and reopen to assert disabled persisted
        let backButton = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 5), "Back button not found")
        tapElement(backButton)

        XCTAssertTrue(createdRow.waitForExistence(timeout: 10), "Created skill row not found after navigating back")
        tapElement(createdRow)

        let reopenedToggle = skillDetailToggle()
        XCTAssertTrue(reopenedToggle.waitForExistence(timeout: 10), "Enable toggle not found on reopen")
        XCTAssertTrue(waitForToggle(reopenedToggle, toBe: false, timeout: 10), "Disabled state should persist across navigation")
        assertUnknownCompatibility(scope: "detail", expectedStatus: "DISABLED")

        // 5. Re-enable
        tapToggle(reopenedToggle)
        XCTAssertTrue(waitForToggle(reopenedToggle, toBe: true, timeout: 10), "Skill should be re-enabled")
        assertUnknownCompatibility(scope: "detail", expectedStatus: "PARSE_ONLY")

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
        assertUnknownCompatibility(scope: "import")

        let originSHA = app.descendants(matching: .any)["hanlin-skill-import-sha256"].firstMatch
        XCTAssertTrue(originSHA.waitForExistence(timeout: 5), "SHA-256 not found in preview")

        let installButton = app.buttons["hanlin-skill-import-install-button"].firstMatch
        XCTAssertTrue(installButton.waitForExistence(timeout: 5), "Install button not found in preview")
        XCTAssertTrue(installButton.isEnabled, "Unknown compatibility must not block installing instructions/resources")
        tapElement(installButton)

        // Verify imported skill appears in skill center list
        let importedRow = app.descendants(matching: .any)["hanlin-skill-center-skill-row-ui-import-skill"].firstMatch
        if !importedRow.waitForExistence(timeout: 5) { app.swipeUp() }
        XCTAssertTrue(importedRow.waitForExistence(timeout: 10), "Imported skill row not found in catalog")
        tapElement(importedRow)
        assertUnknownCompatibility(scope: "detail", expectedStatus: "PARSE_ONLY")
    }

    func testImportedSkillExecutionRequiresApprovalAndPersistsAfterColdLaunch() throws {
        let fixtureID = "ui-exec-" + UUID().uuidString.lowercased()
        app.terminate()
        app.launchEnvironment["HANLIN_SKILL_ZIP_FIXTURE_ID"] = fixtureID
        app.launch()
        openSkillCenter()
        tapElement(app.buttons["hanlin-skill-center-import-button"].firstMatch)
        tapElement(app.buttons["hanlin-skill-import-tab-zip"].firstMatch)
        tapElement(app.buttons["hanlin-skill-import-fixture-button"].firstMatch)
        let install = app.buttons["hanlin-skill-import-install-button"].firstMatch
        XCTAssertTrue(install.waitForExistence(timeout: 10)); tapElement(install)
        let row = app.descendants(matching: .any)["hanlin-skill-center-skill-row-\(fixtureID)"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10)); tapElement(row)
        let action = app.buttons["hanlin-skill-action-picker"].firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 10)); tapElement(action)
        tapElement(app.buttons["scripts/run.py"].firstMatch)
        let run = app.buttons["hanlin-skill-run"].firstMatch
        for _ in 0..<5 where !run.isHittable { app.swipeUp() }
        XCTAssertTrue(run.waitForExistence(timeout: 5)); tapElement(run)
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.waitForExistence(timeout: 1) {
            tapElement(cancel)
        } else {
            // Native iPad confirmation popovers omit the cancel action. A tap
            // outside dismisses the unapproved operation without executing it.
            app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(app.buttons["Allow once"].firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["hanlin-skill-execution-output"].exists)
        tapElement(run)
        let allow = app.buttons["Allow once"].firstMatch
        XCTAssertTrue(allow.waitForExistence(timeout: 5)); tapElement(allow)
        let status = app.descendants(matching: .any)["hanlin-skill-detail-compatibility-status"].firstMatch
        let passed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'EXECUTION_PASS'"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [passed], timeout: 90), .completed)
        let output = app.staticTexts["hanlin-skill-execution-output"].firstMatch
        XCTAssertTrue(output.label.contains("test script"))
        let receipt = app.staticTexts["hanlin-skill-execution-receipt"].firstMatch
        XCTAssertTrue(receipt.exists)
        let receiptID = String(receipt.label.suffix(8))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "skill-real-python-execution"; attachment.lifetime = .keepAlways; add(attachment)
        app.terminate(); app.launch()
        openSkillCenter()
        XCTAssertTrue(row.waitForExistence(timeout: 10)); tapElement(row)
        tapElement(action); tapElement(app.buttons["scripts/run.py"].firstMatch)
        XCTAssertTrue(receipt.waitForExistence(timeout: 10))
        XCTAssertTrue(receipt.label.hasSuffix(receiptID), "Cold launch must load the original execution receipt")
        XCTAssertTrue(output.waitForExistence(timeout: 5)); XCTAssertTrue(output.label.contains("test script"))
    }

    func testCancelActuallyRunningImportedNodeSkillRetainsPartialOutput() throws {
        let fixtureID = "ui-exec-" + UUID().uuidString.lowercased()
        app.terminate(); app.launchEnvironment["HANLIN_SKILL_ZIP_FIXTURE_ID"] = fixtureID; app.launch()
        openSkillCenter()
        tapElement(app.buttons["hanlin-skill-center-import-button"].firstMatch)
        tapElement(app.buttons["hanlin-skill-import-tab-zip"].firstMatch)
        tapElement(app.buttons["hanlin-skill-import-fixture-button"].firstMatch)
        let install = app.buttons["hanlin-skill-import-install-button"].firstMatch
        XCTAssertTrue(install.waitForExistence(timeout: 10)); tapElement(install)
        let row = app.descendants(matching: .any)["hanlin-skill-center-skill-row-\(fixtureID)"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10)); tapElement(row)
        let action = app.buttons["hanlin-skill-action-picker"].firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 10)); tapElement(action)
        tapElement(app.buttons["scripts/slow.mjs"].firstMatch)
        let run = app.buttons["hanlin-skill-run"].firstMatch
        for _ in 0..<5 where !run.isHittable { app.swipeUp() }
        tapElement(run)
        let allow = app.buttons["Allow once"].firstMatch
        XCTAssertTrue(allow.waitForExistence(timeout: 5)); tapElement(allow)
        let output = app.staticTexts["hanlin-skill-execution-output"].firstMatch
        let started = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "STARTED_" + fixtureID), object: output)
        XCTAssertEqual(XCTWaiter.wait(for: [started], timeout: 90), .completed)
        let cancel = app.buttons["hanlin-skill-cancel-execution"].firstMatch
        XCTAssertTrue(cancel.isEnabled); tapElement(cancel)
        let receipt = app.staticTexts["hanlin-skill-execution-receipt"].firstMatch
        let cancelled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'CANCELLED'"), object: receipt)
        XCTAssertEqual(XCTWaiter.wait(for: [cancelled], timeout: 15), .completed)
        let status = app.descendants(matching: .any)["hanlin-skill-detail-compatibility-status"].firstMatch
        let currentStatus = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'CANCELLED'"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [currentStatus], timeout: 10), .completed)
        XCTAssertFalse(receipt.label.contains("Historical"), "The just-cancelled original job must match current source and engine facts")
        XCTAssertTrue(output.label.contains("STARTED_" + fixtureID))
        XCTAssertFalse(output.label.contains("UNEXPECTED_LATE"))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "skill-cancel-real-node-job-partial-output"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testImportInstructionOnlyMarkdownShowsParseOnlyWithoutExecution() throws {
        openSkillCenter()
        tapElement(app.buttons["hanlin-skill-center-import-button"].firstMatch)
        let install = stageMarkdownFixture()
        tapElement(install)
        let row = app.descendants(matching: .any)["hanlin-skill-center-skill-row-\(markdownFixtureID)"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        tapElement(row)
        assertUnknownCompatibility(scope: "detail", expectedStatus: "PARSE_ONLY")
        let toggle = skillDetailToggle()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertTrue(isToggleOn(toggle))
        tapElement(app.buttons["hanlin-skill-detail-delete-button"].firstMatch)
        let confirm = app.buttons["Delete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        tapElement(confirm)
        XCTAssertTrue(row.waitForNonExistence(timeout: 5), "Delete only this test's unique imported skill")
    }

    func testCancelPreviewThenRetryDoesNotInstallOrLoseUnknownState() throws {
        openSkillCenter()
        tapElement(app.buttons["hanlin-skill-center-import-button"].firstMatch)
        _ = stageMarkdownFixture()
        let cancel = app.buttons["hanlin-skill-import-cancel-button"].firstMatch
        tapElement(cancel)
        _ = stageMarkdownFixture()
        tapElement(cancel)
        tapElement(cancel)
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 5))
        let search = app.searchFields.firstMatch
        if !search.isHittable { app.descendants(matching: .any)["hanlin-skill-center-list"].firstMatch.swipeDown() }
        tapElement(search)
        search.typeText(markdownFixtureID)
        XCTAssertTrue(app.staticTexts["No skills found"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["hanlin-skill-center-skill-row-\(markdownFixtureID)"].exists,
                       "Preview/cancel/retry must not install the unique fixture")
    }

    private func stageMarkdownFixture() -> XCUIElement {
        let fixture = app.buttons["hanlin-skill-import-markdown-fixture-button"].firstMatch
        XCTAssertTrue(fixture.waitForExistence(timeout: 5))
        tapElement(fixture)
        let title = app.descendants(matching: .any)["hanlin-skill-import-preview-title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, markdownFixtureID)
        assertUnknownCompatibility(scope: "import")
        XCTAssertTrue(app.staticTexts["hanlin-skill-import-preview-resources-empty"].waitForExistence(timeout: 5))
        let install = app.buttons["hanlin-skill-import-install-button"].firstMatch
        XCTAssertTrue(install.waitForExistence(timeout: 5))
        XCTAssertTrue(install.isEnabled, "Instruction-only skills must remain installable without runtime proof")
        return install
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
        let input = chatInputElement()
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
        let settings = app.descendants(matching: .any)["hanlin-settings-list"].firstMatch
        for attempt in 0..<2 {
            if skillCenterLink.waitForExistence(timeout: 5) && skillCenterLink.isHittable {
                tapElement(skillCenterLink)
                return
            }
            if settings.exists && settings.isHittable { settings.swipeUp() }
            if skillCenterLink.exists && skillCenterLink.isHittable {
                tapElement(skillCenterLink)
                return
            }
            if attempt == 0 {
                // Native TabView can still expose the outgoing tab's AX snapshot
                // during a transition. Revisit the actual tabs, never tap an
                // offscreen Settings link through that stale snapshot.
                XCTAssertTrue(selectTab(identifier: "hanlin-home-tab", labels: ["List", "Chats"]))
                XCTAssertTrue(selectSettingsTab())
            }
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

    private func chatInputElement() -> XCUIElement {
        let tf = app.textFields["hanlin-chat-input"].firstMatch
        if tf.exists { return tf }
        let tv = app.textViews["hanlin-chat-input"].firstMatch
        if tv.exists { return tv }
        return app.descendants(matching: .any)["hanlin-chat-input"].firstMatch
    }

    private func openChat() {
        navigateBackToSettingsRoot()
        _ = selectTab(identifier: "hanlin-home-tab", labels: ["Chats", "Messages", "Home", "列表"])

        let input = chatInputElement()
        if !input.waitForExistence(timeout: 5) {
            let chatPredicate = NSPredicate(format: "label CONTAINS 'Agent Acceptance Chat' OR identifier CONTAINS 'Agent Acceptance Chat'")
            let seededChat = app.descendants(matching: .any).matching(chatPredicate).firstMatch
            if seededChat.waitForExistence(timeout: 15) {
                tapElement(seededChat)
            }
        }
    }

    private func tapElement(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<6 where !element.isHittable {
            let containers = ["hanlin-skill-detail-list", "hanlin-skill-center-list", "hanlin-skill-import-preview-list", "hanlin-settings-list"]
            guard let list = containers.map({ app.descendants(matching: .any)[$0].firstMatch })
                .first(where: { $0.exists && $0.isHittable }) else { break }
            let above = element.exists && element.frame.maxY < list.frame.minY
            let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: above ? 0.3 : 0.7))
            let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: above ? 0.7 : 0.3))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            element.exists && element.isHittable
        }, object: element)
        let result = XCTWaiter.wait(for: [hittable], timeout: 5)
        XCTAssertEqual(result, .completed, "Expected an accessible, hittable element", file: file, line: line)
        guard result == .completed else { return }
        element.tap()
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
