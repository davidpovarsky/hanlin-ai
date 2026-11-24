import XCTest

/// Both unmodified product targets must be installed with their existing App
/// Group on the same owned simulator. Only the model's HTTP response is scripted.
@MainActor
final class HanlinPairedProductUITests: XCTestCase {
    private let ai = XCUIApplication(bundleIdentifier: "com.itorah.chavrusachat")
    private let mini = XCUIApplication(bundleIdentifier: "com.itorah.hanlinminiapps")
    private var pairedRequestStartedAt: Date?
    private var capturedFailureSnapshot = false

    override func setUpWithError() throws {
        pairedRequestStartedAt = nil
        capturedFailureSnapshot = false
        continueAfterFailure = false
        executionTimeAllowance = 600
        for app in [ai, mini] {
            app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
            app.launchEnvironment["HANLIN_COMPOSER_EDIT_DIAGNOSTICS"] = "1"
            app.launchEnvironment["HANLIN_COMPACT_KEYBOARD_WITNESS"] = "1"
        }
    }

    override func tearDownWithError() throws {
        let failed = (testRun?.totalFailureCount ?? 0) > 0
        for (name, app) in [("AI", ai), ("MiniApps", mini)] {
            if app.state == .runningForeground {
                let picture = XCTAttachment(screenshot: app.screenshot())
                picture.name = name + "-paired-product"; picture.lifetime = .keepAlways; add(picture)
                if failed && !capturedFailureSnapshot {
                    let tree = XCTAttachment(string: app.debugDescription)
                    tree.name = name + "-paired-accessibility"; tree.lifetime = .keepAlways; add(tree)
                }
            }
        }
        for app in [ai, mini] where app.state != .notRunning {
            app.terminate()
        }
    }

    func testCompanionReturnsActualPrivateValueToOriginalChat() throws {
        let nonce = UUID().uuidString
        let originalChat = try beginOriginalRequest("PAIRED_OPEN_" + nonce)
        let name = mini.textFields["Name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 30))
        replace(name, with: "PAIRED_VALUE_" + nonce)
        tap(mini, "Save")
        XCTAssertTrue(mini.staticTexts["Saved in canonical private container"].waitForExistence(timeout: 15))
        tap(mini, "miniapps.return-to-origin")
        if !ai.wait(for: .runningForeground, timeout: 30) {
            let summary = recordPairedFailureDiagnostics(caseKind: "open_return", stage: "foreground_return")
            XCTFail("Hanlin did not return to foreground (\(summary))")
        }
        assertPairedResult("PAIRED_RETURN_VERIFIED_" + nonce, caseKind: "open_return")
        XCTAssertEqual(ai.staticTexts["hanlin-phase2-chat-id"].label, originalChat)
        XCTAssertFalse(ai.alerts["Mini App result unavailable"].exists)
        XCTAssertFalse(ai.buttons["hanlin-tool-consent-allow-once"].exists)
        XCTAssertFalse(ai.buttons["hanlin-tool-consent-allow-remember"].exists)
    }

    func testCompanionCancellationReturnsWithoutChangingPrivateState() throws {
        let nonce = UUID().uuidString
        let originalChat = try beginOriginalRequest("PAIRED_CANCEL_" + nonce)
        let name = mini.textFields["Name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 30))
        let before = name.value as? String
        tap(mini, "Cancel")
        if !ai.wait(for: .runningForeground, timeout: 30) {
            let summary = recordPairedFailureDiagnostics(caseKind: "cancel_return", stage: "foreground_return")
            XCTFail("Hanlin did not return to foreground (\(summary))")
        }
        assertPairedResult("PAIRED_CANCEL_RETURN_" + nonce, caseKind: "cancel_return")
        XCTAssertEqual(ai.staticTexts["hanlin-phase2-chat-id"].label, originalChat)
        XCTAssertFalse(ai.alerts["Mini App result unavailable"].exists)
        XCTAssertFalse(ai.buttons["hanlin-tool-consent-allow-once"].exists)
        XCTAssertFalse(ai.buttons["hanlin-tool-consent-allow-remember"].exists)
        mini.terminate(); mini.launch()
        tap(mini, "hanlin-package-card-Swift Parity")
        XCTAssertTrue(name.waitForExistence(timeout: 15))
        XCTAssertEqual(name.value as? String, before)
    }

    func testOriginalPackageAndSavedStateTransferThenRollback() throws {
        // Establish real source state through the original importer and runtime.
        // The legacy host is an existing engine component probe, not new product navigation.
        ai.launchEnvironment["HANLIN_SCRIPTUI_E2E"] = "1"
        ai.launch()
        tap(ai, "hanlin-apps-add")
        tap(ai, "hanlin-import-script-package")
        tap(ai, "HanlinTransferAcceptance")
        let install = ai.buttons["hanlin-package-install"].firstMatch
        XCTAssertTrue(install.waitForExistence(timeout: 30) && install.isEnabled)
        install.tap()
        // The importer returns after the real install/update and snapshot read.
        // A compiler failure can hide Install behind an alert without installing.
        let importer = ai.buttons["hanlin-file-importer"].firstMatch
        XCTAssertTrue(importer.waitForExistence(timeout: 60),
                      "Original package installation did not complete. \(ai.alerts.debugDescription)")
        XCTAssertFalse(item(ai, "hanlin-import-error-message").exists)
        XCTAssertFalse(ai.alerts["Script App Error"].exists)
        ai.terminate(); ai.launch()
        openOriginalPackage(named: "Hanlin Transfer Acceptance")
        XCTAssertTrue(ai.staticTexts["Not saved"].waitForExistence(timeout: 30))
        tap(ai, "Save transfer value")
        assertText(ai, "Saved by the original ScriptUI runtime")
        ai.terminate()
        ai.launchEnvironment.removeValue(forKey: "HANLIN_SCRIPTUI_E2E")
        ai.launch()

        // Use the shipping Profile -> Transfer flow, then the real companion wake.
        tap(ai, "hanlin-settings-tab")
        reveal(ai, identifier: "hanlin-transfer-link", container: "hanlin-settings-list")
        tap(ai, "hanlin-transfer-link")
        tap(ai, "hanlin-transfer-prepare")
        assertText(ai, "Copy ready. Open Hanlin MiniApps and choose Transfer from Hanlin.")
        if mini.state != .notRunning {
            mini.terminate()
        }
        tap(ai, "hanlin-transfer-open-companion")
        XCTAssertTrue(mini.wait(for: .runningForeground, timeout: 30))
        // Fresh process guarantees no prior compiled-storage/runtime use and applies test launch args.
        mini.terminate(); mini.launch()
        tap(mini, "hanlin-miniapps-transfer")
        tap(mini, "hanlin-transfer-import")
        assertText(mini, "Transfer complete. Your mini apps are ready.")
        mini.terminate(); mini.launch()
        let imported = mini.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH 'hanlin-package-card-' AND label CONTAINS %@", "Hanlin Transfer Acceptance")).firstMatch
        for _ in 0..<5 {
            if imported.exists && imported.isHittable { break }
            mini.swipeUp()
        }
        XCTAssertTrue(imported.waitForExistence(timeout: 30))
        XCTAssertTrue(imported.isHittable)
        imported.tap()
        assertText(mini, "Saved by the original ScriptUI runtime")

        // Fresh process guarantees every old runtime owner has finished before rollback.
        mini.terminate(); mini.launch()
        tap(mini, "hanlin-miniapps-transfer")
        tap(mini, "hanlin-transfer-rollback")
        tap(mini, "Restore previous data")
        assertText(mini, "Previous data restored. The original copy in Hanlin is unchanged.")
        mini.terminate(); mini.launch()
        XCTAssertTrue(item(mini, "hanlin-apps-add").waitForExistence(timeout: 30))
        XCTAssertFalse(imported.exists, "Rollback must restore the actual pre-transfer catalog")

        ai.terminate(); ai.launchEnvironment["HANLIN_SCRIPTUI_E2E"] = "1"; ai.launch()
        openOriginalPackage(named: "Hanlin Transfer Acceptance")
        assertText(ai, "Saved by the original ScriptUI runtime")
    }

    private func openOriginalPackage(named name: String) {
        // The original hub puts ScriptUI below the lazy Swift catalog. Reveal the
        // installed card through its shipping search before testing its state.
        let search = ai.searchFields["Search Apps"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 30))
        tap(ai, "Search Apps")
        search.typeText(name)
        let filtered = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", name), object: search)
        XCTAssertEqual(XCTWaiter.wait(for: [filtered], timeout: 10), .completed,
                       "The original catalog must apply the exact package search")
        tap(ai, "hanlin-package-card-\(name)")
    }

    private func beginOriginalRequest(_ prompt: String) throws -> String {
        // Publish the real companion catalog before the original Host resolves it.
        mini.launch()
        XCTAssertTrue(item(mini, "hanlin-package-card-Swift Parity").waitForExistence(timeout: 45))
        mini.terminate()
        ai.launchEnvironment["HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE"] = "1"
        ai.launchEnvironment["HANLIN_PHASE2_STORE_ID"] = UUID().uuidString
        ai.launch()
        try revokeRememberedSplitPermission()
        // Compact Home has its own persistent composer. Select the original
        // seeded conversation explicitly before recording its durable identity.
        let home = ai.buttons["hanlin-compact-view-all-button"].firstMatch
        if home.waitForExistence(timeout: 10) {
            let recent = ai.buttons["hanlin-compact-recent-row-0"].firstMatch
            XCTAssertTrue(recent.waitForExistence(timeout: 10))
            XCTAssertTrue(recent.label.contains("Agent Acceptance Chat"))
            recent.tap()
        } else if !ai.staticTexts["hanlin-phase2-chat-id"].exists {
            let chat = ai.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Agent Acceptance Chat")).firstMatch
            XCTAssertTrue(chat.waitForExistence(timeout: 20)); chat.tap()
        }
        XCTAssertTrue(input().waitForExistence(timeout: 20))
        let identity = ai.staticTexts["hanlin-phase2-chat-id"].firstMatch
        XCTAssertTrue(identity.waitForExistence(timeout: 10))
        let originalChat = identity.label
        XCTAssertNotNil(UUID(uuidString: originalChat))
        let editor = input()
        typeNativeText(prompt, into: editor, failureMessage: "Native typing must preserve the original request before Send")
        XCTAssertEqual(editor.value as? String, prompt, "Native typing must preserve the original request before Send")
        tap(ai, "hanlin-chat-send")
        let allow = ai.buttons["hanlin-tool-consent-allow-remember"].firstMatch
        XCTAssertTrue(allow.waitForExistence(timeout: 45),
            "The original Host request must expose its scoped remembered permission")
        XCTAssertFalse(allow.isEnabled, "The original request must be reviewed before it can be approved")
        XCTAssertFalse(ai.buttons["hanlin-tool-consent-allow-once"].exists,
            "This Host-scoped request must not be mistaken for provider-only one-use consent")
        tap(ai, "hanlin-tool-consent-review-toggle")
        let originalRequest = ai.staticTexts["hanlin-tool-consent-original-request"].firstMatch
        XCTAssertTrue(originalRequest.waitForExistence(timeout: 15),
            "Review the actual cross-product request before allowing its original continuation")
        XCTAssertFalse(originalRequest.label.isEmpty)
        let arguments = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(originalRequest.label.utf8)) as? [String: Any],
            "The visible original request must be reviewable JSON")
        XCTAssertEqual(Set(arguments.keys), Set(["target", "action", "payload"]))
        XCTAssertEqual(arguments["target"] as? String, "hanlin.demo.swift-parity")
        XCTAssertEqual(arguments["action"] as? String, "share.value")
        XCTAssertTrue(arguments["payload"] is NSNull)
        tap(ai, "hanlin-tool-consent-allow-remember")
        pairedRequestStartedAt = Date()
        XCTAssertTrue(mini.wait(for: .runningForeground, timeout: 45))
        XCTAssertTrue(mini.buttons["miniapps.return-to-origin"].waitForExistence(timeout: 30))
        return originalChat
    }

    /// The original Host grant spans conversations; a fresh SwiftData fixture
    /// does not reset it. Revoke only this tool through its shipping Settings UI.
    private func revokeRememberedSplitPermission() throws {
        tap(ai, "hanlin-settings-tab")
        let settings = item(ai, "hanlin-settings-list")
        _ = try XCTUnwrap(settings.waitForExistence(timeout: 10) ? settings : nil,
            "Original Settings must open before preparing the paired consent fixture")
        reveal(ai, identifier: "hanlin-tool-permissions-link", container: "hanlin-settings-list")
        tap(ai, "hanlin-tool-permissions-link")
        let permissions = item(ai, "hanlin-tool-permissions-list")
        _ = try XCTUnwrap(permissions.waitForExistence(timeout: 10) ? permissions : nil,
            "The original per-tool permission controls must open")
        let matching = permissions.buttons.matching(NSPredicate(
            format: "label == %@", "Revoke permission for open_mini_app"))
        for _ in 0..<8 {
            if matching.count > 0 || item(ai, "hanlin-tool-permissions-empty").exists { break }
            permissions.swipeUp()
        }
        let scoped = try XCTUnwrap(matching.count <= 1 ? matching : nil,
            "Multiple indistinguishable split-tool grants cannot be revoked by this fixture")
        if scoped.count == 1 {
            let revoke = scoped.firstMatch
            for _ in 0..<8 where !revoke.isHittable { permissions.swipeUp() }
            let reachable = try XCTUnwrap(revoke.isHittable ? revoke : nil,
                "The original split-tool revocation must be reachable")
            reachable.tap()
            _ = try XCTUnwrap(revoke.waitForNonExistence(timeout: 10) ? permissions : nil,
                "The original split-tool permission must be revoked before a fresh request")
        }
        let back = ai.navigationBars["Tool permissions"].buttons.element(boundBy: 0)
        _ = try XCTUnwrap(back.waitForExistence(timeout: 5) && back.isHittable ? back : nil,
            "The original permission screen must return through its own Back control")
        back.tap()
        _ = try XCTUnwrap(settings.waitForExistence(timeout: 5) ? settings : nil,
            "Permission revocation must return to the original Settings screen")
        let done = ai.buttons["hanlin-profile-done"].firstMatch
        tap(ai, "hanlin-profile-done")
        _ = try XCTUnwrap(done.waitForNonExistence(timeout: 5) ? settings : nil,
            "The original Profile sheet must dismiss before primary navigation")
        tap(ai, "hanlin-home-tab")
    }

    private func input() -> XCUIElement {
        let textView = ai.textViews["hanlin-chat-input"].firstMatch
        return textView.exists ? textView : ai.textFields["hanlin-chat-input"].firstMatch
    }

    private func item(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    private func tap(_ app: XCUIApplication, _ id: String) {
        let element = item(app, id)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(
            format: "exists == true AND enabled == true AND hittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 45), .completed, "Unreachable product control: \(id)")
        element.tap()
    }

    private func replace(_ field: XCUIElement, with value: String) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(
            format: "exists == true AND enabled == true AND hittable == true"), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed, "Unreachable text field")
        field.tap()
        let previous = field.value as? String ?? ""
        if !previous.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count))
            let cleared = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == '' OR value == %@ OR value == nil", "Name"), object: field)
            XCTAssertEqual(XCTWaiter.wait(for: [cleared], timeout: 10), .completed, "Text field did not clear before native typing")
        }
        typeNativeSegments(value, into: field, failureMessage: "Native typing must preserve the companion value")
        XCTAssertEqual(field.value as? String, value, "Native typing must preserve the companion value")
    }

    private func typeNativeText(
        _ text: String,
        into field: XCUIElement,
        failureMessage: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(
            format: "exists == true AND enabled == true AND hittable == true"), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed,
                       "Native text input was not ready before typing", file: file, line: line)
        field.tap()
        let placeholderCleared = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", "Message"), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [placeholderCleared], timeout: 10), .completed,
                       "Native text input did not gain focus and clear placeholder", file: file, line: line)
        typeNativeSegments(text, into: field, failureMessage: failureMessage, file: file, line: line)
    }

    private func typeNativeSegments(
        _ text: String,
        into field: XCUIElement,
        failureMessage: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
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

    private func assertText(_ app: XCUIApplication, _ value: String) {
        let text = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@", value, value)).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 60), "Missing actual product result: \(value)")
    }

    private func assertPairedResult(_ expected: String, caseKind: String) {
        let expectedElement = ai.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@", expected, expected)).firstMatch
        let failedMarker = ai.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@", "PAIRED_RESULT_NOT_VERIFIED", "PAIRED_RESULT_NOT_VERIFIED")).firstMatch
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            if ai.state == .runningForeground {
                if expectedElement.exists { return }
                if failedMarker.exists { break }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        let summary = recordPairedFailureDiagnostics(caseKind: caseKind, stage: "result_verification")
        XCTFail("Missing actual product result: \(expected) (\(summary))")
    }

    @discardableResult
    private func recordPairedFailureDiagnostics(caseKind: String, stage: String) -> String {
        let elapsed = pairedRequestStartedAt.map { String(format: "%.2fs", Date().timeIntervalSince($0)) } ?? "unknown"
        let aiState = ai.state
        let miniState = mini.state
        let aiOutcome = classifyAIOutcomeCategory(state: aiState)
        let miniBanner = classifyMiniAppsBannerCategory(state: miniState)
        let miniFailure = classifyMiniAppsFailureCode(state: miniState)
        let summary = "case=\(caseKind) stage=\(stage) elapsed=\(elapsed) ai_state=\(describeState(aiState)) mini_state=\(describeState(miniState)) ai_outcome=\(aiOutcome) mini_banner=\(miniBanner) mini_failure=\(miniFailure)"
        let attachment = XCTAttachment(string: summary)
        attachment.name = "paired-return-diagnostics"
        attachment.lifetime = .keepAlways
        add(attachment)
        captureForegroundFailureSnapshot(caseKind: caseKind, stage: stage, aiState: aiState, miniState: miniState)
        return summary
    }

    private func captureForegroundFailureSnapshot(
        caseKind: String,
        stage: String,
        aiState: XCUIApplication.State,
        miniState: XCUIApplication.State
    ) {
        for (name, app, state) in [("AI", ai, aiState), ("MiniApps", mini, miniState)] where state == .runningForeground {
            let picture = XCTAttachment(screenshot: app.screenshot())
            picture.name = "\(name)-\(caseKind)-\(stage)"
            picture.lifetime = .keepAlways
            add(picture)
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "\(name)-\(caseKind)-\(stage)-accessibility"
            tree.lifetime = .keepAlways
            add(tree)
            capturedFailureSnapshot = true
        }
    }

    private func classifyAIOutcomeCategory(state: XCUIApplication.State) -> String {
        guard state == .runningForeground else { return "not_foreground_\(describeState(state))" }
        let failedElement = ai.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@", "PAIRED_RESULT_NOT_VERIFIED", "PAIRED_RESULT_NOT_VERIFIED")).firstMatch
        if failedElement.exists { return "paired_result_not_verified" }
        if ai.alerts["Mini App result unavailable"].exists { return "alert_result_unavailable" }
        if ai.buttons["hanlin-tool-consent-allow-once"].exists
            || ai.buttons["hanlin-tool-consent-allow-remember"].exists { return "consent_still_pending" }
        return "pending_or_missing"
    }

    private func classifyMiniAppsBannerCategory(state: XCUIApplication.State) -> String {
        guard state == .runningForeground else { return "not_foreground_\(describeState(state))" }
        let interrupted = "This action was interrupted. Its outcome must be checked before it can run again."
        let returnFailed = "The request could not be opened or returned to Hanlin. Open Hanlin and try again."
        if mini.alerts["Hanlin request unavailable"].firstMatch.exists { return "alert_request_unavailable" }
        if mini.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", interrupted)).firstMatch.exists {
            return "outcome_unknown_banner"
        }
        if mini.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", returnFailed)).firstMatch.exists {
            return "open_or_return_failed_banner"
        }
        if mini.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Request unavailable")).firstMatch.exists {
            return "request_unavailable_view"
        }
        return "none"
    }

    private func classifyMiniAppsFailureCode(state: XCUIApplication.State) -> String {
        guard state == .runningForeground else { return "not_foreground_\(describeState(state))" }
        let alert = mini.alerts["Hanlin request unavailable"].firstMatch
        if alert.exists {
            for element in alert.staticTexts.allElementsBoundByIndex {
                if let code = extractDiagnosticCode(from: element.label) {
                    return code
                }
                if let value = element.value as? String, let code = extractDiagnosticCode(from: value) {
                    return code
                }
            }
        }
        let failureText = mini.staticTexts["miniapps.last-failure-code"].firstMatch
        if failureText.exists {
            for candidate in [failureText.value as? String, failureText.label].compactMap({ $0 }) {
                if let code = extractDiagnosticCode(from: candidate) {
                    return code
                }
                let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty,
                   trimmed != "none",
                   trimmed.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "." || $0 == ":") }) {
                    return trimmed
                }
            }
        }
        let diagnosticBanner = mini.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "[diagnostic:")
        ).firstMatch
        if diagnosticBanner.exists, let code = extractDiagnosticCode(from: diagnosticBanner.label) {
            return code
        }
        let button = mini.buttons["miniapps.return-to-origin"].firstMatch
        if button.exists, let code = button.value as? String, !code.isEmpty {
            return extractDiagnosticCode(from: code) ?? code
        }
        return "none"
    }

    private func extractDiagnosticCode(from text: String) -> String? {
        guard let start = text.range(of: "[diagnostic:")?.upperBound,
              let end = text[start...].firstIndex(of: "]") else {
            return nil
        }
        let payload = text[start..<end]
        let parts = payload.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              !parts[0].isEmpty, !parts[1].isEmpty,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == ".") } }) else {
            return nil
        }
        return "diagnostic:\(parts[0]):\(parts[1])"
    }

    private func describeState(_ state: XCUIApplication.State) -> String {
        switch state {
        case .notRunning: return "notRunning"
        case .runningBackgroundSuspended: return "runningBackgroundSuspended"
        case .runningBackground: return "runningBackground"
        case .runningForeground: return "runningForeground"
        case .unknown: return "unknown"
        @unknown default: return "unknown"
        }
    }

    private func reveal(_ app: XCUIApplication, identifier: String, container: String) {
        for _ in 0..<8 {
            if item(app, identifier).isHittable { return }
            item(app, container).swipeUp()
        }
        XCTFail("Product entry was not reachable: \(identifier)")
    }
}
