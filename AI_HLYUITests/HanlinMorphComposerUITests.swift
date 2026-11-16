import XCTest

@MainActor
final class HanlinMorphComposerUITests: XCTestCase {
    func testLargeTextLongDraftFitsWithKeyboardAndAfterPalette() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE"] = "1"
        app.launchEnvironment["HANLIN_DOCK_ACCEPTANCE_FIXTURES"] = "1"
        app.launch()
        defer { app.terminate() }

        let input = app.descendants(matching: .any)["hanlin-chat-input"].firstMatch
        if !input.waitForExistence(timeout: 5) {
            let chat = app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS 'Agent Acceptance Chat' OR identifier CONTAINS 'Agent Acceptance Chat'")
            ).firstMatch
            XCTAssertTrue(chat.waitForExistence(timeout: 15))
            chat.tap()
        }
        XCTAssertTrue(input.waitForExistence(timeout: 20))
        input.tap()
        let draft = String(repeating: "Wrapped accessible draft text ", count: 32)
        input.typeText(draft)
        let window = app.windows.firstMatch
        XCTAssertGreaterThanOrEqual(input.frame.minY, window.frame.minY - 1)
        XCTAssertLessThanOrEqual(input.frame.maxY, window.frame.maxY + 1)
        XCTAssertEqual(input.value as? String, draft)
        let plus = app.buttons["hanlin-composer-general-menu"].firstMatch
        XCTAssertTrue(plus.waitForExistence(timeout: 5))
        plus.tap()
        XCTAssertTrue(app.descendants(matching: .any)["morphing-action-panel"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(input.frame.minY, window.frame.minY - 1)
        XCTAssertLessThanOrEqual(input.frame.maxY, window.frame.maxY + 1)
        plus.tap()
        XCTAssertEqual(input.value as? String, draft)
    }

    func testDismissModelPickerKeepsSelectedModelAndDraft() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE"] = "1"
        app.launchEnvironment["HANLIN_DOCK_ACCEPTANCE_FIXTURES"] = "1"
        app.launch()
        defer { app.terminate() }

        // The retained iOS 27.2 hierarchy exposes the real UIKit editor with
        // its parent surface ID. Keep the query typed and the draft assertions.
        let input = app.textViews.matching(NSPredicate(
            format: "identifier == 'hanlin-chat-input' OR identifier == 'hanlin-composer-surface'"
        )).firstMatch
        if !input.waitForExistence(timeout: 5) {
            let chat = app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS 'Agent Acceptance Chat' OR identifier CONTAINS 'Agent Acceptance Chat'")
            ).firstMatch
            XCTAssertTrue(chat.waitForExistence(timeout: 15))
            chat.tap()
        }
        XCTAssertTrue(input.waitForExistence(timeout: 20))
        input.tap()
        let draft = "Draft survives model picker cancellation"
        input.typeText(draft)
        let model = app.buttons["hanlin-composer-model-picker"].firstMatch
        XCTAssertTrue(model.waitForExistence(timeout: 5))
        let originalLabel = model.label
        XCTAssertFalse(originalLabel.isEmpty)
        model.tap()
        let picker = app.descendants(matching: .any)["hanlin-model-picker-popover"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 10))
        model.tap()
        XCTAssertTrue(picker.waitForNonExistence(timeout: 5))
        XCTAssertEqual(model.label, originalLabel)
        XCTAssertEqual(input.value as? String, draft)
    }

    func testRTLToolChipKeepsLongDraftAndAccessibleLabel() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(he)", "-AppleLocale", "he_IL"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE"] = "1"
        app.launchEnvironment["HANLIN_DOCK_ACCEPTANCE_FIXTURES"] = "1"
        app.launch()
        defer { app.terminate() }

        let input = app.descendants(matching: .any)["hanlin-chat-input"].firstMatch
        if !input.waitForExistence(timeout: 5) {
            let chat = app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS 'Agent Acceptance Chat' OR identifier CONTAINS 'Agent Acceptance Chat'")
            ).firstMatch
            XCTAssertTrue(chat.waitForExistence(timeout: 15))
            chat.tap()
        }
        XCTAssertTrue(input.waitForExistence(timeout: 20))
        let tools = app.buttons["hanlin-composer-tools-direct"].firstMatch
        XCTAssertTrue(tools.waitForExistence(timeout: 5))
        tools.tap()
        let toggle = app.descendants(matching: .any)["hanlin-tool-use-toggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if (toggle.value as? String) != "1" { toggle.tap() }
        tools.tap()

        let chip = app.buttons["composer-chip-tools"].firstMatch
        let plus = app.buttons["hanlin-composer-general-menu"].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        XCTAssertEqual(chip.label, "כלים", "Icon-only layout must retain the localized capability label")
        XCTAssertEqual(chip.value as? String, "מופעל")
        XCTAssertGreaterThan(plus.frame.midX, input.frame.midX, "Launcher must follow the RTL layout")
        input.tap()
        let draft = String(repeating: "Long accessible composer draft. ", count: 18)
        input.typeText(draft)
        XCTAssertEqual(input.value as? String, draft)
        chip.tap()
        XCTAssertFalse(chip.exists)
        tools.tap()
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, draft)
    }

    func testEnabledToolsChipOpensSettingsAndContextMenuDisables() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE"] = "1"
        app.launchEnvironment["HANLIN_DOCK_ACCEPTANCE_FIXTURES"] = "1"
        app.launch()
        defer { app.terminate() }

        let input = app.descendants(matching: .any)["hanlin-chat-input"].firstMatch
        if !input.waitForExistence(timeout: 5) {
            let chat = app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS 'Agent Acceptance Chat' OR identifier CONTAINS 'Agent Acceptance Chat'")
            ).firstMatch
            XCTAssertTrue(chat.waitForExistence(timeout: 15))
            chat.tap()
        }
        XCTAssertTrue(input.waitForExistence(timeout: 20))
        let toolsButton = app.buttons["hanlin-composer-tools-direct"].firstMatch
        XCTAssertTrue(toolsButton.waitForExistence(timeout: 5))
        toolsButton.tap()
        let toggle = app.descendants(matching: .any)["hanlin-tool-use-toggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Test requires a model that supports tool use")
        if (toggle.value as? String) != "1" { toggle.tap() }
        let catalog = app.buttons["hanlin-tools-open-catalog"].firstMatch
        XCTAssertTrue(catalog.waitForExistence(timeout: 5))
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Enabled"), object: catalog)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed,
                       "Expanded tools must highlight the live enabled capability")
        XCTAssertFalse(app.buttons["composer-chip-tools"].exists, "Expanded bubble must not duplicate the external chips")
        toolsButton.tap()

        let row = app.descendants(matching: .any)["active-tool-chips-above-composer"].firstMatch
        let chip = app.buttons["composer-chip-tools"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        XCTAssertEqual(chip.label, "Tools")
        XCTAssertEqual(chip.value as? String, "Enabled")
        chip.tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertFalse(row.exists, "Detached chips must be hidden while the bubble is open")
        toolsButton.tap()
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        chip.press(forDuration: 1)
        let disable = app.buttons["Turn off tool use in this chat"].firstMatch
        XCTAssertTrue(disable.waitForExistence(timeout: 5))
        disable.tap()
        XCTAssertTrue(chip.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["composer-chip-skills"].exists)
        XCTAssertFalse(app.buttons["composer-chip-runtimes"].exists)
        XCTAssertFalse(app.buttons["composer-chip-mcp"].exists)
        toolsButton.tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0", "Context menu must update the real chat binding")
    }

    func testCompactNavigationKeepsDraft() throws {
        try verifyNavigation(expectWide: false)
    }

    func testWideNavigationKeepsDraft() throws {
        try verifyNavigation(expectWide: true)
    }

    func testCompactLargeTextWithAttachment() throws {
        try verifyNavigation(expectWide: false, largeText: true)
    }

    func testParameterOverlayDismissesOnComposerBackground() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE"] = "1"
        app.launchEnvironment["HANLIN_DOCK_ACCEPTANCE_FIXTURES"] = "1"
        app.launch()
        defer { app.terminate() }

        let chat = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'Agent Acceptance Chat' OR identifier CONTAINS 'Agent Acceptance Chat'")
        ).firstMatch
        XCTAssertTrue(chat.waitForExistence(timeout: 20))
        chat.tap()
        let input = app.descendants(matching: .any)["hanlin-chat-input"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        let draft = "Preserved while dismissing parameters"
        input.typeText(draft)
        let navigationButtons = app.navigationBars.buttons
        XCTAssertGreaterThan(navigationButtons.count, 0)
        navigationButtons.element(boundBy: navigationButtons.count - 1).tap()
        let parameters = app.buttons["调整模型参数"].firstMatch
        XCTAssertTrue(parameters.waitForExistence(timeout: 5))
        parameters.tap()
        let temperature = app.buttons["调整采样温度"].firstMatch
        XCTAssertTrue(temperature.waitForExistence(timeout: 5))
        temperature.tap()
        let overlay = app.descendants(matching: .any)["hanlin-temperature-overlay"].firstMatch
        XCTAssertTrue(overlay.waitForExistence(timeout: 5))
        let surface = app.descendants(matching: .any)["hanlin-composer-surface"].firstMatch
        XCTAssertTrue(surface.waitForExistence(timeout: 5))
        surface.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.06)).tap()
        XCTAssertTrue(overlay.waitForNonExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, draft)
    }

    private func verifyNavigation(expectWide: Bool, largeText: Bool = false) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE"] = "1"
        app.launchEnvironment["HANLIN_DOCK_ACCEPTANCE_FIXTURES"] = "1"
        app.launch()
        defer { app.terminate() }

        let input = app.descendants(matching: .any)["hanlin-chat-input"].firstMatch
        if !input.waitForExistence(timeout: 5) {
            let chat = app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS 'Agent Acceptance Chat' OR identifier CONTAINS 'Agent Acceptance Chat'")
            ).firstMatch
            XCTAssertTrue(chat.waitForExistence(timeout: 15))
            chat.tap()
        }
        XCTAssertTrue(input.waitForExistence(timeout: 20))
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        let actualWidth = window.frame.width
        if expectWide {
            XCTAssertGreaterThanOrEqual(actualWidth, 900, "Run the wide selector on a real wide iPad viewport")
            XCTAssertFalse(app.descendants(matching: .any)["hanlin-compact-chat-workspace"].exists, "Wide selector must use the wide workspace")
            XCTAssertGreaterThan(input.frame.width, 400, "The actual editor frame must be wide enough to exercise the wide layout")
        } else {
            XCTAssertLessThan(actualWidth, 640, "Run the compact selector on an actual narrow viewport")
            XCTAssertTrue(app.descendants(matching: .any)["hanlin-compact-chat-workspace"].waitForExistence(timeout: 5))
        }
        input.tap()
        let draft = "Morph keeps this draft"
        input.typeText(draft)

        let plus = app.buttons["hanlin-composer-general-menu"].firstMatch
        XCTAssertTrue(plus.waitForExistence(timeout: 10))
        plus.tap()
        let panel = app.descendants(matching: .any)["morphing-action-panel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 10))
        let sampleImage = app.buttons["hanlin-attach-sample-image"].firstMatch
        for _ in 0..<6 where !sampleImage.isHittable { panel.swipeUp() }
        XCTAssertTrue(sampleImage.isHittable)
        sampleImage.tap()
        let attachment = app.descendants(matching: .any)["hanlin-composer-image-attachment"].firstMatch
        XCTAssertTrue(attachment.waitForExistence(timeout: 5))
        let resize = app.descendants(matching: .any)["hanlin-composer-resize-handle"].firstMatch
        XCTAssertTrue(resize.waitForExistence(timeout: 5))
        let start = resize.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.2, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -70)))
        plus.tap()
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(panel.frame.minY, window.frame.minY - 1)
        XCTAssertLessThanOrEqual(panel.frame.maxY, window.frame.maxY + 1)
        XCTAssertLessThanOrEqual(input.frame.maxY, window.frame.maxY + 1)
        let prompts = app.buttons["hanlin-general-prompts-button"].firstMatch
        for _ in 0..<6 where !prompts.isHittable { panel.swipeUp() }
        XCTAssertTrue(prompts.isHittable)
        prompts.tap()
        let back = app.buttons["hanlin-general-subpage-back"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertTrue(panel.exists, "Internal navigation must retain the panel")
        back.tap()
        XCTAssertTrue(panel.exists)
        plus.tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, draft)
        XCTAssertTrue(attachment.exists)

        let tools = app.buttons["hanlin-composer-tools-direct"].firstMatch
        XCTAssertTrue(tools.waitForExistence(timeout: 5))
        tools.tap()
        let skills = app.buttons["hanlin-tools-open-skills"].firstMatch
        for _ in 0..<6 where !skills.isHittable { panel.swipeUp() }
        XCTAssertTrue(skills.isHittable)
        skills.tap()
        let toolsBack = app.buttons["hanlin-tools-subpage-back"].firstMatch
        XCTAssertTrue(toolsBack.waitForExistence(timeout: 5))
        XCTAssertTrue(panel.exists)
        let manage = app.buttons["hanlin-tools-open-full-skill-center"].firstMatch
        for _ in 0..<6 where !manage.isHittable { panel.swipeUp() }
        XCTAssertTrue(manage.isHittable)
        manage.tap()
        let management = app.descendants(matching: .any)["hanlin-tools-management-skills"].firstMatch
        XCTAssertTrue(management.waitForExistence(timeout: 10))
        app.buttons["hanlin-tools-management-done"].firstMatch.tap()
        XCTAssertTrue(management.waitForNonExistence(timeout: 5))
        toolsBack.tap()
        XCTAssertTrue(skills.waitForExistence(timeout: 5))
        tools.tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, draft)
    }
}
