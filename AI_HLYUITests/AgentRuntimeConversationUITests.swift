import XCTest
import notify
import UIKit
import Vision

@MainActor
final class AgentRuntimeConversationUITests: XCTestCase {
    func testLiveGeminiPythonConsentAndColdReopen() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HANLIN_LIVE_PROVIDER_CASE"] == "1",
            "Live provider acceptance requires its explicitly staged, owner-authorized account; ordinary fixture suites do not provide credentials")
        continueAfterFailure = false
        executionTimeAllowance = 420
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-agentDiagnosticsAutomaticCaptureMigrationV1", "YES", "-agentDiagnosticsLevel", "off"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_COMPOSER_EDIT_DIAGNOSTICS"] = "1"
        app.launchEnvironment["HANLIN_COMPACT_KEYBOARD_WITNESS"] = "1"
        app.launchEnvironment["HANLIN_LIVE_GEMINI_ACCEPTANCE"] = "1"
        app.launchEnvironment["HANLIN_PHASE2_STORE_ID"] = UUID().uuidString
        // No fixture provider flag, response interceptor, secret launch argument,
        // manufactured grant, tool response or preinstalled result.
        app.launch()
        openChat(in: app)
        let identity = app.staticTexts["hanlin-phase2-chat-id"].firstMatch
        XCTAssertTrue(identity.waitForExistence(timeout: 15))
        let nonce = identity.label
        XCTAssertNotNil(UUID(uuidString: nonce))
        print("HANLIN_LIVE_PROVIDER_CHALLENGE=" + nonce)
        XCTAssertEqual(app.staticTexts["hanlin-phase2-request-count"].label, "0")
        let source = "import sys\nprint('LIVE_HANLIN_" + nonce + ":' + sys.version.split()[0] + ':' + str(129 * 673))"
        let arguments: [String: Any] = ["source": source, "arguments": [String](), "timeout_seconds": 15]
        let encoded = String(decoding: try JSONSerialization.data(withJSONObject: arguments, options: [.sortedKeys]), as: UTF8.self)
        sendPrompt("Call execute_local_python_code exactly once with exactly this JSON: " + encoded
            + ". You may use tool_search only if discovery is necessary. Wait for the actual result and then reply only with its stdout. Do not compute or invent a result.", in: app)
        let reviewToggle = app.descendants(matching: .any)["hanlin-tool-consent-review-toggle"].firstMatch
        XCTAssertTrue(reviewToggle.waitForExistence(timeout: 90), "The live model must request the original privileged Python tool")
        tapElement(reviewToggle)
        let review = app.staticTexts["hanlin-tool-consent-original-request"].firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: 15))
        let submitted = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(review.label.utf8)) as? [String: Any])
        // Approve only the bounded, known harmless script, even though the tool
        // arguments arrived from a live model. Extra code cannot get consent.
        XCTAssertEqual(submitted["source"] as? String, source)
        XCTAssertTrue(Set(submitted.keys).isSubset(of: ["source", "arguments", "timeout_seconds"]))
        XCTAssertTrue((submitted["arguments"] as? [String] ?? []).isEmpty)
        if let limit = submitted["timeout_seconds"] as? Int { XCTAssertTrue((1...30).contains(limit)) }
        tapElement(app.buttons["hanlin-tool-consent-allow-once"].firstMatch)
        let expected = "LIVE_HANLIN_" + nonce + ":3.14.6:86817"
        let answer = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@", expected)).firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 180), "Live Gemini must return the real original CPython tool result")
        let stop = app.buttons["hanlin-chat-stop"].firstMatch
        XCTAssertTrue(stop.waitForNonExistence(timeout: 30))
        let draft = "UNSENT_LIVE_" + nonce
        let input = chatInputElement(in: app)
        tapElement(input); input.typeText(draft)
        openSettings(in: app)
        attachScreenshot("live-gemini-original-tool-before-cold-reopen", in: app)
        app.terminate(); app.launch()
        openChat(in: app)
        XCTAssertTrue(answer.waitForExistence(timeout: 30))
        XCTAssertEqual(identity.label, nonce)
        XCTAssertEqual(chatInputElement(in: app).value as? String, draft)
        XCTAssertFalse(app.buttons["hanlin-tool-consent-allow-once"].exists)
        XCTAssertEqual(app.staticTexts["hanlin-phase2-request-count"].label, "0")
        attachScreenshot("live-gemini-original-conversation-cold-reopen", in: app)
        print("HANLIN_LIVE_PROVIDER_COMPLETED=" + nonce)
    }

    func testPhase2OfficialToolSurfaceContinuesThroughTheSameOriginalChat() throws {
        continueAfterFailure = false
        let app = XCUIApplication(), nonce = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE"] = "1"
        app.launchEnvironment["HANLIN_PHASE2_STORE_ID"] = UUID().uuidString
        app.launch()
        openChat(in: app)
        sendPrompt("PHASE2_TOOL_A2UI_" + nonce, in: app)
        let reviewToggle = app.descendants(matching: .any)["hanlin-tool-consent-review-toggle"].firstMatch
        XCTAssertTrue(reviewToggle.waitForExistence(timeout: 45))
        XCTAssertFalse(app.staticTexts["hanlin-tool-consent-original-request"].exists, "Raw parameters stay closed until reviewed")
        tapElement(reviewToggle)
        let review = app.staticTexts["hanlin-tool-consent-original-request"].firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: 45))
        XCTAssertTrue(review.label.contains("createSurface") && review.label.contains("Tool name"))
        tapElement(app.buttons["hanlin-tool-consent-allow-once"].firstMatch)
        let ready = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "PHASE2_TOOL_SURFACE_READY_" + nonce)).firstMatch
        XCTAssertTrue(ready.waitForExistence(timeout: 45))
        let field = app.textFields["Tool name"].firstMatch
        if !field.waitForExistence(timeout: 3) {
            let disclosure = app.descendants(matching: .any)["hanlin-reasoning-toggle"].firstMatch
            XCTAssertTrue(disclosure.waitForExistence(timeout: 10)); tapElement(disclosure)
        }
        XCTAssertTrue(field.waitForExistence(timeout: 15) && field.isEnabled, "The original tool receipt must admit the official Surface")
        tapElement(field)
        let old = try XCTUnwrap(field.value as? String)
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + "Grace")
        let draft = "UNSENT_TOOL_A2UI_" + nonce
        let input = chatInputElement(in: app)
        tapElement(input); input.typeText(draft)
        let submit = app.buttons["Submit tool form"].firstMatch
        XCTAssertTrue(submit.isEnabled); tapElement(submit)
        let answer = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "PHASE2_TOOL_ACTION_VERIFIED_" + nonce)).firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 45), "The actual edited action must return through the original Host/Session, not an injected UI callback")
        XCTAssertEqual(chatInputElement(in: app).value as? String, draft)
        XCTAssertFalse(app.webViews.firstMatch.exists)
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = "original-host-tool-official-surface-and-action-continuation"; proof.lifetime = .keepAlways; add(proof)
    }

    func testPhase2ActualPythonToolApprovalAndColdConversationRestoration() throws {
        continueAfterFailure = false
        let app = XCUIApplication(), nonce = UUID().uuidString
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE"] = "1"
        app.launchEnvironment["HANLIN_PHASE2_STORE_ID"] = UUID().uuidString
        app.launch()
        openChat(in: app)
        sendPrompt("PHASE2_REAL_PYTHON_" + nonce, in: app)
        let reviewToggle = app.descendants(matching: .any)["hanlin-tool-consent-review-toggle"].firstMatch
        XCTAssertTrue(reviewToggle.waitForExistence(timeout: 45))
        XCTAssertFalse(app.staticTexts["hanlin-tool-consent-original-request"].exists, "Raw parameters stay closed until reviewed")
        tapElement(reviewToggle)
        let request = app.staticTexts["hanlin-tool-consent-original-request"].firstMatch
        XCTAssertTrue(request.waitForExistence(timeout: 45), "The actual code request must require review before dispatch")
        XCTAssertTrue(request.label.contains(nonce) && request.label.contains("import sys"))
        tapElement(app.buttons["hanlin-tool-consent-allow-once"].firstMatch)
        let answer = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@", "PHASE2_VERIFIED_" + nonce + ":3.14.6:42")).firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 90), "The HTTP fixture requires the original tool response to contain the actual Python version and nonce result")
        let toggle = app.descendants(matching: .any)["hanlin-reasoning-toggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 10)); tapElement(toggle)
        let activity = app.descendants(matching: .any)["hanlin-agent-activity-phase2-python-" + nonce].firstMatch
        XCTAssertTrue(activity.waitForExistence(timeout: 10), "Original tool activity must remain inspectable")
        let originalChat = app.staticTexts["hanlin-phase2-chat-id"].label
        XCTAssertNotNil(UUID(uuidString: originalChat))
        let draft = "UNSENT_PHASE2_" + nonce
        let input = chatInputElement(in: app)
        tapElement(input); input.typeText(draft)
        openSettings(in: app) // A real navigation action flushes the original conversation draft.
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = "actual-python-tool-completed-before-cold-reopen"; proof.lifetime = .keepAlways; add(proof)
        app.terminate(); app.launch()
        openChat(in: app)
        XCTAssertTrue(answer.waitForExistence(timeout: 20))
        XCTAssertEqual(app.staticTexts["hanlin-phase2-chat-id"].label, originalChat)
        XCTAssertEqual(chatInputElement(in: app).value as? String, draft)
        XCTAssertEqual(app.staticTexts["hanlin-phase2-request-count"].label, "0", "Restoration must not replay the model or tool request")
        XCTAssertFalse(app.buttons["hanlin-tool-consent-allow-once"].exists)
        let restored = XCTAttachment(screenshot: app.screenshot())
        restored.name = "cold-original-conversation-draft-and-history-without-replay"; restored.lifetime = .keepAlways; add(restored)
    }

    /// Uses the canonical message store and the real compact external composer
    /// on iPhone, plus the original overlaid composer on iPad. No offset or
    /// visibility is injected; every transition comes from native user actions.
    func testFollowLatestArrowTracksRealBottomAcrossScrollAndComposerChanges() throws {
        continueAfterFailure = false
        executionTimeAllowance = 240
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE"] = "1"
        app.launchEnvironment["HANLIN_PHASE2_STORE_ID"] = UUID().uuidString
        app.launchEnvironment["HANLIN_SCROLL_BOTTOM_ACCEPTANCE_FIXTURE"] = "1"
        app.launchEnvironment["HANLIN_COMPOSER_EDIT_DIAGNOSTICS"] = "1"
        app.launch()
        openChat(in: app)

        let transcript = app.descendants(matching: .any)["hanlin-chat-transcript"].firstMatch
        let arrow = app.buttons["hanlin-chat-follow-latest"].firstMatch
        let last = app.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@", "POST149101_SCROLL_LAST")).firstMatch
        if UIDevice.current.userInterfaceIdiom == .phone {
            XCTAssertTrue(app.descendants(matching: .any)["hanlin-compact-chat-workspace"].firstMatch.exists,
                          "The phone regression must exercise the persistent external composer")
        }
        func assertAtBottom(_ stage: String) {
            let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                last.exists && last.isHittable && !arrow.exists
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 12), .completed,
                           "The final real message must be visible with no arrow at \(stage)")
        }
        XCTAssertTrue(transcript.waitForExistence(timeout: 15))
        assertAtBottom("initial attachment")

        transcript.swipeDown()
        transcript.swipeDown()
        XCTAssertTrue(arrow.waitForExistence(timeout: 8) && arrow.isHittable,
                      "Reading earlier messages must reveal a reachable original arrow")
        let composerTopWhileReading = chatInputElement(in: app).frame.minY
        let viewportHeightWhileReading = transcript.frame.height
        attachScreenshot("follow-latest-original-blue-glass-reading-history", in: app)
        arrow.tap()
        assertAtBottom("jump button")
        XCTAssertEqual(chatInputElement(in: app).frame.minY, composerTopWhileReading, accuracy: 2,
                       "Removing the floating arrow must not change composer layout")
        XCTAssertEqual(transcript.frame.height, viewportHeightWhileReading, accuracy: 2,
                       "Arrow visibility must not resize the compact transcript viewport")

        // Reach the bottom manually, without pressing the button. This is the
        // reported failure mode and must resume tracking from the real offset.
        transcript.swipeDown()
        transcript.swipeDown()
        XCTAssertTrue(arrow.waitForExistence(timeout: 8))
        for _ in 0..<8 where arrow.exists { transcript.swipeUp() }
        assertAtBottom("manual scroll")

        let draft = "UNSENT_BOTTOM_REGRESSION"
        let input = chatInputElement(in: app)
        XCTAssertTrue(input.isHittable)
        input.tap(); input.typeText(draft)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        assertAtBottom("keyboard and composer growth")
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = app.windows.firstMatch.frame
            return frame.width > frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 10), .completed)
        assertAtBottom("rotated keyboard viewport")
        XCTAssertEqual(chatInputElement(in: app).value as? String, draft)
        attachScreenshot("follow-latest-bottom-keyboard-landscape", in: app)
        XCUIDevice.shared.orientation = .portrait

        // Leave an explicitly paused, long chat for an empty new one. An old
        // endpoint or invalidated layout cannot carry its arrow into that chat.
        transcript.swipeDown()
        transcript.swipeDown()
        XCTAssertTrue(arrow.waitForExistence(timeout: 8))
        let identity = app.staticTexts["hanlin-phase2-chat-id"].firstMatch
        XCTAssertTrue(identity.waitForExistence(timeout: 5))
        let oldID = identity.label
        let newChat = chatListToolbarButton("hanlin-new-chat-button", in: app)
        XCTAssertTrue(newChat.isHittable)
        newChat.tap()
        let replaced = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            identity.exists && identity.label != oldID && UUID(uuidString: identity.label) != nil
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [replaced], timeout: 12), .completed)
        XCTAssertTrue(arrow.waitForNonExistence(timeout: 8),
                      "A new, fitting chat has no older scroll target")
        XCTAssertEqual(app.staticTexts["hanlin-phase2-request-count"].label, "0",
                       "Reading and jumping in historical messages cannot execute a model request")
        attachScreenshot("follow-latest-new-short-chat-without-arrow", in: app)
    }

    /// Exercises the production transcript, Host approval and actual Python
    /// output through the existing controlled provider. No replacement view,
    /// preinstalled tool result or synthetic scroll geometry is involved.
    func testOriginalChatActivitySurvivesKeyboardRotationAndConversationReattachment() throws {
        continueAfterFailure = false
        executionTimeAllowance = 300
        let app = XCUIApplication(), nonce = UUID().uuidString
        XCUIDevice.shared.orientation = .portrait
        defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE"] = "1"
        app.launchEnvironment["HANLIN_PHASE2_STORE_ID"] = UUID().uuidString
        app.launch()
        openChat(in: app)
        revokeRememberedToolPermissions(in: app)

        let transcript = app.descendants(matching: .any)["hanlin-chat-transcript"].firstMatch
        func checkViewport(_ stage: String) {
            XCTAssertEqual(app.state, .runningForeground, "The production app stopped at \(stage)")
            XCTAssertTrue(transcript.waitForExistence(timeout: 10))
            let frame = transcript.frame
            XCTAssertTrue([frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite))
            XCTAssertGreaterThan(frame.width, 1)
            XCTAssertGreaterThan(frame.height, 1)
            let proof = XCTAttachment(string: "stage=\(stage)\nviewport=\(frame)\nwindow=\(app.windows.firstMatch.frame)")
            proof.name = "chat-viewport-" + stage; proof.lifetime = .keepAlways; add(proof)
            attachScreenshot("chat-scroll-regression-" + stage, in: app)
        }
        func revealAndTap(_ control: XCUIElement) {
            XCTAssertTrue(control.waitForExistence(timeout: 10))
            for _ in 0..<4 where !control.isHittable {
                if control.frame.maxY <= transcript.frame.minY { transcript.swipeDown() }
                else { transcript.swipeUp() }
            }
            XCTAssertTrue(control.isHittable, "The original control must be reachable before tapping")
            guard control.isHittable else { return }
            control.tap()
        }
        func rotate(_ orientation: UIDeviceOrientation, landscape: Bool) {
            XCUIDevice.shared.orientation = orientation
            let window = app.windows.firstMatch
            let resized = expectation(for: NSPredicate { _, _ in
                landscape ? window.frame.width > window.frame.height : window.frame.height > window.frame.width
            }, evaluatedWith: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [resized], timeout: 10), .completed,
                           "The actual application viewport must rotate")
        }

        let identity = app.staticTexts["hanlin-phase2-chat-id"].firstMatch
        XCTAssertTrue(identity.waitForExistence(timeout: 10))
        let originalChat = identity.label
        XCTAssertNotNil(UUID(uuidString: originalChat))
        let source = "import sys; print('PHASE2_RESULT_\(nonce):' + sys.version.split()[0] + ':' + str(6*7))"

        // Review the exact harmless request under the original Host's remembered
        // permission scope. Its deadline remains authoritative; exercise slower
        // rotations after it has completed.
        sendPrompt("PHASE2_REAL_PYTHON_" + nonce, in: app)
        approveOriginalToolRequest(["source": source], in: app, remembersDecision: true)
        let expected = "PHASE2_VERIFIED_" + nonce + ":3.14.6:42"
        let answer = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@", expected)).firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 90))
        XCTAssertTrue(app.buttons["hanlin-chat-stop"].firstMatch.waitForNonExistence(timeout: 15))

        let draft = "UNSENT_SCROLL_" + nonce
        let input = chatInputElement(in: app)
        revealAndTap(input); input.typeText(draft)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        checkViewport("completed-tool-keyboard-portrait")
        rotate(.landscapeLeft, landscape: true)
        XCTAssertEqual(chatInputElement(in: app).value as? String, draft)
        XCTAssertEqual(identity.label, originalChat)
        checkViewport("completed-tool-keyboard-landscape")

        let activity = app.descendants(matching: .any)["hanlin-agent-activity-phase2-python-" + nonce].firstMatch
        let hierarchy = app.descendants(matching: .any)["hanlin-reasoning-toggle"].firstMatch
        if !activity.waitForExistence(timeout: 2) { revealAndTap(hierarchy) }
        XCTAssertTrue(activity.waitForExistence(timeout: 10))
        revealAndTap(activity)
        let details = app.descendants(matching: .any)["hanlin-tool-content-expanded-text"].firstMatch
        XCTAssertTrue(details.waitForExistence(timeout: 10), "Actual tool details must mount inside the original transcript")
        for _ in 0..<3 {
            revealAndTap(hierarchy)
            XCTAssertTrue(details.waitForNonExistence(timeout: 5))
            revealAndTap(hierarchy)
            XCTAssertTrue(details.waitForExistence(timeout: 5), "Reopening must retain the original expanded tool payload")
        }
        rotate(.portrait, landscape: false)
        XCTAssertTrue(details.waitForExistence(timeout: 10))
        checkViewport("completed-expanded-details-portrait")

        // This replaces the actual conversation/reader, rather than merely
        // presenting a sheet over the still-mounted chat.
        let requestCount = app.staticTexts["hanlin-phase2-request-count"].label
        revealAndTap(chatListToolbarButton("hanlin-new-chat-button", in: app))
        XCTAssertTrue(app.descendants(matching: .any)["hanlin-info-bubble"].firstMatch.waitForExistence(timeout: 10))
        let replaced = expectation(for: NSPredicate { _, _ in
            identity.exists && identity.label != originalChat && UUID(uuidString: identity.label) != nil
        }, evaluatedWith: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [replaced], timeout: 10), .completed,
                       "The original transcript must actually be replaced by a different conversation")
        ensureChatListVisible(in: app)
        selectChatRow(named: "Agent Acceptance Chat", in: app)
        XCTAssertTrue(answer.waitForExistence(timeout: 20))
        XCTAssertEqual(identity.label, originalChat)
        XCTAssertEqual(chatInputElement(in: app).value as? String, draft)
        XCTAssertEqual(app.staticTexts["hanlin-phase2-request-count"].label, requestCount,
                       "Reattaching the transcript cannot replay any provider or tool operation")
        XCTAssertFalse(app.buttons["hanlin-tool-consent-allow-remember"].exists)
        XCTAssertFalse(app.buttons["hanlin-tool-consent-allow-once"].exists)
        if !activity.waitForExistence(timeout: 2) { revealAndTap(hierarchy) }
        XCTAssertTrue(activity.waitForExistence(timeout: 10))
        if !details.exists { revealAndTap(activity) }
        XCTAssertTrue(details.waitForExistence(timeout: 10))
        checkViewport("same-conversation-reattached")
    }

    func testDiagnosticsReviewsTheAutomaticallyCapturedRunWithoutSharingItsKey() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        // This case verifies the screen/key/replay binding, with a known capture
        // level supplied through the process argument domain. It is not the
        // separate new-install/default-migration acceptance test.
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-agentDiagnosticsLevel", "fullLocalDebug"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE"] = "1"
        app.launch()
        openChat(in: app)
        let marker = "DIAGNOSTIC_CAPTURE_" + UUID().uuidString
        let expected = "CAPTURED_" + marker
        sendPrompt(marker, in: app)
        let answer = app.descendants(matching: .any).matching(NSPredicate(format: "value == %@ OR label == %@", expected, expected)).firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 60), "A fresh uniquely identified ordinary turn did not complete")
        openSettings(in: app)
        let diagnostics = app.descendants(matching: .any)["hanlin-agent-diagnostics-link"].firstMatch
        for _ in 0..<8 where !diagnostics.isHittable { app.swipeUp() }
        XCTAssertTrue(diagnostics.waitForExistence(timeout: 10))
        tapElement(diagnostics)
        let session = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "hanlin-diagnostics-session-")
        ).firstMatch
        for _ in 0..<6 where !session.isHittable { app.swipeUp() }
        XCTAssertTrue(session.waitForExistence(timeout: 10), "The completed ordinary turn did not automatically produce a session")
        tapElement(session)
        let reviewButton = app.descendants(matching: .any)["hanlin-diagnostics-review-encrypted"].firstMatch
        for _ in 0..<6 where !reviewButton.isHittable { app.swipeUp() }
        XCTAssertTrue(reviewButton.waitForExistence(timeout: 10))
        tapElement(reviewButton)
        let confirm = app.descendants(matching: .any)["hanlin-diagnostics-confirm-local-review"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "Encrypted capture must require a separate deliberate confirmation")
        tapElement(confirm)
        let report = app.descendants(matching: .any)["hanlin-diagnostics-local-review-text"].firstMatch
        let reportExists = report.waitForExistence(timeout: 60)
        if !reportExists {
            let state = XCTAttachment(string: app.debugDescription)
            state.name = "Local encrypted review binding state"
            state.lifetime = .keepAlways
            add(state)
        }
        XCTAssertTrue(reportExists, "Actual device-key lookup/decryption/offline replay did not produce a review")
        let text = report.label + (report.value as? String ?? "")
        if !text.contains(expected) || !text.contains("SDK content:") {
            let state = XCTAttachment(string: text)
            state.name = "Actual bounded encrypted review preview"
            state.lifetime = .keepAlways
            add(state)
        }
        XCTAssertTrue(text.contains("Authenticated records") && text.contains("not an exact raw export"))
        XCTAssertTrue(text.contains(expected) && text.contains("SDK content:"), "The review did not replay the actual newly captured response")
        XCTAssertFalse(text.contains("NOT_CAPTURED: no transport request or response records are available."))
        XCTAssertFalse(text.contains("acceptance-only"), "The actual captured synthetic Authorization credential leaked into the preview")
        let share = app.descendants(matching: .any)["hanlin-diagnostics-share-reviewed-report"].firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 10) && share.isEnabled)
        // Sharing stays a separate owner action; do not open an external app.
        tapElement(app.navigationBars["Local capture review"].buttons["Done"].firstMatch)
    }

    func testOriginalBubbleRendersLocalCodeFencesAndPreservesSourceActions() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE"] = "1"
        app.launch()
        openChat(in: app)
        sendPrompt("RENDER_CODE_FENCES", in: app)

        let diagram = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "hanlin-code-fence-mermaid-")
        ).firstMatch
        let comparison = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "hanlin-code-fence-diff-")
        ).firstMatch
        XCTAssertTrue(diagram.waitForExistence(timeout: 30), "The original parsed Markdown hook did not produce a diagram block")
        XCTAssertTrue(comparison.waitForExistence(timeout: 30), "The original parsed Markdown hook did not produce a Diff block")
        let diagramPreview = diagram.descendants(matching: .webView).firstMatch
        XCTAssertTrue(diagramPreview.waitForExistence(timeout: 60), "Actual local Mermaid WebKit output did not reach the original bubble")
        XCTAssertTrue(comparison.descendants(matching: .webView).firstMatch.waitForExistence(timeout: 30),
                      "Actual local Diff WebKit output did not reach the original bubble")
        // Toggle retains native accessibility semantics even with .button style;
        // locate the actual control by its stable ID rather than assuming UIButton.
        let sourceToggle = diagram.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "hanlin-code-fence-source-toggle-")
        ).firstMatch
        let sourceControlExists = sourceToggle.waitForExistence(timeout: 10)
        if !sourceControlExists {
            let state = XCTAttachment(string: app.debugDescription)
            state.name = "Original code-fence source control hierarchy"
            state.lifetime = .keepAlways
            add(state)
        }
        XCTAssertTrue(sourceControlExists)
        tapElement(sourceToggle)
        let source = diagram.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "hanlin-code-fence-source-text-")
        ).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 10), "Showing source must preserve the original Mermaid input")
        let shownSource = source.label + (source.value as? String ?? "")
        XCTAssertTrue(shownSource.contains("flowchart LR") && shownSource.contains("שלום🙂"),
                      "The source toggle must expose the actual complete Unicode diagram input")
        tapElement(diagram.buttons["Code block actions"].firstMatch)
        tapElement(app.buttons["Expand"].firstMatch)
        XCTAssertTrue(app.navigationBars["Diagram"].waitForExistence(timeout: 10))
        tapElement(app.buttons["Done"].firstMatch)
        XCTAssertTrue(diagram.waitForExistence(timeout: 10), "Closing the expanded view must retain the original bubble")
    }

    func testRealChatUISendsPromptShowsToolActivityAndFinalAnswer() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE"] = "1"
        app.launch()

        // Runtime status is observational; engine activation must not require a toggle.
        openRuntimeCenter(in: app)
        let pythonState = runtimeState(for: "localPython", in: app)
        if !pythonState.waitForExistence(timeout: 3) { app.swipeUp() }
        XCTAssertTrue(pythonState.waitForExistence(timeout: 10), "Python runtime state missing in developer diagnostics")
        XCTAssertFalse(app.switches["hanlin-runtime-availability-localPython"].exists,
                       "No manual Python lifecycle switch should be exposed")

        let toolPerm = app.switches["hanlin-tool-permission-execute_local_python_code"].firstMatch
        for _ in 0..<3 where !toolPerm.waitForExistence(timeout: 3) {
            app.swipeUp()
        }
        XCTAssertTrue(toolPerm.waitForExistence(timeout: 10), "Assistant Python permission switch was missing in Runtime Center")
        XCTAssertTrue(isToggleOn(toolPerm), "Assistant Python permission should unconditionally be ON")

        // 2. Switch to Chat and prompt the Agent to execute Python
        openChat(in: app)

        sendPrompt("Run the local Python acceptance tool and report the result.", in: app)
        approveOriginalToolRequest(["source": "print('ui-' + 'tool-ok')"], in: app)

        let finalAnswer = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'AGENT_UI_ACCEPTANCE_COMPLETE'")
        ).firstMatch
        XCTAssertTrue(finalAnswer.waitForExistence(timeout: 45), "The deterministic provider's final answer was not rendered.")

        let toolToggle = app.descendants(matching: .any)["hanlin-reasoning-toggle"].firstMatch
        XCTAssertTrue(toolToggle.waitForExistence(timeout: 10), "The completed tool content toggle was not rendered.")
        tapElement(toolToggle)

        let failedCall = app.descendants(matching: .any)["hanlin-agent-activity-ui-python-invalid-call"].firstMatch
        XCTAssertTrue(failedCall.waitForExistence(timeout: 10), "The failed call must remain individually inspectable")
        tapElement(failedCall)
        let expandedToolText = app.descendants(matching: .any)["hanlin-tool-content-expanded-text"].firstMatch
        XCTAssertTrue(expandedToolText.waitForExistence(timeout: 10), "Expanded tool content text did not appear: \(app.debugDescription)")

        let failedActivity = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == 'hanlin-tool-content-expanded-text' OR label CONTAINS[c] 'invalid' OR label CONTAINS[c] 'unexpected' OR label CONTAINS[c] '⚠️'")
        ).firstMatch
        XCTAssertTrue(failedActivity.waitForExistence(timeout: 10), "The intentional tool failure was not presented truthfully in the real chat UI.")

        let toolActivity = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS[c] 'Local Python' OR label CONTAINS[c] 'execute_local_python_code' OR label CONTAINS[c] 'ui-tool-ok'")
        ).firstMatch
        XCTAssertTrue(toolActivity.waitForExistence(timeout: 45), "Tool activity/result was not rendered in the real chat UI.")

        // Verify that agent execution prepared Python without a manual switch.
        openRuntimeCenter(in: app)
        XCTAssertTrue(waitForRuntimeReady("localPython", in: app, timeout: 20),
                      "Python runtime should become ready automatically after agent execution")
    }

    func testProductionCodeSkillLocalPythonNeedsNoUserNudge() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE"] = "1"
        app.launch()

        // Runtime status is observational; engine activation must not require a toggle.
        openRuntimeCenter(in: app)
        let pythonState = runtimeState(for: "localPython", in: app)
        if !pythonState.waitForExistence(timeout: 3) { app.swipeUp() }
        XCTAssertTrue(pythonState.waitForExistence(timeout: 10), "Python runtime state missing in developer diagnostics")
        XCTAssertFalse(app.switches["hanlin-runtime-availability-localPython"].exists,
                       "No manual Python lifecycle switch should be exposed")

        let toolPerm = app.switches["hanlin-tool-permission-execute_local_python_code"].firstMatch
        for _ in 0..<3 where !toolPerm.waitForExistence(timeout: 3) {
            app.swipeUp()
        }
        XCTAssertTrue(toolPerm.waitForExistence(timeout: 10), "Assistant Python permission switch was missing in Runtime Center")
        XCTAssertTrue(isToggleOn(toolPerm), "Assistant Python permission should unconditionally be ON")

        // 2. Open Chat and send prompt (single user turn, no second nudge required)
        openChat(in: app)
        sendPrompt("Use Python to calculate 6*7 and tell me the result.", in: app)
        approveOriginalToolRequest(["source": "print('HANLIN_LOCAL_PYTHON_RESULT:' + str(6 * 7))"], in: app)

        // 3. Final answer renders in the same user turn without extra user nudge
        let finalAnswer = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'LOCAL_PYTHON_COMPLETE'")
        ).firstMatch
        XCTAssertTrue(finalAnswer.waitForExistence(timeout: 45), "Final answer LOCAL_PYTHON_COMPLETE was not rendered in the same user turn.")
        XCTAssertTrue(finalAnswer.label.contains("42"), "Calculated result 42 was not rendered.")

        // Verify tool activity is present and no remote python was invoked
        let remoteActivity = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'execute_remote_python_code'")).firstMatch
        XCTAssertFalse(remoteActivity.exists, "Remote Python must not be invoked when local python is supported")

        // Verify that agent execution prepared Python without a manual switch.
        openRuntimeCenter(in: app)
        XCTAssertTrue(waitForRuntimeReady("localPython", in: app, timeout: 20),
                      "Python runtime should become ready automatically after agent execution")
    }

    func testStopThenNewMessageHasNoGhostOldRun() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE"] = "1"
        app.launch()

        openChat(in: app)
        let input = chatInputElement(in: app)
        XCTAssertTrue(input.waitForExistence(timeout: 20), "The real chat input did not appear.")
        tapElement(input)
        input.typeText("START_DELAYED_RUN_A")

        let send = app.buttons["hanlin-chat-send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 10))
        tapElement(send)

        // 1. Assert stop button appears while Run A is delayed and tap Stop
        let stopButton = app.buttons["hanlin-chat-stop"].firstMatch
        XCTAssertTrue(stopButton.waitForExistence(timeout: 10), "Stop button did not appear during delayed run A")
        tapElement(stopButton)

        // 2. Input becomes available again for Run B
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Input field did not become ready after stopping run A")
        tapElement(input)
        input.typeText("START_RUN_B")
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        tapElement(send)

        // 3. Run B finishes cleanly
        let assistantBubbles = app.otherElements.matching(identifier: "hanlin-assistant-bubble")
        // Native Markdown exposes a UITextView with value plus a nested text
        // accessibility element. Match the owning value, not sidebar labels
        // or StaticText-only descendants, and count that answer exactly once.
        let runBAnswer = assistantBubbles.descendants(matching: .textView).matching(
            NSPredicate(format: "value == %@", "RUN_B_COMPLETE")
        ).firstMatch
        let runBCompleted = runBAnswer.waitForExistence(timeout: 30)
        if !runBCompleted {
            let state = XCTAttachment(string: app.debugDescription)
            state.name = "Stop then new run UI state"
            state.lifetime = .keepAlways
            add(state)
        }
        XCTAssertTrue(runBCompleted, "Run B did not complete with RUN_B_COMPLETE")

        // 4. Wait beyond deterministic Run A delay interval (~1.5s)
        Thread.sleep(forTimeInterval: 2.0)

        // 5. Assert RUN_A_LATE_GHOST does not exist, RUN_B_COMPLETE exists exactly once in chat bubbles, no stale Stop, no stuck Thinking
        let runAGhost = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'RUN_A_LATE_GHOST'")
        ).firstMatch
        XCTAssertFalse(runAGhost.exists, "Run A late ghost answer RUN_A_LATE_GHOST must not appear after being cancelled")

        let runBMatches = assistantBubbles.descendants(matching: .textView).matching(
            NSPredicate(format: "value == %@", "RUN_B_COMPLETE")
        )
        XCTAssertEqual(runBMatches.count, 1, "RUN_B_COMPLETE must exist exactly once")

        XCTAssertFalse(stopButton.exists, "Stop button should not remain active after run completion")

        let stuckProcessing = assistantBubbles.descendants(matching: .staticText).matching(
            NSPredicate(format: "label == 'Thinking' OR label == 'Thinking…' OR label == 'Processing'")
        ).firstMatch
        XCTAssertFalse(stuckProcessing.exists, "Chat should not be stuck in Thinking or Processing state")
    }

    // MARK: - P0 Source-First Classic Restoration & Full Agent Acceptance (UI-01 .. UI-08)

    func testUI01UnifiedHistoryPinSearchSwitchDraftPreservation() throws {
        let app = launchAcceptanceApp()
        openChat(in: app)

        let input = chatInputElement(in: app)
        XCTAssertTrue(input.waitForExistence(timeout: 20), "Chat input did not appear in Agent Acceptance Chat")
        tapElement(input)
        input.typeText("Draft preserved across switch")
        XCTAssertEqual(input.value as? String, "Draft preserved across switch",
                       "Verify native typing before measuring navigation draft preservation")

        // Open sidebar / list view and create a new conversation
        let newChatButton = chatListToolbarButton("hanlin-new-chat-button", in: app)
        tapElement(newChatButton)

        // A new conversation contains no synthetic welcome message and has an empty draft.
        let freshInput = chatInputElement(in: app)
        XCTAssertTrue(freshInput.waitForExistence(timeout: 10))
        XCTAssertEqual(freshInput.value as? String ?? "", "")
        let infoBubble = app.descendants(matching: .any)["hanlin-info-bubble"].firstMatch
        XCTAssertFalse(infoBubble.exists, "New conversations must not insert a group welcome message")
        XCTAssertFalse(app.staticTexts["New Group Chat"].exists)

        // Switch back to Agent Acceptance Chat and verify the draft was preserved
        ensureChatListVisible(in: app)
        selectChatRow(named: "Agent Acceptance Chat", in: app)

        let restoredInput = chatInputElement(in: app)
        XCTAssertTrue(restoredInput.waitForExistence(timeout: 10))
        let draftValue = (restoredInput.value as? String) ?? ""
        XCTAssertTrue(
            draftValue.contains("Draft preserved across switch"),
            "Expected draft 'Draft preserved across switch' to be preserved after switching chats, got: '\(draftValue)'"
        )
        attachScreenshot("UI-01_UnifiedHistoryPinSearchSwitchDraftPreservation", in: app)
    }

    func testUI02ClassicUserAndAssistantBubbleWithDirectActionButtons() throws {
        let app = launchAcceptanceApp()
        openChat(in: app)

        sendPrompt("PROMPT_UI02_CLASSIC_BUBBLES", in: app)

        let finalAnswer = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'UI02_CLASSIC_COMPLETE'")
        ).firstMatch
        XCTAssertTrue(finalAnswer.waitForExistence(timeout: 30), "UI02 classic bubble final answer did not render")

        XCTAssertTrue(app.descendants(matching: .any)["hanlin-user-bubble"].firstMatch.exists, "User bubble must exist")
        XCTAssertTrue(app.descendants(matching: .any)["hanlin-assistant-bubble"].firstMatch.exists, "Assistant bubble must exist")

        // Verify direct action buttons are visible below the assistant bubble without opening any menu
        let actionRow = app.descendants(matching: .any)["hanlin-action-buttons-row"].firstMatch
        XCTAssertTrue(actionRow.waitForExistence(timeout: 10), "Direct action buttons row must be visible below assistant bubble")
        XCTAssertTrue(app.buttons["hanlin-action-copy"].firstMatch.exists, "Copy action button must be directly visible")
        XCTAssertTrue(app.buttons["hanlin-action-select"].firstMatch.exists, "Select text action button must be directly visible")
        XCTAssertTrue(app.buttons["hanlin-action-tts"].firstMatch.exists, "Read aloud action button must be directly visible")
        XCTAssertTrue(app.buttons["hanlin-action-translate"].firstMatch.exists, "Translate action button must be directly visible")
        XCTAssertTrue(app.buttons["hanlin-action-retry"].firstMatch.exists, "Retry action button must be directly visible")

        attachScreenshot("UI-02_ClassicUserAndAssistantBubbleWithDirectActionButtons", in: app)
    }

    func testUserBubbleLongPressKeepsNativeActionsAndOriginalMessage() throws {
        continueAfterFailure = false
        let app = launchAcceptanceApp(isolatedStore: true)
        defer { app.terminate() }
        openChat(in: app)
        let prompt = "PROMPT_UI02_CLASSIC_BUBBLES"
        sendPrompt(prompt, in: app)
        let final = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'UI02_CLASSIC_COMPLETE'")).firstMatch
        XCTAssertTrue(final.waitForExistence(timeout: 30))
        let bubble = app.descendants(matching: .any)["hanlin-user-bubble"].firstMatch
        XCTAssertTrue(bubble.waitForExistence(timeout: 5))
        XCTAssertTrue(bubble.isHittable)
        let originalFrame = bubble.frame
        XCTAssertEqual(bubble.label, prompt)
        attachScreenshot("user-bubble-before-native-lift", in: app)
        // Retain a simulator screen recording around this actual gesture to
        // inspect the lift's first frames as well as the settled screenshot.
        // A screenshot after menu presentation alone cannot prove that interval.
        print("HANLIN_USER_BUBBLE_LIFT_START uptime=\(ProcessInfo.processInfo.systemUptime)")
        bubble.press(forDuration: 1.2)
        let copy = app.buttons["Copy Content"].firstMatch
        let select = app.buttons["Select Text"].firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 10), "The original user menu must remain native")
        XCTAssertTrue(select.exists, "The shared shape correction must preserve host actions")
        print("HANLIN_USER_BUBBLE_LIFT_PRESENTED uptime=\(ProcessInfo.processInfo.systemUptime)")
        attachScreenshot("user-bubble-native-lift-presented", in: app)
        tapElement(select)
        let done = app.buttons["hanlin-text-selection-done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        let selectedText = app.textViews.matching(
            NSPredicate(format: "value == %@ OR label == %@", prompt, prompt)).firstMatch
        XCTAssertTrue(selectedText.waitForExistence(timeout: 5),
                      "The original message must reach the existing native selection sheet")
        tapElement(done)
        XCTAssertTrue(done.waitForNonExistence(timeout: 10))
        XCTAssertTrue(bubble.isHittable)
        XCTAssertEqual(bubble.label, prompt)
        XCTAssertEqual(bubble.frame.width, originalFrame.width, accuracy: 1)
        XCTAssertEqual(bubble.frame.height, originalFrame.height, accuracy: 1)
        XCTAssertTrue(final.exists, "Menu dismissal must preserve the conversation")
        attachScreenshot("user-bubble-native-lift-restored", in: app)
    }

    func testUI03SearchMessageAndDeduplicatedCitations() throws {
        try exerciseUI03SearchMessageAndDeduplicatedCitations(hebrew: false)
    }

    func testUI03HebrewRTLSearchMessageAndDeduplicatedCitations() throws {
        try exerciseUI03SearchMessageAndDeduplicatedCitations(hebrew: true)
    }

    private func exerciseUI03SearchMessageAndDeduplicatedCitations(hebrew: Bool) throws {
        continueAfterFailure = false
        let app = launchAcceptanceApp(language: hebrew ? "he" : "en", locale: hebrew ? "he_IL" : "en_US",
                                      isolatedStore: true)
        let screenshotPrefix = hebrew ? "UI-03_HE_RTL" : "UI-03"
        let verificationSource = "print('UI03_LOCAL_RESULT_' + str(6 * 7))"
        openChat(in: app)
        revokeRememberedToolPermissions(in: app)

        sendPrompt(hebrew ? "PROMPT_UI03_SEARCH_CITATIONS_HE" : "PROMPT_UI03_SEARCH_CITATIONS", in: app)
        let inspectHebrewApproval: ((XCUIElement) -> Void)? = hebrew ? { owner in
            // Read one coherent native snapshot. Re-querying each label can
            // consume the unchanged Host deadline before the request is reviewed.
            guard let snapshot = try? owner.snapshot() else {
                XCTFail("The original Hebrew approval must have an accessible snapshot")
                return
            }
            var elements = [snapshot]
            var index = 0
            while index < elements.count {
                elements.append(contentsOf: elements[index].children)
                index += 1
            }
            let review = elements.first { $0.identifier == "hanlin-tool-consent-review-toggle" }
            let allow = elements.first { $0.identifier == "hanlin-tool-consent-allow-remember" }
            let deny = elements.first { $0.identifier == "hanlin-tool-consent-deny" }
            let scope = elements.first { $0.identifier == "hanlin-tool-consent-visible-request" }
            XCTAssertFalse(elements.contains { $0.identifier == "hanlin-tool-consent-original-request" },
                           "The pending compact approval must keep raw request details closed")
            XCTAssertEqual(allow?.label, "לאשר ולזכור")
            XCTAssertEqual(deny?.label, "לדחות")
            XCTAssertTrue(review?.label.contains("מריץ קוד") == true, "The actual Python approval action title must be Hebrew")
            XCTAssertTrue(review?.label.contains("ממתין לאישור") == true, "The actual pending status must be Hebrew")
            XCTAssertTrue(scope?.label.contains(verificationSource) == true, "The compact scope must show the actual bounded Python operation")
            let labels = elements.map(\.label)
            XCTAssertTrue(labels.contains("ההרשאה הזאת תחול גם בשיחות האחרות שלך."),
                          "The real remembered permission scope must be disclosed in Hebrew")
            XCTAssertFalse(labels.contains { $0.contains("??") || $0.contains("\u{FFFD}") },
                           "The actual Hebrew approval card must not contain corrupted labels")
            let pending = XCTAttachment(screenshot: owner.screenshot())
            pending.name = screenshotPrefix + "_CompactPendingApprovalBeforeReview"
            pending.lifetime = .keepAlways
            self.add(pending)
            self.attachScreenshot(screenshotPrefix + "_PendingApprovalInOriginalChat", in: app)
        } : nil
        // Public page reads deliberately do not require consent. Exercise the
        // original privileged Python approval before those unchanged read calls.
        approveOriginalToolRequest(["source": verificationSource], in: app, remembersDecision: true,
                                   inspectPendingCard: inspectHebrewApproval)

        let finalAnswer = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'UI03_SEARCH_COMPLETE'")
        ).firstMatch
        XCTAssertTrue(finalAnswer.waitForExistence(timeout: 45), "UI03 search final answer did not render")

        let searchBubbles = app.descendants(matching: .any).matching(identifier: "hanlin-search-bubble")
        XCTAssertTrue(searchBubbles.firstMatch.waitForExistence(timeout: 10), "Classic role==search bubble did not render")
        XCTAssertEqual(searchBubbles.count, 1, "Multiple search updates in one turn must update the single search bubble in-place")

        let referenceMaterials = app.descendants(matching: .any)["hanlin-reference-materials"].firstMatch
        XCTAssertTrue(referenceMaterials.waitForExistence(timeout: 10), "Reference materials citation section did not render")

        // The original native renderer exposes an inline attachment's source
        // title in its paragraph label, not as a separate XCUI link. The answer
        // never contains this title, so the two together prove an attachment.
        let citedParagraph = app.textViews.matching(NSPredicate(
            format: "label CONTAINS 'UI03_SEARCH_COMPLETE' AND label CONTAINS 'Hanlin Reference Source'"
        )).firstMatch
        XCTAssertTrue(citedParagraph.waitForExistence(timeout: 10),
                      "The verified source must appear inside the actual native answer paragraph")
        if hebrew {
            XCTAssertTrue(citedParagraph.label.contains("המקורות משולבים בתוך ההודעה"),
                          "The original answer must contain the Hebrew paragraph, not the English fixture")
            XCTAssertFalse(citedParagraph.label.contains("??") || citedParagraph.label.contains("\u{FFFD}"))
        }
        let allSources = app.buttons.matching(identifier: "hanlin-all-sources")
        XCTAssertEqual(allSources.count, 1, "A turn must retain exactly one complete sources footer")
        attachScreenshot(screenshotPrefix + "_SearchMessageAndDeduplicatedCitations", in: app)

        // Locate the chip in the actual screenshot, then tap the real native
        // attachment. No test-only URL callback or synthetic sheet is used.
        let paragraphScreenshot = citedParagraph.screenshot()
        let paragraphAttachment = XCTAttachment(screenshot: paragraphScreenshot)
        paragraphAttachment.name = screenshotPrefix + "_ActualInlineCitationBeforeTap"
        paragraphAttachment.lifetime = .keepAlways
        add(paragraphAttachment)
        let image = try XCTUnwrap(paragraphScreenshot.image.cgImage)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        let boxes = try (request.results ?? []).compactMap { observation -> CGRect? in
            guard let text = observation.topCandidates(1).first,
                  let range = text.string.range(of: "agent.acceptance", options: .caseInsensitive) else { return nil }
            return try text.boundingBox(for: range)?.boundingBox
        }
        XCTAssertEqual(boxes.count, 1, "Expected one actual inline source chip in the paragraph image")
        let box = try XCTUnwrap(boxes.first)
        let measuredBox = XCTAttachment(string: "Inline citation rectangle in normalized screenshot coordinates: \(box)")
        measuredBox.name = screenshotPrefix + "_MeasuredCitationTapTarget"
        measuredBox.lifetime = .keepAlways
        add(measuredBox)
        citedParagraph.coordinate(withNormalizedOffset: CGVector(dx: box.midX, dy: 1 - box.midY)).tap()

        let sourceSheet = app.descendants(matching: .any)["hanlin-scoped-sources"].firstMatch
        XCTAssertTrue(sourceSheet.waitForExistence(timeout: 10), "Tapping the inline chip must open its scoped sources")
        assertReadableSourcesSheet(sourceSheet, in: app)
        let sourceRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'hanlin-source-'"))
        XCTAssertEqual(sourceRows.count, 1, "This sentence cites one canonical returned source")
        XCTAssertTrue(sourceRows.firstMatch.label.contains("Hanlin Reference Source"))
        attachScreenshot(screenshotPrefix + "_InlineCitationScopedSources", in: app)
        tapElement(app.buttons["hanlin-sources-close"].firstMatch)
        XCTAssertTrue(citedParagraph.waitForExistence(timeout: 10), "Closing sources must restore the original answer")

        tapElement(allSources.firstMatch)
        XCTAssertTrue(sourceSheet.waitForExistence(timeout: 10))
        XCTAssertEqual(sourceRows.count, 1, "Fragment variants of the same returned page must remain deduplicated")
        tapElement(app.buttons["hanlin-sources-close"].firstMatch)
        XCTAssertEqual(allSources.count, 1)
        if hebrew {
            XCTAssertTrue(citedParagraph.waitForExistence(timeout: 10))
            let paragraph = XCTAttachment(screenshot: citedParagraph.screenshot())
            paragraph.name = screenshotPrefix + "_FinalHebrewParagraph"
            paragraph.lifetime = .keepAlways
            add(paragraph)
            attachScreenshot(screenshotPrefix + "_FinalRTLAnswer", in: app)
        }
    }


    // Regression for the real all-sources footer: both one and many sources
    // must use the shared native sheet at a usable width, with real scrolling.
    func testSourcesSheetSingleSourceHasReadableNativeSize() throws {
        try exerciseSourcesSheet(count: 1, hebrew: false)
    }

    func testSourcesSheetTwentySevenSourcesScrollsInHebrew() throws {
        try exerciseSourcesSheet(count: 27, hebrew: true)
    }

    private func assertReadableSourcesSheet(_ sheet: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThanOrEqual(sheet.frame.width, min(320, window.width * 0.7),
            "A sources list must retain native readable width instead of fitting to a favicon.")
        XCTAssertGreaterThanOrEqual(sheet.frame.height, min(300, window.height * 0.35),
            "The native sheet must provide useful space for text and scrolling.")
        XCTAssertLessThanOrEqual(sheet.frame.width, window.width + 2)
        XCTAssertLessThanOrEqual(sheet.frame.height, window.height + 2)
        let close = app.buttons["hanlin-sources-close"].firstMatch
        XCTAssertTrue(close.isHittable, "The native dismiss control must stay reachable.")
    }

    private func exerciseSourcesSheet(count: Int, hebrew: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", hebrew ? "(he)" : "(en)",
                               "-AppleLocale", hebrew ? "he_IL" : "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE"] = "1"
        // Each count fixture owns a fresh store; prior cases cannot supply its answer.
        app.launchEnvironment["HANLIN_PHASE2_STORE_ID"] = UUID().uuidString
        app.launchEnvironment["HANLIN_SOURCES_SHEET_ACCEPTANCE_COUNT"] = String(count)
        app.launch()
        defer { app.terminate() }
        openChat(in: app)

        let footer = app.buttons["hanlin-all-sources"].firstMatch
        XCTAssertTrue(footer.waitForExistence(timeout: 20))
        let footerLabel = footer.label
        XCTAssertTrue(footerLabel.contains(String(count)),
            "The original footer must retain every source. Expected \(count); label=\(footerLabel); value=\(String(describing: footer.value))")
        tapElement(footer)
        let sheet = app.descendants(matching: .any)["hanlin-scoped-sources"].firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 10))
        assertReadableSourcesSheet(sheet, in: app)

        let first = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'hanlin-source-' AND label BEGINSWITH 'Source 1:'"
        )).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(first.frame.width, sheet.frame.width * 0.6,
            "A readable title must occupy the sheet, not a compressed icon-width column.")
        XCTAssertTrue(first.isHittable)
        attachScreenshot("Sources-\(count)-Readable-\(hebrew ? "HE" : "EN")", in: app)

        if count > 1 {
            let last = app.buttons.matching(NSPredicate(
                format: "identifier BEGINSWITH 'hanlin-source-' AND label BEGINSWITH %@",
                "Source \(count):"
            )).firstMatch
            for _ in 0..<12 where !last.isHittable { sheet.swipeUp() }
            XCTAssertTrue(last.isHittable, "Every returned source must remain reachable by scrolling.")
            XCTAssertTrue(last.label.contains("מקור לבדיקה"))
            attachScreenshot("Sources-\(count)-Last-Row", in: app)
        }
        tapElement(app.buttons["hanlin-sources-close"].firstMatch)
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 10))
        XCTAssertTrue(footer.isHittable, "Closing sources must restore the same answer footer.")
    }

    func testNativePartialSelectionSaveAndOriginalLongPressPreview() throws {
        continueAfterFailure = false
        let app = launchAcceptanceApp()
        openChat(in: app)
        sendPrompt("PROMPT_CHAT_PRESENTATION", in: app)
        let paragraph = app.textViews.matching(NSPredicate(format: "label == 'alpha beta gamma'")).firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 45), "The actual native Markdown paragraph did not render")
        paragraph.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.5)).doubleTap()
        let save = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Save for myself'")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10), "Native selected-text Save action is missing: \(app.debugDescription)")
        tapElement(save)

        // The visible model header owns the original whole-message long hold.
        // Keep this separate from the native paragraph's selected-text action;
        // the outer gap above the paragraph is not a gesture target.
        let assistant = app.otherElements["hanlin-assistant-bubble"].firstMatch
        let modelHeader = assistant.staticTexts["Agent Acceptance"].firstMatch
        XCTAssertTrue(modelHeader.waitForExistence(timeout: 10), "The original assistant model header must be visible")
        XCTAssertTrue(modelHeader.isHittable, "The original message-actions gesture must be reachable")
        modelHeader.press(forDuration: 1.2)
        let wholeCopy = app.descendants(matching: .any)["hanlin-message-menu-copy"].firstMatch
        XCTAssertTrue(wholeCopy.waitForExistence(timeout: 10), "Original whole-message preview/menu was lost: \(app.debugDescription)")
        attachScreenshot("Chat_OriginalOpaquePreview", in: app)
        tapElement(wholeCopy)

        let saved = chatListToolbarButton("hanlin-saved-messages-open", in: app)
        tapElement(saved)
        let excerpt = app.staticTexts["hanlin-saved-excerpt-text"].firstMatch
        XCTAssertTrue(excerpt.waitForExistence(timeout: 10))
        XCTAssertEqual(excerpt.label, "alpha", "The selected substring, not the whole paragraph, must reach personal storage")
        tapElement(excerpt)
        let openSource = app.buttons["hanlin-saved-open-source"].firstMatch
        XCTAssertTrue(openSource.waitForExistence(timeout: 5))
        tapElement(openSource)
        XCTAssertTrue(paragraph.waitForExistence(timeout: 10), "The saved excerpt did not return through the original conversation")
        attachScreenshot("Chat_SelectedExcerptSource", in: app)
    }

    func testMarkdownLinkOpensAndClosesTheInternalSafariBrowser() throws {
        let app = launchAcceptanceApp()
        openChat(in: app)
        sendPrompt("PROMPT_CHAT_PRESENTATION", in: app)
        let link = app.links.matching(NSPredicate(format: "label == 'Example'")).firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 45), "The actual Markdown link did not render")
        tapElement(link)
        let done = app.buttons["Close"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 15), "The original in-app Safari controller did not open: \(app.debugDescription)")
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 15), "The internal browser has no web content")
        attachScreenshot("Chat_InternalSafariBrowser", in: app)
        tapElement(done)
        let paragraph = app.textViews.matching(NSPredicate(format: "label == 'alpha beta gamma'")).firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 10), "Dismissing the browser did not restore the original chat")
    }

    func testActivityAutoExpansionManualCollapseFinalCollapseAndColdReasoning() throws {
        continueAfterFailure = false
        executionTimeAllowance = 420
        // The fixture advances only after the preceding UI assertions pass.
        // A unique, retained state token cannot miss an acknowledgment.
        let checkpointNonce = UUID().uuidString
        let checkpointName = "com.itorah.hanlin.ui-acceptance.activity." + checkpointNonce
        var checkpointToken: Int32 = 0
        let checkpointRegistration = notify_register_check(checkpointName, &checkpointToken)
        XCTAssertEqual(checkpointRegistration, UInt32(NOTIFY_STATUS_OK))
        guard checkpointRegistration == UInt32(NOTIFY_STATUS_OK) else { return }
        defer { notify_cancel(checkpointToken) }
        XCTAssertEqual(notify_set_state(checkpointToken, 0), UInt32(NOTIFY_STATUS_OK))
        func acknowledgeCheckpoint(_ phase: UInt64) {
            var previous: UInt64 = 0
            XCTAssertEqual(notify_get_state(checkpointToken, &previous), UInt32(NOTIFY_STATUS_OK))
            XCTAssertEqual(previous, phase - 1, "Fixture phases must advance in order")
            XCTAssertEqual(notify_set_state(checkpointToken, phase), UInt32(NOTIFY_STATUS_OK))
            print("HANLIN_ACTIVITY_FIXTURE_ACK=\(phase) uptime=\(ProcessInfo.processInfo.systemUptime)")
        }
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE"] = "1"
        app.launchEnvironment["HANLIN_PHASE2_STORE_ID"] = UUID().uuidString
        app.launchEnvironment["HANLIN_ACTIVITY_FIXTURE_CHECKPOINT"] = checkpointNonce
        app.launch()
        openChat(in: app)
        sendPrompt("PROMPT_ACTIVITY_LIFECYCLE", in: app)
        let summary = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ AND label CONTAINS %@", "hanlin-reasoning-expanded-text",
            "ACTIVITY_FIRST_CHECKPOINT")).firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 15), "Actual activity must expand without a tap")
        XCTAssertGreaterThan(summary.label.count, 140, "Long displayable output stays visible")
        let toggle = app.descendants(matching: .any)["hanlin-reasoning-toggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertTrue(toggle.label.contains("Thinking"), "Expanded work keeps Thinking at the root")
        XCTAssertFalse(toggle.label.contains("Working"), "The generic Working root must not return")
        XCTAssertFalse(app.descendants(matching: .any)["hanlin-reasoning-live-status"].exists,
                       "Provider text must not add a second Thinking header below the root")
        attachScreenshot("activity-thinking-root-expanded", in: app)
        XCTAssertFalse(app.staticTexts["Thinking & tools"].exists)
        XCTAssertFalse(toggle.label.contains("Activity history"))
        tapElement(toggle)
        XCTAssertTrue(summary.waitForNonExistence(timeout: 5))
        XCTAssertTrue(toggle.label.contains("Thinking"), "Manual collapse keeps the same root title")
        attachScreenshot("activity-thinking-root-collapsed", in: app)
        acknowledgeCheckpoint(1)

        let interim = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@", "ACTIVITY_INTERIM_CHECKPOINT")).firstMatch
        XCTAssertTrue(interim.waitForExistence(timeout: 20))
        XCTAssertFalse(summary.exists, "Interim text must respect manual collapse")
        XCTAssertFalse(toggle.label.contains("Worked for"), "Provisional text is not a final answer")
        acknowledgeCheckpoint(2)
        let nextThinking = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "Thinking"), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [nextThinking], timeout: 15), .completed)
        XCTAssertFalse(summary.exists, "New reasoning must not force a manually collapsed tree open")
        tapElement(toggle)
        let second = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ AND label CONTAINS %@", "hanlin-reasoning-expanded-text",
            "ACTIVITY_SECOND_CHECKPOINT")).firstMatch
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        XCTAssertTrue(toggle.label.contains("Thinking"), "New reasoning still uses the one root indicator")
        XCTAssertFalse(app.descendants(matching: .any)["hanlin-reasoning-live-status"].exists)
        XCTAssertTrue(summary.exists, "The first completed summary is retained beside later work")
        acknowledgeCheckpoint(3)

        let final = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@", "ACTIVITY_FINAL_COMPLETE")).firstMatch
        XCTAssertTrue(final.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["hanlin-chat-stop"].firstMatch.waitForNonExistence(timeout: 10))
        XCTAssertTrue(summary.waitForNonExistence(timeout: 5), "The completed activity collapses automatically")
        XCTAssertTrue(toggle.label.contains("Worked for"))
        tapElement(toggle)
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(second.exists)
        XCTAssertFalse(app.descendants(matching: .any)["hanlin-reasoning-live-status"].exists,
            "Historical reasoning has no permanent Thinking label")
        attachScreenshot("activity-live-disclosure-completed-history", in: app)
        openSettings(in: app)
        app.terminate()
        app.launch()
        openChat(in: app)
        XCTAssertTrue(final.waitForExistence(timeout: 20))
        if !summary.waitForExistence(timeout: 2) { tapElement(toggle) }
        XCTAssertTrue(summary.waitForExistence(timeout: 5), "The saved summary survives a cold conversation reopen")
        XCTAssertTrue(second.exists)
        XCTAssertEqual(app.staticTexts["hanlin-phase2-request-count"].label, "0",
            "Opening history does not replay a provider request")
        attachScreenshot("activity-reasoning-cold-restoration", in: app)
    }

    func testUI04CollapsedProgressAndInspectorWithoutRawCoT() throws {
        let app = launchAcceptanceApp(isolatedStore: true)
        openChat(in: app)
        // UI03 intentionally remembers Python consent across conversations.
        // Start this consent journey through the original Settings revocation.
        revokeRememberedToolPermissions(in: app)

        sendPrompt("PROMPT_UI04_REASONING_INSPECTOR", in: app)
        // Local Python uses the original Host's remembered scope, like UI03.
        // Provider-only approvals use the helper's one-use default instead.
        approveOriginalToolRequest(["source": "print(6 * 7)"], in: app, remembersDecision: true)

        let finalAnswer = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'UI04_REASONING_COMPLETE'")
        ).firstMatch
        XCTAssertTrue(finalAnswer.waitForExistence(timeout: 45), "UI04 reasoning final answer did not render")

        let activityToggle = app.descendants(matching: .any)["hanlin-reasoning-toggle"].firstMatch
        XCTAssertTrue(activityToggle.waitForExistence(timeout: 10), "Original chat must render one unified activity disclosure: \(app.debugDescription)")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "hanlin-agent-activity-toggle").count, 1)
        XCTAssertFalse(activityToggle.label.contains("<think>"))
        tapElement(activityToggle)

        let rawCoTText = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS[c] 'Let me think privately' OR label CONTAINS '<think>'")
        ).firstMatch
        XCTAssertFalse(rawCoTText.exists, "Expanded original reasoning/tool sections must never display raw chain-of-thought monologue")

        attachScreenshot("UI-04_CollapsedProgressAndInspectorWithoutRawCoT", in: app)
    }

    func testUI05RichCodeBlockHTMLCardAndAttachments() throws {
        let app = launchAcceptanceApp()
        openChat(in: app)

        // Attach sample image and sample document via composer general `+` menu
        let generalMenu = app.descendants(matching: .any)["hanlin-composer-general-menu"].firstMatch
        XCTAssertTrue(generalMenu.waitForExistence(timeout: 10), "Composer general `+` menu did not appear")
        tapElement(generalMenu)

        let attachImage = app.buttons.matching(
            NSPredicate(format: "identifier == 'hanlin-attach-sample-image' OR label CONTAINS 'Sample Image'")
        ).firstMatch
        XCTAssertTrue(attachImage.waitForExistence(timeout: 5), "Attach Sample Image button did not appear")
        tapElement(attachImage)
        XCTAssertTrue(app.descendants(matching: .any)["hanlin-composer-image-attachment"].firstMatch.waitForExistence(timeout: 5))

        tapElement(generalMenu)
        let attachDoc = app.buttons.matching(
            NSPredicate(format: "identifier == 'hanlin-attach-sample-document' OR label CONTAINS 'Sample Document'")
        ).firstMatch
        XCTAssertTrue(attachDoc.waitForExistence(timeout: 5), "Attach Sample Document button did not appear")
        tapElement(attachDoc)
        XCTAssertTrue(app.descendants(matching: .any)["hanlin-composer-document-attachment"].firstMatch.waitForExistence(timeout: 5))

        sendPrompt("PROMPT_UI05_RICH_CONTENT", in: app)
        approveOriginalToolRequest(["source": "print('Code output: ' + str(6 * 7))"], in: app)
        approveOriginalToolRequest(["code": "<h1>UI05 Interactive Card</h1><p>Rendered HTML surface</p>"], in: app)

        let finalAnswer = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'UI05_RICH_COMPLETE'")
        ).firstMatch
        XCTAssertTrue(finalAnswer.waitForExistence(timeout: 45), "UI05 rich content final answer did not render")

        XCTAssertTrue(app.descendants(matching: .any)["hanlin-user-image-attachment"].firstMatch.exists, "User image attachment was not rendered in bubble")
        XCTAssertTrue(app.descendants(matching: .any)["hanlin-user-document-attachment"].firstMatch.exists, "User document attachment was not rendered in bubble")
        XCTAssertTrue(app.descendants(matching: .any)["hanlin-code-block-row"].firstMatch.exists, "CodeBlockRow was not rendered in assistant bubble")
        XCTAssertTrue(app.descendants(matching: .any)["hanlin-code-view-source"].firstMatch.exists, "View Code button was not rendered in CodeBlockRow")
        XCTAssertTrue(app.descendants(matching: .any)["hanlin-html-web-bubble"].firstMatch.exists, "HTML web card was not rendered in assistant bubble")

        attachScreenshot("UI-05_RichCodeBlockHTMLCardAndAttachments", in: app)
    }

    func testUI06ComposerMultilineAttachmentsModelSelectorNoOverlap() throws {
        let app = launchAcceptanceApp()
        openChat(in: app)

        // 1. Attach and remove image and document via General `+` popover
        let generalMenu = app.descendants(matching: .any)["hanlin-composer-general-menu"].firstMatch
        XCTAssertTrue(generalMenu.waitForExistence(timeout: 10), "General `+` button must exist in composer")
        tapElement(generalMenu)
        let attachImgBtn = app.buttons.matching(
            NSPredicate(format: "identifier == 'hanlin-attach-sample-image' OR label CONTAINS 'Sample Image'")
        ).firstMatch
        XCTAssertTrue(attachImgBtn.waitForExistence(timeout: 5))
        tapElement(attachImgBtn)

        let composerImage = app.descendants(matching: .any)["hanlin-composer-image-attachment"].firstMatch
        XCTAssertTrue(composerImage.waitForExistence(timeout: 5), "Composer image attachment strip did not appear")
        let removeImage = app.buttons["hanlin-remove-image-attachment"].firstMatch
        XCTAssertTrue(removeImage.waitForExistence(timeout: 5))
        tapElement(removeImage)

        tapElement(generalMenu)
        let attachDocBtn = app.buttons.matching(
            NSPredicate(format: "identifier == 'hanlin-attach-sample-document' OR label CONTAINS 'Sample Document'")
        ).firstMatch
        XCTAssertTrue(attachDocBtn.waitForExistence(timeout: 5))
        tapElement(attachDocBtn)
        let composerDoc = app.descendants(matching: .any)["hanlin-composer-document-attachment"].firstMatch
        XCTAssertTrue(composerDoc.waitForExistence(timeout: 5), "Composer document attachment strip did not appear")
        let removeDoc = app.buttons["hanlin-remove-document-attachment"].firstMatch
        XCTAssertTrue(removeDoc.waitForExistence(timeout: 5))
        tapElement(removeDoc)

        // 2. Direct 1-Tap Tools / Skills / MCP button opens Tools popover directly without General `+`
        let toolsDirect = app.descendants(matching: .any)["hanlin-composer-tools-direct"].firstMatch
        XCTAssertTrue(toolsDirect.waitForExistence(timeout: 5), "Direct Tools/Skills/MCP button must exist in composer")
        tapElement(toolsDirect)

        let toolsPopover = app.descendants(matching: .any)["hanlin-composer-tools-popover"].firstMatch
        XCTAssertTrue(toolsPopover.waitForExistence(timeout: 5), "Direct Tools button must open Tools root popover in 1 tap")
        XCTAssertFalse(
            app.descendants(matching: .any)["hanlin-composer-general-popover"].firstMatch.exists,
            "General popover must not be open when Tools popover is open"
        )

        // Navigate into Native Tools subpage inside Tools popover and back
        let nativeToolsRow = app.buttons["hanlin-tools-open-catalog"].firstMatch
        XCTAssertTrue(nativeToolsRow.waitForExistence(timeout: 5), "Native Tools row must exist in Tools popover")
        tapElement(nativeToolsRow)
        let nativeToolsPage = app.descendants(matching: .any)["hanlin-tools-catalog-page"].firstMatch
        XCTAssertTrue(nativeToolsPage.waitForExistence(timeout: 5), "Native Tools subpage did not appear")
        let backBtn = app.buttons["hanlin-tools-subpage-back"].firstMatch
        XCTAssertTrue(backBtn.waitForExistence(timeout: 5), "Back button must exist in Native Tools subpage")
        tapElement(backBtn)

        // Dismiss Tools popover
        XCTAssertTrue(toolsPopover.exists, "Tools popover must still exist after returning from subpage")
        tapElement(toolsDirect)
        XCTAssertTrue(toolsPopover.waitForNonExistence(timeout: 5), "Tools popover must dismiss on tap")

        let input = chatInputElement(in: app)
        tapElement(input)
        if let focused = input.value(forKey: "hasKeyboardFocus") as? Bool, !focused {
            tapElement(input)
        }

        // 3. Verify multiline input and non-overlapping two-entry composer controls
        input.typeText("Line 1 of multiline composer test\nLine 2 of multiline composer test\nLine 3 of multiline composer test")

        let modelPicker = app.descendants(matching: .any)["hanlin-composer-model-picker"].firstMatch
        let sendButton = app.buttons["hanlin-chat-send"].firstMatch
        XCTAssertTrue(modelPicker.waitForExistence(timeout: 5), "Compact model picker capsule must exist in composer")
        XCTAssertTrue(sendButton.waitForExistence(timeout: 5), "Send button must exist in composer")
        XCTAssertFalse(
            generalMenu.frame.intersects(toolsDirect.frame),
            "General `+` button and Direct Tools button must never overlap"
        )
        XCTAssertFalse(
            toolsDirect.frame.intersects(modelPicker.frame),
            "Direct Tools button and Model Picker capsule must never overlap"
        )
        XCTAssertFalse(
            modelPicker.frame.intersects(sendButton.frame),
            "Model picker capsule (\(modelPicker.frame)) and send button (\(sendButton.frame)) must never overlap"
        )

        // 4. Open Model Picker popover, navigate into All Models, and back
        tapElement(modelPicker)
        let modelPopover = app.descendants(matching: .any)["hanlin-model-picker-popover"].firstMatch
        XCTAssertTrue(modelPopover.waitForExistence(timeout: 5), "Model picker popover must appear on tap")
        let allModelsButton = app.buttons["hanlin-model-picker-all-models-button"].firstMatch
        XCTAssertTrue(allModelsButton.waitForExistence(timeout: 5), "All Models button must exist in model picker popover")
        tapElement(allModelsButton)

        let modelSearchField = app.textFields["hanlin-model-picker-search"].firstMatch
        XCTAssertTrue(modelSearchField.waitForExistence(timeout: 5), "Model search textfield did not appear")
        let modelBackBtn = app.buttons["hanlin-model-picker-back-button"].firstMatch
        XCTAssertTrue(modelBackBtn.waitForExistence(timeout: 5), "Back button must exist in All Models page")
        tapElement(modelBackBtn)

        XCTAssertTrue(allModelsButton.waitForExistence(timeout: 5), "Model picker root must reappear after tapping Back")
        tapElement(modelPicker)
        if !modelPopover.waitForNonExistence(timeout: 2) {
            app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.2)).tap()
        }
        XCTAssertTrue(modelPopover.waitForNonExistence(timeout: 5), "Model picker popover must dismiss on tap")

        attachScreenshot("UI-06_ComposerMultilineAttachmentsModelSelectorNoOverlap", in: app)
    }

    func testUI07StopAndRetryRecoveryWithoutDuplicateBubbles() throws {
        let app = launchAcceptanceApp()
        openChat(in: app)

        sendPrompt("PROMPT_UI07_FAIL_ONCE", in: app)

        let errorBubble = app.descendants(matching: .any)["hanlin-error-bubble"].firstMatch
        XCTAssertTrue(errorBubble.waitForExistence(timeout: 20), "Error bubble did not appear on simulated HTTP 500 failure")

        let retryButton = app.buttons["hanlin-error-retry-button"].firstMatch
        XCTAssertTrue(retryButton.waitForExistence(timeout: 10), "Retry button inside error bubble did not appear")
        tapElement(retryButton)

        let assistantBubbles = app.otherElements.matching(identifier: "hanlin-assistant-bubble")
        // Count canonical assistant rows containing the actual native paragraph.
        // UITextView exposes both an outer and an inner accessibility text node;
        // neither node duplication nor the sidebar preview is a second message.
        let recoveredAnswers = assistantBubbles.containing(
            .textView, identifier: "UI07_RETRY_RECOVERY_COMPLETE"
        )
        XCTAssertTrue(recoveredAnswers.firstMatch.waitForExistence(timeout: 30), "Retry did not recover with UI07_RETRY_RECOVERY_COMPLETE")

        XCTAssertFalse(errorBubble.exists, "Stale error bubble must be removed on retry")
        XCTAssertEqual(assistantBubbles.count, 1, "Assistant bubble must exist exactly once after retry")
        XCTAssertEqual(recoveredAnswers.count, 1, "Retry must produce exactly 1 assistant bubble without duplicates")
        let userPrompts = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'PROMPT_UI07_FAIL_ONCE'")
        )
        XCTAssertEqual(userPrompts.count, 1, "Retry must not duplicate the user prompt bubble")

        attachScreenshot("UI-07_StopAndRetryRecoveryWithoutDuplicateBubbles", in: app)
    }

    func testUI08ConversationalMCPLifecycleAndSecondTurnReuse() throws {
        let app = launchAcceptanceApp()
        openChat(in: app)

        // Turn 1: Install local .tgz MCP server via manage_mcp_servers and call mcp__hanlin_echo_mcp__echo_ping in the same turn
        sendPrompt("PROMPT_UI08_MCP_TURN_1", in: app)

        let turn1Answer = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'UI08_MCP_TURN_1_COMPLETE'")
        ).firstMatch
        XCTAssertTrue(turn1Answer.waitForExistence(timeout: 90), "Turn 1 conversational MCP install + tool call did not complete")
        XCTAssertTrue(turn1Answer.label.contains("ECHO_PONG_OK:turn1"), "Turn 1 did not include live MCP worker response ECHO_PONG_OK:turn1")

        // Turn 2: Reuse the installed MCP server tool in the next turn of the same conversation without reinstalling
        sendPrompt("PROMPT_UI08_MCP_TURN_2", in: app)

        let turn2Answer = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'UI08_MCP_TURN_2_COMPLETE'")
        ).firstMatch
        XCTAssertTrue(turn2Answer.waitForExistence(timeout: 60), "Turn 2 conversational MCP tool reuse did not complete")
        XCTAssertTrue(turn2Answer.label.contains("ECHO_PONG_OK:turn2"), "Turn 2 did not include live MCP worker response ECHO_PONG_OK:turn2")

        attachScreenshot("UI-08_ConversationalMCPLifecycleAndSecondTurnReuse", in: app)
    }

    func testUI09DirectToolsCatalogAndSkillsNavigation() throws {
        let app = launchAcceptanceApp()
        openChat(in: app)

        let toolsDirect = app.descendants(matching: .any)["hanlin-composer-tools-direct"].firstMatch
        XCTAssertTrue(toolsDirect.waitForExistence(timeout: 5), "Direct Tools button must exist")
        tapElement(toolsDirect)

        let toolsPopover = app.descendants(matching: .any)["hanlin-composer-tools-popover"].firstMatch
        XCTAssertTrue(toolsPopover.waitForExistence(timeout: 5), "Direct Tools button must open Tools popover")
        XCTAssertFalse(app.descendants(matching: .any)["hanlin-composer-general-popover"].firstMatch.exists)

        // 1. Tool Use Toggle exists
        let toolUseToggle = app.descendants(matching: .any)["hanlin-tool-use-toggle"].firstMatch
        XCTAssertTrue(toolUseToggle.waitForExistence(timeout: 5), "Tool use toggle must exist")

        // 2. Open Native Tools Catalog subpage and return
        let catalogRow = app.buttons["hanlin-tools-open-catalog"].firstMatch
        XCTAssertTrue(catalogRow.waitForExistence(timeout: 5), "Open catalog row must exist")
        tapElement(catalogRow)

        let catalogPage = app.descendants(matching: .any)["hanlin-tools-catalog-page"].firstMatch
        XCTAssertTrue(catalogPage.waitForExistence(timeout: 5), "Native tools catalog subpage must appear")
        let backBtn1 = app.buttons["hanlin-tools-subpage-back"].firstMatch
        XCTAssertTrue(backBtn1.waitForExistence(timeout: 5), "Back button must exist")
        tapElement(backBtn1)

        // 3. Open Skills subpage, search field exists, return
        let skillsRow = app.buttons["hanlin-tools-open-skills"].firstMatch
        XCTAssertTrue(skillsRow.waitForExistence(timeout: 5), "Open skills row must exist")
        tapElement(skillsRow)

        let skillsPage = app.descendants(matching: .any)["hanlin-tools-skills-page"].firstMatch
        XCTAssertTrue(skillsPage.waitForExistence(timeout: 5), "Skills subpage must appear")
        let skillsSearch = app.textFields["hanlin-tools-skills-search"].firstMatch
        XCTAssertTrue(skillsSearch.waitForExistence(timeout: 5), "Skills search field must exist")
        let backBtn2 = app.buttons["hanlin-tools-subpage-back"].firstMatch
        XCTAssertTrue(backBtn2.waitForExistence(timeout: 5))
        tapElement(backBtn2)

        // 4. Open MCP subpage, assert global MCP toggle, return
        let mcpRow = app.buttons["hanlin-tools-open-mcp"].firstMatch
        XCTAssertTrue(mcpRow.waitForExistence(timeout: 5), "Open MCP row must exist")
        tapElement(mcpRow)

        let mcpPage = app.descendants(matching: .any)["hanlin-tools-mcp-page"].firstMatch
        XCTAssertTrue(mcpPage.waitForExistence(timeout: 5), "MCP subpage must appear")
        let mcpToggle = app.descendants(matching: .any)["hanlin-mcp-global-toggle"].firstMatch
        XCTAssertTrue(mcpToggle.waitForExistence(timeout: 5), "MCP global toggle must exist")
        let backBtn3 = app.buttons["hanlin-tools-subpage-back"].firstMatch
        XCTAssertTrue(backBtn3.waitForExistence(timeout: 5))
        tapElement(backBtn3)

        // 5. Open Runtime subpage and return
        let runtimeRow = app.buttons["hanlin-tools-open-runtime"].firstMatch
        XCTAssertTrue(runtimeRow.waitForExistence(timeout: 5), "Open runtime row must exist")
        tapElement(runtimeRow)

        let runtimePage = app.descendants(matching: .any)["hanlin-tools-runtime-page"].firstMatch
        XCTAssertTrue(runtimePage.waitForExistence(timeout: 5), "Runtime subpage must appear")
        let backBtn4 = app.buttons["hanlin-tools-subpage-back"].firstMatch
        XCTAssertTrue(backBtn4.waitForExistence(timeout: 5))
        tapElement(backBtn4)

        // Close Tools popover
        tapElement(toolsDirect)
        XCTAssertTrue(toolsPopover.waitForNonExistence(timeout: 5))

        attachScreenshot("UI-09_DirectToolsCatalogAndSkillsNavigation", in: app)
    }

    func testUI10ModelPickerSearchSelectionAndPersistence() throws {
        let app = launchAcceptanceApp()
        openChat(in: app)

        let modelPicker = app.descendants(matching: .any)["hanlin-composer-model-picker"].firstMatch
        XCTAssertTrue(modelPicker.waitForExistence(timeout: 5), "Compact model picker capsule must exist")
        tapElement(modelPicker)

        let modelPopover = app.descendants(matching: .any)["hanlin-model-picker-popover"].firstMatch
        XCTAssertTrue(modelPopover.waitForExistence(timeout: 5), "Model picker popover must appear")

        let allModelsButton = app.buttons["hanlin-model-picker-all-models-button"].firstMatch
        XCTAssertTrue(allModelsButton.waitForExistence(timeout: 5), "All Models button must exist")
        tapElement(allModelsButton)

        let searchField = app.textFields["hanlin-model-picker-search"].firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "Search field must exist")
        tapElement(searchField)
        searchField.typeText("GPT")

        let firstOption = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'hanlin-model-picker-option-'")
        ).firstMatch
        if firstOption.waitForExistence(timeout: 5) {
            tapElement(firstOption)
            _ = modelPopover.waitForNonExistence(timeout: 5)
        } else {
            let backBtn = app.buttons["hanlin-model-picker-back-button"].firstMatch
            if backBtn.waitForExistence(timeout: 5) {
                tapElement(backBtn)
                tapElement(modelPicker)
            }
        }

        attachScreenshot("UI-10_ModelPickerSearchSelectionAndPersistence", in: app)
    }

    // MARK: - §7B InteriorOrganizer V3.3 Source-Parity OrganizerDock & Compact Workspace XCUI Suite

    func testDockCompactHomeShowsThreeRecentWithOnePersistentComposer() throws {
        let app = launchDockAcceptanceApp(simulatedWidth: "390")
        _ = selectTab(identifier: "hanlin-home-tab", labels: ["Chats", "Messages", "Home", "列表"], in: app)

        let recentSection = app.descendants(matching: .any)["hanlin-compact-recent-section"].firstMatch
        let viewAllBtn = app.buttons["hanlin-compact-view-all-button"].firstMatch
        XCTAssertTrue(recentSection.waitForExistence(timeout: 15), "Compact Recent Conversations section must appear on Home")
        XCTAssertTrue(viewAllBtn.waitForExistence(timeout: 10), "View All zoom source button must appear on Home")

        // Exactly 3 recent conversation rows (sorted strictly by lastEdited descending)
        let row0 = app.buttons["hanlin-compact-recent-row-0"].firstMatch
        let row1 = app.buttons["hanlin-compact-recent-row-1"].firstMatch
        let row2 = app.buttons["hanlin-compact-recent-row-2"].firstMatch
        let row3 = app.buttons["hanlin-compact-recent-row-3"].firstMatch
        XCTAssertTrue(row0.waitForExistence(timeout: 10), "Recent row 0 must exist")
        XCTAssertTrue(row1.waitForExistence(timeout: 5), "Recent row 1 must exist")
        XCTAssertTrue(row2.waitForExistence(timeout: 5), "Recent row 2 must exist")
        XCTAssertFalse(row3.exists, "At most 3 recent conversations may be shown on compact Home")
        XCTAssertTrue(row0.label.contains("Agent Acceptance Chat"), "Newest conversation must be row 0")

        // The original Morph input stays anchored at the bottom of compact Home
        let dock = app.descendants(matching: .any)["hanlin-composer-surface"].firstMatch
        let input = chatInputElement(in: app)
        XCTAssertTrue(dock.waitForExistence(timeout: 10), "Persistent Morph composer must exist on compact Home")
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Persistent chat input must exist on compact Home")
        XCTAssertGreaterThan(
            dock.frame.maxY,
            app.windows.firstMatch.frame.height * 0.65,
            "Persistent Morph composer must be anchored near the bottom of the screen"
        )

        attachScreenshot("7B-01_CompactHome_ThreeRecent_PersistentComposer", in: app)
    }

    func testViewAllZoomSourceToLibraryAndCancelledInteractiveBack() throws {
        let app = launchDockAcceptanceApp(simulatedWidth: "390")
        _ = selectTab(identifier: "hanlin-home-tab", labels: ["Chats", "Messages", "Home", "列表"], in: app)

        let viewAllBtn = app.buttons["hanlin-compact-view-all-button"].firstMatch
        XCTAssertTrue(viewAllBtn.waitForExistence(timeout: 15), "View All button must exist on compact Home")
        attachScreenshot("7B-02a_BeforeViewAllZoom", in: app)
        tapElement(viewAllBtn)

        let library = app.descendants(matching: .any)["hanlin-compact-conversation-library"].firstMatch
        XCTAssertTrue(library.waitForExistence(timeout: 10), "Full Conversation Library must open via zoom transition")
        attachScreenshot("7B-02b_InsideConversationLibrary", in: app)

        // All 4 seeded conversations (including the 4th older pinned thread) appear in the library
        let olderRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'Older Archived Thread' OR identifier CONTAINS 'Older Archived Thread'")
        ).firstMatch
        XCTAssertTrue(olderRow.waitForExistence(timeout: 10), "4th conversation must be visible in full library")

        // Persistent bottom composer is hidden while browsing the full conversation library
        let dock = app.descendants(matching: .any)["hanlin-composer-surface"].firstMatch
        XCTAssertFalse(dock.exists && dock.isHittable, "Persistent composer dock must be hidden on the full conversation library screen")

        // Simulate a short cancelled interactive edge-swipe back (dx 0.02 -> 0.16)
        let window = app.windows.firstMatch
        let startCoord = window.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
        let shortDragCoord = window.coordinate(withNormalizedOffset: CGVector(dx: 0.16, dy: 0.5))
        startCoord.press(forDuration: 0.05, thenDragTo: shortDragCoord)

        // Navigate back to compact Home and verify the persistent composer dock is restored
        if library.exists {
            navigateBack(in: app)
        }
        XCTAssertTrue(viewAllBtn.waitForExistence(timeout: 10), "Must return to compact Home after library back navigation")
        XCTAssertTrue(dock.waitForExistence(timeout: 10), "Persistent composer dock must be restored on compact Home")
        attachScreenshot("7B-02c_ReturnedFromLibraryZoom", in: app)
    }

    func testIpadNarrowShowsRecentAndWidePreservesSplitSidebar() throws {
        // 1. Narrow (< 640pt) must present compact Recent Conversations
        let narrowApp = launchDockAcceptanceApp(simulatedWidth: "500")
        _ = selectTab(identifier: "hanlin-home-tab", labels: ["Chats", "Messages", "Home", "列表"], in: narrowApp)
        let recentSection = narrowApp.descendants(matching: .any)["hanlin-compact-recent-section"].firstMatch
        XCTAssertTrue(recentSection.waitForExistence(timeout: 15), "Narrow width (<640pt) must present compact Recent Conversations")
        attachScreenshot("7B-03a_WidthAdaptiveWorkspace_Narrow500pt", in: narrowApp)
        narrowApp.terminate()

        // 2. Wide (>= 640pt) must preserve NavigationSplitView sidebar
        let wideApp = launchDockAcceptanceApp(simulatedWidth: "1024")
        _ = selectTab(identifier: "hanlin-home-tab", labels: ["Chats", "Messages", "Home", "列表"], in: wideApp)
        ensureChatListVisible(in: wideApp)
        let sidebar = wideApp.navigationBars["Hanlin"].firstMatch
        let originalRow = wideApp.buttons["hanlin-chat-row-Agent Acceptance Chat"].firstMatch
        XCTAssertTrue(sidebar.exists && sidebar.isHittable, "Wide iPad must preserve the native sidebar")
        XCTAssertTrue(originalRow.exists && originalRow.isHittable, "The original conversation must remain reachable in the sidebar")
        attachScreenshot("7B-03b_WidthAdaptiveWorkspace_Wide1024pt", in: wideApp)
    }

    // Keep the original selector for acceptance traceability. The approved
    // Morph design places its panel above the persistent input; the retired
    // Organizer ZStack and its drag-to-open handle are not shipping controls.
    func testDrawerGrowsFromComposerNotPopover() throws {
        let app = launchDockAcceptanceApp()
        openChat(in: app)

        let panel = app.descendants(matching: .any)["morphing-action-panel"].firstMatch
        let composer = app.descendants(matching: .any)["hanlin-composer-surface"].firstMatch
        let general = app.buttons["hanlin-composer-general-menu"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        XCTAssertTrue(general.waitForExistence(timeout: 10) && general.isHittable)
        XCTAssertFalse(panel.exists, "A collapsed Morph composer must not mount a detached panel")
        let collapsedFrame = composer.frame
        attachScreenshot("7B-04a_MorphCollapsed", in: app)

        general.tap()
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        let content = app.descendants(matching: .any)["hanlin-composer-general-popover"].firstMatch
        XCTAssertTrue(content.waitForExistence(timeout: 5))
        XCTAssertLessThan(panel.frame.minY, collapsedFrame.minY - 180,
                          "The original action panel must grow upward above the input")
        XCTAssertLessThanOrEqual(panel.frame.maxY, composer.frame.minY + 1,
                                 "The approved Morph panel must stay above the persistent input")
        XCTAssertLessThan(abs(composer.frame.maxY - collapsedFrame.maxY), 16,
                          "Opening the palette must preserve the input's bottom anchor")
        XCTAssertEqual(app.popovers.count, 0, "The action panel must remain in the original composer")
        let saved = app.buttons["hanlin-general-prompts-button"].firstMatch
        let pageScroll = app.scrollViews["hanlin-composer-page-scroll"].firstMatch
        XCTAssertTrue(pageScroll.waitForExistence(timeout: 5))
        for _ in 0..<5 {
            if saved.isHittable { break }
            pageScroll.swipeUp()
        }
        XCTAssertTrue(saved.isHittable, "The original saved-prompts action must remain reachable below the capability grid")
        attachScreenshot("7B-04b_MorphExpanded", in: app)

        let close = app.buttons["composer-toolbar-close"].firstMatch
        XCTAssertTrue(close.exists && close.isHittable)
        close.tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
        XCTAssertTrue(composer.exists, "Closing the palette must preserve the same input")
    }

    // Keep the existing test selector used by acceptance scripts. The approved
    // Morph uses automatic native line growth and a sheet, not an input handle.
    func testDrawerHandleDragCloseOpenAndComposerResize() throws {
        let app = launchDockAcceptanceApp()
        openChat(in: app)

        let expand = app.buttons["hanlin-composer-expand-editor"].firstMatch
        let composerShell = app.descendants(matching: .any)["hanlin-composer-surface"].firstMatch
        let generalBtn = app.buttons["hanlin-composer-general-menu"].firstMatch
        let panel = app.descendants(matching: .any)["morphing-action-panel"].firstMatch
        XCTAssertTrue(expand.waitForExistence(timeout: 10), "The native expanded editor action must remain reachable")
        XCTAssertTrue(composerShell.waitForExistence(timeout: 10))
        XCTAssertTrue(generalBtn.exists && generalBtn.isHittable)

        generalBtn.tap()
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        let close = app.buttons["composer-toolbar-close"].firstMatch
        XCTAssertTrue(close.exists && close.isHittable)
        close.tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
        generalBtn.tap()
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "The original palette must reopen")
        generalBtn.tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
        attachScreenshot("7B-05a_AfterMorphCloseReopen", in: app)

        let input = chatInputElement(in: app)
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        let old = (input.value as? String) ?? ""
        input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count))
        let emptyHeight = input.frame.height
        let draft = "Native automatic composer draft"
        input.typeText(draft)
        let grown = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            input.frame.height > emptyHeight + 5
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [grown], timeout: 5), .completed,
                       "The first draft text must grow the native editor to its two-line minimum")
        XCTAssertEqual(input.value as? String, draft)
        attachScreenshot("7B-05b_AutomaticComposerGrowth", in: app)

        expand.tap()
        let expandedSheet = app.descendants(matching: .any)["hanlin-expanded-editor-sheet"].firstMatch
        XCTAssertTrue(expandedSheet.waitForExistence(timeout: 5))
        let expandedText = expandedSheet.textViews.firstMatch
        XCTAssertTrue(expandedText.waitForExistence(timeout: 5))
        XCTAssertEqual(expandedText.value as? String, draft)
        expandedText.tap()
        let suffix = " — edited in the native sheet"
        expandedText.typeText(suffix)
        let editedDraft = (expandedText.value as? String) ?? ""
        XCTAssertTrue(editedDraft.contains(suffix), "The expanded native editor must accept typing")
        let sheetClose = app.buttons["hanlin-expanded-editor-close"].firstMatch
        XCTAssertTrue(sheetClose.waitForExistence(timeout: 5))
        sheetClose.tap()
        XCTAssertTrue(expandedSheet.waitForNonExistence(timeout: 5))
        XCTAssertEqual(input.value as? String, editedDraft,
                       "Closing the expanded editor must preserve the same draft owner")
    }

    func testDirectToolsOneTapAndRealState() throws {
        let app = launchDockAcceptanceApp()
        openChat(in: app)

        let tools = app.buttons["hanlin-composer-tools-direct"].firstMatch
        let panel = app.descendants(matching: .any)["morphing-action-panel"].firstMatch
        let composer = app.descendants(matching: .any)["hanlin-composer-surface"].firstMatch
        XCTAssertTrue(tools.waitForExistence(timeout: 10) && tools.isHittable)
        tools.tap()
        let toolsContent = app.descendants(matching: .any)["hanlin-composer-tools-popover"].firstMatch
        XCTAssertTrue(toolsContent.waitForExistence(timeout: 5), "One tap must open the original Tools root")
        XCTAssertTrue(panel.exists)
        XCTAssertEqual(app.popovers.count, 0)
        let inputFrame = composer.frame
        attachScreenshot("7B-06a_DirectToolsInMorph", in: app)

        // The original Morph back control returns to its home page. The plus
        // launcher closes an open palette; it is not a mode-switch button.
        let back = app.buttons["hanlin-tools-subpage-back"].firstMatch
        XCTAssertTrue(back.exists && back.isHittable)
        back.tap()
        let home = app.descendants(matching: .any)["hanlin-composer-general-popover"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 5))
        XCTAssertFalse(toolsContent.exists)
        XCTAssertTrue(panel.exists, "Back must retain the original expanded palette")
        XCTAssertLessThanOrEqual(panel.frame.maxY, composer.frame.minY + 1)
        XCTAssertLessThan(abs(composer.frame.maxY - inputFrame.maxY), 16,
                          "Changing palette pages must preserve the input anchor")
        XCTAssertEqual(app.popovers.count, 0)
        attachScreenshot("7B-06b_MorphBackToHome", in: app)

        let close = app.buttons["composer-toolbar-close"].firstMatch
        XCTAssertTrue(close.exists && close.isHittable)
        close.tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
    }

    func testClassicHanlinIconAndVisualParity() throws {
        let app = launchDockAcceptanceApp()
        openChat(in: app)

        let generalBtn = app.descendants(matching: .any)["hanlin-composer-general-menu"].firstMatch
        let toolsDirect = app.descendants(matching: .any)["hanlin-composer-tools-direct"].firstMatch
        let modelPicker = app.descendants(matching: .any)["hanlin-composer-model-picker"].firstMatch
        let micBtn = app.buttons["hanlin-chat-mic"].firstMatch

        XCTAssertTrue(generalBtn.waitForExistence(timeout: 10))
        XCTAssertTrue(toolsDirect.waitForExistence(timeout: 5))
        XCTAssertTrue(modelPicker.waitForExistence(timeout: 5))
        XCTAssertTrue(micBtn.waitForExistence(timeout: 5), "Classic mic button must appear when draft is empty")

        XCTAssertFalse(generalBtn.frame.intersects(toolsDirect.frame))
        XCTAssertFalse(toolsDirect.frame.intersects(modelPicker.frame))
        XCTAssertFalse(modelPicker.frame.intersects(micBtn.frame))

        // Typing draft reveals classic send button (`arrow.up.circle.fill`)
        let input = chatInputElement(in: app)
        tapElement(input)
        input.typeText("Classic visual parity check")
        let sendBtn = app.buttons["hanlin-chat-send"].firstMatch
        XCTAssertTrue(sendBtn.waitForExistence(timeout: 5), "Classic send button must appear when draft is non-empty")
        attachScreenshot("7B-07_ClassicHanlinVisualParity", in: app)
    }

    func testCompactToolsManagementDestinationsPreserveDraft() throws {
        try verifyToolsManagementDestinations(simulatedWidth: "390")
    }

    func testWideToolsManagementDestinationsPreserveDraft() throws {
        try verifyToolsManagementDestinations(simulatedWidth: "1024")
    }

    private func verifyToolsManagementDestinations(simulatedWidth: String) throws {
        let app = launchDockAcceptanceApp(simulatedWidth: simulatedWidth)
        defer { app.terminate() }
        openChat(in: app)
        let draft = "Keep this draft while managing tools"
        let input = chatInputElement(in: app)
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        tapElement(input)
        input.typeText(draft)

        let tools = app.buttons["hanlin-composer-tools-direct"].firstMatch
        XCTAssertTrue(tools.waitForExistence(timeout: 5))
        tapElement(tools)
        let routes = [
            ("skills", "hanlin-tools-open-skills", "hanlin-tools-open-full-skill-center"),
            ("mcp", "hanlin-tools-open-mcp", "hanlin-tools-open-full-mcp-settings"),
            ("runtime", "hanlin-tools-open-runtime", "hanlin-tools-open-full-runtime-center")
        ]
        for (destination, routeID, linkID) in routes {
            let route = app.buttons[routeID].firstMatch
            XCTAssertTrue(route.waitForExistence(timeout: 5))
            tapElement(route)
            let fullLink = app.buttons[linkID].firstMatch
            XCTAssertTrue(fullLink.waitForExistence(timeout: 5))
            if !fullLink.isHittable {
                app.scrollViews["hanlin-composer-page-scroll"].firstMatch.swipeUp()
            }
            tapElement(fullLink)
            let presented = app.descendants(matching: .any)["hanlin-tools-management-\(destination)"].firstMatch
            XCTAssertTrue(presented.waitForExistence(timeout: 10), "Full management screen must be presented")
            let done = app.buttons["hanlin-tools-management-done"].firstMatch
            XCTAssertTrue(done.waitForExistence(timeout: 5))
            attachScreenshot("Management_\(simulatedWidth)_\(destination)", in: app)
            tapElement(done)
            XCTAssertTrue(presented.waitForNonExistence(timeout: 5))
            let back = app.buttons["hanlin-tools-subpage-back"].firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            tapElement(back)
        }
        tapElement(tools)
        XCTAssertEqual(chatInputElement(in: app).value as? String, draft)
    }

    func testModelPopoverZoomExpandThenNavigate() throws {
        try verifyModelPopoverZoom(simulatedWidth: "1024")
    }

    func testModelPopoverZoomNarrowAndRepeatedPresentation() throws {
        try verifyModelPopoverZoom(simulatedWidth: "500", repeatPresentation: true)
    }

    func testModelPopoverZoomWithKeyboardAndDraft() throws {
        try verifyModelPopoverZoom(simulatedWidth: "500", keyboardOpen: true)
    }

    private func verifyModelPopoverZoom(
        simulatedWidth: String, repeatPresentation: Bool = false, keyboardOpen: Bool = false
    ) throws {
        let app = launchDockAcceptanceApp(simulatedWidth: simulatedWidth)
        openChat(in: app)
        let draft = "Model picker keeps this draft"
        if keyboardOpen {
            let input = chatInputElement(in: app)
            XCTAssertTrue(input.waitForExistence(timeout: 10))
            tapElement(input)
            input.typeText(draft)
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        }

        let modelPicker = app.descendants(matching: .any)["hanlin-composer-model-picker"].firstMatch
        XCTAssertTrue(modelPicker.waitForExistence(timeout: 10))
        let sourceFrame = modelPicker.frame
        // Keep action times and source rectangles beside the uninterrupted simctl
        // recording. Final-state AX assertions alone do not verify a zoom animation.
        var motionEvents: [[String: Any]] = []
        func mark(_ action: String, frame: CGRect) {
            motionEvents.append(["action": action, "time": Date().timeIntervalSince1970,
                "x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height])
        }
        defer {
            if let data = try? JSONSerialization.data(withJSONObject: motionEvents, options: [.prettyPrinted, .sortedKeys]) {
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                attachment.name = "ModelPopover_MotionEvents_\(simulatedWidth)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        mark("open-from-model-button", frame: sourceFrame)
        tapElement(modelPicker)

        let modelPopover = app.descendants(matching: .any)["hanlin-model-picker-popover"].firstMatch
        XCTAssertTrue(modelPopover.waitForExistence(timeout: 5), "Model picker popover must appear")
        let compactPopoverFrame = modelPopover.frame
        attachScreenshot("7B-08a_ModelPopover_CompactRoot", in: app)
        assertModelPopoverIsRendered(in: app, frame: compactPopoverFrame, stage: "compact")

        let allModelsBtn = app.buttons["hanlin-model-picker-all-models-button"].firstMatch
        XCTAssertTrue(allModelsBtn.waitForExistence(timeout: 5))
        mark("zoom-from-all-models-button", frame: allModelsBtn.frame)
        tapElement(allModelsBtn)

        // SwiftUI can flatten an intermediate page group into its containing
        // popover. Require the actual destination controls, then its pixels.
        let search = app.textFields["hanlin-model-picker-search"].firstMatch
        let backBtn = app.buttons["hanlin-model-picker-back-button"].firstMatch
        guard search.waitForExistence(timeout: 5), backBtn.waitForExistence(timeout: 5) else {
            attachScreenshot("ModelPopover_TransitionFailure", in: app)
            XCTFail("All Models page must appear after expansion and navigation")
            return
        }
        guard modelPopover.exists else {
            XCTFail("The model popover must remain presented while navigating")
            return
        }
        let expandedPopoverFrame = modelPopover.frame
        XCTAssertGreaterThan(
            expandedPopoverFrame.height,
            compactPopoverFrame.height + 40,
            "Model popover must expand before/during All Models transition (compact: \(compactPopoverFrame.height), expanded: \(expandedPopoverFrame.height))"
        )
        attachScreenshot("7B-08b_ModelPopover_ExpandedAllModels", in: app)
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(search.isHittable, "Expanded search must be ready for interaction")
        XCTAssertTrue(modelPopover.frame.contains(search.frame), "Search must not be clipped outside the popover")
        assertModelPopoverIsRendered(in: app, frame: modelPopover.frame, stage: "all-models")
        mark("expanded-rendered", frame: modelPopover.frame)

        // Back button collapses back to compact root
        XCTAssertTrue(backBtn.waitForExistence(timeout: 5))
        mark("zoom-back-to-all-models-button", frame: backBtn.frame)
        tapElement(backBtn)
        XCTAssertTrue(allModelsBtn.waitForExistence(timeout: 5))
        let collapsed = NSPredicate { _, _ in
            abs(modelPopover.frame.height - compactPopoverFrame.height) < 8
        }
        let collapsedExpectation = expectation(for: collapsed, evaluatedWith: modelPopover)
        XCTAssertEqual(XCTWaiter.wait(for: [collapsedExpectation], timeout: 5), .completed)
        assertModelPopoverIsRendered(in: app, frame: modelPopover.frame, stage: "back")
        mark("compact-after-back", frame: modelPopover.frame)
        // Dismiss outside the popover, then reopen from the same stable source.
        mark("dismiss-to-model-button", frame: sourceFrame)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.3)).tap()
        XCTAssertTrue(modelPopover.waitForNonExistence(timeout: 5))
        XCTAssertEqual(modelPicker.frame, sourceFrame, "The zoom source must not move when the presentation closes")
        if keyboardOpen {
            XCTAssertTrue(app.keyboards.firstMatch.exists, "Opening the picker must not hide the keyboard and move its source")
            XCTAssertEqual(chatInputElement(in: app).value as? String, draft)
        }
        if repeatPresentation {
            mark("reopen-from-model-button", frame: modelPicker.frame)
            tapElement(modelPicker)
            XCTAssertTrue(allModelsBtn.waitForExistence(timeout: 5))
            mark("double-tap-all-models", frame: allModelsBtn.frame)
            allModelsBtn.doubleTap()
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            XCTAssertTrue(backBtn.waitForExistence(timeout: 5))
            tapElement(backBtn)
            XCTAssertTrue(allModelsBtn.waitForExistence(timeout: 5), "Repeated taps must not push duplicate destinations")
            attachScreenshot("ModelPopover_Reopened_Narrow", in: app)
        }
    }

    /// In 42539502009 AX still reported hittable controls after the entire page
    /// stopped drawing. The fixture has an empty chat behind this header, so its
    /// natural blue title/back text must actually occur in the screenshot pixels.
    private func assertModelPopoverIsRendered(in app: XCUIApplication, frame: CGRect, stage: String) {
        let screenshot = app.screenshot()
        guard let image = screenshot.image.cgImage else {
            XCTFail("Missing model popover screenshot"); return
        }
        let scaleX = CGFloat(image.width) / app.frame.width
        let scaleY = CGFloat(image.height) / app.frame.height
        let header = CGRect(x: (frame.minX - app.frame.minX) * scaleX,
                            y: (frame.minY - app.frame.minY) * scaleY,
                            width: frame.width * scaleX, height: min(80, frame.height) * scaleY)
            .integral.intersection(CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
        guard let crop = image.cropping(to: header) else {
            XCTFail("Model header is outside the screenshot"); return
        }
        var pixels = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
        var bluePixels = 0
        pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: crop.width, height: crop.height,
                bitsPerComponent: 8, bytesPerRow: crop.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: CGFloat(crop.width), height: CGFloat(crop.height)))
            let data = bytes.bindMemory(to: UInt8.self)
            for offset in stride(from: 0, to: data.count, by: 4) {
                let red = Int(data[offset]), green = Int(data[offset + 1]), blue = Int(data[offset + 2])
                // The decorative 22%-opacity blue border cannot reach this
                // contrast against the neutral surface; require real glyphs.
                if blue > red + 70, green > red + 30 { bluePixels += 1 }
            }
        }
        if bluePixels <= 30 {
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "ModelPopover_VisualFailure_\(stage)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertGreaterThan(bluePixels, 30, "\(stage): AX presence is insufficient; the model header must actually render")
    }

    func testDraftAndAttachmentPersistenceAtoBAndFirstSend() throws {
        // Part 1: Compact Home first-turn send + compact A -> B -> A draft & attachment isolation
        let compactApp = launchDockAcceptanceApp(simulatedWidth: "390")
        _ = selectTab(identifier: "hanlin-home-tab", labels: ["Chats", "Messages", "Home", "列表"], in: compactApp)

        let viewAllBtn = compactApp.buttons["hanlin-compact-view-all-button"].firstMatch
        XCTAssertTrue(viewAllBtn.waitForExistence(timeout: 15), "View All button must exist on compact Home")

        sendPrompt("PROMPT_FIRST_TURN_HOME", in: compactApp)
        let firstTurnAnswer = compactApp.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'FIRST_TURN_HOME_COMPLETE'")
        ).firstMatch
        XCTAssertTrue(firstTurnAnswer.waitForExistence(timeout: 30), "Sending from compact Home must create a new chat and complete first turn")
        attachScreenshot("7B-09a_FirstTurnFromCompactHome", in: compactApp)

        // Return to compact Home
        navigateBack(in: compactApp)
        XCTAssertTrue(viewAllBtn.waitForExistence(timeout: 10))
        compactApp.terminate()

        // Part 2: Wide workspace A -> B -> A draft AND attachment persistence
        let app = launchDockAcceptanceApp(simulatedWidth: "1024")
        _ = selectTab(identifier: "hanlin-home-tab", labels: ["Chats", "Messages", "Home", "列表"], in: app)
        ensureChatListVisible(in: app)
        selectChatRow(named: "Agent Acceptance Chat", in: app)

        let inputA = chatInputElement(in: app)
        XCTAssertTrue(inputA.waitForExistence(timeout: 10))
        tapElement(inputA)
        inputA.typeText("Isolated Draft For Chat A")

        // Attach sample image in Chat A
        let generalBtn = app.descendants(matching: .any)["hanlin-composer-general-menu"].firstMatch
        XCTAssertTrue(generalBtn.waitForExistence(timeout: 5))
        tapElement(generalBtn)
        let sampleImageBtn = app.buttons["hanlin-attach-sample-image"].firstMatch
        XCTAssertTrue(sampleImageBtn.waitForExistence(timeout: 5), "Sample image attachment action must exist in General drawer")
        tapElement(sampleImageBtn)

        let imageChip = app.descendants(matching: .any)["hanlin-composer-image-attachment"].firstMatch
        XCTAssertTrue(imageChip.waitForExistence(timeout: 5), "Image attachment preview chip must appear in Chat A")

        // Switch to Architecture Review Notes and verify empty draft and no leaked attachment
        ensureChatListVisible(in: app)
        selectChatRow(named: "Architecture Review Notes", in: app)
        let inputB = chatInputElement(in: app)
        XCTAssertTrue(inputB.waitForExistence(timeout: 10))
        let valB = (inputB.value as? String) ?? ""
        XCTAssertFalse(valB.contains("Isolated Draft For Chat A"), "Chat B must not inherit Chat A's draft")
        XCTAssertFalse(imageChip.exists, "Chat B must not inherit Chat A's image attachment")

        // Switch back to Agent Acceptance Chat and verify Chat A's draft AND image attachment were preserved
        ensureChatListVisible(in: app)
        selectChatRow(named: "Agent Acceptance Chat", in: app)
        let restoredInputA = chatInputElement(in: app)
        XCTAssertTrue(restoredInputA.waitForExistence(timeout: 10))
        let restoredValA = (restoredInputA.value as? String) ?? ""
        XCTAssertTrue(restoredValA.contains("Isolated Draft For Chat A"), "Chat A draft must be preserved across navigation")
        XCTAssertTrue(imageChip.waitForExistence(timeout: 5), "Chat A image attachment must be preserved across navigation")
        attachScreenshot("7B-09b_PerChatDraftAndAttachmentIsolation", in: app)
    }

    func testStreamingStopObserveTemporaryAndStateTransitions() throws {
        let app = launchDockAcceptanceApp()
        openChat(in: app)

        // Start delayed run and verify stop button + disabled drawer handle during active run
        sendPrompt("START_DELAYED_RUN_A", in: app)
        let stopBtn = app.buttons["hanlin-chat-stop"].firstMatch
        XCTAssertTrue(stopBtn.waitForExistence(timeout: 10), "Stop button must appear during streaming run")

        let drawerHandle = app.buttons["hanlin-organizer-drawer-handle"].firstMatch
        if drawerHandle.exists {
            XCTAssertFalse(drawerHandle.isEnabled, "Drawer handle must be disabled while streaming")
        }
        tapElement(stopBtn)
        XCTAssertTrue(stopBtn.waitForNonExistence(timeout: 10), "Stop button must disappear after stopping run")
        attachScreenshot("7B-10_StreamingStopAndStateTransition", in: app)
    }

    func testAccessibilityKeyboardRTLReduceMotion() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(he)", "-AppleLocale", "he_IL"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE"] = "1"
        app.launchEnvironment["HANLIN_DOCK_ACCEPTANCE_FIXTURES"] = "1"
        app.launch()

        openChat(in: app)

        let generalBtn = app.descendants(matching: .any)["hanlin-composer-general-menu"].firstMatch
        let expand = app.buttons["hanlin-composer-expand-editor"].firstMatch
        XCTAssertTrue(generalBtn.waitForExistence(timeout: 10))
        XCTAssertTrue(expand.waitForExistence(timeout: 10))

        // The approved Morph palette replaces the former organizer drawer.
        tapElement(generalBtn)
        let generalContent = app.descendants(matching: .any)["morphing-action-panel"].firstMatch
        XCTAssertTrue(generalContent.waitForExistence(timeout: 5))

        let input = chatInputElement(in: app)
        tapElement(input)
        XCTAssertTrue(generalContent.waitForNonExistence(timeout: 5), "Focusing the native editor must dismiss the Morph palette")
        let draft = "שלום مرحبا — RTL keyboard draft"
        input.typeText(draft)
        XCTAssertEqual(input.value as? String, draft)
        attachScreenshot("7B-11_RTL_KeyboardAutoCollapse_Accessibility", in: app)
    }

    // MARK: - Navigation & Toggle Helpers

    private func launchDockAcceptanceApp(simulatedWidth: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE"] = "1"
        app.launchEnvironment["HANLIN_DOCK_ACCEPTANCE_FIXTURES"] = "1"
        if let simulatedWidth {
            app.launchEnvironment["HANLIN_SIMULATE_CONTAINER_WIDTH"] = simulatedWidth
        }
        app.launch()
        return app
    }

    private func launchAcceptanceApp(language: String = "en", locale: String = "en_US",
                                     isolatedStore: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_COMPOSER_EDIT_DIAGNOSTICS"] = "1"
        app.launchEnvironment["HANLIN_COMPACT_KEYBOARD_WITNESS"] = "1"
        app.launchEnvironment["HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE"] = "1"
        if isolatedStore {
            // A fresh store cannot expose the previous case's rows before fixture seeding.
            app.launchEnvironment["HANLIN_PHASE2_STORE_ID"] = UUID().uuidString
        }
        app.launch()
        return app
    }

    private func chatInputElement(in app: XCUIApplication) -> XCUIElement {
        let tf = app.textFields["hanlin-chat-input"].firstMatch
        if tf.exists { return tf }
        let tv = app.textViews["hanlin-chat-input"].firstMatch
        if tv.exists { return tv }
        return app.descendants(matching: .any)["hanlin-chat-input"].firstMatch
    }

    private func sendPrompt(_ text: String, in app: XCUIApplication,
                            file: StaticString = #filePath, line: UInt = #line) {
        let input = chatInputElement(in: app)
        XCTAssertTrue(input.waitForExistence(timeout: 20), "Chat input field did not appear", file: file, line: line)
        guard input.exists else { return }
        XCTAssertTrue(input.isHittable, "The original editor must be reachable", file: file, line: line)
        guard input.isHittable else { return }
        input.tap()
        input.typeText(text)
        XCTAssertEqual(input.value as? String, text,
                       "Native editing must preserve the complete prompt before submission", file: file, line: line)
        guard input.value as? String == text else { return }
        let send = app.buttons["hanlin-chat-send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 10), "Chat send button did not appear", file: file, line: line)
        guard send.exists else { return }
        XCTAssertTrue(send.isEnabled && send.isHittable,
                      "Send must remain reachable above the keyboard", file: file, line: line)
        guard send.isEnabled && send.isHittable else { return }
        send.tap()
    }

    /// Approve only the exact fixture business request through the original UI.
    /// This is not another chat turn, an injected grant, or a tool-result stub.
    private func approveOriginalToolRequest(_ expected: [String: String], in app: XCUIApplication,
                                            remembersDecision: Bool = false,
                                            inspectPendingCard: ((XCUIElement) -> Void)? = nil,
                                            file: StaticString = #filePath, line: UInt = #line) {
        let allowIdentifier = remembersDecision ? "hanlin-tool-consent-allow-remember" : "hanlin-tool-consent-allow-once"
        let unexpectedIdentifier = remembersDecision ? "hanlin-tool-consent-allow-once" : "hanlin-tool-consent-allow-remember"
        let owner = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'hanlin-tool-approval-'")).firstMatch
        let ownerExists = owner.waitForExistence(timeout: 45)
        XCTAssertTrue(ownerExists, "The original Host must request consent", file: file, line: line)
        guard ownerExists else { return }
        let ownerID = owner.identifier
        guard ownerID.hasPrefix("hanlin-tool-approval-") else {
            XCTFail("The original immutable approval owner must exist", file: file, line: line)
            return
        }
        let requestID = String(ownerID.dropFirst("hanlin-tool-approval-".count))
        XCTAssertNotNil(UUID(uuidString: requestID), "The owner must identify the actual immutable request", file: file, line: line)
        guard UUID(uuidString: requestID) != nil else { return }

        func currentOwner() -> XCUIElement {
            app.descendants(matching: .any)[ownerID].firstMatch
        }
        let unexpectedKind = currentOwner().buttons[unexpectedIdentifier].exists
        XCTAssertFalse(unexpectedKind, "The request must expose exactly the expected consent scope", file: file, line: line)
        guard !unexpectedKind else { return }

        func tapOwnedButton(_ identifier: String) -> Bool {
            // Each reveal resolves the original request again. Once reachable,
            // tap immediately: repeated AX probes can outlive its Host deadline.
            for reveal in 0...3 {
                let button = currentOwner().buttons[identifier].firstMatch
                guard button.exists else { return false }
                if button.isHittable {
                    button.tap()
                    return true
                }
                guard reveal < 3 else { return false }
                let scroll = app.scrollViews.containing(.any, identifier: ownerID).firstMatch
                guard scroll.exists else { return false }
                scroll.swipeUp()
            }
            return false
        }

        if let inspectPendingCard {
            // Reveal the real compact card before opening its original details.
            // This optional witness leaves the existing English journey unchanged.
            var compactActionsVisible = false
            for reveal in 0...3 {
                let pending = currentOwner()
                if pending.buttons["hanlin-tool-consent-review-toggle"].firstMatch.isHittable,
                   pending.buttons[allowIdentifier].firstMatch.isHittable {
                    compactActionsVisible = true
                    break
                }
                guard reveal < 3 else { break }
                let scroll = app.scrollViews.containing(.any, identifier: ownerID).firstMatch
                guard scroll.exists else { break }
                scroll.swipeUp()
            }
            XCTAssertTrue(compactActionsVisible, "The compact approval and its original action must be visible together", file: file, line: line)
            guard compactActionsVisible else { return }
            inspectPendingCard(currentOwner())
        }
        let reviewed = tapOwnedButton("hanlin-tool-consent-review-toggle")
        XCTAssertTrue(reviewed, "The original approval must be reachable", file: file, line: line)
        guard reviewed else { return }
        let review = currentOwner().staticTexts["hanlin-tool-consent-original-request"].firstMatch
        let reviewExists = review.waitForExistence(timeout: 10)
        XCTAssertTrue(reviewExists, file: file, line: line)
        guard reviewExists,
              let actual = (try? JSONSerialization.jsonObject(with: Data(review.label.utf8))) as? [String: Any] else {
            XCTFail("The original request must contain reviewable JSON", file: file, line: line); return
        }
        let allowed = Set(expected.keys).union(["progress_summary", "result_presentation"])
        XCTAssertTrue(Set(actual.keys).isSubset(of: allowed), "Unexpected business arguments", file: file, line: line)
        for (key, value) in expected { XCTAssertEqual(actual[key] as? String, value, file: file, line: line) }
        guard Set(actual.keys).isSubset(of: allowed),
              expected.allSatisfy({ actual[$0.key] as? String == $0.value }) else { return }
        let approved = tapOwnedButton(allowIdentifier)
        XCTAssertTrue(approved, "The reviewed approval must retain its expected scope and remain reachable", file: file, line: line)
        guard approved else { return }
        XCTAssertTrue(currentOwner().waitForNonExistence(timeout: 10),
                      "The original request must disappear after approval", file: file, line: line)
    }

    /// Remembered Host grants intentionally span conversations. Clear the test
    /// account through its original settings action so each consent journey
    /// reviews a real new request, independent of which UI case ran first.
    private func revokeRememberedToolPermissions(in app: XCUIApplication,
                                                 file: StaticString = #filePath, line: UInt = #line) {
        openSettings(in: app)
        let link = app.descendants(matching: .any)["hanlin-tool-permissions-link"].firstMatch
        for _ in 0..<6 where !link.isHittable { app.swipeUp() }
        XCTAssertTrue(link.isHittable, "The original tool permissions settings must be reachable", file: file, line: line)
        guard link.isHittable else { return }
        link.tap()

        let permissions = app.descendants(matching: .any)["hanlin-tool-permissions-list"].firstMatch
        XCTAssertTrue(permissions.waitForExistence(timeout: 10), "The original tool permissions screen must open", file: file, line: line)
        let revoke = app.buttons["hanlin-tool-permissions-revoke-all"].firstMatch
        if revoke.exists {
            for _ in 0..<6 where !revoke.isHittable { permissions.swipeUp() }
            XCTAssertTrue(revoke.isHittable, "The original permission revocation must be reachable", file: file, line: line)
            guard revoke.isHittable else { return }
            revoke.tap()
        }
        let empty = app.descendants(matching: .any)["hanlin-tool-permissions-empty"].firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 10), "Each consent journey must begin without a remembered tool grant", file: file, line: line)
        // Scope Back to this actual destination, not the first navigation item
        // in the underlying iPad sidebar.
        let permissionsNavigation = app.navigationBars.matching(NSPredicate(
            format: "identifier == %@ OR identifier == %@", "Tool permissions", "הרשאות כלים")).firstMatch
        let back = permissionsNavigation.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 5) && back.isHittable,
                      "The original permissions Back control must be reachable", file: file, line: line)
        guard back.exists && back.isHittable else { return }
        back.tap()
        XCTAssertTrue(app.descendants(matching: .any)["hanlin-settings-list"].firstMatch.waitForExistence(timeout: 5),
                      "Permission review must return to the original Settings screen", file: file, line: line)
        openChat(in: app)
        XCTAssertTrue(chatInputElement(in: app).waitForExistence(timeout: 10), "The original chat must reopen before its request is sent", file: file, line: line)
    }

    private func ensureChatListVisible(in app: XCUIApplication,
                                       file: StaticString = #filePath, line: UInt = #line) {
        let sidebar = app.navigationBars["Hanlin"].firstMatch
        if sidebar.exists && sidebar.isHittable { return }

        let sidebarToggle = app.navigationBars.buttons.matching(
            NSPredicate(format: "identifier == 'ToggleSidebar' OR label == 'Show Sidebar'")
        ).firstMatch
        if sidebarToggle.exists && sidebarToggle.isHittable {
            sidebarToggle.tap()
            if sidebar.waitForExistence(timeout: 5) && sidebar.isHittable { return }
        }

        // A compact conversation returns through its real Back control. Never
        // tap the first toolbar item: on iPad that item is the software guide.
        let back = app.navigationBars.buttons.matching(
            NSPredicate(format: "identifier == 'BackButton' OR label == 'Back'")
        ).firstMatch
        if back.exists && back.isHittable { back.tap() }
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5) && sidebar.isHittable,
                      "The original chat list must be visible", file: file, line: line)
    }

    private func chatListToolbarButton(_ identifier: String, in app: XCUIApplication,
                                       file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        ensureChatListVisible(in: app, file: file, line: line)
        let button = app.buttons[identifier].firstMatch
        if button.exists && button.isHittable { return button }
        // The 320-point iPad sidebar puts New Chat and Saved Messages in its
        // native overflow menu. The detail column has a different More button.
        let overflow = app.navigationBars["Hanlin"].buttons["TopOverflowBarButtonItem"].firstMatch
        XCTAssertTrue(overflow.waitForExistence(timeout: 5) && overflow.isHittable,
                      "The sidebar's native overflow control must be reachable", file: file, line: line)
        if overflow.exists && overflow.isHittable { overflow.tap() }
        if button.waitForExistence(timeout: 2) && button.isHittable { return button }

        // UIKit's native overflow creates menu buttons with their visible
        // labels, without forwarding the original toolbar identifiers. Scope
        // the fallback to the single opened sidebar menu, never a global label.
        let actionTitle: String
        switch identifier {
        case "hanlin-saved-messages-open": actionTitle = "Saved messages"
        case "hanlin-new-chat-button": actionTitle = "New chat"
        default:
            XCTFail("No scoped overflow action is defined for \(identifier)", file: file, line: line)
            return button
        }
        let overflowMenus = app.collectionViews.containing(.button, identifier: "Saved messages")
        XCTAssertTrue(overflowMenus.firstMatch.waitForExistence(timeout: 5),
                      "The opened sidebar overflow must contain Saved messages", file: file, line: line)
        XCTAssertEqual(overflowMenus.count, 1,
                       "The sidebar overflow must resolve to one native menu", file: file, line: line)
        guard overflowMenus.count == 1 else { return button }
        let menuAction = overflowMenus.firstMatch.buttons[actionTitle].firstMatch
        XCTAssertTrue(menuAction.waitForExistence(timeout: 5) && menuAction.isHittable,
                      "Missing original chat-list action: \(identifier)", file: file, line: line)
        return menuAction
    }

    private func selectChatRow(named name: String, in app: XCUIApplication) {
        let rowByID = app.descendants(matching: .any)["hanlin-chat-row-\(name)"].firstMatch
        if rowByID.waitForExistence(timeout: 5) {
            tapElement(rowByID)
            return
        }
        let predicate = NSPredicate(format: "label CONTAINS %@ OR identifier CONTAINS %@", name, name)
        let match = app.descendants(matching: .any).matching(predicate).firstMatch
        if match.waitForExistence(timeout: 10) {
            tapElement(match)
        }
    }

    private func attachScreenshot(_ name: String, in app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func selectTab(identifier: String, labels: [String] = [], in app: XCUIApplication) -> Bool {
        // Profile is the owner's approved native sheet. Return through its
        // real Done control before selecting a primary destination beneath it.
        if identifier == "hanlin-home-tab" || identifier == "hanlin-library-tab" {
            let done = app.buttons["hanlin-profile-done"].firstMatch
            if done.exists {
                XCTAssertTrue(done.isHittable, "The original Profile close control must be usable")
                guard done.isHittable else { return false }
                done.tap()
                XCTAssertTrue(done.waitForNonExistence(timeout: 5), "Profile must actually dismiss before primary navigation")
                guard !done.exists else { return false }
            }
        }
        var candidates: [XCUIElement] = [
            app.tabBars.buttons[identifier].firstMatch,
            app.buttons[identifier].firstMatch,
            app.tabs[identifier].firstMatch
        ]
        for label in labels {
            candidates.append(app.tabBars.buttons[label].firstMatch)
            candidates.append(app.buttons[label].firstMatch)
            candidates.append(app.tabs[label].firstMatch)
        }

        func findCandidate() -> Bool {
            let primary = app.buttons[identifier].firstMatch
            if primary.waitForExistence(timeout: 2) && primary.isHittable {
                primary.tap()
                return true
            }
            for candidate in candidates where candidate.exists && candidate.isHittable {
                candidate.tap()
                return true
            }
            return false
        }

        // 1. Try directly on current tab page
        if findCandidate() { return true }

        // 2. Try Previous Page (e.g. if we are on later tab page like Settings and want Home)
        let prevPage = app.buttons["Previous Page"].firstMatch
        if prevPage.waitForExistence(timeout: 2) && prevPage.isHittable {
            prevPage.tap()
            if findCandidate() { return true }
        }

        // 3. Try Next Page (e.g. if target tab is on subsequent page)
        let nextPage = app.buttons["Next Page"].firstMatch
        if nextPage.waitForExistence(timeout: 2) && nextPage.isHittable {
            nextPage.tap()
            if findCandidate() { return true }
        }

        // 4. Fallback to broad hierarchy predicate
        let labelClauses = labels.map { "label CONTAINS '\($0)'" }
        let format = (["identifier == '\(identifier)'"] + labelClauses).joined(separator: " OR ")
        let fallback = app.descendants(matching: .any).matching(NSPredicate(format: format)).firstMatch
        if fallback.waitForExistence(timeout: 3) && fallback.isHittable {
            fallback.tap()
            return true
        }

        return false
    }

    private func openSettings(in app: XCUIApplication) {
        let settingsNav = app.navigationBars["设置"].firstMatch
        let settingsNavEn = app.navigationBars["Settings"].firstMatch
        if settingsNav.exists || settingsNavEn.exists { return }
        if !selectTab(identifier: "hanlin-settings-tab", labels: ["Settings", "设置"], in: app) {
            navigateBack(in: app)
            _ = selectTab(identifier: "hanlin-settings-tab", labels: ["Settings", "设置"], in: app)
        }
        let settings = app.descendants(matching: .any)["hanlin-settings-list"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10),
            "The original Profile settings must open before the test relies on leaving the chat")
    }

    private func navigateBack(in app: XCUIApplication) {
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        if backButton.waitForExistence(timeout: 3) && backButton.isHittable {
            backButton.tap()
        }
    }

    private func openRuntimeCenter(in app: XCUIApplication) {
        if app.navigationBars["Runtime diagnostics"].exists { return }
        openSettings(in: app)
        let runtimeCenterNav = app.navigationBars["Runtime diagnostics"].firstMatch
        if runtimeCenterNav.waitForExistence(timeout: 3) { return }
        let link = app.descendants(matching: .any)["hanlin-runtime-diagnostics-link"].firstMatch
        for _ in 0..<8 where !link.isHittable { app.swipeUp() }
        XCTAssertTrue(link.waitForExistence(timeout: 10), "Developer runtime diagnostics link missing")
        tapElement(link)
        _ = runtimeCenterNav.waitForExistence(timeout: 10)
    }

    private func tapElement(_ element: XCUIElement) {
        if element.isHittable {
            element.tap()
        } else if element.exists {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    private func openChat(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        while app.navigationBars["Runtime diagnostics"].exists {
            let backButton = app.navigationBars.buttons.element(boundBy: 0)
            if backButton.waitForExistence(timeout: 2) && backButton.isHittable {
                backButton.tap()
            } else {
                break
            }
        }

        let compactViewAll = app.buttons["hanlin-compact-view-all-button"].firstMatch
        let seededRow = app.descendants(matching: .any)["hanlin-chat-row-Agent Acceptance Chat"].firstMatch
        let recentRow = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "hanlin-compact-recent-row-", "Agent Acceptance Chat"
        )).firstMatch

        let compactWorkspace = app.descendants(matching: .any)["hanlin-compact-chat-workspace"].firstMatch
        let isCompactWorkspace = compactWorkspace.exists
        let title = app.navigationBars.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@", "Agent Acceptance Chat")
        ).firstMatch

        func currentChatIsReady() -> Bool {
            let input = chatInputElement(in: app)
            return input.exists && input.isEnabled && input.isHittable
                && !compactViewAll.exists && title.exists
        }
        func waitForSelectedChat() -> Bool {
            let hasTitle = title.waitForExistence(timeout: 15)
            XCTAssertTrue(hasTitle, "Selection must open the actual Agent Acceptance Chat destination",
                          file: file, line: line)
            guard hasTitle else { return false }
            let input = chatInputElement(in: app)
            let hasInput = input.waitForExistence(timeout: 15)
            XCTAssertTrue(hasInput, "The selected conversation must retain its original editor",
                          file: file, line: line)
            guard hasInput else { return false }
            let hittable = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "hittable == true"), object: input)
            let ready = XCTWaiter.wait(for: [hittable], timeout: 10)
            XCTAssertEqual(ready, .completed, "The selected conversation editor must be reachable",
                           file: file, line: line)
            XCTAssertTrue(input.isEnabled, "The selected conversation editor must be enabled",
                          file: file, line: line)
            let homeDismissed = !isCompactWorkspace || compactViewAll.waitForNonExistence(timeout: 10)
            XCTAssertTrue(homeDismissed, "The compact Home screen must yield to the selected chat",
                          file: file, line: line)
            return ready == .completed && input.isEnabled && homeDismissed
        }
        func selectVisibleSeededRow() -> Bool {
            // A retained, disabled history row can have an on-screen AX frame.
            // Select the real compact Home control first; never tap disabled rows.
            let rows = isCompactWorkspace ? [recentRow, seededRow] : [seededRow, recentRow]
            for row in rows where row.exists && row.isEnabled && row.isHittable {
                row.tap()
                return waitForSelectedChat()
            }
            return false
        }

        // A wide launch can already expose the seeded row. Do not hide that
        // sidebar or navigate through unrelated tabs before selecting it.
        if currentChatIsReady() || selectVisibleSeededRow() { return }
        _ = selectTab(identifier: "hanlin-home-tab", labels: ["Chats", "Messages", "Home", "列表"], in: app)
        if currentChatIsReady() || selectVisibleSeededRow() { return }

        let compactHistory = app.buttons["hanlin-history-open"].firstMatch
        if compactHistory.exists && compactHistory.isHittable {
            compactHistory.tap()
        } else if compactViewAll.exists && compactViewAll.isHittable {
            compactViewAll.tap()
        } else {
            // These are the actual iOS 27 English/Hebrew "show" labels.
            // ToggleSidebar alone also matches "Hide Sidebar"; never tap that.
            let showSidebar = app.navigationBars.buttons.matching(NSPredicate(
                format: "label IN %@", ["Show Sidebar", "הצגת סרגל הצד"]
            )).firstMatch
            if showSidebar.waitForExistence(timeout: 2) && showSidebar.isHittable {
                showSidebar.tap()
            }
        }

        XCTAssertTrue(seededRow.waitForExistence(timeout: 15),
            "The original seeded conversation row must be available", file: file, line: line)
        guard seededRow.exists else { return }
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"), object: seededRow)
        let ready = XCTWaiter.wait(for: [hittable], timeout: 5)
        XCTAssertEqual(ready, .completed,
            "The seeded row must be visible before selection", file: file, line: line)
        guard ready == .completed else { return }
        XCTAssertTrue(seededRow.isEnabled, "The visible conversation row must be enabled",
                      file: file, line: line)
        guard seededRow.isEnabled else { return }
        seededRow.tap()
        _ = waitForSelectedChat()
    }

    private func runtimeState(for kindRaw: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts["hanlin-runtime-state-\(kindRaw)"].firstMatch
    }

    private func waitForRuntimeReady(
        _ kindRaw: String, in app: XCUIApplication, timeout: TimeInterval
    ) -> Bool {
        let state = runtimeState(for: kindRaw, in: app)
        if !state.waitForExistence(timeout: 3) { app.swipeUp() }
        guard state.waitForExistence(timeout: 10) else { return false }
        let predicate = NSPredicate(format: "label == %@", "Ready")
        return XCTWaiter.wait(for: [expectation(for: predicate, evaluatedWith: state)],
                              timeout: timeout) == .completed
    }

    private func isToggleOn(_ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        if let valStr = element.value as? String {
            return valStr == "1" || valStr.lowercased() == "on" || valStr.lowercased() == "true"
        }
        if let valInt = element.value as? Int {
            return valInt == 1
        }
        return false
    }

}
