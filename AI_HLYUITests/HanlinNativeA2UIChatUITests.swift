import XCTest

/// The real app bootstraps an isolated in-memory store before preloads and replaces only HTTP.
/// These controls require the enabled combined app graph. No legacy runtime fixture flag,
/// direct renderer mounting, synthetic action callback or separate model engine is used here.
@MainActor
final class HanlinNativeA2UIChatUITests: XCTestCase {
    private var app: XCUIApplication!
    private let prompt = "NATIVE_A2UI_FIRST"
    override func setUp() { continueAfterFailure = false }

    func testOriginalFormSubmitsEditedValueAndPreservesUnsentComposerDraft() throws {
        try launch(continuation: true)
        sendFirstPrompt()
        let originalPart = surface().identifier
        let draft = "UNSENT_DRAFT_MUST_STAY_LOCAL"
        let composer = input()
        composer.tap(); composer.typeText(draft)
        try submitEditedForm()
        assertText("NATIVE_A2UI_CONTINUATION_OK")
        assertTransport(count: 2)
        XCTAssertEqual(input().value as? String, draft)
        XCTAssertTrue(app.descendants(matching: .any)[originalPart].firstMatch.exists)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "hanlin-assistant-bubble").count, 2)
        record("original-action-continuation-kept-draft")
    }

    func testExpandedDismissalRetainsTheOriginalFormAndDoesNotIssueARequest() throws {
        try launch(continuation: true)
        sendFirstPrompt()
        let originalPart = surface().identifier
        let expand = app.buttons["expansion_action_sheet"].firstMatch
        XCTAssertTrue(expand.waitForExistence(timeout: 10))
        expand.tap()
        let done = app.navigationBars["Result"].buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        record("original-surface-expanded")
        done.tap()
        XCTAssertTrue(app.descendants(matching: .any)[originalPart].firstMatch.waitForExistence(timeout: 10))
        assertTransport(count: 1)
        try submitEditedForm()
        assertText("NATIVE_A2UI_CONTINUATION_OK")
        assertTransport(count: 2)
    }

    func testSameProcessReopenRestoresCanonicalReadOnlyMediaWithoutAnotherModelRequest() throws {
        try launch(continuation: false)
        sendFirstPrompt()
        let originalPart = surface().identifier
        let originalChat = element("hanlin-native-a2ui-chat-id").label
        XCTAssertNotNil(UUID(uuidString: originalChat))
        let back = app.navigationBars.buttons.matching(NSPredicate(
            format: "identifier == 'BackButton' OR label == 'Hylic.AI' OR label == 'Back'"
        )).firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10), "The forced compact workspace must expose its native back control")
        back.tap()
        XCTAssertTrue(element("hanlin-compact-home-screen").waitForExistence(timeout: 10))
        let originalRecent = app.buttons["hanlin-compact-recent-row-0"].firstMatch
        XCTAssertTrue(originalRecent.waitForExistence(timeout: 10))
        originalRecent.tap()
        XCTAssertTrue(app.descendants(matching: .any)[originalPart].firstMatch.waitForExistence(timeout: 20),
                      "Rich history must appear before any second model request")
        XCTAssertEqual(element("hanlin-native-a2ui-chat-id").label, originalChat)
        assertTransport(count: 1)
        let submit = app.buttons["Submit replay form"].firstMatch
        XCTAssertTrue(submit.exists)
        XCTAssertFalse(submit.isEnabled)
        XCTAssertFalse(app.textFields["Replay name"].firstMatch.isEnabled)
        XCTAssertTrue(app.buttons["Load YouTube player"].firstMatch.isEnabled)
        XCTAssertTrue(app.links["Open in YouTube"].firstMatch.isEnabled)
        XCTAssertFalse(app.webViews.firstMatch.exists)
        XCTAssertFalse(element("hanlin-a2ui-history-unavailable").exists)
        app.buttons["Load YouTube player"].firstMatch.tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(submit.isEnabled, "Real local media interaction must not re-enable the original form")
        let unexpected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != 'idle'"),
                                                  object: element("hanlin-native-a2ui-state"))
        unexpected.isInverted = true
        wait(for: [unexpected], timeout: 2)
        assertTransport(count: 1)
        record("same-original-chat-canonical-history-before-request")
    }

    func testSurfaceOnlyNativeResponseUsesTheOriginalAssistantRow() throws {
        try launch(continuation: false, surfaceOnly: true)
        sendFirstPrompt(expectText: false)
        assertTransport(count: 1)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "hanlin-assistant-bubble").count, 1)
        XCTAssertTrue(app.textFields["Replay name"].firstMatch.exists)
        XCTAssertTrue(app.buttons["Submit replay form"].firstMatch.isEnabled)
        XCTAssertFalse(element("hanlin-a2ui-model-fallback").exists)
        record("surface-only-original-assistant-row")
    }

    private func launch(continuation: Bool, surfaceOnly: Bool = false) throws {
        let bundle = Bundle(for: Self.self)
        let url = bundle.url(forResource: "A2UIReplayMedia", withExtension: "jsonl", subdirectory: "Fixtures")
            ?? bundle.url(forResource: "A2UIReplayMedia", withExtension: "jsonl")
        let fixture = try XCTUnwrap(url, "The synchronized UI target must include the real JSONL fixture resource")
        let frames = try String(contentsOf: fixture, encoding: .utf8).split(separator: "\n").map(String.init)
        var parts: [[String: Any]] = []
        if !surfaceOnly { parts.append(textPart("before", "NATIVE_A2UI_BEFORE\n")) }
        parts += frames.map { ["part": "form", "kind": "a2ui", "text": NSNull(), "a2uiJSON": $0] }
        if !surfaceOnly { parts.append(textPart("after", "NATIVE_A2UI_AFTER\n")) }
        func wire(_ parts: [[String: Any]]) throws -> String {
            String(decoding: try JSONSerialization.data(withJSONObject: ["parts": parts]), as: UTF8.self)
        }
        var steps: [[String: Any]] = [["expectedInputContains": [prompt], "forbiddenInputContains": [],
            "expectedActionID": NSNull(), "expectedSubmittedValue": NSNull(),
            "structuredObjectJSON": try wire(parts), "delayMilliseconds": 0]]
        if continuation {
            steps.append(["expectedInputContains": ["Grace"],
                "forbiddenInputContains": ["UNSENT_DRAFT_MUST_STAY_LOCAL"],
                "expectedActionID": "submit", "expectedSubmittedValue": "Grace",
                "structuredObjectJSON": try wire([textPart("answer", "NATIVE_A2UI_CONTINUATION_OK")]),
                "delayMilliseconds": 0])
        }
        let plan = String(decoding: try JSONSerialization.data(withJSONObject: ["steps": steps]), as: UTF8.self)
        XCTAssertLessThan(plan.utf8.count, 262_144)
        app = XCUIApplication()
        addTeardownBlock { @MainActor [weak self] () async throws in
            guard let self, let app = self.app else { return }
            self.record("original-app-final"); app.terminate(); self.app = nil
        }
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_SIMULATE_CONTAINER_WIDTH"] = "390"
        app.launchEnvironment["HANLIN_NATIVE_A2UI_ACCEPTANCE"] = "1"
        app.launchEnvironment["HANLIN_NATIVE_A2UI_FIXTURE_PLAN"] = plan
        app.launch()
        let home = element("hanlin-home-tab")
        if home.waitForExistence(timeout: 10), home.isHittable { home.tap() }
        let original = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Native A2UI Acceptance")).firstMatch
        XCTAssertTrue(original.waitForExistence(timeout: 20), "The isolated SDK bootstrap did not expose its original seeded conversation")
        original.tap()
        XCTAssertTrue(input().waitForExistence(timeout: 15))
        assertTransport(count: 0)
    }
    private func textPart(_ id: String, _ text: String) -> [String: Any] {
        ["part": id, "kind": "text", "text": text, "a2uiJSON": NSNull()]
    }
    private func sendFirstPrompt(expectText: Bool = true) {
        input().tap(); input().typeText(prompt)
        app.buttons["hanlin-chat-send"].firstMatch.tap()
        XCTAssertTrue(surface().waitForExistence(timeout: 45), "The real native-schema/validator/owner path did not render its Surface")
        if expectText { assertText("NATIVE_A2UI_BEFORE"); assertText("NATIVE_A2UI_AFTER") }
        assertTransport(count: 1)
        XCTAssertFalse(app.webViews.firstMatch.exists)
        record("original-native-response")
    }
    private func submitEditedForm() throws {
        let field = app.textFields["Replay name"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10) && field.isEnabled)
        field.tap()
        let old = try XCTUnwrap(field.value as? String)
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + "Grace")
        let submit = app.buttons["Submit replay form"].firstMatch
        XCTAssertTrue(submit.isEnabled); submit.tap()
    }
    private func assertTransport(count: Int) {
        XCTAssertTrue(wait(NSPredicate(format: "label == 'idle'"), on: element("hanlin-native-a2ui-state")))
        XCTAssertTrue(wait(NSPredicate(format: "label == %@", String(count)), on: element("hanlin-native-a2ui-request-count")))
        XCTAssertEqual(element("hanlin-native-a2ui-request-failure").label, "none", "A rejected HTTP attempt invalidates integration acceptance")
    }
    private func assertText(_ marker: String) {
        let text = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", marker, marker)).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 30))
    }
    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }
    private func input() -> XCUIElement {
        if app.textFields["hanlin-chat-input"].firstMatch.exists { return app.textFields["hanlin-chat-input"].firstMatch }
        return app.textViews["hanlin-chat-input"].firstMatch
    }
    private func surface() -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "hanlin-a2ui-model-part-")).firstMatch
    }
    private func wait(_ predicate: NSPredicate, on element: XCUIElement) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 30) == .completed
    }
    private func record(_ name: String) {
        let pixels = XCTAttachment(screenshot: app.screenshot())
        pixels.name = name; pixels.lifetime = .keepAlways; add(pixels)
        let ax = XCTAttachment(string: app.debugDescription)
        ax.name = name + "-AX"; ax.lifetime = .keepAlways; add(ax)
    }
}
