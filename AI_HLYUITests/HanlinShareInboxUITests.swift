import XCTest

/// The original App Group/store creates input; the real Composer, document
/// processing, SDK request and saved conversation consume it. HTTP alone is scripted.
/// OS share-sheet presentation is a separate device acceptance gate.
@MainActor
final class HanlinShareInboxUITests: XCTestCase {
    func testSharedTextURLAndFileReachTheOriginalChatOnlyAfterSend() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let nonce = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_COMPOSER_EDIT_DIAGNOSTICS"] = "1"
        app.launchEnvironment["HANLIN_COMPACT_KEYBOARD_WITNESS"] = "1"
        app.launchEnvironment["HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE"] = "1"
        app.launchEnvironment["HANLIN_PHASE2_STORE_ID"] = nonce
        app.launchEnvironment["HANLIN_SHARE_DRAFT_ACCEPTANCE_ID"] = nonce
        app.launch()
        defer {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "original-shared-draft"; screenshot.lifetime = .keepAlways; add(screenshot)
            if testRun?.hasSucceeded == false {
                let tree = XCTAttachment(string: app.debugDescription)
                tree.name = "share-draft-accessibility"; tree.lifetime = .keepAlways; add(tree)
            }
            app.terminate()
        }
        if app.buttons["hanlin-compact-view-all-button"].waitForExistence(timeout: 10) {
            let recent = app.buttons["hanlin-compact-recent-row-0"].firstMatch
            XCTAssertTrue(recent.waitForExistence(timeout: 15))
            XCTAssertTrue(recent.label.contains("Agent Acceptance Chat")); recent.tap()
        } else if !app.staticTexts["hanlin-phase2-chat-id"].exists {
            tap(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Agent Acceptance Chat")).firstMatch, app: app)
        }
        let identity = app.staticTexts["hanlin-phase2-chat-id"]
        XCTAssertTrue(identity.waitForExistence(timeout: 15))
        let chatID = identity.label
        let original = "UNSENT_PREEXISTING_" + nonce
        let editor = input(app)
        typeNativeText(original, into: editor, app: app, failureMessage: "Native typing must preserve the draft before opening the inbox")
        XCTAssertEqual(editor.value as? String, original, "Native typing must preserve the draft before opening the inbox")
        openInbox(app)
        XCTAssertTrue(app.staticTexts["SHARE_DRAFT_" + nonce].waitForExistence(timeout: 20))
        tap(app.buttons["hanlin-share-inbox-cancel"], app: app)
        XCTAssertEqual(input(app).value as? String, original)
        XCTAssertEqual(app.staticTexts["hanlin-phase2-request-count"].label, "0")
        openInbox(app)
        let addButton = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'hanlin-share-add-draft-'")).firstMatch
        tap(addButton, app: app)
        XCTAssertTrue(app.buttons["hanlin-share-inbox-cancel"].waitForNonExistence(timeout: 20))
        let draft = try XCTUnwrap(input(app).value as? String)
        XCTAssertTrue(draft.contains(original) && draft.contains("SHARE_DRAFT_" + nonce))
        XCTAssertTrue(draft.contains("https://example.org/hanlin-share?case=" + nonce))
        XCTAssertTrue(app.staticTexts["shared-note.txt"].waitForExistence(timeout: 10))
        XCTAssertEqual(identity.label, chatID)
        XCTAssertEqual(app.staticTexts["hanlin-phase2-request-count"].label, "0",
                       "Reading or adding a shared batch must not contact a model")
        tap(app.buttons["hanlin-chat-send"], app: app)
        let delivered = "SHARED_DRAFT_DELIVERED_" + nonce
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", delivered))
            .firstMatch.waitForExistence(timeout: 60),
            "The original request must contain the draft, shared text, source URL and actual file contents")
        XCTAssertEqual(identity.label, chatID)
        app.terminate(); app.launch()
        if app.buttons["hanlin-compact-view-all-button"].waitForExistence(timeout: 10) {
            tap(app.buttons["hanlin-compact-recent-row-0"], app: app)
        }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", delivered))
            .firstMatch.waitForExistence(timeout: 30))
        XCTAssertEqual(app.staticTexts["hanlin-phase2-request-count"].label, "0")
    }

    private func input(_ app: XCUIApplication) -> XCUIElement {
        let field = app.textFields["hanlin-chat-input"].firstMatch
        return field.exists ? field : app.textViews["hanlin-chat-input"].firstMatch
    }

    private func typeNativeText(
        _ text: String,
        into field: XCUIElement,
        app: XCUIApplication,
        failureMessage: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        tap(field, app: app, file: file, line: line)
        let placeholderCleared = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", "Message"), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [placeholderCleared], timeout: 10), .completed,
                       "Native text input did not gain focus and clear placeholder", file: file, line: line)
        var expected = ""
        for chunk in Self.nativeTypingSegments(text) {
            field.typeText(chunk)
            expected += chunk
            let synced = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", expected), object: field)
            if XCTWaiter.wait(for: [synced], timeout: 10) != .completed {
                let actual = field.value as? String
                XCTAssertEqual(actual, expected,
                               "\(failureMessage) (segment=\(chunk) expectedLength=\(expected.count) actualLength=\(actual?.count ?? -1))",
                               file: file, line: line)
                return
            }
        }
    }

    private static func nativeTypingSegments(_ text: String) -> [String] {
        var chunks: [String] = []
        var current = ""
        for ch in text {
            if ch == "_" {
                if !current.isEmpty { chunks.append(current); current = "" }
                chunks.append(String(ch))
            } else {
                current.append(ch)
                if current.count >= 12 {
                    chunks.append(current)
                    current = ""
                }
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    private func openInbox(_ app: XCUIApplication) {
        tap(app.buttons["hanlin-composer-general-menu"], app: app)
        tap(app.buttons["hanlin-general-share-inbox"], app: app)
    }

    private func tap(
        _ element: XCUIElement,
        app: XCUIApplication? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(
            format: "exists == true AND enabled == true AND hittable == true"), object: element)
        let result = XCTWaiter.wait(for: [ready], timeout: 30)
        if result != .completed {
            let exists = element.exists
            let enabled = exists ? element.isEnabled : false
            let hittable = exists ? element.isHittable : false
            let frame = exists ? String(describing: element.frame) : "none"
            let diagnostics = "Tap readiness failed (waitResult=\(result.rawValue)) for \(element): exists=\(exists), enabled=\(enabled), hittable=\(hittable), frame=\(frame)"
            let diagAttachment = XCTAttachment(string: diagnostics)
            diagAttachment.name = "tap-failure-diagnostics"
            diagAttachment.lifetime = .keepAlways
            add(diagAttachment)
            if let app {
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = "tap-failure-screenshot"
                screenshot.lifetime = .keepAlways
                add(screenshot)
                let hierarchy = XCTAttachment(string: app.debugDescription)
                hierarchy.name = "tap-failure-hierarchy"
                hierarchy.lifetime = .keepAlways
                add(hierarchy)
            }
            XCTAssertEqual(result, .completed, diagnostics, file: file, line: line)
            return
        }
        element.tap()
    }
}
