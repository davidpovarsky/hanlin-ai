import XCTest

/// Actual imported NativeScript UI and real scene URLs. The bridge helper only
/// stages incoming requests; it independently verifies the results after XCTest.
@MainActor
final class MiniAppsNativeScriptWindowUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.itorah.hanlinminiapps")
    private var openedRequests: [NativeScriptWindowUIInteractions.Request] = []
    private static var fixtureInstalled = false
    private let packageName = "Hanlin NativeScript Window Factory E2E"
    private let requests = [
        "alpha": "1e23a001-6a2c-4c0f-b001-202611240001",
        "beta": "1e23a002-6a2c-4c0f-b002-202611240002",
        "gamma": "1e23a003-6a2c-4c0f-b003-202611240003",
        "delta": "1e23a004-6a2c-4c0f-b004-202611240004",
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 360
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launch()
    }

    override func tearDown() async throws {
        await MainActor.run {
            if testRun?.hasSucceeded == false {
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = "native-window-failure"
                screenshot.lifetime = .keepAlways
                add(screenshot)
                let tree = XCTAttachment(string: app.debugDescription)
                tree.name = "native-window-accessibility"
                tree.lifetime = .keepAlways
                add(tree)
                NativeScriptWindowUIInteractions.closeFailedRequestWindows(in: app, requests: openedRequests)
            }
            app.terminate()
        }
    }

    func testTwoNativeWindowsCompleteInReverseOrderWithoutContextMixing() throws {
        // XCTest's synchronous setup hook is nonisolated; fixture work stays
        // in this test's MainActor context after the original app launch.
        installFixtureIfNeeded()
        let alpha = try open("alpha")
        editAndPrepare(alpha, name: "alpha", increments: 1)
        capture("native-window-alpha-prepared")

        let beta = try open("beta")
        editAndPrepare(beta, name: "beta", increments: 2)
        capture("native-window-beta-prepared-with-alpha-live")
        complete(beta)
        capture("native-window-beta-result-before-alpha")
        closeCompleted(beta)

        let survivingAlpha = try focus("alpha")
        assertValue(survivingAlpha.textViews["hanlin-ns-window-input"], equals: "alpha-edited")
        assertLabel(survivingAlpha.staticTexts["hanlin-ns-window-counter"], equals: "1")
        assertLabel(survivingAlpha.staticTexts["hanlin-ns-window-status"], equals: "Prepared")
        survivingAlpha.buttons["hanlin-ns-window-increment"].tap()
        assertLabel(survivingAlpha.staticTexts["hanlin-ns-window-counter"], equals: "2")
        // Return the closure prepared before beta existed. It must still carry
        // alpha's original request/document and counter=1, not current globals.
        complete(survivingAlpha)
        capture("native-window-alpha-result-after-beta-closed")
        closeCompleted(survivingAlpha)
    }

    func testCancellingOneNativeWindowKeepsOtherWindowAndPreparedCallbackAlive() throws {
        // XCTest's synchronous setup hook is nonisolated; fixture work stays
        // in this test's MainActor context after the original app launch.
        installFixtureIfNeeded()
        let gamma = try open("gamma")
        editAndPrepare(gamma, name: "gamma", increments: 1)
        let delta = try open("delta")
        editAndPrepare(delta, name: "delta", increments: 1)
        capture("native-window-delta-prepared-with-gamma-live")

        let cancellingGamma = try focus("gamma")
        cancellingGamma.buttons["miniapps.external.cancel"].tap()
        XCTAssertTrue(cancellingGamma.staticTexts["Cancelled"].waitForExistence(timeout: 20))
        capture("native-window-gamma-cancelled-delta-live")
        closeCompleted(cancellingGamma)

        let survivingDelta = try focus("delta")
        assertValue(survivingDelta.textViews["hanlin-ns-window-input"], equals: "delta-edited")
        assertLabel(survivingDelta.staticTexts["hanlin-ns-window-counter"], equals: "1")
        assertLabel(survivingDelta.staticTexts["hanlin-ns-window-status"], equals: "Prepared")
        survivingDelta.buttons["hanlin-ns-window-increment"].tap()
        assertLabel(survivingDelta.staticTexts["hanlin-ns-window-counter"], equals: "2")
        complete(survivingDelta)
        capture("native-window-delta-result-after-gamma-cancelled")
        closeCompleted(survivingDelta)
    }

    private func open(_ name: String) throws -> XCUIElement {
        let window = try focus(name)
        assertLabel(window.staticTexts["hanlin-ns-window-status"], equals: "Ready", timeout: 90)
        assertValue(window.textViews["hanlin-ns-window-input"], equals: name)
        assertLabel(window.staticTexts["hanlin-ns-window-counter"], equals: "0")
        return window
    }

    private func focus(_ name: String) throws -> XCUIElement {
        let id = try XCTUnwrap(requests[name])
        app.open(try XCTUnwrap(URL(string: "hanlinminiapps://x-callback-url/run?request=" + id)))
        let window = app.windows.containing(.navigationBar, identifier: "NativeScript window " + name).firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 60), "The incoming request must open/focus its own actual iPad scene.")
        if !openedRequests.contains(where: { $0.id == id }) {
            openedRequests.append(.init(id: id, title: "NativeScript window " + name))
        }
        let requestID = try XCTUnwrap(UUID(uuidString: id))
        assertLabel(window.staticTexts["hanlin-ns-window-request"], equals: requestID.uuidString, timeout: 90)
        return window
    }

    private func editAndPrepare(_ window: XCUIElement, name: String, increments: Int) {
        for _ in 0..<increments { window.buttons["hanlin-ns-window-increment"].tap() }
        assertLabel(window.staticTexts["hanlin-ns-window-counter"], equals: String(increments))
        let input = window.textViews["hanlin-ns-window-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        XCTAssertTrue(input.isHittable)
        NativeScriptWindowUIInteractions.append("-edited", to: input)
        assertValue(input, equals: name + "-edited")
        let prepare = window.buttons["hanlin-ns-window-prepare-return"]
        XCTAssertTrue(prepare.isHittable)
        prepare.tap()
        assertLabel(window.staticTexts["hanlin-ns-window-status"], equals: "Prepared")
    }

    private func complete(_ window: XCUIElement) {
        let complete = window.buttons["hanlin-ns-window-return"]
        XCTAssertTrue(complete.waitForExistence(timeout: 15))
        XCTAssertTrue(complete.isHittable)
        complete.tap()
        XCTAssertTrue(window.staticTexts["Result saved"].waitForExistence(timeout: 30),
                      "The original Host must persist the real engine's completion.")
        XCTAssertFalse(window.staticTexts["Cancelled"].exists)
    }

    private func closeCompleted(_ window: XCUIElement) {
        let close = window.buttons["miniapps.external.cancel"]
        XCTAssertTrue(close.waitForExistence(timeout: 15))
        close.tap()
        XCTAssertTrue(window.waitForNonExistence(timeout: 15),
                      "The request-bound navigation content must leave this scene.")
        XCTAssertTrue(app.buttons["hanlin-apps-add"].firstMatch.waitForExistence(timeout: 20),
                      "Closing this invocation must return its own scene to the catalog.")
    }

    private func assertLabel(_ element: XCUIElement, equals value: String, timeout: TimeInterval = 15) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout))
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: timeout), .completed)
    }

    private func assertValue(_ element: XCUIElement, equals value: String) {
        XCTAssertTrue(element.waitForExistence(timeout: 15))
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 15), .completed)
    }

    private func installFixtureIfNeeded() {
        if Self.fixtureInstalled { return }
        let card = app.buttons["hanlin-package-card-" + packageName].firstMatch
        if card.exists { Self.fixtureInstalled = true; return }
        let addApp = app.buttons["hanlin-apps-add"].firstMatch
        XCTAssertTrue(addApp.waitForExistence(timeout: 40))
        addApp.tap()
        let importPackage = app.buttons["hanlin-import-script-package"].firstMatch
        XCTAssertTrue(importPackage.waitForExistence(timeout: 15))
        importPackage.tap()
        let packages = app.collectionViews["hanlin-package-import-list"].firstMatch
        XCTAssertTrue(packages.waitForExistence(timeout: 15))
        let archive = app.buttons["window-factory"].firstMatch
        for _ in 0..<8 {
            if archive.exists && archive.isHittable { break }
            packages.swipeUp()
        }
        XCTAssertTrue(archive.exists && archive.isHittable)
        archive.tap()
        let install = app.buttons["hanlin-package-install"].firstMatch
        XCTAssertTrue(install.waitForExistence(timeout: 30))
        XCTAssertTrue(install.isEnabled)
        install.tap()
        XCTAssertTrue(install.waitForNonExistence(timeout: 60), "The original package installer must finish.")
        let done = app.buttons["hanlin-package-import-done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 15))
        done.tap()
        let closeAdd = app.buttons["hanlin-apps-add-done"].firstMatch
        XCTAssertTrue(closeAdd.waitForExistence(timeout: 15))
        closeAdd.tap()
        for _ in 0..<8 {
            if card.exists && card.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        Self.fixtureInstalled = true
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}


// Shared real-input actions for both NativeScript acceptance suites.
@MainActor
enum NativeScriptWindowUIInteractions {
    struct Request {
        let id: String
        let title: String
    }

    static func append(_ suffix: String, to input: XCUIElement) {
        input.tap()
        // The original 4b772 run's AX snapshots contain "-editedgamma" and
        // "-editedalpha": a center tap put the native caret at the beginning.
        // Use the public iPad hardware-key event to move to the end of this
        // one-line value, then preserve the same real edit and exact assertion.
        input.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: .command)
        input.typeText(suffix)
    }

    static func closeFailedRequestWindows(in app: XCUIApplication, requests: [Request]) {
        // Called only after preserving failure screenshot and AX evidence.
        // Touch only request scenes this exact test actually opened.
        for request in requests.reversed() {
            let window = app.windows.containing(.navigationBar, identifier: request.title).firstMatch
            guard window.exists,
                  let url = URL(string: "hanlinminiapps://x-callback-url/run?request=" + request.id)
            else { continue }
            app.open(url)
            let close = window.buttons["miniapps.external.cancel"]
            guard close.waitForExistence(timeout: 5), close.isHittable else { continue }
            close.tap()
            if window.waitForNonExistence(timeout: 3) { continue }
            // An unfinished request first persists cancellation. The remaining
            // native Close control then returns only that request's scene.
            if close.waitForExistence(timeout: 5), close.isHittable {
                close.tap()
                _ = window.waitForNonExistence(timeout: 5)
            }
        }
    }
}
