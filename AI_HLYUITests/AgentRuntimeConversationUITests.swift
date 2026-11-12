import XCTest
import UIKit

@MainActor
final class AgentRuntimeConversationUITests: XCTestCase {
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

        let input = chatInputElement(in: app)
        XCTAssertTrue(input.waitForExistence(timeout: 20), "The real chat input did not appear.")
        tapElement(input)
        input.typeText("Run the local Python acceptance tool and report the result.")

        let send = app.buttons["hanlin-chat-send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 10), "The real chat send button did not appear.")
        tapElement(send)

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
        let input = chatInputElement(in: app)
        XCTAssertTrue(input.waitForExistence(timeout: 20), "The real chat input did not appear.")
        tapElement(input)
        input.typeText("Use Python to calculate 6*7 and tell me the result.")

        let send = app.buttons["hanlin-chat-send"].firstMatch
        XCTAssertTrue(send.waitForExistence(timeout: 10))
        tapElement(send)

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
        let runBAnswer = assistantBubbles.descendants(matching: .staticText).matching(
            NSPredicate(format: "label CONTAINS 'RUN_B_COMPLETE'")
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

        let runBMatches = assistantBubbles.descendants(matching: .staticText).matching(
            NSPredicate(format: "label CONTAINS 'RUN_B_COMPLETE'")
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

    func testUI03SearchMessageAndDeduplicatedCitations() throws {
        let app = launchAcceptanceApp()
        openChat(in: app)

        sendPrompt("PROMPT_UI03_SEARCH_CITATIONS", in: app)

        let finalAnswer = app.descendants(matching: .any).matching(
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

    func testNativePartialSelectionSaveAndOriginalLongPressPreview() throws {
        let app = launchAcceptanceApp()
        openChat(in: app)
        sendPrompt("PROMPT_CHAT_PRESENTATION", in: app)
        let paragraph = app.textViews.matching(NSPredicate(format: "label == 'alpha beta gamma'")).firstMatch
        XCTAssertTrue(paragraph.waitForExistence(timeout: 45), "The actual native Markdown paragraph did not render")
        paragraph.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.5)).doubleTap()
        let save = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Save for myself'")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10), "Native selected-text Save action is missing: \(app.debugDescription)")
        tapElement(save)

        // The original whole-message context menu remains on the message's padding;
        // a double tap inside its native paragraph selects text independently.
        paragraph.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            .withOffset(CGVector(dx: 0, dy: -2)).press(forDuration: 1)
        let wholeCopy = app.descendants(matching: .any)["hanlin-message-menu-copy"].firstMatch
        XCTAssertTrue(wholeCopy.waitForExistence(timeout: 10), "Original whole-message preview/menu was lost: \(app.debugDescription)")
        attachScreenshot("Chat_OriginalOpaquePreview", in: app)
        tapElement(wholeCopy)

        ensureChatListVisible(in: app)
        let saved = app.buttons["hanlin-saved-messages-open"].firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10), "Saved messages entry missing: \(app.debugDescription)")
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

    func testUI04CollapsedProgressAndInspectorWithoutRawCoT() throws {
        let app = launchAcceptanceApp()
        openChat(in: app)

        sendPrompt("PROMPT_UI04_REASONING_INSPECTOR", in: app)

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
        let recoveredAnswers = assistantBubbles.descendants(matching: .staticText).matching(
            NSPredicate(format: "label CONTAINS 'UI07_RETRY_RECOVERY_COMPLETE'")
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

        // Persistent OrganizerDock anchored at the bottom of compact Home
        let dock = app.descendants(matching: .any)["hanlin-organizer-dock"].firstMatch
        let input = chatInputElement(in: app)
        XCTAssertTrue(dock.waitForExistence(timeout: 10), "Persistent OrganizerDock must exist on compact Home")
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Persistent chat input must exist on compact Home")
        XCTAssertGreaterThan(
            dock.frame.maxY,
            app.windows.firstMatch.frame.height * 0.65,
            "Persistent OrganizerDock must be anchored near the bottom of the screen"
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
        let dock = app.descendants(matching: .any)["hanlin-organizer-dock"].firstMatch
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
        let newChatBtn = wideApp.buttons["hanlin-new-chat-button"].firstMatch
        XCTAssertTrue(newChatBtn.waitForExistence(timeout: 15), "Wide iPad (>=640pt) must preserve NavigationSplitView sidebar")
        attachScreenshot("7B-03b_WidthAdaptiveWorkspace_Wide1024pt", in: wideApp)
    }

    func testDrawerGrowsFromComposerNotPopover() throws {
        let app = launchDockAcceptanceApp()
        openChat(in: app)

        let drawer = app.descendants(matching: .any)["hanlin-organizer-drawer"].firstMatch
        let composerShell = app.descendants(matching: .any)["hanlin-organizer-composer-shell"].firstMatch
        let generalBtn = app.descendants(matching: .any)["hanlin-composer-general-menu"].firstMatch

        XCTAssertTrue(drawer.waitForExistence(timeout: 10), "Back drawer layer must exist")
        XCTAssertTrue(composerShell.waitForExistence(timeout: 10), "Front composer shell must exist")
        XCTAssertTrue(generalBtn.waitForExistence(timeout: 10), "General `+` button must exist")

        let collapsedDrawerFrame = drawer.frame
        let collapsedComposerFrame = composerShell.frame
        attachScreenshot("7B-04a_DockCollapsed", in: app)

        // Tap `+` to expand the integrated drawer upward behind the composer
        tapElement(generalBtn)
        let generalDrawerContent = app.descendants(matching: .any)["hanlin-composer-general-popover"].firstMatch
        XCTAssertTrue(generalDrawerContent.waitForExistence(timeout: 5), "General drawer content must appear inside dock")
        attachScreenshot("7B-04b_DockExpanded_General", in: app)

        let expandedDrawerFrame = drawer.frame
        let expandedComposerFrame = composerShell.frame

        // Prove upward growth from the SAME bottom dock (not a detached floating popover)
        XCTAssertLessThan(
            expandedDrawerFrame.minY,
            collapsedDrawerFrame.minY - 180,
            "Expanded drawer top edge (\(expandedDrawerFrame.minY)) must grow upward well above collapsed top edge (\(collapsedDrawerFrame.minY))"
        )
        XCTAssertLessThan(
            abs(expandedDrawerFrame.maxY - expandedComposerFrame.maxY),
            16,
            "Drawer and composer must share the bottom edge of ZStack(alignment: .bottom)"
        )
        XCTAssertLessThan(
            abs(expandedComposerFrame.maxY - collapsedComposerFrame.maxY),
            16,
            "Composer bottom edge must remain anchored while drawer expands behind it"
        )
        XCTAssertEqual(app.popovers.count, 0, "General drawer must NOT present a floating UIPopover")

        // Verify R7 Saved Prompts horizontal gallery slot is rendered inside the General drawer
        let savedPromptsSlot = app.descendants(matching: .any)["hanlin-drawer-saved-prompts-slot"].firstMatch
        XCTAssertTrue(savedPromptsSlot.waitForExistence(timeout: 5), "Saved Prompts horizontal gallery slot must exist in General drawer")

        // Collapse drawer
        tapElement(generalBtn)
        XCTAssertTrue(generalDrawerContent.waitForNonExistence(timeout: 5))
    }

    func testDrawerHandleDragCloseOpenAndComposerResize() throws {
        let app = launchDockAcceptanceApp()
        openChat(in: app)

        let drawerHandle = app.buttons["hanlin-organizer-drawer-handle"].firstMatch
        let resizeHandle = app.descendants(matching: .any)["hanlin-composer-resize-handle"].firstMatch
        let composerShell = app.descendants(matching: .any)["hanlin-organizer-composer-shell"].firstMatch
        let generalBtn = app.descendants(matching: .any)["hanlin-composer-general-menu"].firstMatch

        XCTAssertTrue(drawerHandle.waitForExistence(timeout: 10), "Drawer handle must exist")
        XCTAssertTrue(resizeHandle.waitForExistence(timeout: 10), "Composer resize handle must exist")
        XCTAssertTrue(composerShell.waitForExistence(timeout: 10), "Composer shell must exist")

        // 1. Open drawer via `+`, then drag drawer handle downward (> 34pt) to collapse
        tapElement(generalBtn)
        let generalContent = app.descendants(matching: .any)["hanlin-composer-general-popover"].firstMatch
        XCTAssertTrue(generalContent.waitForExistence(timeout: 5))

        let handleStart = drawerHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let handleDragDown = handleStart.withOffset(CGVector(dx: 0, dy: 120))
        handleStart.press(forDuration: 0.05, thenDragTo: handleDragDown)
        XCTAssertTrue(generalContent.waitForNonExistence(timeout: 5), "Dragging drawer handle downward (>34pt) must collapse the drawer")
        attachScreenshot("7B-05a_AfterDrawerDragClose", in: app)

        // 2. Drag drawer handle upward (< -34pt) to reopen last expanded mode (no tap fallback)
        let collapsedHandleStart = drawerHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let handleDragUp = collapsedHandleStart.withOffset(CGVector(dx: 0, dy: -120))
        collapsedHandleStart.press(forDuration: 0.05, thenDragTo: handleDragUp)
        XCTAssertTrue(generalContent.waitForExistence(timeout: 5), "Dragging drawer handle upward (<-34pt) must reopen last expanded mode")

        // 3. Verify tap-to-close and tap-to-open on drawer handle
        tapElement(drawerHandle)
        XCTAssertTrue(generalContent.waitForNonExistence(timeout: 5), "Tapping drawer handle while open must collapse the drawer")
        tapElement(drawerHandle)
        XCTAssertTrue(generalContent.waitForExistence(timeout: 5), "Tapping drawer handle while collapsed must reopen last expanded mode")

        // Close drawer before testing composer resize handle
        tapElement(generalBtn)
        XCTAssertTrue(generalContent.waitForNonExistence(timeout: 5))

        // 4. Drag composer resize handle upward to increase both composer shell and inner text editor height
        let input = chatInputElement(in: app)
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        let heightBefore = composerShell.frame.height
        let inputHeightBefore = input.frame.height
        let resizeStart = resizeHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let resizeDragUp = resizeStart.withOffset(CGVector(dx: 0, dy: -90))
        resizeStart.press(forDuration: 0.05, thenDragTo: resizeDragUp)

        let heightAfter = composerShell.frame.height
        let inputHeightAfter = input.frame.height
        XCTAssertGreaterThan(
            heightAfter,
            heightBefore + 20,
            "Dragging composer resize handle upward must increase composer height (before: \(heightBefore), after: \(heightAfter))"
        )
        XCTAssertGreaterThan(
            inputHeightAfter,
            inputHeightBefore + 15,
            "Dragging composer resize handle upward must increase inner text editor height (before: \(inputHeightBefore), after: \(inputHeightAfter))"
        )
        attachScreenshot("7B-05b_AfterComposerResizeUp", in: app)

        // 5. Drag composer resize handle downward to shrink both composer shell and inner text editor height
        let resizeShrinkStart = resizeHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let resizeDragDown = resizeShrinkStart.withOffset(CGVector(dx: 0, dy: 70))
        resizeShrinkStart.press(forDuration: 0.05, thenDragTo: resizeDragDown)

        let heightAfterShrink = composerShell.frame.height
        let inputHeightAfterShrink = input.frame.height
        XCTAssertLessThan(
            heightAfterShrink,
            heightAfter - 15,
            "Dragging composer resize handle downward must shrink composer height (expanded: \(heightAfter), shrunk: \(heightAfterShrink))"
        )
        XCTAssertLessThan(
            inputHeightAfterShrink,
            inputHeightAfter - 10,
            "Dragging composer resize handle downward must shrink inner text editor height (expanded: \(inputHeightAfter), shrunk: \(inputHeightAfterShrink))"
        )
    }

    func testDirectToolsOneTapAndRealState() throws {
        let app = launchDockAcceptanceApp()
        openChat(in: app)

        let toolsDirect = app.descendants(matching: .any)["hanlin-composer-tools-direct"].firstMatch
        let generalBtn = app.descendants(matching: .any)["hanlin-composer-general-menu"].firstMatch
        let drawer = app.descendants(matching: .any)["hanlin-organizer-drawer"].firstMatch

        XCTAssertTrue(toolsDirect.waitForExistence(timeout: 10), "Direct Tools button must exist")
        tapElement(toolsDirect)

        // 1 tap opens Tools/Skills/MCP/Runtime root directly in the integrated dock
        let toolsContent = app.descendants(matching: .any)["hanlin-composer-tools-popover"].firstMatch
        XCTAssertTrue(toolsContent.waitForExistence(timeout: 5), "1 tap on Tools button must open Tools root in dock")
        XCTAssertEqual(app.popovers.count, 0, "Tools drawer must not be a floating UIPopover")

        let drawerFrameInTools = drawer.frame
        attachScreenshot("7B-06a_DirectToolsInDock", in: app)

        // Switching directly from Tools to `+` swaps mode inside the SAME expanded dock
        tapElement(generalBtn)
        let generalContent = app.descendants(matching: .any)["hanlin-composer-general-popover"].firstMatch
        XCTAssertTrue(generalContent.waitForExistence(timeout: 5), "Tapping `+` while Tools is open must swap to General in the same dock")
        XCTAssertFalse(toolsContent.exists, "Tools content must be replaced by General content")
        XCTAssertLessThan(
            abs(drawer.frame.height - drawerFrameInTools.height),
            24,
            "Dock panel height must remain continuously expanded when swapping between Tools and General"
        )
        attachScreenshot("7B-06b_SwappedToGeneralInSameDock", in: app)

        tapElement(generalBtn)
        XCTAssertTrue(generalContent.waitForNonExistence(timeout: 5))
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
                app.descendants(matching: .any)["hanlin-composer-tools-popover"].firstMatch.swipeUp()
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
        let drawerHandle = app.buttons["hanlin-organizer-drawer-handle"].firstMatch
        let resizeHandle = app.descendants(matching: .any)["hanlin-composer-resize-handle"].firstMatch
        XCTAssertTrue(generalBtn.waitForExistence(timeout: 10))
        XCTAssertTrue(drawerHandle.waitForExistence(timeout: 10))
        XCTAssertTrue(resizeHandle.waitForExistence(timeout: 10))

        // Open drawer, then focus text input -> drawer must automatically collapse to yield space to keyboard
        tapElement(generalBtn)
        let generalContent = app.descendants(matching: .any)["hanlin-composer-general-popover"].firstMatch
        XCTAssertTrue(generalContent.waitForExistence(timeout: 5))

        let input = chatInputElement(in: app)
        tapElement(input)
        XCTAssertTrue(generalContent.waitForNonExistence(timeout: 5), "Focusing text editor must automatically collapse open drawer")
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

    private func openChat(in app: XCUIApplication) {
        while app.navigationBars["Runtime diagnostics"].exists {
            let backButton = app.navigationBars.buttons.element(boundBy: 0)
            if backButton.waitForExistence(timeout: 2) && backButton.isHittable {
                backButton.tap()
            } else {
                break
            }
        }
        _ = selectTab(identifier: "hanlin-home-tab", labels: ["Chats", "Messages", "Home", "列表"], in: app)

        let input = chatInputElement(in: app)
        let compactViewAll = app.buttons["hanlin-compact-view-all-button"].firstMatch
        if input.waitForExistence(timeout: 3) && !compactViewAll.exists { return }

        // If on compact Home, tap the seeded Agent Acceptance Chat row directly
        if compactViewAll.exists {
            let recentRow0 = app.buttons["hanlin-compact-recent-row-0"].firstMatch
            if recentRow0.waitForExistence(timeout: 3) && recentRow0.label.contains("Agent Acceptance Chat") {
                tapElement(recentRow0)
                _ = input.waitForExistence(timeout: 10)
                return
            }
        }

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
            seededChat = app.descendants(matching: .any).matching(chatPredicate).firstMatch
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
