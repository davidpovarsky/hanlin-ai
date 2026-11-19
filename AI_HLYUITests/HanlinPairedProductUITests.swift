import XCTest

/// Both unmodified product targets must be installed with their existing App
/// Group on the same owned simulator. Only the model's HTTP response is scripted.
@MainActor
final class HanlinPairedProductUITests: XCTestCase {
    private let ai = XCUIApplication(bundleIdentifier: "com.itorah.chavrusachat")
    private let mini = XCUIApplication(bundleIdentifier: "com.itorah.hanlinminiapps")

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 600
        for app in [ai, mini] {
            app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        }
    }

    override func tearDownWithError() throws {
        for (name, app) in [("AI", ai), ("MiniApps", mini)] {
            if app.state != .notRunning {
                let picture = XCTAttachment(screenshot: app.screenshot())
                picture.name = name + "-paired-product"; picture.lifetime = .keepAlways; add(picture)
                if testRun?.hasSucceeded == false {
                    let tree = XCTAttachment(string: app.debugDescription)
                    tree.name = name + "-paired-accessibility"; tree.lifetime = .keepAlways; add(tree)
                }
            }
            app.terminate()
        }
    }

    func testCompanionReturnsActualPrivateValueToOriginalChat() throws {
        let nonce = UUID().uuidString
        let originalChat = try beginOriginalRequest("PAIRED_OPEN_" + nonce)
        let name = mini.textFields["Name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 30))
        replace(name, with: "PAIRED_VALUE_" + nonce)
        tap(mini, "Save")
        XCTAssertTrue(mini.staticTexts["Saved in canonical private container"].waitForExistence(timeout: 15))
        tap(mini, "miniapps.return-to-origin")
        XCTAssertTrue(ai.wait(for: .runningForeground, timeout: 30))
        assertText(ai, "PAIRED_RETURN_VERIFIED_" + nonce)
        XCTAssertEqual(ai.staticTexts["hanlin-phase2-chat-id"].label, originalChat)
        XCTAssertFalse(ai.alerts["Mini App result unavailable"].exists)
        XCTAssertFalse(ai.buttons["hanlin-tool-consent-allow-once"].exists)
    }

    func testCompanionCancellationReturnsWithoutChangingPrivateState() throws {
        let nonce = UUID().uuidString
        let originalChat = try beginOriginalRequest("PAIRED_CANCEL_" + nonce)
        let name = mini.textFields["Name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 30))
        let before = name.value as? String
        tap(mini, "Cancel")
        XCTAssertTrue(ai.wait(for: .runningForeground, timeout: 30))
        assertText(ai, "PAIRED_CANCEL_RETURN_" + nonce)
        XCTAssertEqual(ai.staticTexts["hanlin-phase2-chat-id"].label, originalChat)
        mini.terminate(); mini.launch()
        tap(mini, "hanlin-miniapp-hanlin.demo.swift-parity")
        tap(mini, "hanlin-miniapps-open")
        XCTAssertTrue(name.waitForExistence(timeout: 15))
        XCTAssertEqual(name.value as? String, before)
    }

    func testOriginalPackageAndSavedStateTransferThenRollback() throws {
        // Establish real source state through the original importer and runtime.
        // The legacy host is an existing engine component probe, not new product navigation.
        ai.launchEnvironment["HANLIN_SCRIPTUI_E2E"] = "1"
        ai.launch()
        tap(ai, "hanlin-apps-add")
        tap(ai, "hanlin-import-script-package")
        tap(ai, "HanlinTransferAcceptance")
        let install = ai.buttons["hanlin-package-install"].firstMatch
        XCTAssertTrue(install.waitForExistence(timeout: 30) && install.isEnabled)
        install.tap()
        XCTAssertTrue(install.waitForNonExistence(timeout: 60))
        ai.terminate(); ai.launch()
        openOriginalPackage(named: "Hanlin Transfer Acceptance")
        XCTAssertTrue(ai.staticTexts["Not saved"].waitForExistence(timeout: 30))
        tap(ai, "Save transfer value")
        assertText(ai, "Saved by the original ScriptUI runtime")
        ai.terminate()
        ai.launchEnvironment.removeValue(forKey: "HANLIN_SCRIPTUI_E2E")
        ai.launch()

        // Use the shipping Profile -> Transfer flow, then the real companion wake.
        tap(ai, "hanlin-settings-tab")
        reveal(ai, identifier: "hanlin-transfer-link", container: "hanlin-settings-list")
        tap(ai, "hanlin-transfer-link")
        tap(ai, "hanlin-transfer-prepare")
        assertText(ai, "Copy ready. Open Hanlin MiniApps and choose Transfer from Hanlin.")
        tap(ai, "hanlin-transfer-open-companion")
        XCTAssertTrue(mini.wait(for: .runningForeground, timeout: 30))
        tap(mini, "hanlin-miniapps-transfer")
        tap(mini, "hanlin-transfer-import")
        assertText(mini, "Transfer complete. Your mini apps are ready.")
        mini.terminate(); mini.launch()
        let imported = mini.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH 'hanlin-miniapp-' AND label CONTAINS %@", "Hanlin Transfer Acceptance")).firstMatch
        XCTAssertTrue(imported.waitForExistence(timeout: 30))
        imported.tap(); tap(mini, "hanlin-miniapps-open")
        assertText(mini, "Saved by the original ScriptUI runtime")

        // Fresh process guarantees every old runtime owner has finished before rollback.
        mini.terminate(); mini.launch()
        tap(mini, "hanlin-miniapps-transfer")
        tap(mini, "hanlin-transfer-rollback")
        tap(mini, "Restore previous data")
        assertText(mini, "Previous data restored. The original copy in Hanlin is unchanged.")
        mini.terminate(); mini.launch()
        XCTAssertTrue(item(mini, "hanlin-miniapps-management").waitForExistence(timeout: 30))
        XCTAssertFalse(imported.exists, "Rollback must restore the actual pre-transfer catalog")

        ai.terminate(); ai.launchEnvironment["HANLIN_SCRIPTUI_E2E"] = "1"; ai.launch()
        openOriginalPackage(named: "Hanlin Transfer Acceptance")
        assertText(ai, "Saved by the original ScriptUI runtime")
    }

    private func openOriginalPackage(named name: String) {
        // The original hub puts ScriptUI below the lazy Swift catalog. Reveal the
        // installed card through its shipping search before testing its state.
        let search = ai.searchFields["Search Apps"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 30))
        tap(ai, "Search Apps")
        search.typeText(name)
        let filtered = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", name), object: search)
        XCTAssertEqual(XCTWaiter.wait(for: [filtered], timeout: 10), .completed,
                       "The original catalog must apply the exact package search")
        tap(ai, "hanlin-package-card-\(name)")
    }

    private func beginOriginalRequest(_ prompt: String) throws -> String {
        // Publish the real companion catalog before the original Host resolves it.
        mini.launch()
        XCTAssertTrue(item(mini, "hanlin-miniapp-hanlin.demo.swift-parity").waitForExistence(timeout: 45))
        mini.terminate()
        ai.launchEnvironment["HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE"] = "1"
        ai.launchEnvironment["HANLIN_PHASE2_STORE_ID"] = UUID().uuidString
        ai.launch()
        // Compact Home has its own persistent composer. Select the original
        // seeded conversation explicitly before recording its durable identity.
        let home = ai.buttons["hanlin-compact-view-all-button"].firstMatch
        if home.waitForExistence(timeout: 10) {
            let recent = ai.buttons["hanlin-compact-recent-row-0"].firstMatch
            XCTAssertTrue(recent.waitForExistence(timeout: 10))
            XCTAssertTrue(recent.label.contains("Agent Acceptance Chat"))
            recent.tap()
        } else if !ai.staticTexts["hanlin-phase2-chat-id"].exists {
            let chat = ai.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Agent Acceptance Chat")).firstMatch
            XCTAssertTrue(chat.waitForExistence(timeout: 20)); chat.tap()
        }
        XCTAssertTrue(input().waitForExistence(timeout: 20))
        let identity = ai.staticTexts["hanlin-phase2-chat-id"].firstMatch
        XCTAssertTrue(identity.waitForExistence(timeout: 10))
        let originalChat = identity.label
        XCTAssertNotNil(UUID(uuidString: originalChat))
        input().tap(); input().typeText(prompt)
        tap(ai, "hanlin-chat-send")
        tap(ai, "hanlin-tool-consent-allow-once")
        XCTAssertTrue(mini.wait(for: .runningForeground, timeout: 45))
        XCTAssertTrue(mini.buttons["miniapps.return-to-origin"].waitForExistence(timeout: 30))
        return originalChat
    }

    private func input() -> XCUIElement {
        let field = ai.textFields["hanlin-chat-input"].firstMatch
        return field.exists ? field : ai.textViews["hanlin-chat-input"].firstMatch
    }

    private func item(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func tap(_ app: XCUIApplication, _ id: String) {
        let element = item(app, id)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(
            format: "exists == true AND enabled == true AND hittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 45), .completed, "Unreachable product control: \(id)")
        element.tap()
    }

    private func replace(_ field: XCUIElement, with value: String) {
        field.tap()
        let previous = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + value)
    }

    private func assertText(_ app: XCUIApplication, _ value: String) {
        let text = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@", value, value)).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 60), "Missing actual product result: \(value)")
    }

    private func reveal(_ app: XCUIApplication, identifier: String, container: String) {
        for _ in 0..<8 {
            if item(app, identifier).isHittable { return }
            item(app, container).swipeUp()
        }
        XCTFail("Product entry was not reachable: \(identifier)")
    }
}
