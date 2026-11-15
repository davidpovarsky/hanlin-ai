import XCTest

@MainActor
final class MediaReplayUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() { continueAfterFailure = false }
    override func tearDown() {
        if let app { record("final"); app.terminate() }
        app = nil
    }

    func testHistoryYouTubeAllowsOnlyExplicitLocalMedia() throws {
        launch()
        let submit = app.buttons["Submit replay form"].firstMatch
        let input = app.textFields["Replay name"].firstMatch
        XCTAssertTrue(submit.waitForExistence(timeout: 15))
        XCTAssertFalse(submit.isEnabled)
        XCTAssertTrue(input.exists)
        XCTAssertFalse(input.isEnabled)
        XCTAssertFalse(player().exists, "History must not construct an autoplaying player")
        record("history-before-explicit-load")
        source().tap()
        XCTAssertEqual(app.staticTexts["proof-source-result"].label, "https://www.youtube.com/watch?v=M7lc1UVf-VE")
        // A coordinate tap also reaches the real disabled form rather than relying only on AX.
        submit.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["proof-probe"].tap() // Actual retained SDK action and callAgentFunction.
        let noRPC = NSPredicate(format: "label == %@", "NO_LISTENER")
        XCTAssertTrue(wait(noRPC, on: app.staticTexts["proof-probe-result"]))
        let unexpected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", "outbound:0"),
                                                  object: app.staticTexts["proof-outbound"])
        unexpected.isInverted = true
        wait(for: [unexpected], timeout: 1)
        load().tap()
        XCTAssertTrue(player().waitForExistence(timeout: 10))
        XCTAssertFalse(submit.isEnabled)
        XCTAssertEqual(app.staticTexts["proof-outbound"].label, "outbound:0")
        record("history-explicit-player")
    }

    func testHistoryVideoAllowsExplicitLoadAndApprovedSource() { checkNativeHistory("--video") }
    func testHistoryAudioAllowsExplicitLoadAndApprovedSource() { checkNativeHistory("--audio") }

    func testSealingALiveOwnerDoesNotGrantHistoryMediaPermission() {
        launch(live: true)
        load().tap()
        XCTAssertTrue(player().waitForExistence(timeout: 10))
        app.buttons["proof-seal"].tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), on: player()))
        XCTAssertTrue(load().exists)
        XCTAssertFalse(load().isEnabled)
        XCTAssertFalse(source().isEnabled)
        XCTAssertFalse(app.buttons["Submit replay form"].isEnabled)
        record("sealed-live-owner-stays-disabled")
    }

    func testParentDisabledBlocksAndUnloadsEveryMediaBuilder() {
        for kind in ["", "--video", "--audio"] {
            launch(kind)
            load().tap()
            XCTAssertTrue(player().waitForExistence(timeout: 10))
            app.buttons["proof-disable"].tap()
            XCTAssertTrue(wait(NSPredicate(format: "exists == false"), on: player()))
            XCTAssertTrue(load().exists)
            XCTAssertFalse(load().isEnabled)
            XCTAssertFalse(source().isEnabled)
            record("parent-disabled-\(kind)")
            app.buttons["proof-disable"].tap()
            XCTAssertTrue(load().isEnabled)
            XCTAssertFalse(player().exists, "Re-enabling the host must require a fresh user request")
            XCTAssertFalse(app.buttons["Submit replay form"].isEnabled)
        }
    }

    func testBoundURLReplacementUnloadsEveryRequestedPlayer() {
        for kind in ["", "--video", "--audio"] {
            launch(kind, live: true)
            let submit = app.buttons["Submit replay form"]
            XCTAssertTrue(submit.isEnabled, "The positive live control must remain functional")
            submit.tap()
            XCTAssertTrue(wait(NSPredicate(format: "label == %@", "outbound:1"), on: app.staticTexts["proof-outbound"]))
            load().tap()
            XCTAssertTrue(player().waitForExistence(timeout: 10))
            app.buttons["proof-change-source"].tap()
            XCTAssertTrue(wait(NSPredicate(format: "exists == false"), on: player()))
            XCTAssertTrue(load().isEnabled)
            source().tap()
            let expected = kind.isEmpty ? "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
                : "https://media.example.com/second." + (kind == "--video" ? "mp4" : "mp3")
            XCTAssertEqual(app.staticTexts["proof-source-result"].label, expected)
            record("bound-source-replaced-\(kind)")
        }
    }

    func testBackgroundDisappearanceAndDisposalUnloadEveryPlayer() {
        for kind in ["", "--video", "--audio"] {
            launch(kind)
            load().tap()
            XCTAssertTrue(player().waitForExistence(timeout: 10))
            XCUIDevice.shared.press(.home)
            app.activate()
            XCTAssertTrue(load().waitForExistence(timeout: 10))
            XCTAssertFalse(player().exists, "Returning from background requires another explicit request")
            load().tap()
            XCTAssertTrue(player().waitForExistence(timeout: 10))
            app.buttons["proof-hide"].tap()
            XCTAssertTrue(wait(NSPredicate(format: "exists == false"), on: player()))
            app.buttons["proof-hide"].tap()
            XCTAssertTrue(load().waitForExistence(timeout: 10))
            XCTAssertFalse(player().exists)
            load().tap()
            XCTAssertTrue(player().waitForExistence(timeout: 10))
            app.buttons["proof-close"].tap()
            XCTAssertTrue(wait(NSPredicate(format: "exists == false"), on: player()))
            XCTAssertFalse(load().exists)
            XCTAssertFalse(source().exists)
            XCTAssertFalse(app.buttons["Submit replay form"].exists)
            XCTAssertEqual(app.staticTexts["proof-outbound"].label, "outbound:0")
            record("closed-owner-\(kind)")
        }
    }

    private func checkNativeHistory(_ kind: String) {
        launch(kind)
        XCTAssertFalse(player().exists)
        XCTAssertFalse(app.buttons["Submit replay form"].isEnabled)
        XCTAssertTrue(source().isEnabled)
        source().tap()
        let expected = "https://media.example.com/fixture." + (kind == "--video" ? "mp4" : "mp3")
        XCTAssertEqual(app.staticTexts["proof-source-result"].label, expected)
        load().tap()
        XCTAssertTrue(player().waitForExistence(timeout: 10), "The actual official catalog builder did not mount")
        XCTAssertEqual(app.staticTexts["proof-outbound"].label, "outbound:0")
        record("native-history-loaded-\(kind)")
    }
    private func launch(_ kind: String = "", live: Bool = false) {
        app?.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", kind]
        if live { app.launchArguments.append("--live") }
        app.launch()
        XCTAssertTrue(load().waitForExistence(timeout: 20))
    }
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    private func load() -> XCUIElement { element(app.launchArguments.contains("--video") || app.launchArguments.contains("--audio") ? "hanlin-media-load-player" : "hanlin-youtube-load") }
    private func source() -> XCUIElement { element(app.launchArguments.contains("--video") || app.launchArguments.contains("--audio") ? "hanlin-media-source" : "hanlin-youtube-source") }
    private func player() -> XCUIElement { element(app.launchArguments.contains("--video") || app.launchArguments.contains("--audio") ? "hanlin-media-player" : "hanlin-youtube-player") }
    private func wait(_ predicate: NSPredicate, on element: XCUIElement) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 10) == .completed
    }
    private func record(_ name: String) {
        let pixels = XCTAttachment(screenshot: app.screenshot())
        pixels.name = name; pixels.lifetime = .keepAlways; add(pixels)
        let ax = XCTAttachment(string: app.debugDescription)
        ax.name = name + "-AX"; ax.lifetime = .keepAlways; add(ax)
    }
}
