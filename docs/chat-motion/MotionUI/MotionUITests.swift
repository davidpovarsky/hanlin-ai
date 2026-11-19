import XCTest

@MainActor
final class MotionUITests: XCTestCase {
    private var app: XCUIApplication!
    private var originalReduceMotion: Bool?

    override func tearDown() async throws {
        if let originalReduceMotion {
            setSystemReduceMotion(originalReduceMotion)
        }
        XCUIDevice.shared.orientation = .portrait
        // Preserve an assertion failure while ending this test-owned process;
        // the next cold launch must not inherit a failed case's live application.
        app?.terminate()
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
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed,
                       "Actual geometry: \(state.label); native action receipt: \(String(describing: state.value))")
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
        XCTAssertTrue(toggle.isHittable)
        toggle.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        let state = app.staticTexts["proof-geometry-state"]
        let receipt = XCTAttachment(string: "Triple tap delivered: \(String(describing: state.value)); geometry: \(state.label)")
        receipt.name = "original-toggle-rapid-action-receipt"
        receipt.lifetime = .keepAlways
        add(receipt)
        XCTAssertTrue((state.value as? String)?.hasPrefix("actions=3;expanded=true;") == true,
                      "The original production button must receive all three rapid actions")
        waitForGeometry("expanded")
        selectPreset("Height reveal", id: "v1.height-reveal")
        waitForGeometry("expanded")
        // An identifier on the whole native DisclosureGroup propagates to its
        // output and masks proof-tool-output. Address the actual header by label.
        app.buttons["Repeated tool name"].tap()
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

    private struct RapidInputSample: Codable {
        let control: String
        let uptime: TimeInterval
        let wasExpanded: Bool?
        let isExpanded: Bool?
        let visibleHeight: Double?
        let naturalHeight: Double?
    }

    private struct ScrollTouchConfiguration: Codable, Equatable {
        let phase: String
        let originalDelaysContentTouches: Bool
        let delaysContentTouches: Bool
        let canCancelContentTouches: Bool
        let isScrollEnabled: Bool
    }

    private struct RapidInputReport: Encodable {
        let diagnosticOnly: Bool
        let phase: String
        let scrollConfiguration: ScrollTouchConfiguration
        let control: String
        let delivery: String
        let expectedActions: Int
        let observedActions: Int
        let receiptReachedThree: Bool
        let actionTimeGaps: [TimeInterval]
        let laterActionsAtIntermediateGeometry: [Bool]
        let samples: [RapidInputSample]
    }

    // Passing this method means the observations were retained, not that rapid
    // reversal passed. B still requires the original production button's exact
    // three callbacks. Coordinate taps may idle between actions: retain actual
    // uptime gaps and pre-action geometry instead of silently calling them rapid.
    func testDRapidInputDiagnosticOnly() throws {
        app.terminate()
        app.launchArguments.append("--rapid-input-diagnostic")
        app.launch()
        let receipt = app.staticTexts["rapid-input-receipt"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 10))
        let cases = [
            ("rapid-native-outside", "multi-tap"),
            ("rapid-native-scroll", "multi-tap"),
            ("rapid-native-plain", "multi-tap"),
            ("rapid-production-static", "multi-tap"),
            ("rapid-production-animated", "multi-tap"),
            ("rapid-production-animated", "independent-coordinate-taps")
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var reports: [RapidInputReport] = []
        let configurationElement = app.staticTexts["rapid-scroll-configuration"]
        let configurationToggle = app.buttons["rapid-scroll-delay-toggle"]
        var baselineConfiguration: ScrollTouchConfiguration?
        var changedTouchDelay = false
        defer {
            if changedTouchDelay && configurationToggle.exists {
                configurationToggle.tap()
            }
        }

        for phase in ["native-default", "immediate-touch-down"] {
            if phase == "immediate-touch-down" {
                configurationToggle.tap()
                changedTouchDelay = true
            }
            let configurationReady = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label == %@", phase), object: configurationElement)
            XCTAssertEqual(XCTWaiter.wait(for: [configurationReady], timeout: 5), .completed,
                           "The actual containing UIScrollView must report the requested diagnostic phase")
            let configurationRaw = try XCTUnwrap(configurationElement.value as? String)
            let configuration = try JSONDecoder().decode(ScrollTouchConfiguration.self,
                                                          from: Data(configurationRaw.utf8))
            let configurationAttachment = XCTAttachment(string: configurationRaw)
            configurationAttachment.name = "rapid-scroll-configuration-\(phase)"
            configurationAttachment.lifetime = .keepAlways
            add(configurationAttachment)
            XCTAssertTrue(configuration.canCancelContentTouches,
                          "Scroll cancellation must remain enabled during this experiment")
            XCTAssertTrue(configuration.isScrollEnabled)
            if let baselineConfiguration {
                XCTAssertEqual(configuration.originalDelaysContentTouches,
                               baselineConfiguration.originalDelaysContentTouches)
                XCTAssertEqual(configuration.canCancelContentTouches,
                               baselineConfiguration.canCancelContentTouches)
                XCTAssertFalse(configuration.delaysContentTouches)
            } else {
                baselineConfiguration = configuration
                XCTAssertEqual(configuration.delaysContentTouches,
                               configuration.originalDelaysContentTouches)
            }

            for (identifier, delivery) in cases {
                app.buttons["rapid-input-reset"].tap()
                let collapsed = XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "label == %@", "static=collapsed;animated=collapsed"),
                    object: app.staticTexts["rapid-input-geometry"])
                XCTAssertEqual(XCTWaiter.wait(for: [collapsed], timeout: 5), .completed)
                let button = app.buttons[identifier]
                XCTAssertTrue(button.waitForExistence(timeout: 5))
                XCTAssertTrue(button.isHittable)
                if delivery == "multi-tap" {
                    button.tap(withNumberOfTaps: 3, numberOfTouches: 1)
                } else {
                    let coordinate = button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                    for _ in 0..<3 { coordinate.tap() }
                }
                let reachedThree = XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "label == %@", "3"), object: receipt)
                let receiptReachedThree = XCTWaiter.wait(for: [reachedThree], timeout: 5) == .completed
                let raw = try XCTUnwrap(receipt.value as? String)
                let samples = try JSONDecoder().decode([RapidInputSample].self, from: Data(raw.utf8))
                XCTAssertTrue(samples.allSatisfy { $0.control == identifier })
                let gaps = zip(samples.dropFirst(), samples).map { $0.0.uptime - $0.1.uptime }
                let intermediate = samples.dropFirst().map { sample in
                    guard let visible = sample.visibleHeight, let natural = sample.naturalHeight,
                          natural > 0 else { return false }
                    return visible > 0.5 && visible < natural + 6 - 0.5
                }
                let report = RapidInputReport(diagnosticOnly: true, phase: phase,
                    scrollConfiguration: configuration, control: identifier, delivery: delivery,
                    expectedActions: 3, observedActions: samples.count, receiptReachedThree: receiptReachedThree,
                    actionTimeGaps: gaps, laterActionsAtIntermediateGeometry: intermediate, samples: samples)
                reports.append(report)
                let attachment = XCTAttachment(string: String(decoding: try encoder.encode(report), as: UTF8.self))
                attachment.name = "\(phase)-\(identifier)-\(delivery)-input-observations"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            attach("rapid-input-\(phase)")
        }

        configurationToggle.tap()
        changedTouchDelay = false
        let restored = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "native-default"), object: configurationElement)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)
        let restoredRaw = try XCTUnwrap(configurationElement.value as? String)
        let restoredConfiguration = try JSONDecoder().decode(ScrollTouchConfiguration.self,
                                                              from: Data(restoredRaw.utf8))
        XCTAssertEqual(restoredConfiguration, try XCTUnwrap(baselineConfiguration),
                       "The probe must restore the original scroll-view configuration")
        let restoredAttachment = XCTAttachment(string: restoredRaw)
        restoredAttachment.name = "rapid-scroll-configuration-restored"
        restoredAttachment.lifetime = .keepAlways
        add(restoredAttachment)

        let attachment = XCTAttachment(string: String(decoding: try encoder.encode(reports), as: UTF8.self))
        attachment.name = "rapid-input-diagnostic-only"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

}
