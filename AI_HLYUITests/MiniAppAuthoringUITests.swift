import XCTest

/// Both shipping products and the original compiler/tools run on the same
/// disposable simulator. Only the model HTTP response is deterministic.
@MainActor
final class MiniAppAuthoringUITests: XCTestCase {
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
        for (name, app) in [("Hanlin AI", ai), ("MiniApps", mini)] {
            if app.state == .runningForeground {
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = name + " authoring"; screenshot.lifetime = .keepAlways; add(screenshot)
                if testRun?.hasSucceeded == false {
                    let tree = XCTAttachment(string: app.debugDescription)
                    tree.name = name + " authoring accessibility"; tree.lifetime = .keepAlways; add(tree)
                }
            }
            if app.state != .notRunning { app.terminate() }
        }
    }

    func testMalformedArchiveShowsOriginalImportDiagnostic() {
        mini.launch()
        importPackage("InvalidMiniApp")
        XCTAssertTrue(item(mini, "hanlin-import-diagnostics-sheet").waitForExistence(timeout: 30))
        let originalError = mini.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@", "PACKAGE_IMPORT")).firstMatch
        reveal(originalError, in: item(mini, "hanlin-import-diagnostics-sheet"))
        XCTAssertTrue(originalError.exists)
        XCTAssertTrue(mini.buttons["hanlin-import-repair-agent"].isEnabled)
        XCTAssertTrue(mini.buttons["hanlin-import-diagnostics-copy"].exists)
    }

    func testTypeErrorRepairsThroughOriginalAgentBuildAndCompanionImport() throws {
        ai.launchEnvironment["HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE"] = "1"
        ai.launchEnvironment["HANLIN_MINIAPP_AUTHORING_ACCEPTANCE"] = "1"
        ai.launchEnvironment["HANLIN_PHASE2_STORE_ID"] = UUID().uuidString
        ai.launchEnvironment["HANLIN_COMPOSER_EDIT_DIAGNOSTICS"] = "1"
        ai.launchEnvironment["HANLIN_COMPACT_KEYBOARD_WITNESS"] = "1"
        ai.launch()
        // Wait for the actual prepared original account, then let the repair URL
        // create its own conversation through the shipping application context.
        let ready = ai.buttons["hanlin-settings-tab"].firstMatch
        XCTAssertTrue(ready.waitForExistence(timeout: 45))

        mini.launch()
        importPackage("MiniAppTypeError")
        XCTAssertTrue(item(mini, "hanlin-import-diagnostics-sheet").waitForExistence(timeout: 90))
        let typeError = mini.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@", "TS2322", "Line 1")).firstMatch
        reveal(typeError, in: item(mini, "hanlin-import-diagnostics-sheet"))
        XCTAssertTrue(typeError.exists, "The real compiler must report the original source position.")
        let diagnosticImage = XCTAttachment(screenshot: mini.screenshot())
        diagnosticImage.name = "MiniApp original TypeScript diagnostics"
        diagnosticImage.lifetime = .keepAlways
        add(diagnosticImage)
        let sheet = item(mini, "hanlin-import-diagnostics-sheet")
        let fix = mini.buttons["hanlin-import-repair-agent"].firstMatch
        for _ in 0..<8 {
            if fix.isHittable { break }
            sheet.swipeDown()
        }
        tap(fix)
        XCTAssertTrue(ai.wait(for: .runningForeground, timeout: 30))
        XCTAssertFalse(ai.alerts["MiniApp repair unavailable"].exists)
        let request = ai.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "[MiniApp repair ")).firstMatch
        XCTAssertTrue(request.waitForExistence(timeout: 45),
                      "The original composer must persist the repair request.")

        // Actual tool calls correct the source, validate, build and open MiniApps.
        XCTAssertTrue(mini.wait(for: .runningForeground, timeout: 180))
        let importer = mini.buttons["hanlin-file-importer"].firstMatch
        XCTAssertTrue(importer.waitForExistence(timeout: 90),
                      "The real companion installer did not finish the corrected archive.")
        XCTAssertFalse(item(mini, "hanlin-import-error-message").exists)
        XCTAssertFalse(item(mini, "hanlin-import-diagnostics-sheet").exists)
        if mini.navigationBars["Script Package"].buttons["Done"].exists {
            mini.navigationBars["Script Package"].buttons["Done"].tap()
        }
        if mini.buttons["hanlin-apps-add-done"].exists { mini.buttons["hanlin-apps-add-done"].tap() }
        let search = mini.searchFields["Search Apps"].firstMatch
        if !search.isHittable { mini.swipeDown() }
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        tap(search); search.typeText("MiniApp Authoring Acceptance")
        let card = mini.buttons["hanlin-package-card-MiniApp Authoring Acceptance"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 30))
        tap(card)
        XCTAssertTrue(mini.staticTexts["miniapp-authoring-result"].waitForExistence(timeout: 45))
        XCTAssertEqual(mini.staticTexts["miniapp-authoring-result"].label, "MiniApp repair result 42")
        let repairedImage = XCTAttachment(screenshot: mini.screenshot())
        repairedImage.name = "MiniApp repaired native result"
        repairedImage.lifetime = .keepAlways
        add(repairedImage)

        ai.activate()
        let completed = ai.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "MINIAPP_AUTHORING_INSTALLED_VERIFIED")).firstMatch
        XCTAssertTrue(completed.waitForExistence(timeout: 90),
                      "The agent must read an actual installed receipt after the OS handoff.")
        XCTAssertFalse(ai.buttons["hanlin-tool-consent-allow-once"].exists)
    }

    private func importPackage(_ name: String) {
        tap(mini.buttons["hanlin-apps-add"].firstMatch)
        tap(mini.buttons["hanlin-import-script-package"].firstMatch)
        let file = mini.buttons[name].firstMatch
        let list = item(mini, "hanlin-package-import-list")
        XCTAssertTrue(list.waitForExistence(timeout: 20))
        reveal(file, in: list)
        tap(file)
    }

    private func reveal(_ element: XCUIElement, in container: XCUIElement) {
        for _ in 0..<10 {
            if element.exists && element.isHittable { break }
            container.swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: 15))
    }

    private func item(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(
            format: "exists == true AND enabled == true AND hittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed, file: file, line: line)
        element.tap()
    }
}
