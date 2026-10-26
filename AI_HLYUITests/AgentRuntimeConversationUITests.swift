import XCTest

@MainActor
final class AgentRuntimeConversationUITests: XCTestCase {
    func testRealChatUISendsPromptShowsToolActivityAndFinalAnswer() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE"] = "1"
        app.launch()

        // 1. Initial State: Python runtime is OFF + Assistant Python permission is ON
        openRuntimeCenter(in: app)
        let initialPythonToggle = toggleSwitch(for: "localPython", in: app)
        if !initialPythonToggle.waitForExistence(timeout: 5) { app.swipeUp() }
        XCTAssertTrue(initialPythonToggle.waitForExistence(timeout: 10), "Python toggle card was missing in Runtime Center")
        XCTAssertFalse(isToggleOn(initialPythonToggle), "Python toggle should initially be OFF on fresh process")

        let toolPerm = app.switches["hanlin-tool-permission-execute_local_python_code"].firstMatch
        for _ in 0..<3 where !toolPerm.waitForExistence(timeout: 3) {
            app.swipeUp()
        }
        XCTAssertTrue(toolPerm.waitForExistence(timeout: 10), "Assistant Python permission switch was missing in Runtime Center")
        XCTAssertTrue(isToggleOn(toolPerm), "Assistant Python permission should unconditionally be ON")

        // 2. Switch to Chat and prompt the Agent to execute Python
        openChat(in: app)

        let input = chatInputElement(in: app)
        XCTAssertTrue(input.waitForExistence(timeout: 20), "The real chat input did not appear.")
        tapElement(input)
        input.typeText("Run the local Python acceptance tool and report the result.")

        let send = app.buttons["hanlin-chat-send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 10), "The real chat send button did not appear.")
        tapElement(send)

        let finalAnswer = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'AGENT_UI_ACCEPTANCE_COMPLETE'")
        ).firstMatch
        XCTAssertTrue(finalAnswer.waitForExistence(timeout: 45), "The deterministic provider's final answer was not rendered.")

        let activitySummary = app.buttons["hanlin-agent-activity-summary"].firstMatch
        XCTAssertTrue(activitySummary.waitForExistence(timeout: 10), "The completed agent activity summary was not rendered.")
        activitySummary.tap()

        let failedActivity = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == 'hanlin-agent-tool-failed' OR label CONTAINS[c] 'invalid'")
        ).firstMatch
        XCTAssertTrue(failedActivity.waitForExistence(timeout: 10), "The intentional tool failure was not presented truthfully in the real chat UI.")

        let toolActivity = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Local Python' OR label CONTAINS[c] 'ui-tool-ok'")
        ).firstMatch
        XCTAssertTrue(toolActivity.waitForExistence(timeout: 45), "Tool activity/result was not rendered in the real chat UI.")

        // 3. Verify Runtime Center reactively shows Python ON after agent execution
        openRuntimeCenter(in: app)
        let postPythonToggle = toggleSwitch(for: "localPython", in: app)
        if !postPythonToggle.waitForExistence(timeout: 3) { app.swipeDown() }
        if !postPythonToggle.waitForExistence(timeout: 3) { app.swipeUp() }
        XCTAssertTrue(
            waitForToggle(postPythonToggle, toBe: true, timeout: 20),
            "Python runtime should auto-start on agent execution and Runtime Center must show Python ON"
        )
    }

    func testProductionCodeSkillLocalPythonNeedsNoUserNudge() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE"] = "1"
        app.launch()

        // 1. Initial State: Python runtime is OFF in Runtime Center + Assistant Python permission is ON
        openRuntimeCenter(in: app)
        let initialPythonToggle = toggleSwitch(for: "localPython", in: app)
        if !initialPythonToggle.waitForExistence(timeout: 5) { app.swipeUp() }
        XCTAssertTrue(initialPythonToggle.waitForExistence(timeout: 10), "Python toggle card was missing in Runtime Center")
        XCTAssertFalse(isToggleOn(initialPythonToggle), "Python toggle should initially be OFF on fresh process")

        let toolPerm = app.switches["hanlin-tool-permission-execute_local_python_code"].firstMatch
        for _ in 0..<3 where !toolPerm.waitForExistence(timeout: 3) {
            app.swipeUp()
        }
        XCTAssertTrue(toolPerm.waitForExistence(timeout: 10), "Assistant Python permission switch was missing in Runtime Center")
        XCTAssertTrue(isToggleOn(toolPerm), "Assistant Python permission should unconditionally be ON")

        // 2. Open Chat and send prompt (single user turn, no second nudge required)
        openChat(in: app)
        let input = chatInputElement(in: app)
        XCTAssertTrue(input.waitForExistence(timeout: 20), "The real chat input did not appear.")
        tapElement(input)
        input.typeText("Use Python to calculate 6*7 and tell me the result.")

        let send = app.buttons["hanlin-chat-send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 10))
        tapElement(send)

        // 3. Final answer renders in the same user turn without extra user nudge
        let finalAnswer = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'LOCAL_PYTHON_COMPLETE'")
        ).firstMatch
        XCTAssertTrue(finalAnswer.waitForExistence(timeout: 45), "Final answer LOCAL_PYTHON_COMPLETE was not rendered in the same user turn.")
        XCTAssertTrue(finalAnswer.label.contains("42"), "Calculated result 42 was not rendered.")

        // Verify tool activity is present and no remote python was invoked
        let remoteActivity = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'execute_remote_python_code'")).firstMatch
        XCTAssertFalse(remoteActivity.exists, "Remote Python must not be invoked when local python is supported")

        // 4. Runtime Center reactively shows Python toggle ON after execution
        openRuntimeCenter(in: app)
        let postPythonToggle = toggleSwitch(for: "localPython", in: app)
        if !postPythonToggle.waitForExistence(timeout: 3) { app.swipeDown() }
        if !postPythonToggle.waitForExistence(timeout: 3) { app.swipeUp() }
        XCTAssertTrue(
            waitForToggle(postPythonToggle, toBe: true, timeout: 20),
            "Python runtime should auto-start on agent execution and Runtime Center must show Python ON"
        )
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
        let runBAnswer = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'RUN_B_COMPLETE'")
        ).firstMatch
        XCTAssertTrue(runBAnswer.waitForExistence(timeout: 30), "Run B did not complete with RUN_B_COMPLETE")

        // 4. Wait beyond deterministic Run A delay interval (~1.5s)
        Thread.sleep(forTimeInterval: 2.0)

        // 5. Assert RUN_A_LATE_GHOST does not exist, RUN_B_COMPLETE exists exactly once, no stale Stop, no stuck Thinking
        let runAGhost = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'RUN_A_LATE_GHOST'")
        ).firstMatch
        XCTAssertFalse(runAGhost.exists, "Run A late ghost answer RUN_A_LATE_GHOST must not appear after being cancelled")

        let runBMatches = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'RUN_B_COMPLETE'")
        )
        XCTAssertEqual(runBMatches.count, 1, "RUN_B_COMPLETE must exist exactly once")

        XCTAssertFalse(stopButton.exists, "Stop button should not remain active after run completion")

        let stuckProcessing = app.staticTexts.matching(
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

        // Open sidebar / list view and create a new conversation
        ensureChatListVisible(in: app)
        let newChatButton = app.buttons["hanlin-new-chat-button"].firstMatch
        XCTAssertTrue(newChatButton.waitForExistence(timeout: 10), "New chat button was not visible in ListView")
        tapElement(newChatButton)

        // Verify the newly created chat opens with an information welcome bubble and empty draft
        let infoBubble = app.descendants(matching: .any)["hanlin-info-bubble"].firstMatch
        XCTAssertTrue(infoBubble.waitForExistence(timeout: 10), "New chat welcome information bubble did not appear")

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

        let finalAnswer = app.staticTexts.matching(
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

    func testUI03SearchMessageAndDeduplicatedCitations() throws {
        let app = launchAcceptanceApp()
        openChat(in: app)

        sendPrompt("PROMPT_UI03_SEARCH_CITATIONS", in: app)

        let finalAnswer = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'UI03_SEARCH_COMPLETE'")
        ).firstMatch
        XCTAssertTrue(finalAnswer.waitForExistence(timeout: 45), "UI03 search final answer did not render")

        let searchBubbles = app.descendants(matching: .any).matching(identifier: "hanlin-search-bubble")
        XCTAssertTrue(searchBubbles.firstMatch.waitForExistence(timeout: 10), "Classic role==search bubble did not render")
        XCTAssertEqual(searchBubbles.count, 1, "Multiple search updates in one turn must update the single search bubble in-place")

        let referenceMaterials = app.descendants(matching: .any)["hanlin-reference-materials"].firstMatch
        XCTAssertTrue(referenceMaterials.waitForExistence(timeout: 10), "Reference materials citation section did not render")

        attachScreenshot("UI-03_SearchMessageAndDeduplicatedCitations", in: app)
    }

    func testUI04CollapsedProgressAndInspectorWithoutRawCoT() throws {
        let app = launchAcceptanceApp()
        openChat(in: app)

        sendPrompt("PROMPT_UI04_REASONING_INSPECTOR", in: app)

        let finalAnswer = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'UI04_REASONING_COMPLETE'")
        ).firstMatch
        XCTAssertTrue(finalAnswer.waitForExistence(timeout: 45), "UI04 reasoning final answer did not render")

        let summaryPill = app.buttons["hanlin-agent-activity-summary"].firstMatch
        XCTAssertTrue(summaryPill.waitForExistence(timeout: 10), "Collapsed agent activity summary pill did not render")
        XCTAssertFalse(summaryPill.label.contains("<think>"), "Collapsed summary pill must never expose <think> tags")
        XCTAssertFalse(summaryPill.label.localizedCaseInsensitiveContains("Let me think"), "Collapsed summary pill must never expose raw CoT")

        // Open the inspector sheet and verify raw CoT is never displayed
        tapElement(summaryPill)
        let inspector = app.descendants(matching: .any)["hanlin-agent-activity-inspector"].firstMatch
        XCTAssertTrue(inspector.waitForExistence(timeout: 10), "Agent activity inspector sheet did not open")

        let rawCoTText = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Let me think privately' OR label CONTAINS '<think>'")
        ).firstMatch
        XCTAssertFalse(rawCoTText.exists, "Inspector must never display raw chain-of-thought monologue")

        attachScreenshot("UI-04_CollapsedProgressAndInspectorWithoutRawCoT", in: app)
    }

    func testUI05RichCodeBlockHTMLCardAndAttachments() throws {
        let app = launchAcceptanceApp()
        openChat(in: app)

        // Attach sample image and sample document via composer plus menu
        let plusMenu = app.descendants(matching: .any)["hanlin-composer-plus-menu"].firstMatch
        XCTAssertTrue(plusMenu.waitForExistence(timeout: 10), "Composer plus menu did not appear")
        tapElement(plusMenu)

        let attachImage = app.buttons.matching(
            NSPredicate(format: "identifier == 'hanlin-attach-sample-image' OR label CONTAINS 'Attach Sample Image'")
        ).firstMatch
        XCTAssertTrue(attachImage.waitForExistence(timeout: 5), "Attach Sample Image button did not appear")
        tapElement(attachImage)
        XCTAssertTrue(app.descendants(matching: .any)["hanlin-composer-image-attachment"].firstMatch.waitForExistence(timeout: 5))

        tapElement(plusMenu)
        let attachDoc = app.buttons.matching(
            NSPredicate(format: "identifier == 'hanlin-attach-sample-document' OR label CONTAINS 'Attach Sample Document'")
        ).firstMatch
        XCTAssertTrue(attachDoc.waitForExistence(timeout: 5), "Attach Sample Document button did not appear")
        tapElement(attachDoc)
        XCTAssertTrue(app.descendants(matching: .any)["hanlin-composer-document-attachment"].firstMatch.waitForExistence(timeout: 5))

        sendPrompt("PROMPT_UI05_RICH_CONTENT", in: app)

        let finalAnswer = app.staticTexts.matching(
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

        // 1. Attach and remove image and document in composer
        let plusMenu = app.descendants(matching: .any)["hanlin-composer-plus-menu"].firstMatch
        XCTAssertTrue(plusMenu.waitForExistence(timeout: 10))
        tapElement(plusMenu)
        let attachImgBtn = app.buttons.matching(
            NSPredicate(format: "identifier == 'hanlin-attach-sample-image' OR label CONTAINS 'Attach Sample Image'")
        ).firstMatch
        XCTAssertTrue(attachImgBtn.waitForExistence(timeout: 5))
        tapElement(attachImgBtn)

        let composerImage = app.descendants(matching: .any)["hanlin-composer-image-attachment"].firstMatch
        XCTAssertTrue(composerImage.waitForExistence(timeout: 5), "Composer image attachment strip did not appear")
        let removeImage = app.buttons["hanlin-remove-image-attachment"].firstMatch
        XCTAssertTrue(removeImage.waitForExistence(timeout: 5))
        tapElement(removeImage)

        tapElement(plusMenu)
        let attachDocBtn = app.buttons.matching(
            NSPredicate(format: "identifier == 'hanlin-attach-sample-document' OR label CONTAINS 'Attach Sample Document'")
        ).firstMatch
        XCTAssertTrue(attachDocBtn.waitForExistence(timeout: 5))
        tapElement(attachDocBtn)
        let composerDoc = app.descendants(matching: .any)["hanlin-composer-document-attachment"].firstMatch
        XCTAssertTrue(composerDoc.waitForExistence(timeout: 5), "Composer document attachment strip did not appear")
        let removeDoc = app.buttons["hanlin-remove-document-attachment"].firstMatch
        XCTAssertTrue(removeDoc.waitForExistence(timeout: 5))
        tapElement(removeDoc)

        // 2. Verify multiline input and non-overlapping accessory bar controls
        let input = chatInputElement(in: app)
        tapElement(input)
        input.typeText("Line 1 of multiline composer test\nLine 2 of multiline composer test\nLine 3 of multiline composer test")

        let modelCapsule = app.descendants(matching: .any)["hanlin-model-selector-capsule"].firstMatch
        let continuePill = app.descendants(matching: .any)["hanlin-continue-generation-pill"].firstMatch
        XCTAssertTrue(modelCapsule.waitForExistence(timeout: 5), "Model selector capsule must exist in accessory bar")
        XCTAssertTrue(continuePill.waitForExistence(timeout: 5), "Continue generation pill must exist in accessory bar")
        XCTAssertFalse(
            modelCapsule.frame.intersects(continuePill.frame),
            "Model selector capsule (\(modelCapsule.frame)) and continue pill (\(continuePill.frame)) must never overlap"
        )

        // 3. Open model selector menu/sheet
        tapElement(modelCapsule)
        let modelCandidate = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'Agent Acceptance'")
        ).firstMatch
        XCTAssertTrue(modelCandidate.waitForExistence(timeout: 10), "Model selector did not display Agent Acceptance model")

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

        let recoveredAnswer = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'UI07_RETRY_RECOVERY_COMPLETE'")
        ).firstMatch
        XCTAssertTrue(recoveredAnswer.waitForExistence(timeout: 30), "Retry did not recover with UI07_RETRY_RECOVERY_COMPLETE")

        XCTAssertFalse(errorBubble.exists, "Stale error bubble must be removed on retry")
        let assistantBubbles = app.descendants(matching: .any).matching(identifier: "hanlin-assistant-bubble")
        XCTAssertEqual(assistantBubbles.count, 1, "Retry must produce exactly 1 assistant bubble without duplicates")

        attachScreenshot("UI-07_StopAndRetryRecoveryWithoutDuplicateBubbles", in: app)
    }

    func testUI08ConversationalMCPLifecycleAndSecondTurnReuse() throws {
        let app = launchAcceptanceApp()
        openChat(in: app)

        // Turn 1: Install local .tgz MCP server via manage_mcp_servers and call mcp__hanlin_echo_mcp__echo_ping in the same turn
        sendPrompt("PROMPT_UI08_MCP_TURN_1", in: app)

        let turn1Answer = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'UI08_MCP_TURN_1_COMPLETE'")
        ).firstMatch
        XCTAssertTrue(turn1Answer.waitForExistence(timeout: 90), "Turn 1 conversational MCP install + tool call did not complete")
        XCTAssertTrue(turn1Answer.label.contains("ECHO_PONG_OK:turn1"), "Turn 1 did not include live MCP worker response ECHO_PONG_OK:turn1")

        // Turn 2: Reuse the installed MCP server tool in the next turn of the same conversation without reinstalling
        sendPrompt("PROMPT_UI08_MCP_TURN_2", in: app)

        let turn2Answer = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'UI08_MCP_TURN_2_COMPLETE'")
        ).firstMatch
        XCTAssertTrue(turn2Answer.waitForExistence(timeout: 60), "Turn 2 conversational MCP tool reuse did not complete")
        XCTAssertTrue(turn2Answer.label.contains("ECHO_PONG_OK:turn2"), "Turn 2 did not include live MCP worker response ECHO_PONG_OK:turn2")

        attachScreenshot("UI-08_ConversationalMCPLifecycleAndSecondTurnReuse", in: app)
    }

    // MARK: - Navigation & Toggle Helpers

    private func launchAcceptanceApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["HANLIN_UNIT_TEST_HOST"] = "0"
        app.launchEnvironment["HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE"] = "1"
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

    private func sendPrompt(_ text: String, in app: XCUIApplication) {
        let input = chatInputElement(in: app)
        XCTAssertTrue(input.waitForExistence(timeout: 20), "Chat input field did not appear")
        tapElement(input)
        input.typeText(text)
        let send = app.buttons["hanlin-chat-send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 10), "Chat send button did not appear")
        tapElement(send)
    }

    private func ensureChatListVisible(in app: XCUIApplication) {
        let newChatButton = app.buttons["hanlin-new-chat-button"].firstMatch
        if newChatButton.exists && newChatButton.isHittable { return }

        let sidebarToggle = app.navigationBars.buttons.matching(
            NSPredicate(format: "identifier == 'ToggleSidebar' OR label CONTAINS[c] 'Sidebar' OR label CONTAINS[c] 'סרגל'")
        ).firstMatch
        if sidebarToggle.waitForExistence(timeout: 2) && sidebarToggle.isHittable {
            sidebarToggle.tap()
            if newChatButton.waitForExistence(timeout: 3) && newChatButton.isHittable { return }
        }

        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        if backButton.waitForExistence(timeout: 2) && backButton.isHittable {
            backButton.tap()
        }
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
        _ = settingsNavEn.waitForExistence(timeout: 5) || settingsNav.waitForExistence(timeout: 5)
    }

    private func navigateBack(in app: XCUIApplication) {
        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        if backButton.waitForExistence(timeout: 3) && backButton.isHittable {
            backButton.tap()
        }
    }

    private func openRuntimeCenter(in app: XCUIApplication) {
        if app.navigationBars["Runtimes & Packages"].exists { return }
        openSettings(in: app)
        let runtimeCenterNav = app.navigationBars["Runtimes & Packages"].firstMatch
        if runtimeCenterNav.waitForExistence(timeout: 3) { return }
        let link = app.descendants(matching: .any)["hanlin-runtimes-packages-link"].firstMatch
        if !link.waitForExistence(timeout: 5) {
            app.swipeUp()
        }
        if link.waitForExistence(timeout: 10) {
            if link.isHittable {
                link.tap()
            } else {
                app.swipeUp()
                link.tap()
            }
        }
        _ = runtimeCenterNav.waitForExistence(timeout: 10)
    }

    private func tapElement(_ element: XCUIElement) {
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    private func openChat(in app: XCUIApplication) {
        while app.navigationBars["Runtimes & Packages"].exists {
            let backButton = app.navigationBars.buttons.element(boundBy: 0)
            if backButton.waitForExistence(timeout: 2) && backButton.isHittable {
                backButton.tap()
            } else {
                break
            }
        }
        _ = selectTab(identifier: "hanlin-home-tab", labels: ["Chats", "Messages", "Home", "列表"], in: app)

        let input = chatInputElement(in: app)
        if input.waitForExistence(timeout: 3) { return }

        // Expand sidebar on iPad if collapsed
        let sidebarToggle = app.navigationBars.buttons.matching(
            NSPredicate(format: "identifier == 'ToggleSidebar' OR label CONTAINS[c] 'Sidebar' OR label CONTAINS[c] 'סרגל'")
        ).firstMatch
        if sidebarToggle.waitForExistence(timeout: 2) && sidebarToggle.isHittable {
            sidebarToggle.tap()
        }

        let chatPredicate = NSPredicate(format: "label CONTAINS 'Agent Acceptance Chat' OR identifier CONTAINS 'Agent Acceptance Chat'")
        var seededChat = app.buttons.matching(chatPredicate).firstMatch
        if !seededChat.exists {
            seededChat = app.staticTexts.matching(chatPredicate).firstMatch
        }
        if !seededChat.exists {
            seededChat = app.cells.matching(chatPredicate).firstMatch
        }
        if !seededChat.exists {
            seededChat = app.descendants(matching: .any).matching(chatPredicate).firstMatch
        }

        if seededChat.waitForExistence(timeout: 15) {
            tapElement(seededChat)
        } else {
            let anyChat = app.cells.firstMatch
            if anyChat.waitForExistence(timeout: 3) {
                tapElement(anyChat)
            }
        }

        _ = input.waitForExistence(timeout: 15)
    }

    private func toggleSwitch(for kindRaw: String, in app: XCUIApplication) -> XCUIElement {
        let sw = app.switches["hanlin-runtime-availability-\(kindRaw)"].firstMatch
        if sw.exists { return sw }
        return app.descendants(matching: .switch)["hanlin-runtime-availability-\(kindRaw)"].firstMatch
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

    private func waitForToggle(_ element: XCUIElement, toBe targetState: Bool, timeout: TimeInterval = 15) -> Bool {
        let predicate = NSPredicate { _, _ in
            self.isToggleOn(element) == targetState
        }
        let exp = expectation(for: predicate, evaluatedWith: element)
        let result = XCTWaiter.wait(for: [exp], timeout: timeout)
        return result == .completed
    }
}
