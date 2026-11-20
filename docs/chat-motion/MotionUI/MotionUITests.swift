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
                       "Expected geometry: \(value); actual geometry: \(state.label); native action receipt: \(String(describing: state.value))")
    }

    private func waitForOrientation(landscape: Bool, timeout: TimeInterval = 5) {
        let state = app.staticTexts["proof-geometry-state"]
        let expected = landscape ? "orientation=landscape" : "orientation=portrait"
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", expected), object: state)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed,
                       "Expected \(expected); actual geometry: \(state.label); native action receipt: \(String(describing: state.value))")
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

    private func receiptField(_ key: String, in raw: String?) -> String? {
        guard let raw else { return nil }
        for part in raw.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1)
            if pair.count == 2, pair[0] == key { return String(pair[1]) }
        }
        return nil
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
        waitForGeometry("collapsed")
        let toggle = app.buttons["proof-thinking"]
        XCTAssertTrue(toggle.isHittable)
        toggle.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        let state = app.staticTexts["proof-geometry-state"]
        let rapidValue = state.value as? String
        let receipt = XCTAttachment(string: "Triple tap delivered: \(String(describing: rapidValue)); geometry: \(state.label)")
        receipt.name = "original-toggle-rapid-action-receipt"
        receipt.lifetime = .keepAlways
        add(receipt)
        XCTAssertTrue(rapidValue?.hasPrefix("actions=3;expanded=true;") == true,
                      "The original production button must receive all three rapid actions")
        let rapidGaps = (receiptField("gaps", in: rapidValue) ?? "")
            .split(separator: ",").compactMap { Double($0) }
        XCTAssertEqual(rapidGaps.count, 2, "Three rapid actions must report two inter-action gaps: \(String(describing: rapidValue))")
        XCTAssertTrue(rapidGaps.allSatisfy { $0 < 0.5 },
                      "Rapid multi-tap gaps must remain sub-second rather than idle sequential taps: \(String(describing: rapidValue))")
        let rapidIntermediate = (receiptField("intermediate", in: rapidValue) ?? "").split(separator: ",")
        XCTAssertTrue(rapidIntermediate.contains("true"),
                      "Rapid reversal must observe at least one later action at intermediate geometry: \(String(describing: rapidValue))")
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
        // Negative scroll/drag check: immediate touch-down must still cancel the
        // button tap and scroll the transcript when a vertical drag starts on it.
        app.buttons["proof-long"].tap()
        app.buttons["proof-type"].tap()
        waitForGeometry("expanded")
        XCTAssertTrue(toggle.isHittable)
        let beforeDragValue = state.value as? String
        let beforeScrollY = Double(receiptField("scrollY", in: beforeDragValue) ?? "") ?? 0
        let dragStart = toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        dragStart.press(forDuration: 0.05, thenDragTo: dragStart.withOffset(CGVector(dx: 0, dy: -120)))
        let afterDragValue = state.value as? String
        let afterScrollY = Double(receiptField("scrollY", in: afterDragValue) ?? "") ?? 0
        let dragReceipt = XCTAttachment(string: "before=\(String(describing: beforeDragValue)); after=\(String(describing: afterDragValue))")
        dragReceipt.name = "scroll-drag-from-toggle-receipt"
        dragReceipt.lifetime = .keepAlways
        add(dragReceipt)
        XCTAssertTrue(afterDragValue?.hasPrefix("actions=5;expanded=true;") == true,
                      "Dragging from ToggleButton must cancel the button touch without toggling: \(String(describing: afterDragValue))")
        XCTAssertGreaterThan(afterScrollY, beforeScrollY + 20,
                             "Containing ScrollView must still scroll when a vertical drag starts on ToggleButton: before=\(beforeScrollY) after=\(afterScrollY)")
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
        waitForOrientation(landscape: true)
        waitForGeometry("expanded"); attach("long-rtl-accessibility-type-landscape")
        app.buttons["proof-finish"].tap()
        XCTAssertEqual(app.staticTexts["proof-effective-motion"].label, "shimmer=false;numeric=true")
        XCUIDevice.shared.orientation = .portrait
        waitForOrientation(landscape: false)
        waitForGeometry("expanded")
        let toggle = app.buttons["proof-thinking"]
        XCTAssertTrue(toggle.isHittable)
        toggle.tap(); waitForGeometry("collapsed")
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
        let observationSemantics: String
        let receiptLabel: String
        let receiptObservedThree: Bool
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
            let configurationSnapshot = try configurationElement.snapshot()
            XCTAssertEqual(configurationSnapshot.label, phase,
                           "The actual containing UIScrollView must report the requested diagnostic phase")
            let configurationRaw = try XCTUnwrap(configurationSnapshot.value as? String)
            let configuration = try JSONDecoder().decode(ScrollTouchConfiguration.self,
                                                          from: Data(configurationRaw.utf8))
            XCTAssertEqual(configuration.phase, phase)
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
                let geometryElement = app.staticTexts["rapid-input-geometry"]
                // Reset is a setup transition, not an input-delivery deadline.
                // Allow the original disclosure to close before the next gesture;
                // keep the post-gesture action receipt a single native snapshot.
                let resetExpectation = XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "label == %@", "static=collapsed;animated=collapsed"),
                    object: geometryElement)
                let resetResult = XCTWaiter.wait(for: [resetExpectation], timeout: 5)
                let geometrySnapshot = try geometryElement.snapshot()
                let baseline = XCTAttachment(string:
                    "\(geometrySnapshot.label); geometry=\(String(describing: geometrySnapshot.value))")
                baseline.name = "\(phase)-\(identifier)-\(delivery)-reset-baseline"
                baseline.lifetime = .keepAlways
                add(baseline)
                XCTAssertEqual(resetResult, .completed,
                               "The original disclosure must finish reset within five seconds: \(geometrySnapshot.label)")
                XCTAssertEqual(geometrySnapshot.label, "static=collapsed;animated=collapsed")
                let button = app.buttons[identifier]
                XCTAssertTrue(button.isHittable)
                if delivery == "multi-tap" {
                    button.tap(withNumberOfTaps: 3, numberOfTouches: 1)
                } else {
                    let coordinate = button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                    for _ in 0..<3 { coordinate.tap() }
                }
                let receiptSnapshot = try receipt.snapshot()
                let raw = try XCTUnwrap(receiptSnapshot.value as? String)
                let samples = try JSONDecoder().decode([RapidInputSample].self, from: Data(raw.utf8))
                let observedLabelCount = try XCTUnwrap(Int(receiptSnapshot.label))
                XCTAssertEqual(observedLabelCount, samples.count,
                               "The receipt label and samples must describe the same native snapshot")
                let receiptObservedThree = observedLabelCount == 3
                XCTAssertTrue(samples.allSatisfy { $0.control == identifier })
                let gaps = zip(samples.dropFirst(), samples).map { $0.0.uptime - $0.1.uptime }
                let intermediate = samples.dropFirst().map { sample in
                    guard let visible = sample.visibleHeight, let natural = sample.naturalHeight,
                          natural > 0 else { return false }
                    return visible > 0.5 && visible < natural + 6 - 0.5
                }
                let report = RapidInputReport(diagnosticOnly: true, phase: phase,
                    scrollConfiguration: configuration, control: identifier, delivery: delivery,
                    expectedActions: 3, observedActions: samples.count,
                    observationSemantics: "single-native-snapshot-after-gesture;not-a-five-second-delivery-deadline",
                    receiptLabel: receiptSnapshot.label, receiptObservedThree: receiptObservedThree,
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
        let restoredSnapshot = try configurationElement.snapshot()
        XCTAssertEqual(restoredSnapshot.label, "native-default")
        let restoredRaw = try XCTUnwrap(restoredSnapshot.value as? String)
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
