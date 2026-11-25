import XCTest

/// Exercises the original shipping composer on iPhone and iPad. The optional
/// Catalog & Map descriptor is UI metadata only; these tests never claim a
/// remote model response or tool execution from that descriptor.
@MainActor
final class HanlinComposerCapabilitiesUITests: XCTestCase {
    private var app: XCUIApplication!
    private let calculatorReference = "4:tool13:native.system15:quick_calculate"
    private let fixtureReference = "4:tool20:hanlin.ui.acceptance14:library-region"

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 180
    }

    override func tearDownWithError() throws {
        if let app, app.state == .runningForeground {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = name + "-composer"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            if (testRun?.totalFailureCount ?? 0) > 0 {
                let hierarchy = XCTAttachment(string: app.debugDescription)
                hierarchy.name = name + "-hierarchy"
                hierarchy.lifetime = .keepAlways
                add(hierarchy)
            }
            app.terminate()
        }
        app = nil
    }

    func testMiniAppSelectionAttachesWithoutLaunchingAndEnablesAttachmentOnlySend() throws {
        let input = launch()
        clear(input)
        let activityCount = toolActivities.count
        openBubble()
        tapInBubble(app.buttons["tool-miniApps"].firstMatch)
        let row = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'hanlin-capability-attach-' AND identifier CONTAINS 'miniApp' AND identifier CONTAINS 'nativeapp.sefaria'"
        )).firstMatch
        revealInBubble(row)
        let reference = String(row.identifier.dropFirst("hanlin-capability-attach-".count))
        row.tap()
        let automatic = app.buttons["hanlin-capability-action-automatic-" + reference].firstMatch
        XCTAssertTrue(automatic.waitForExistence(timeout: 5))
        automatic.tap()

        XCTAssertTrue(element("hanlin-capability-configuration").waitForExistence(timeout: 5))
        XCTAssertTrue(element("morphing-action-panel").exists)
        XCTAssertFalse(app.navigationBars["Sefaria"].exists,
                       "Choosing the assistant entrypoint must not open the foreground Sefaria app")
        tapInBubble(app.buttons["hanlin-capability-configuration-done"].firstMatch)
        closeBubble()
        let chip = editChip(reference: reference)
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        XCTAssertTrue(input.exists && input.isHittable,
                      "The original chat editor must remain the active surface")
        XCTAssertEqual(toolActivities.count, activityCount,
                       "Attaching a MiniApp must not start an assistant tool invocation")
        let send = app.buttons["hanlin-chat-send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        XCTAssertTrue(send.isEnabled, "A valid explicit attachment is an outgoing request even without text")
        removeAttachments()
        XCTAssertTrue(send.waitForNonExistence(timeout: 5),
                      "Removing the last attachment must restore the empty composer")
    }

    func testMentionAndSlashPreserveHebrewTextAtTheRealCaretAndInsertTheSameIdentity() throws {
        let input = launch(language: "he", locale: "he_IL")
        clear(input)
        let prefix = "Prefix שלום 🌍 "
        let suffix = " suffix"
        input.typeText(prefix + "@quick_calculate" + suffix)
        for _ in suffix { input.typeKey(XCUIKeyboardKey.leftArrow.rawValue, modifierFlags: []) }
        let suggestion = app.buttons["hanlin-capability-suggestion-" + calculatorReference].firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5),
                      "@ suggestions must follow the actual caret before an existing suffix")
        suggestion.tap()
        expectValue(prefix + suffix, in: input)
        XCTAssertTrue(editChip(reference: calculatorReference).waitForExistence(timeout: 5))
        // Do not tap the editor: UIKit must have retained focus and the requested
        // insertion point after replacing the selected token.
        input.typeText("כאן")
        expectValue(prefix + "כאן" + suffix, in: input)
        removeAttachments()

        clear(input)
        input.typeText("/quick_calculate")
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
        suggestion.tap()
        XCTAssertTrue(editChip(reference: calculatorReference).waitForExistence(timeout: 5),
                      "/ and @ must attach the same provider-scoped identity")
        input.typeText("שלם")
        expectValue("שלם", in: input)
        XCTAssertFalse((input.value as? String ?? "").contains("/quick_calculate"))
        removeAttachments()
    }

    func testManifestCatalogAndMapPanelsKeepUserConfigurationAcrossEditing() throws {
        let input = launch(configurationFixture: true)
        clear(input)
        let activityCount = toolActivities.count
        openBubble()
        tapInBubble(app.buttons["hanlin-composer-open-capabilities"].firstMatch)
        let search = app.textFields["hanlin-capability-search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Composer Catalog & Map")
        let row = app.buttons["hanlin-capability-attach-" + fixtureReference].firstMatch
        tapInBubble(row)

        let tanakh = app.switches["hanlin-capability-option-collections-tanakh"].firstMatch
        let talmud = app.switches["hanlin-capability-option-collections-talmud"].firstMatch
        tapInBubble(talmud)
        tapInBubble(tanakh)
        XCTAssertEqual(talmud.value as? String, "1")
        XCTAssertEqual(tanakh.value as? String, "0")

        selectPanel("Region")
        let map = element("hanlin-capability-location-map")
        revealInBubble(map)
        XCTAssertTrue(map.isHittable)
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.72, dy: 0.32)).tap()
        let latitude = app.textFields["hanlin-capability-input-location.latitude"].firstMatch
        revealInBubble(latitude)
        XCTAssertTrue(latitude.waitForExistence(timeout: 5))
        let pinMoved = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let value = latitude.value as? String, let number = Double(value) else { return false }
            return number >= -90 && number <= 90 && abs(number - 31.78) > 0.00001
        }, object: latitude)
        XCTAssertEqual(XCTWaiter.wait(for: [pinMoved], timeout: 5), .completed,
                       "Tapping the real MapKit surface must update the structured coordinate")
        let selectedLatitude = try XCTUnwrap(latitude.value as? String)
        let radius = app.textFields["hanlin-capability-input-location.radiusMeters"].firstMatch
        revealInBubble(radius)
        replace(radius, with: "1500")
        expectValue("1500", in: radius)
        let mapScreenshot = XCTAttachment(screenshot: app.screenshot())
        mapScreenshot.name = "manifest-map-configured"
        mapScreenshot.lifetime = .keepAlways
        add(mapScreenshot)

        tapInBubble(app.buttons["hanlin-capability-configuration-done"].firstMatch)
        closeBubble()
        let chip = editChip(reference: fixtureReference)
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        XCTAssertTrue(chip.label.contains("Talmud"))
        chip.tap()
        XCTAssertTrue(element("hanlin-capability-configuration").waitForExistence(timeout: 5))
        selectPanel("Catalog")
        revealInBubble(talmud)
        XCTAssertEqual(talmud.value as? String, "1")
        XCTAssertEqual(tanakh.value as? String, "0")
        selectPanel("Region")
        revealInBubble(radius)
        expectValue("1500", in: radius)
        expectValue(selectedLatitude, in: latitude)
        XCTAssertEqual(toolActivities.count, activityCount,
                       "Editing catalog and map configuration must not execute a tool")
        tapInBubble(app.buttons["hanlin-capability-configuration-done"].firstMatch)
        closeBubble()
        removeAttachments()
        XCTAssertFalse(editChip(reference: fixtureReference).exists)
    }

    private var toolActivities: XCUIElementQuery {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'hanlin-agent-activity-'"))
    }

    private func launch(language: String = "en", locale: String = "en_US",
                        configurationFixture: Bool = false) -> XCUIElement {
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_COMPOSER_EDIT_DIAGNOSTICS"] = "1"
        app.launchEnvironment["HANLIN_COMPACT_KEYBOARD_WITNESS"] = "1"
        app.launchEnvironment["HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE"] = "1"
        app.launchEnvironment["HANLIN_DOCK_ACCEPTANCE_FIXTURES"] = "1"
        if configurationFixture {
            app.launchEnvironment["HANLIN_COMPOSER_CAPABILITY_UI_FIXTURES"] = "1"
        }
        app.launch()
        let input = app.textViews.matching(NSPredicate(
            format: "identifier == 'hanlin-chat-input' OR identifier == 'hanlin-composer-surface'"
        )).firstMatch
        if !input.waitForExistence(timeout: 5) {
            let chat = app.descendants(matching: .any).matching(NSPredicate(
                format: "label CONTAINS 'Agent Acceptance Chat' OR identifier CONTAINS 'Agent Acceptance Chat'"
            )).firstMatch
            XCTAssertTrue(chat.waitForExistence(timeout: 15))
            chat.tap()
        }
        XCTAssertTrue(input.waitForExistence(timeout: 20))
        removeAttachments()
        return input
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func editChip(reference: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'hanlin-capability-edit-' AND identifier ENDSWITH %@", reference)).firstMatch
    }

    private func removeAttachments() {
        let buttons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'hanlin-capability-remove-'"))
        for _ in 0..<10 {
            guard buttons.count > 0 else { return }
            let first = buttons.firstMatch
            XCTAssertTrue(first.isHittable)
            first.tap()
        }
        XCTAssertEqual(buttons.count, 0, "The selected capability chips must be removable")
    }

    private func openBubble() {
        let plus = app.buttons["hanlin-composer-general-menu"].firstMatch
        XCTAssertTrue(plus.waitForExistence(timeout: 5))
        plus.tap()
        XCTAssertTrue(element("morphing-action-panel").waitForExistence(timeout: 5))
    }

    private func closeBubble() {
        let plus = app.buttons["hanlin-composer-general-menu"].firstMatch
        XCTAssertTrue(plus.isHittable)
        plus.tap()
        XCTAssertTrue(element("morphing-action-panel").waitForNonExistence(timeout: 5))
    }

    private func selectPanel(_ title: String) {
        let picker = app.buttons["hanlin-capability-panel"].firstMatch
        tapInBubble(picker)
        let option = app.buttons[title].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        option.tap()
    }

    private func tapInBubble(_ control: XCUIElement) {
        revealInBubble(control)
        XCTAssertTrue(control.isHittable, "Unreachable composer control: \(control.identifier)")
        control.tap()
    }

    private func revealInBubble(_ control: XCUIElement) {
        let viewport = app.scrollViews["hanlin-composer-page-scroll"].firstMatch
        XCTAssertTrue(viewport.waitForExistence(timeout: 5))
        for _ in 0..<10 {
            if control.isHittable { return }
            if control.exists && control.frame.midY < viewport.frame.midY {
                viewport.swipeDown()
            } else {
                viewport.swipeUp()
            }
        }
        XCTFail("Composer control did not become reachable: \(control.identifier)")
    }

    private func clear(_ input: XCUIElement) {
        input.tap()
        input.typeKey("a", modifierFlags: .command)
        input.typeText(XCUIKeyboardKey.delete.rawValue)
    }

    private func replace(_ input: XCUIElement, with text: String) {
        clear(input)
        input.typeText(text)
    }

    private func expectValue(_ value: String, in input: XCUIElement) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: input)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed)
    }
}
