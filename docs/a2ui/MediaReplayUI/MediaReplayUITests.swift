import XCTest

@MainActor
final class MediaReplayUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() { continueAfterFailure = false }

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
        recordHostContinuity("live-before-player")
        load().tap()
        XCTAssertTrue(player().waitForExistence(timeout: 10))
        recordHostContinuity("live-with-player")
        app.buttons["proof-seal"].tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), on: player()))
        XCTAssertTrue(load().exists)
        XCTAssertFalse(load().isEnabled)
        XCTAssertFalse(source().isEnabled)
        XCTAssertFalse(app.buttons["Submit replay form"].isEnabled)
        record("sealed-live-owner-stays-disabled")
        recordHostContinuity("sealed-before-host-action")
        // Existing host control, outside the Surface: a real interaction and actual
        // changed receipt distinguish host liveness/redraw from an AX-only assertion.
        app.buttons["proof-probe"].tap()
        XCTAssertTrue(wait(NSPredicate(format: "label == %@", "NO_LISTENER"), on: app.staticTexts["proof-probe-result"]))
        XCTAssertEqual(app.staticTexts["proof-outbound"].label, "outbound:0")
        recordHostContinuity("sealed-after-host-action")
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
            let unloaded = wait(NSPredicate(format: "exists == false"), on: player())
            if !unloaded {
                // The real Link reads the same resolved node URL as the gate. Capture
                // its actual openURL receipt to distinguish stale binding from teardown.
                source().tap()
                record("source-replacement-unload-failed-\(kind)")
            }
            XCTAssertTrue(unloaded)
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
        if app == nil {
            addTeardownBlock { @MainActor [weak self] () async throws in
                guard let self, let app = self.app else { return }
                self.record("final"); app.terminate(); self.app = nil
            }
        }
        app?.terminate()
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", kind]
        if live { app.launchArguments.append("--live") }
        app.launch()
        XCTAssertTrue(load().waitForExistence(timeout: 20))
    }
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    // Official Surface assigns a2ui-root to descendants in the actual AX tree. Resolve the
    // real semantic controls by type/label; do not force taps through a duplicate identifier.
    private var nativeMedia: Bool { app.launchArguments.contains("--video") || app.launchArguments.contains("--audio") }
    private func load() -> XCUIElement { app.buttons[nativeMedia ? "Load media player" : "Load YouTube player"].firstMatch }
    private func source() -> XCUIElement { app.links[nativeMedia ? "Open media source" : "Open in YouTube"].firstMatch }
    private func player() -> XCUIElement {
        nativeMedia ? app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Media player'")).firstMatch
            : app.webViews.firstMatch
    }
    private func wait(_ predicate: NSPredicate, on element: XCUIElement) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 10) == .completed
    }
    private func record(_ name: String) {
        let pixels = XCTAttachment(screenshot: app.screenshot())
        pixels.name = name; pixels.lifetime = .keepAlways; add(pixels)
        let ax = XCTAttachment(string: app.debugDescription)
        ax.name = name + "-AX"; ax.lifetime = .keepAlways; add(ax)
    }

    /// Visual diagnostic, not an automatic pixel-pass assertion. Capture the same
    /// state through independent providers and bounded element rectangles, with no
    /// sleep/coordinate action, so crop/render/capture differences remain observable.
    private func recordHostContinuity(_ phase: String) {
        let header = app.staticTexts["proof-outbound"]
        let receipt = app.staticTexts["proof-probe-result"]
        let probe = app.buttons["proof-probe"]
        let window = app.windows.firstMatch
        XCTAssertTrue(header.exists)
        XCTAssertTrue(receipt.exists)
        XCTAssertTrue(probe.isHittable)
        func attach(_ screenshot: XCUIScreenshot, _ provider: String) {
            let pixels = XCTAttachment(screenshot: screenshot)
            pixels.name = "continuity-\(phase)-\(provider)"
            pixels.lifetime = .keepAlways
            add(pixels)
        }
        attach(app.screenshot(), "app-first")
        attach(XCUIScreen.main.screenshot(), "screen")
        attach(window.screenshot(), "window")
        attach(header.screenshot(), "header-element")
        attach(receipt.screenshot(), "receipt-element")
        attach(app.screenshot(), "app-again")
        let metadata = XCTAttachment(string: """
        phase=\(phase)
        applicationState=\(String(describing: app.state))
        appFrame=\(app.frame)
        windowFrame=\(window.frame)
        headerFrame=\(header.frame) label=\(header.label) hittable=\(header.isHittable)
        receiptFrame=\(receipt.frame) label=\(receipt.label) hittable=\(receipt.isHittable)
        probeFrame=\(probe.frame) hittable=\(probe.isHittable)
        AX=\(app.debugDescription)
        """)
        metadata.name = "continuity-\(phase)-frames-AX"
        metadata.lifetime = .keepAlways
        add(metadata)
    }
}
