import XCTest

@MainActor
final class MotionUITests: XCTestCase {
    private var app: XCUIApplication!
    private var originalReduceMotion: Bool?

    override func tearDown() async throws {
        if let originalReduceMotion {
            setSystemReduceMotion(originalReduceMotion)
        }
    }

    private func setSystemReduceMotion(_ enabled: Bool) {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.activate()
        let toggle = settings.switches["Reduce Motion"]
        if !toggle.waitForExistence(timeout: 2) {
            let accessibility = settings.staticTexts["Accessibility"].firstMatch
            for _ in 0..<6 {
                if accessibility.exists && accessibility.isHittable { break }
                if settings.tables.firstMatch.exists { settings.tables.firstMatch.swipeUp() }
                else { settings.swipeUp() }
            }
            XCTAssertTrue(accessibility.waitForExistence(timeout: 5))
            accessibility.tap()
            let motion = settings.staticTexts["Motion"].firstMatch
            XCTAssertTrue(motion.waitForExistence(timeout: 5)); motion.tap()
        }
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let wasEnabled = (toggle.value as? String) == "1"
        if originalReduceMotion == nil { originalReduceMotion = wasEnabled }
        if wasEnabled != enabled { toggle.tap() }
        app.activate()
    }

    override func setUp() async throws {
        continueAfterFailure = false
        originalReduceMotion = nil
        app = XCUIApplication()
        app.launchArguments = ["--reset-motion", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["proof-thinking"].waitForExistence(timeout: 10))
    }

    private func waitForGeometry(_ value: String, timeout: TimeInterval = 5) {
        let state = app.staticTexts["proof-geometry-state"]
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", value), object: state)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
    }

    private func selectPreset(_ title: String, id: String) {
        app.buttons["hanlin-chat-motion-preset"].tap()
        app.buttons[title].tap()
        let receipt = app.staticTexts["proof-persisted-preset"]
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", id), object: receipt)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }

    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testAAllFivePresetsTwentyCompleteCyclesEach() {
        let presets = [("Smooth and relaxed", "v1.relaxed"), ("Height reveal", "v1.height-reveal"),
            ("Gentle squeeze", "v1.gentle-squeeze"), ("Quiet fade", "v1.quiet-fade"), ("No animations", "v1.none")]
        for (title, id) in presets {
            selectPreset(title, id: id)
            for cycle in 0..<20 {
                app.buttons["proof-thinking"].tap(); waitForGeometry("expanded")
                XCTAssertTrue(app.staticTexts["proof-summary"].exists)
                if cycle == 0 { attach("\(id)-expanded") }
                app.buttons["proof-thinking"].tap(); waitForGeometry("collapsed")
                XCTAssertFalse(app.staticTexts["proof-summary"].exists)
            }
            attach("\(id)-closed-after20")
        }
        app.buttons["proof-save-timeline"].tap()
    }

    func testBRapidReversalPresetSwitchAndPersistence() {
        let toggle = app.buttons["proof-thinking"]
        toggle.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        waitForGeometry("expanded")
        selectPreset("Height reveal", id: "v1.height-reveal")
        waitForGeometry("expanded")
        app.buttons["proof-tool"].tap()
        XCTAssertTrue(app.staticTexts["proof-tool-output"].waitForExistence(timeout: 5))
        toggle.tap(); waitForGeometry("collapsed"); toggle.tap(); waitForGeometry("expanded")
        XCTAssertTrue(app.staticTexts["proof-tool-output"].exists)
        app.buttons["proof-count"].tap(); app.buttons["proof-count"].tap(); app.buttons["proof-count"].tap()
        waitForGeometry("expanded")
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertEqual(app.staticTexts["proof-persisted-preset"].label, "v1.height-reveal")
        app.terminate(); app.launchArguments.append("--invalid-motion"); app.launch()
        XCTAssertEqual(app.staticTexts["proof-persisted-preset"].label, "v1.relaxed")
        setSystemReduceMotion(true)
        XCTAssertEqual(app.staticTexts["proof-effective-motion"].label, "shimmer=false;numeric=false")
        app.buttons["proof-thinking"].tap(); waitForGeometry("expanded")
        app.buttons["proof-thinking"].tap(); waitForGeometry("collapsed")
        attach("reduce-motion-static")
    }

    func testCReadableLongContentRTLTypeOrientationAndCompletion() {
        app.buttons["proof-long"].tap(); app.buttons["proof-rtl"].tap()
        app.buttons["proof-type"].tap()
        app.buttons["proof-thinking"].tap(); waitForGeometry("expanded")
        attach("long-rtl-accessibility-type-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForGeometry("expanded"); attach("long-rtl-accessibility-type-landscape")
        app.buttons["proof-finish"].tap()
        XCTAssertEqual(app.staticTexts["proof-effective-motion"].label, "shimmer=false;numeric=true")
        XCUIDevice.shared.orientation = .portrait
        app.buttons["proof-thinking"].tap(); waitForGeometry("collapsed")
        attach("completed-closed-portrait")
    }
}
