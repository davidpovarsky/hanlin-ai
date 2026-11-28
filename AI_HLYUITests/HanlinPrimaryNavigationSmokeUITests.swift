import XCTest

/// Product navigation accepted by the owner on 2026-11-18. Engine component
/// proofs and installed two-process round trips have separate selectors.
@MainActor
final class HanlinPrimaryNavigationSmokeUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launch()
    }

    override func tearDownWithError() throws { app.terminate() }

    private func item(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func tap(_ identifier: String) {
        let target = item(identifier)
        XCTAssertTrue(target.waitForExistence(timeout: 15), "Missing product control: \(identifier)")
        XCTAssertTrue(target.isHittable, "Product control is not reachable: \(identifier)")
        target.tap()
    }

    private func revealSettings(_ identifier: String) {
        let list = item("hanlin-settings-list")
        for _ in 0..<6 {
            if item(identifier).isHittable { return }
            list.swipeUp()
        }
        XCTFail("Settings entry was not reachable: \(identifier)")
    }

    private func returnToLibrary() {
        let back = app.navigationBars.buttons["Library"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(item("hanlin-personal-library").waitForExistence(timeout: 5))
    }

    func testWholeAppPrimaryNavigationSmoke() throws {
        tap("hanlin-home-tab")
        XCTAssertTrue(app.navigationBars["Hanlin"].firstMatch.waitForExistence(timeout: 15))
        // iPadOS 27 exposes the original top bar as Other with direct Button
        // children; compact layouts may expose a TabBar. Inspect the actual
        // shared container, including unexpected children, not just two queries.
        let destinations: Set<String> = ["hanlin-home-tab", "hanlin-library-tab"]
        let candidates = app.descendants(matching: .any)
            .containing(.button, identifier: "hanlin-home-tab")
            .containing(.button, identifier: "hanlin-library-tab")
            .allElementsBoundByIndex
        let primary = try XCTUnwrap(candidates.first { container in
            let identifiers = Set(container.children(matching: .button).allElementsBoundByIndex.map(\.identifier))
            return destinations.isSubset(of: identifiers)
        }, "The original Chat and Library controls must share a primary navigation container")
        let permanentButtons = primary.children(matching: .button)
        XCTAssertEqual(permanentButtons.count, 2, "Chat and Library are the only permanent destinations")
        XCTAssertEqual(Set(permanentButtons.allElementsBoundByIndex.map(\.identifier)), destinations)
        for legacy in ["hanlin-vision-tab", "hanlin-models-tab", "hanlin-apps-tab", "hanlin-settings-tab"] {
            XCTAssertFalse(primary.descendants(matching: .button)[legacy].exists, "Contextual entry unexpectedly became a permanent tab")
        }

        tap("hanlin-library-tab")
        XCTAssertTrue(item("hanlin-personal-library").waitForExistence(timeout: 10))
        for key in ["knowledge", "memory", "prompts", "canvas", "saved"] {
            XCTAssertTrue(item("hanlin-library-" + key).exists)
        }

        tap("hanlin-library-knowledge")
        XCTAssertTrue(item("hanlin-knowledge-list").waitForExistence(timeout: 10))
        tap("hanlin-library-knowledge-done")
        tap("hanlin-library-memory")
        XCTAssertTrue(item("hanlin-memory-archive").waitForExistence(timeout: 10))
        returnToLibrary()
        tap("hanlin-library-prompts")
        XCTAssertTrue(item("hanlin-prompt-library").waitForExistence(timeout: 10))
        returnToLibrary()
        tap("hanlin-library-canvas")
        XCTAssertTrue(item("hanlin-canvas-library").waitForExistence(timeout: 10))
        returnToLibrary()
        tap("hanlin-library-saved")
        XCTAssertTrue(app.navigationBars["Saved messages"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Done"].firstMatch.tap()

        tap("hanlin-settings-tab")
        XCTAssertTrue(item("hanlin-settings-list").waitForExistence(timeout: 10))
        revealSettings("hanlin-models-tab")
        tap("hanlin-models-tab")
        XCTAssertTrue(item("hanlin-models-list").waitForExistence(timeout: 10))
        tap("hanlin-models-done")
        revealSettings("hanlin-mcp-servers-link")
        XCTAssertTrue(item("hanlin-mcp-servers-link").isHittable)
        revealSettings("hanlin-skill-center-link")
        XCTAssertTrue(item("hanlin-skill-center-link").isHittable)
        tap("hanlin-profile-done")

        tap("hanlin-workspace-actions")
        tap("hanlin-vision-tab")
        let missingModel = app.alerts.firstMatch
        if missingModel.waitForExistence(timeout: 5) {
            missingModel.buttons.firstMatch.tap()
        } else {
            tap("hanlin-vision-close")
        }
        XCTAssertTrue(item("hanlin-personal-library").waitForExistence(timeout: 10))

        // This fresh, AI-only simulator deliberately has no companion installed.
        // A missing companion must preserve the original workspace and explain it.
        tap("hanlin-workspace-actions")
        tap("hanlin-open-miniapps")
        let missingCompanion = app.alerts["MiniApps unavailable"].firstMatch
        XCTAssertTrue(missingCompanion.waitForExistence(timeout: 10))
        missingCompanion.buttons["OK"].tap()
        XCTAssertTrue(item("hanlin-personal-library").exists)
        tap("hanlin-home-tab")
        XCTAssertTrue(app.navigationBars["Hanlin"].firstMatch.waitForExistence(timeout: 10))
    }
}
