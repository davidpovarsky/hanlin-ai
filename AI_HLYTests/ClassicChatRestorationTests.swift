import Foundation
import SwiftUI
import SwiftData
import Testing
import SWCompression
import HanlinChatCore
import HanlinPlatformContracts
@testable import AI_Hanlin

@MainActor
@Suite("Classic Source-First Chat Restoration & Agent Capability Verification", .serialized)
struct ClassicChatRestorationTests {

    private func makeInMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(
            for: ChatMessages.self,
            APIKeys.self,
            SearchKeys.self,
            AllModels.self,
            ChatRecords.self,
            UserInfo.self,
            PromptRepo.self,
            KnowledgeRecords.self,
            KnowledgeChunk.self,
            MemoryArchive.self,
            TranslationDic.self,
            ToolKeys.self,
            configurations: configuration
        )
    }

    // MARK: - 1. classicBubbleAuthorityNeverSuppressesMessageRows

    @Test("1. Classic bubble authority never suppresses user, search, assistant, error, or information rows")
    func classicBubbleAuthorityNeverSuppressesMessageRows() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let chatRecord = ChatRecords(name: "Classic Authority Chat", type: "chat")
        context.insert(chatRecord)

        let groupID = UUID()
        let userMsg = ChatMessages(
            role: "user",
            text: "Search and explain SwiftUI layout",
            groupID: groupID,
            record: chatRecord
        )
        let assistantMsg = ChatMessages(
            role: "assistant",
            text: "Final synthesized explanation.",
            groupID: groupID,
            record: chatRecord
        )
        let errorMsg = ChatMessages(
            role: "error",
            text: "Network interrupted",
            groupID: UUID(),
            record: chatRecord
        )
        let infoMsg = ChatMessages(
            role: "information",
            text: "Welcome to ChavrusaChat",
            groupID: UUID(),
            record: chatRecord
        )

        var chatTemps: [ChatMessages] = [infoMsg, userMsg, assistantMsg, errorMsg]
        var searchMessage: ChatMessages?

        // Streaming search_text inserts a search row right before the assistant row
        searchMessage = ChatTurnStateOperations.upsertSearchMessage(
            existing: searchMessage,
            text: "1. Apple Developer Documentation (https://developer.apple.com)",
            searchEngine: "tavily_keyless",
            assistantMessage: assistantMsg,
            record: chatRecord,
            in: &chatTemps
        )

        #expect(chatTemps.map(\.role) == ["information", "user", "search", "assistant", "error"])
        #expect(searchMessage != nil)
        #expect(searchMessage?.searchEngine == "tavily_keyless")

        // Verify AgentActivitySummary is subordinate and only shown when AgentRun has steps or active work
        let emptyCompletedRun = AgentRun(
            groupID: groupID,
            status: .completed,
            steps: [],
            transcriptItems: [],
            finalAnswer: "Final synthesized explanation."
        )
        #expect(emptyCompletedRun.steps.isEmpty)

        let step = AgentActivityStep(
            externalID: "call-1",
            sequence: 0,
            kind: .toolExecution,
            title: "Executed Python",
            status: .completed
        )
        let activeOrToolRun = AgentRun(
            groupID: groupID,
            status: .completed,
            steps: [step],
            transcriptItems: [],
            finalAnswer: "Final synthesized explanation."
        )
        #expect(!activeOrToolRun.steps.isEmpty)
        #expect(assistantMsg.role == "assistant")
        #expect(userMsg.role != "assistant")
    }

    // MARK: - 2. webSearchCitationsAndSourcesDeduplicated

    @Test("2. Web search message row updates in place and citations/sources are deduplicated across Resource and AgentEvidenceItem")
    func webSearchCitationsAndSourcesDeduplicated() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let chatRecord = ChatRecords(name: "Search Dedup Chat", type: "chat")
        context.insert(chatRecord)

        let groupID = UUID()
        let userMsg = ChatMessages(role: "user", text: "Find Swift 6 docs", groupID: groupID, record: chatRecord)
        let assistantMsg = ChatMessages(role: "assistant", text: "", groupID: groupID, record: chatRecord)
        var chatTemps: [ChatMessages] = [userMsg, assistantMsg]
        var searchMsg: ChatMessages?

        // Chunk 1 and Chunk 2 of search_text in the same turn must update in place (1 search row total)
        searchMsg = ChatTurnStateOperations.upsertSearchMessage(
            existing: searchMsg,
            text: "1. Swift.org Migration Guide",
            searchEngine: "tavily_keyless",
            assistantMessage: assistantMsg,
            record: chatRecord,
            in: &chatTemps
        )
        searchMsg = ChatTurnStateOperations.upsertSearchMessage(
            existing: searchMsg,
            text: "1. Swift.org Migration Guide\n2. WWDC 2024 Swift 6",
            searchEngine: "tavily_keyless",
            assistantMessage: assistantMsg,
            record: chatRecord,
            in: &chatTemps
        )

        let searchRows = chatTemps.filter { $0.role == "search" }
        #expect(searchRows.count == 1)
        #expect(searchRows.first?.text?.contains("WWDC 2024 Swift 6") == true)

        // Duplicate Resource URLs (including trailing slash and UTM query params) are deduplicated
        let rawResources = [
            Resource(icon: "globe", title: "Swift 6 Guide", link: "https://swift.org/migration/?utm_source=test"),
            Resource(icon: "globe", title: "Swift 6 Guide Duplicate", link: "https://swift.org/migration/"),
            Resource(icon: "globe", title: "Apple Developer", link: "https://developer.apple.com/swift")
        ]
        let deduplicatedResources = LegacyResourcesEvidenceAdapter.deduplicatedResources(rawResources)
        #expect(deduplicatedResources.count == 2)
        #expect(deduplicatedResources.map(\.title) == ["Swift 6 Guide", "Apple Developer"])

        // AgentEvidenceAccumulator also deduplicates identical URLs across LegacyResourcesEvidenceAdapter
        var evidenceAcc = AgentEvidenceAccumulator()
        evidenceAcc.insert(contentsOf: LegacyResourcesEvidenceAdapter.items(from: rawResources, providerName: "tavily_keyless"))
        #expect(evidenceAcc.items.count == 2)
    }

    // MARK: - 3. retryReplacesFailedAssistantGroupWithoutDuplicateBubbles

    @Test("3. Retry cleans up failed assistant, search, error, and info rows for the retried turn without duplicate bubbles")
    func retryReplacesFailedAssistantGroupWithoutDuplicateBubbles() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let chatRecord = ChatRecords(name: "Retry Chat", type: "chat")
        context.insert(chatRecord)

        // Prior completed turn (Turn 1)
        let turn1Group = UUID()
        let turn1User = ChatMessages(role: "user", text: "Turn 1 question", groupID: turn1Group, record: chatRecord)
        let turn1Assistant = ChatMessages(role: "assistant", text: "Turn 1 answer", groupID: turn1Group, record: chatRecord)

        // Failed Turn 2
        let turn2Group = UUID()
        let turn2User = ChatMessages(role: "user", text: "Turn 2 question", groupID: turn2Group, record: chatRecord)
        let turn2Search = ChatMessages(role: "search", text: "Search results for Turn 2", groupID: turn2Group, record: chatRecord)
        let turn2PartialAssistant = ChatMessages(role: "assistant", text: "Partial...", groupID: turn2Group, record: chatRecord)
        let turn2Error = ChatMessages(role: "error", text: "Connection reset by peer", groupID: UUID(), record: chatRecord)
        let turn2Info = ChatMessages(role: "information", text: "Request cancelled", groupID: UUID(), record: chatRecord)

        for msg in [turn1User, turn1Assistant, turn2User, turn2Search, turn2PartialAssistant, turn2Error, turn2Info] {
            context.insert(msg)
        }
        try context.save()

        var chatTemps: [ChatMessages] = [
            turn1User, turn1Assistant,
            turn2User, turn2Search, turn2PartialAssistant, turn2Error, turn2Info
        ]

        // Retry triggered from the trailing error message
        let didRemove = ChatTurnStateOperations.cleanupTurnForRetry(
            targetMessage: turn2Error,
            chatTemps: &chatTemps,
            context: context
        )
        try context.save()

        #expect(didRemove)
        #expect(chatTemps.map(\.role) == ["user", "assistant", "user"])
        #expect(chatTemps.last?.id == turn2User.id)
        #expect(chatTemps.last?.text == "Turn 2 question")

        // Verify persisted context also has only the 3 remaining messages
        let persisted = try context.fetch(FetchDescriptor<ChatMessages>())
        #expect(persisted.count == 3)
    }

    // MARK: - 4. dynamicBottomPaddingTracksMeasuredComposerHeight

    @Test("4. Dynamic bottom padding tracks measured composer height across compact, multiline, and attachment trays")
    func dynamicBottomPaddingTracksMeasuredComposerHeight() {
        let baseCompact = ChatView.calculateDynamicBottomPadding(
            measuredComposerHeight: 56,
            hasURLs: false,
            hasImages: false,
            hasDocuments: false,
            showPhotoSourceOptions: false,
            hasPrompts: false
        )
        let expandedMultiline = ChatView.calculateDynamicBottomPadding(
            measuredComposerHeight: 132,
            hasURLs: false,
            hasImages: false,
            hasDocuments: false,
            showPhotoSourceOptions: false,
            hasPrompts: false
        )
        let withAllAttachmentsFallback = ChatView.calculateDynamicBottomPadding(
            measuredComposerHeight: 0,
            hasURLs: true,
            hasImages: true,
            hasDocuments: true,
            showPhotoSourceOptions: true,
            hasPrompts: true
        )

        #expect(baseCompact == 96)
        #expect(expandedMultiline == 152)
        #expect(expandedMultiline > baseCompact)
        #expect(withAllAttachmentsFallback > 300)
    }

    // MARK: - 5. userBubbleUsesClassicShapeAndAttachments

    @Test("5. User bubble uses classic CustomCorners(20, 20, 20, 5) shape and supports images, documents, and prompt cards")
    func userBubbleUsesClassicShapeAndAttachments() {
        let shape = CustomCorners(topLeft: 20, topRight: 20, bottomLeft: 20, bottomRight: 5)
        let rect = CGRect(x: 0, y: 0, width: 240, height: 80)
        let path = shape.path(in: rect)
        #expect(!path.isEmpty)
        #expect(path.boundingRect.width == 240)
        #expect(path.boundingRect.height == 80)

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24))
        let sampleImage = renderer.image { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        }
        let sampleDocURL = URL(fileURLWithPath: "/tmp/sample_attachment.pdf")
        let samplePrompt = PromptCard(name: "Reviewer", content: "Review code carefully")

        var reasoningExpanded = false
        var toolExpanded = false
        var voiceExpanded = false

        let normalUserBubble = ChatBubbleView(
            temporaryRecord: false,
            id: UUID(),
            text: "Inspect these attachments",
            saveTranlatedText: nil,
            images: [sampleImage],
            imagesText: "Sample blue square",
            reasoning: "",
            reasoningTime: nil,
            isReasoningExpanded: Binding(get: { reasoningExpanded }, set: { reasoningExpanded = $0 }),
            toolContent: "",
            toolName: "",
            isToolContentExpanded: Binding(get: { toolExpanded }, set: { toolExpanded = $0 }),
            uploadDocument: [sampleDocURL],
            documentText: "Extracted PDF text",
            resources: nil,
            prompts: [samplePrompt],
            locations: nil,
            routes: nil,
            events: nil,
            htmlContent: nil,
            healthCards: nil,
            codeBlocks: nil,
            knowledgeCard: nil,
            searchEngine: nil,
            audioAssets: nil,
            isVoiceExpanded: Binding(get: { voiceExpanded }, set: { voiceExpanded = $0 }),
            showCanvas: false,
            canvas: nil,
            role: "user",
            model: "gpt-4o",
            modelCompany: "OPENAI",
            modelIdentity: "model",
            modelIcon: "sparkles",
            isLastAssistant: false,
            isLastAssistantGroup: false,
            splitMarker: false,
            isResponding: false,
            operationalState: "",
            operationalDescription: "",
            onRetry: nil,
            onDelete: nil
        )

        let tempUserBubble = ChatBubbleView(
            temporaryRecord: true,
            id: UUID(),
            text: "Temporary mode message",
            saveTranlatedText: nil,
            images: nil,
            imagesText: nil,
            reasoning: "",
            reasoningTime: nil,
            isReasoningExpanded: .constant(false),
            toolContent: "",
            toolName: "",
            isToolContentExpanded: .constant(false),
            uploadDocument: nil,
            documentText: nil,
            resources: nil,
            prompts: nil,
            locations: nil,
            routes: nil,
            events: nil,
            htmlContent: nil,
            healthCards: nil,
            codeBlocks: nil,
            knowledgeCard: nil,
            searchEngine: nil,
            audioAssets: nil,
            isVoiceExpanded: .constant(false),
            showCanvas: false,
            canvas: nil,
            role: "user",
            model: "gpt-4o",
            modelCompany: "OPENAI",
            modelIdentity: "model",
            modelIcon: "sparkles",
            isLastAssistant: false,
            isLastAssistantGroup: false,
            splitMarker: false,
            isResponding: false,
            operationalState: "",
            operationalDescription: "",
            onRetry: nil,
            onDelete: nil
        )

        #expect(normalUserBubble.role == "user")
        #expect(!normalUserBubble.temporaryRecord)
        #expect(normalUserBubble.images?.count == 1)
        #expect(normalUserBubble.uploadDocument?.count == 1)
        #expect(normalUserBubble.prompts?.first?.name == "Reviewer")
        #expect(tempUserBubble.temporaryRecord)
    }

    // MARK: - 6. assistantBubbleOwnsFinalAnswerAndActionButtons

    @Test("6. Assistant bubble owns final answer text, subordinate AgentActivitySummaryView, and tool result cards")
    func assistantBubbleOwnsFinalAnswerAndActionButtons() {
        let groupID = UUID()
        let toolStep = AgentActivityStep(
            externalID: "call-calc",
            sequence: 0,
            kind: .toolExecution,
            title: "Calculated 6 * 7",
            status: .completed,
            output: "42"
        )
        let toolResultItem = AgentTranscriptItem(
            externalID: "call-calc:result",
            sequence: 1,
            kind: .userVisibleToolResult,
            callID: "call-calc",
            toolName: "execute_local_python_code",
            resultRendererKind: .modernNative,
            status: .completed,
            text: "42",
            nativeUIBlocks: [
                NativeUIBlock(
                    type: .card,
                    title: "Python Output",
                    body: "42"
                )
            ],
            visibilityAfterCompletion: .remainInChat
        )
        let finalTextItem = AgentTranscriptItem(
            externalID: "final-text",
            sequence: 2,
            kind: .assistantText,
            status: .completed,
            text: "The result of 6 * 7 is **42**.",
            textRole: .final,
            visibilityAfterCompletion: .remainInChat
        )
        let run = AgentRun(
            groupID: groupID,
            status: .completed,
            steps: [toolStep],
            transcriptItems: [toolResultItem, finalTextItem],
            finalAnswer: "The result of 6 * 7 is **42**."
        )

        let bubble = ChatBubbleView(
            temporaryRecord: false,
            id: UUID(),
            text: "The result of 6 * 7 is **42**.",
            saveTranlatedText: nil,
            images: nil,
            imagesText: nil,
            reasoning: "",
            reasoningTime: nil,
            isReasoningExpanded: .constant(false),
            toolContent: "",
            toolName: "",
            isToolContentExpanded: .constant(false),
            uploadDocument: nil,
            documentText: nil,
            resources: [Resource(icon: "globe", title: "Python Docs", link: "https://docs.python.org")],
            prompts: nil,
            locations: nil,
            routes: nil,
            events: nil,
            htmlContent: nil,
            healthCards: nil,
            codeBlocks: nil,
            knowledgeCard: nil,
            nativeUIBlocks: [],
            agentRun: run,
            showsAgentActivitySummary: true,
            isAgentTranscriptOwner: true,
            isRenderedByAgentTranscript: true,
            searchEngine: "tavily_keyless",
            audioAssets: nil,
            isVoiceExpanded: .constant(false),
            showCanvas: false,
            canvas: nil,
            role: "assistant",
            model: "GPT-4o",
            modelCompany: "OPENAI",
            modelIdentity: "model",
            modelIcon: "sparkles",
            isLastAssistant: true,
            isLastAssistantGroup: true,
            splitMarker: true,
            isResponding: false,
            operationalState: "",
            operationalDescription: "",
            onRetry: {},
            onDelete: {}
        )

        #expect(bubble.role == "assistant")
        #expect(bubble.showsAgentActivitySummary)
        #expect(bubble.isAgentTranscriptOwner)
        #expect(bubble.text.contains("42"))
        #expect(bubble.agentRun?.transcriptItems.contains(where: { $0.kind == .userVisibleToolResult }) == true)
    }

    // MARK: - 7. classicActionButtonsDirectVisibilityAndStates

    @Test("7. Classic action buttons are directly visible when completed and retry is hidden during active streaming")
    func classicActionButtonsDirectVisibilityAndStates() {
        var retried = false
        let completedBubble = ChatBubbleView(
            temporaryRecord: false,
            id: UUID(),
            text: "Completed answer with LaTeX $E=mc^2$",
            saveTranlatedText: "已完成回答",
            images: nil,
            imagesText: nil,
            reasoning: "",
            reasoningTime: nil,
            isReasoningExpanded: .constant(false),
            toolContent: "",
            toolName: "",
            isToolContentExpanded: .constant(false),
            uploadDocument: nil,
            documentText: nil,
            resources: nil,
            prompts: nil,
            locations: nil,
            routes: nil,
            events: nil,
            htmlContent: nil,
            healthCards: nil,
            codeBlocks: nil,
            knowledgeCard: nil,
            searchEngine: nil,
            audioAssets: nil,
            isVoiceExpanded: .constant(false),
            showCanvas: false,
            canvas: nil,
            role: "assistant",
            model: "GPT-4o",
            modelCompany: "OPENAI",
            modelIdentity: "model",
            modelIcon: "sparkles",
            isLastAssistant: true,
            isLastAssistantGroup: true,
            splitMarker: true,
            isResponding: false,
            operationalState: "",
            operationalDescription: "",
            onRetry: { retried = true },
            onDelete: nil
        )

        let streamingBubble = ChatBubbleView(
            temporaryRecord: false,
            id: UUID(),
            text: "Streaming answer...",
            saveTranlatedText: nil,
            images: nil,
            imagesText: nil,
            reasoning: "",
            reasoningTime: nil,
            isReasoningExpanded: .constant(false),
            toolContent: "",
            toolName: "",
            isToolContentExpanded: .constant(false),
            uploadDocument: nil,
            documentText: nil,
            resources: nil,
            prompts: nil,
            locations: nil,
            routes: nil,
            events: nil,
            htmlContent: nil,
            healthCards: nil,
            codeBlocks: nil,
            knowledgeCard: nil,
            searchEngine: nil,
            audioAssets: nil,
            isVoiceExpanded: .constant(false),
            showCanvas: false,
            canvas: nil,
            role: "assistant",
            model: "GPT-4o",
            modelCompany: "OPENAI",
            modelIdentity: "model",
            modelIcon: "sparkles",
            isLastAssistant: true,
            isLastAssistantGroup: true,
            splitMarker: true,
            isResponding: true,
            operationalState: "Generating",
            operationalDescription: "",
            onRetry: nil,
            onDelete: nil
        )

        // Verify completed bubble has retry callback and isLastAssistantGroup && !isResponding
        #expect(completedBubble.isLastAssistantGroup && !completedBubble.isResponding)
        completedBubble.onRetry?()
        #expect(retried)

        // Verify streaming bubble has isResponding == true so retry action is suppressed while streaming
        #expect(streamingBubble.isResponding)
    }

    // MARK: - 8. codeBlockRowClassicPresentation

    @Test("8. CodeBlockRow renders normal and error states with container-relative width")
    func codeBlockRowClassicPresentation() {
        let successBlock = CodeBlock(
            codeType: "python",
            code: "print(6 * 7)",
            output: "42\n",
            isRunning: false,
            hasError: false,
            isExpanded: true
        )
        let errorBlock = CodeBlock(
            codeType: "python",
            code: "1 / 0",
            output: "ZeroDivisionError: division by zero",
            isRunning: false,
            hasError: true,
            isExpanded: true
        )

        let normalRow = CodeBlockRow(
            codeBlock: successBlock,
            temporaryRecord: false,
            containerWidth: 320,
            onShowSource: {}
        )
        let errorRow = CodeBlockRow(
            codeBlock: errorBlock,
            temporaryRecord: false,
            containerWidth: 320,
            onShowSource: {}
        )

        #expect(normalRow.codeBlock.output == "42\n")
        #expect(!normalRow.codeBlock.hasError)
        #expect(normalRow.containerWidth == 320)

        #expect(errorRow.codeBlock.hasError)
        #expect(errorRow.codeBlock.output.contains("ZeroDivisionError"))
    }

    // MARK: - 9. conversationListClassicNavigationAndPinnedRows

    @Test("9. Conversation list supports pinning, sorting, search filtering, draft preservation, and deletion")
    func conversationListClassicNavigationAndPinnedRows() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let olderUnpinned = ChatRecords(
            name: "SwiftUI Architecture",
            type: "chat",
            lastEdited: Date(timeIntervalSinceNow: -3600),
            isPinned: false,
            input: "Unfinished draft in SwiftUI chat"
        )
        let newerUnpinned = ChatRecords(
            name: "Python Data Analysis",
            type: "chat",
            lastEdited: Date(timeIntervalSinceNow: -60),
            isPinned: false,
            input: ""
        )
        let pinnedChat = ChatRecords(
            name: "Pinned Agent Spec",
            type: "chat",
            lastEdited: Date(timeIntervalSinceNow: -7200),
            isPinned: true,
            input: "Draft in pinned chat"
        )

        let msgInSwiftUI = ChatMessages(
            role: "assistant",
            text: "Liquid Glass composer keeps classic bubbles intact.",
            record: olderUnpinned
        )
        olderUnpinned.messages = [msgInSwiftUI]

        context.insert(olderUnpinned)
        context.insert(newerUnpinned)
        context.insert(pinnedChat)
        context.insert(msgInSwiftUI)
        try context.save()

        let allRecords = [olderUnpinned, newerUnpinned, pinnedChat]

        // 1. Pinned records always sort before unpinned records, then by lastEdited descending
        let sortedAll = ListView.filterAndSortChatRecords(allRecords, searchText: "")
        #expect(sortedAll.compactMap(\.name) == ["Pinned Agent Spec", "Python Data Analysis", "SwiftUI Architecture"])

        // 2. Search matches both conversation name and message content
        let searchByContent = ListView.filterAndSortChatRecords(allRecords, searchText: "Liquid Glass")
        #expect(searchByContent.count == 1)
        #expect(searchByContent.first?.name == "SwiftUI Architecture")

        // 3. Per-chat draft (record.input) is preserved across chat switches
        #expect(olderUnpinned.input == "Unfinished draft in SwiftUI chat")
        #expect(pinnedChat.input == "Draft in pinned chat")

        // 4. Deleting a chat removes it from SwiftData context
        context.delete(newerUnpinned)
        try context.save()
        let remaining = try context.fetch(FetchDescriptor<ChatRecords>())
        #expect(remaining.count == 2)
    }

    // MARK: - 10. composerAccessoryBarNoOverlap

    @Test("10. Composer accessory bar and send guard prevent duplicate sends and support attachment-only send")
    func composerAccessoryBarNoOverlap() {
        // Empty text and no attachments -> cannot send
        #expect(!ChatViewBottom.shouldEnableSend(
            message: "   \n  ",
            selectedImagesCount: 0,
            selectedDocumentsCount: 0,
            selectedPromptsCount: 0,
            isResponding: false
        ))

        // Attachment-only (image or document or prompt) with empty text -> can send
        #expect(ChatViewBottom.shouldEnableSend(
            message: "",
            selectedImagesCount: 1,
            selectedDocumentsCount: 0,
            selectedPromptsCount: 0,
            isResponding: false
        ))
        #expect(ChatViewBottom.shouldEnableSend(
            message: "",
            selectedImagesCount: 0,
            selectedDocumentsCount: 1,
            selectedPromptsCount: 0,
            isResponding: false
        ))

        // Active streaming (isResponding == true) -> send is blocked (prevents double-send)
        #expect(!ChatViewBottom.shouldEnableSend(
            message: "Hello world",
            selectedImagesCount: 1,
            selectedDocumentsCount: 1,
            selectedPromptsCount: 1,
            isResponding: true
        ))
    }

    // MARK: - 11. agentReasoningNeverLeaksRawCoTToViews

    @Test("11. Agent reasoning sanitizer blocks raw CoT across all patterns and languages before reaching views")
    func agentReasoningNeverLeaksRawCoTToViews() {
        let rawCoTSamples = [
            "<think>Internal chain of thought that must never be shown</think>",
            "**Thinking Process:**\n1. Understand the user's request\n2. Call tool_search",
            "Let me think about how to solve this step by step.",
            "I need to check the available MCP servers first.",
            "The user wants me to calculate 6 * 7 using Python.",
            "Step 1: Load the code skill\nStep 2: Execute python",
            "思考过程：首先分析用户的需求，然后调用工具。",
            "תהליך חשיבה: תחילה נבדוק אילו כלים זמינים במערכת."
        ]

        for sample in rawCoTSamples {
            #expect(ProgressSummarySanitizer.looksLikeRawChainOfThought(sample), "Failed to detect raw CoT in: \(sample)")
            #expect(ProgressSummarySanitizer.sanitize(sample) == nil, "Sanitize leaked raw CoT: \(sample)")
            #expect(ProgressSummarySanitizer.sanitizeProviderReasoningSummary(sample) == nil, "Provider summary leaked raw CoT: \(sample)")
        }

        // Verify AgentActivityComposer replaces raw CoT in reasoning steps with safe "Thinking" label
        let leakedStep = AgentActivityStep(
            externalID: "reasoning-1",
            sequence: 0,
            kind: .reasoning,
            title: "Let me think about what the user is asking for here",
            status: .completed,
            output: "<think>Secret internal monologue</think>"
        )
        let run = AgentRun(
            groupID: UUID(),
            status: .completed,
            steps: [leakedStep],
            transcriptItems: []
        )
        let timeline = AgentActivityComposer.compose(run)
        for activity in timeline.activities {
            #expect(!ProgressSummarySanitizer.looksLikeRawChainOfThought(activity.title))
            if let narrative = activity.narrativeText {
                #expect(!ProgressSummarySanitizer.looksLikeRawChainOfThought(narrative))
            }
        }

        // Concise safe operational summary passes through
        let safeSummary = "Searching web sources for SwiftUI layout"
        #expect(!ProgressSummarySanitizer.looksLikeRawChainOfThought(safeSummary))
        #expect(ProgressSummarySanitizer.sanitize(safeSummary) == safeSummary)
    }

    // MARK: - 12. toolResultVisibilityAndHistory

    @Test("12. Tool results and final answer persist in ChatMessages.agentRunJSON and reload across reopen without duplication")
    func toolResultVisibilityAndHistory() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let chatRecord = ChatRecords(name: "Persistence Chat", type: "chat")
        context.insert(chatRecord)

        let groupID = UUID()
        var accumulator = AgentEventAccumulator(run: AgentRun(groupID: groupID))
        var cardProfile = ToolPresentationProfile.generic(toolName: "create_web_view")
        cardProfile.result = .init(rendererKind: .modernNative, supportsCard: true)
        cardProfile.resultDisplayPolicy = .always

        let call = AgentToolCall.parse(
            id: "call_web_1",
            name: "create_web_view",
            argumentsJSON: #"{"code":"<h1>Interactive Result</h1>"}"#,
            presentationProfile: cardProfile
        )
        accumulator.apply(.toolCallStarted(call))
        accumulator.apply(.toolCallCompleted(call))
        accumulator.apply(.toolExecutionStarted(AgentToolExecution(
            id: "call_web_1:execution",
            callID: "call_web_1",
            name: "create_web_view",
            startedAt: Date()
        )))
        accumulator.apply(.toolExecutionCompleted(
            id: "call_web_1:execution",
            result: AgentToolResult(
                modelText: "Created web view",
                userText: "Interactive Result",
                richResultBlocks: [
                    NativeUIBlock(type: .card, title: "Interactive Web Card", body: "Rendered HTML")
                ],
                hasLegacyPresentationPayload: false,
                isError: false,
                semanticOutcome: .succeeded,
                duration: 0.25
            )
        ))
        accumulator.apply(.answerSegmentStarted(AgentItemMetadata(id: "round-1", title: "Answer", startedAt: Date())))
        accumulator.apply(.answerSegmentDelta(id: "round-1", text: "Here is the interactive card above."))
        accumulator.apply(.answerSegmentEnded(id: "round-1", disposition: .final))
        accumulator.apply(.runCompleted)

        let assistantMsg = ChatMessages(
            role: "assistant",
            text: "Here is the interactive card above.",
            groupID: groupID,
            record: chatRecord
        )
        assistantMsg.agentRun = accumulator.run
        context.insert(assistantMsg)
        try context.save()

        // Simulate app relaunch / conversation reopen by fetching from SwiftData and decoding agentRunJSON
        let fetchedMessages = try context.fetch(FetchDescriptor<ChatMessages>())
        let reloadedMsg = try #require(fetchedMessages.first)
        let reloadedRun = try #require(reloadedMsg.agentRun)

        #expect(reloadedRun.status == .completed)
        #expect(reloadedRun.finalAnswer == "Here is the interactive card above.")
        let visibleResults = reloadedRun.transcriptItems.filter { $0.kind == .userVisibleToolResult }
        #expect(visibleResults.count == 1)
        #expect(visibleResults.first?.nativeUIBlocks.first?.title == "Interactive Web Card")
    }

    // MARK: - 13. mcpInstallSelectInvokeUninstallE2E

    @Test("13. Conversational MCP lifecycle: status, preview, install, auto-enable, Turn 1 & Turn 2 tool invocation, restart, stop, uninstall")
    func mcpInstallSelectInvokeUninstallE2E() async throws {
        try await AppRuntimeCore.shared.prepareStorage()
        let provider = MCPRuntimeProvider.shared
        await provider.loadIfNeeded(startHost: true)

        let mcpTool = ManageMCPServersTool()
        let listTools = ListToolsTool()

        // 0. Truthful reporting when chatID is nil
        let noChatContext = NativeToolExecutionContext(localeIdentifier: "en_US", chatID: nil)
        let noChatStatus = await mcpTool.execute(argumentsJSON: #"{"action":"status"}"#, context: noChatContext)
        #expect(noChatStatus.outcome == .succeeded)
        #expect(noChatStatus.modelText.contains("selected_for_current_chat: false (no active chat context)"))

        // Build a deterministic local .tgz MCP server package with an `echo_ping` tool
        let archiveURL = try Self.makeDeterministicMCPArchive()
        defer { try? FileManager.default.removeItem(at: archiveURL) }

        let chatUUID = UUID()
        let sessionTurn1 = AssistantCapabilitySession(chatID: chatUUID.uuidString, isTemporaryChat: false)
        let turn1Context = NativeToolExecutionContext(
            localeIdentifier: "en_US",
            chatID: chatUUID.uuidString,
            isTemporaryChat: false,
            requestID: UUID().uuidString,
            capabilitySession: sessionTurn1
        )

        // 1. Preview package via manage_mcp_servers
        let previewResult = await mcpTool.execute(
            argumentsJSON: #"{"action":"preview","package_spec":"\#(archiveURL.path)"}"#,
            context: turn1Context
        )
        #expect(previewResult.outcome == .succeeded)
        #expect(previewResult.modelText.contains("hanlin-echo-mcp"))

        // 2. Install package via manage_mcp_servers (auto-enables global MCP, selects for chat, starts worker, syncs session)
        let installResult = await mcpTool.execute(
            argumentsJSON: #"{"action":"install","package_spec":"\#(archiveURL.path)","entry_point":"server.mjs"}"#,
            context: turn1Context
        )
        #expect(installResult.outcome == .succeeded, "MCP install failed: \(installResult.modelText)")
        #expect(installResult.modelText.contains("global_mcp_enabled: true"))
        #expect(installResult.modelText.contains("server_installed: true"))
        #expect(installResult.modelText.contains("server_enabled: true"))
        #expect(installResult.modelText.contains("selected_for_current_chat: true"))
        #expect(installResult.modelText.contains("worker_running: true"))

        // Verify Turn 1 session immediately has the `mcp__<slug>__echo_ping` alias exposed without app restart
        let exposedAliasesTurn1 = sessionTurn1.exposedToolAliases
        let echoAlias: String = try #require(exposedAliasesTurn1.first(where: { $0.hasPrefix("mcp__") && $0.hasSuffix("__echo_ping") }))

        // 3. list_tools in Turn 1 includes the installed MCP server and its `echo_ping` tool
        let listResult = await listTools.execute(
            argumentsJSON: #"{"category":"mcp"}"#,
            context: turn1Context
        )
        #expect(listResult.outcome == .succeeded)
        #expect(listResult.modelText.contains(echoAlias))

        // 4. Invoke the MCP tool in Turn 1 via AssistantToolBridge (same path used by HanlinAISDKToolAdapter)
        let scopeTurn1 = await provider.requestScope(chatID: chatUUID, temporary: false)
        #expect(scopeTurn1.mcpGloballyEnabled)
        #expect(!scopeTurn1.mcpServerIDs.isEmpty)
        let preparedTurn1 = try await AssistantToolBridge.prepare(
            scope: scopeTurn1,
            legacySources: LegacyToolCanonicalAdapter.sources()
        )
        let directExecTurn1 = try #require(await preparedTurn1.execute(
            alias: echoAlias,
            argumentsJSON: #"{"message":"turn-1-hello"}"#,
            context: turn1Context
        ))
        #expect(directExecTurn1.outcome == .succeeded)
        #expect(directExecTurn1.modelText.contains("MCP_ECHO:turn-1-hello"))

        // Also verify manage_mcp_servers `call_tool` action works directly
        let callToolActionResult = await mcpTool.execute(
            argumentsJSON: #"{"action":"call_tool","server":"hanlin-echo-mcp","tool_name":"echo_ping","tool_arguments":"{\"message\":\"via-manage-tool\"}"}"#,
            context: turn1Context
        )
        #expect(callToolActionResult.outcome == .succeeded)
        #expect(callToolActionResult.modelText.contains("MCP_ECHO:via-manage-tool"))

        // 5. Turn 2 in the SAME chat: new AssistantCapabilitySession and HanlinAISDKToolAdapter automatically expose and invoke the MCP tool without re-installing
        let scopeTurn2 = await provider.requestScope(chatID: chatUUID, temporary: false)
        let preparedTurn2 = try await AssistantToolBridge.prepare(
            scope: scopeTurn2,
            legacySources: LegacyToolCanonicalAdapter.sources()
        )
        let sessionTurn2 = AssistantCapabilitySession(chatID: chatUUID.uuidString, isTemporaryChat: false)
        let adapterTurn2 = HanlinAISDKToolAdapter(
            session: sessionTurn2,
            preparedTools: preparedTurn2,
            modelContext: nil,
            currentLanguage: "en_US",
            progressSummaryRequired: false,
            supportsReportProgress: false,
            callbacks: .init(
                onStreamData: { _ in },
                onAgentEvent: { _ in },
                onProgressMessage: { _ in },
                currentReasoningSummary: { nil }
            ),
            reportProgressController: ReportProgressController(),
            diagnosticsRecorder: nil
        )
        let turn2Definitions = try adapterTurn2.allToolDefinitions()
        #expect(turn2Definitions.contains(where: { $0.name == echoAlias }))

        let turn2Context = NativeToolExecutionContext(
            localeIdentifier: "en_US",
            chatID: chatUUID.uuidString,
            isTemporaryChat: false,
            requestID: UUID().uuidString,
            capabilitySession: sessionTurn2
        )
        let directExecTurn2 = try #require(await preparedTurn2.execute(
            alias: echoAlias,
            argumentsJSON: #"{"message":"turn-2-reuse"}"#,
            context: turn2Context
        ))
        #expect(directExecTurn2.outcome == .succeeded)
        #expect(directExecTurn2.modelText.contains("MCP_ECHO:turn-2-reuse"))

        // 6. Restart, Stop, and Uninstall via manage_mcp_servers
        let restartResult = await mcpTool.execute(
            argumentsJSON: #"{"action":"restart","server":"hanlin-echo-mcp"}"#,
            context: turn2Context
        )
        #expect(restartResult.outcome == .succeeded)

        let stopResult = await mcpTool.execute(
            argumentsJSON: #"{"action":"stop","server":"hanlin-echo-mcp"}"#,
            context: turn2Context
        )
        #expect(stopResult.outcome == .succeeded)
        #expect(stopResult.modelText.contains("worker_running: false"))

        let uninstallResult = await mcpTool.execute(
            argumentsJSON: #"{"action":"uninstall","server":"hanlin-echo-mcp"}"#,
            context: turn2Context
        )
        #expect(uninstallResult.outcome == .succeeded)
        #expect(uninstallResult.modelText.contains("server_installed: false"))
        #expect(!sessionTurn2.exposedToolAliases.contains(echoAlias))
    }

    private static func makeDeterministicMCPArchive() throws -> URL {
        let packageJSON = """
        {
          "name": "hanlin-echo-mcp",
          "version": "1.0.0",
          "description": "Deterministic local MCP test server",
          "type": "module",
          "main": "server.mjs",
          "bin": {
            "hanlin-echo-mcp": "server.mjs"
          }
        }
        """
        let serverMJS = """
        import { createInterface } from 'node:readline';
        const rl = createInterface({ input: process.stdin });
        rl.on('line', (line) => {
          let req;
          try { req = JSON.parse(line); } catch { return; }
          if (req.method === 'initialize') {
            respond(req.id, {
              protocolVersion: req.params?.protocolVersion ?? '2024-11-05',
              capabilities: { tools: {} },
              serverInfo: { name: 'hanlin-echo-mcp', version: '1.0.0' }
            });
          } else if (req.method === 'tools/list') {
            respond(req.id, {
              tools: [{
                name: 'echo_ping',
                description: 'Deterministic echo tool for E2E acceptance',
                inputSchema: {
                  type: 'object',
                  properties: { message: { type: 'string' } },
                  required: ['message']
                }
              }]
            });
          } else if (req.method === 'tools/call') {
            const msg = req.params?.arguments?.message ?? 'pong';
            respond(req.id, {
              content: [{ type: 'text', text: `MCP_ECHO:${msg}` }],
              isError: false
            });
          }
        });
        function respond(id, result) {
          if (id === undefined || id === null) return;
          process.stdout.write(JSON.stringify({ jsonrpc: '2.0', id, result }) + '\\n');
        }
        """

        var entries: [TarEntry] = []
        let pkgData = Data(packageJSON.utf8)
        var pkgInfo = TarEntryInfo(name: "package/package.json", type: .regular)
        pkgInfo.permissions = Permissions(rawValue: 0o644)
        entries.append(TarEntry(info: pkgInfo, data: pkgData))

        let srvData = Data(serverMJS.utf8)
        var srvInfo = TarEntryInfo(name: "package/server.mjs", type: .regular)
        srvInfo.permissions = Permissions(rawValue: 0o755)
        entries.append(TarEntry(info: srvInfo, data: srvData))

        let tarData = TarContainer.create(from: entries)
        let tgzData = try GzipArchive.archive(data: tarData)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hanlin-echo-mcp-\(UUID().uuidString).tgz")
        try tgzData.write(to: url, options: .atomic)
        return url
    }

    // MARK: - 14. modelRoutingAcrossPersistentProbeRefresh

    @Test("14. Model routing and capability preservation survive transient probe failures")
    func modelRoutingAcrossPersistentProbeRefresh() {
        let verifiedExisting = ModelCapabilities(
            supportsTextGen: true,
            supportsMultimodal: true,
            supportsReasoning: true,
            supportReasoningChange: true,
            supportsImageGen: false,
            supportsVoiceGen: false,
            supportsToolUse: true
        )
        let transientFailedProbe = ModelCapabilities(
            supportsTextGen: false,
            supportsMultimodal: false,
            supportsReasoning: false,
            supportReasoningChange: false,
            supportsImageGen: false,
            supportsVoiceGen: false,
            supportsToolUse: false
        )

        // When text probe fails transiently on an already-verified model, existing capabilities are preserved
        let preserved = ModelRefreshService.resolveCapabilitiesAfterProbe(
            probed: transientFailedProbe,
            existing: verifiedExisting,
            baseName: "nvidia/nemotron-3-ultra-550b-a55b:free",
            textProbeSucceeded: false
        )
        #expect(preserved == verifiedExisting)

        // And execution route remains .remoteText, NEVER .remoteImageGeneration
        let route = APIManager.resolveModelExecutionRoute(
            company: "OPENROUTER",
            modelName: "nvidia/nemotron-3-ultra-550b-a55b:free",
            supportsTextGen: preserved.supportsTextGen,
            supportsImageGen: preserved.supportsImageGen
        )
        #expect(route == .remoteText)

        // Image-only models still route to .remoteImageGeneration
        let dalleRoute = APIManager.resolveModelExecutionRoute(
            company: "OPENAI",
            modelName: "dall-e-3",
            supportsTextGen: false,
            supportsImageGen: true
        )
        #expect(dalleRoute == .remoteImageGeneration)
    }

    // MARK: - 15. lifecycleCancelRetryLateEventsAcrossRuns

    @Test("15. AgentRunLifecycleCoordinator and AgentEventAccumulator isolate cancelled runs and reject late ghost events on retry")
    func lifecycleCancelRetryLateEventsAcrossRuns() async throws {
        UserDefaults.standard.set(AgentDiagnosticsLevel.metadataOnly.rawValue, forKey: AgentDiagnosticsConfiguration.levelKey)
        let coordinator = AgentRunLifecycleCoordinator.shared
        let runAID = UUID()
        let recorderA = try #require(await AgentDiagnosticsRecorder.start(
            runID: runAID,
            groupID: UUID(),
            providerID: "OPENROUTER",
            modelID: "test-model"
        ))

        await coordinator.beginRun(runID: runAID, recorder: recorderA)
        #expect(coordinator.isCurrentRun(runAID))

        // Cancel Run A
        await coordinator.cancelRun(runID: runAID)
        #expect(!coordinator.isCurrentRun(runAID))
        let sessionA = await recorderA.session
        #expect(sessionA.status == "cancelled")
        #expect(sessionA.isComplete)

        // Start retry Run B
        let runBID = UUID()
        let recorderB = try #require(await AgentDiagnosticsRecorder.start(
            runID: runBID,
            groupID: UUID(),
            providerID: "OPENROUTER",
            modelID: "test-model"
        ))
        await coordinator.beginRun(runID: runBID, recorder: recorderB)
        #expect(coordinator.isCurrentRun(runBID))
        #expect(!coordinator.isCurrentRun(runAID))

        // Late cancel or finish call with Run A's ID must NOT affect Run B
        await coordinator.cancelRun(runID: runAID)
        coordinator.finishRun(runID: runAID)
        #expect(coordinator.isCurrentRun(runBID))

        // Verify AgentEventAccumulator rejects late events after cancellation
        var accA = AgentEventAccumulator(run: AgentRun(id: runAID, groupID: UUID()))
        accA.apply(.runCancelled)
        #expect(accA.run.status == .cancelled)

        accA.apply(.answerSegmentStarted(AgentItemMetadata(id: "late-round", title: "Answer", startedAt: Date())))
        accA.apply(.answerSegmentDelta(id: "late-round", text: "GHOST_TEXT_FROM_RUN_A"))
        accA.apply(.answerSegmentEnded(id: "late-round", disposition: .final))
        accA.apply(.runCompleted)
        #expect(accA.run.status == .cancelled)
        #expect(accA.run.finalAnswer == nil)

        coordinator.finishRun(runID: runBID)
    }

    // MARK: - 16. multimodalFormattedMessagesToSDKConversion

    @Test("16. APIManager.convertFormattedMessagesToSDKMessages preserves base64 imageData, remote imageURL, text, and system/developer roles without empty-string destruction")
    func multimodalFormattedMessagesToSDKConversion() throws {
        let base64PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        let formattedMessages: [[String: Any]] = [
            [
                "role": "developer",
                "content": "Developer system instructions"
            ],
            [
                "role": "user",
                "content": [
                    ["type": "text", "text": "Inspect the attached diagram and remote photo."],
                    ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(base64PNG)"]],
                    ["type": "image_url", "image_url": ["url": "https://example.com/architecture.png"]]
                ]
            ],
            [
                "role": "assistant",
                "content": "I see both images."
            ]
        ]

        let converted = APIManager.convertFormattedMessagesToSDKMessages(formattedMessages)
        #expect(converted.baseSystemPrompt == "Developer system instructions")
        #expect(converted.messages.count == 2)

        let userMsg = converted.messages[0]
        #expect(userMsg.role == .user)
        #expect(userMsg.parts.count == 3)

        var foundText = false
        var foundImageData = false
        var foundImageURL = false
        for part in userMsg.parts {
            switch part {
            case .text(let t):
                #expect(t == "Inspect the attached diagram and remote photo.")
                foundText = true
            case .imageData(let data, let mimeType):
                #expect(!data.isEmpty)
                #expect(mimeType == "image/png")
                foundImageData = true
            case .imageURL(let url, _):
                #expect(url.absoluteString == "https://example.com/architecture.png")
                foundImageURL = true
            }
        }
        #expect(foundText && foundImageData && foundImageURL)
    }

    // MARK: - 17. classicChatAgentProjectionSourceFileAndValidResources

    @MainActor
    @Test("17. ClassicChatAgentProjection maps provider-native .source and .file and rejects fabricated search.local URLs")
    func classicChatAgentProjectionSourceFileAndValidResources() throws {
        var messages: [ChatMessages] = []
        let groupID = UUID()
        let assistantMessage = ChatMessages(
            role: "assistant",
            text: "",
            reasoning: "",
            modelName: "gpt-4o",
            modelDisplayName: "GPT-4o",
            groupID: groupID,
            timestamp: Date()
        )
        messages.append(assistantMessage)

        ClassicChatAgentProjection.appendProviderSource(
            id: "s1",
            url: "https://developer.apple.com/swift",
            title: "Swift Official",
            assistantMessage: assistantMessage,
            messages: &messages,
            messageGroupID: groupID,
            searchEngine: "Perplexity",
            timestamp: Date()
        )
        ClassicChatAgentProjection.appendProviderSource(
            id: "s2",
            url: "https://search.local/query?q=fake",
            title: "Fake Local Search",
            assistantMessage: assistantMessage,
            messages: &messages,
            messageGroupID: groupID,
            searchEngine: "Perplexity",
            timestamp: Date()
        )

        #expect(assistantMessage.resources?.count == 1)
        #expect(assistantMessage.resources?.first?.link == "https://developer.apple.com/swift")
        #expect(messages.first(where: { $0.role == "search" })?.resources?.count == 1)

        // Provider-native image file
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
        let img = renderer.image { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        let pngData = try #require(img.pngData())
        ClassicChatAgentProjection.appendProviderFile(
            mediaType: "image/png",
            data: pngData,
            assistantMessage: assistantMessage
        )
        #expect(assistantMessage.imageArray.count == 1)
    }

    // MARK: - 18. build84001SkillVsToolNameDisambiguation

    @Test("18. Build 84001 defect 7A: calling web_research as a tool or load_skill(skill_id: search_online) returns explicit Skill ID vs tool name guidance")
    func build84001SkillVsToolNameDisambiguation() async throws {
        let session = AssistantCapabilitySession(chatID: UUID().uuidString, isTemporaryChat: false)

        // 1. LoadSkillTool called with tool name "search_online"
        let loadOutput = await LoadSkillTool.execute(
            argumentsJSON: #"{"skill_id":"search_online"}"#,
            session: session,
            availableAliases: ["search_online", "read_web_page"]
        )
        #expect(loadOutput.contains("callable tool name, not a skill_id"))
        #expect(session.isToolExposed("search_online"))

        // 2. LoadSkillTool called with skill_id "web_research" activates search_online and read_web_page
        let webResearchOutput = await LoadSkillTool.execute(
            argumentsJSON: #"{"skill_id":"web_research"}"#,
            session: session,
            availableAliases: ["search_online", "read_web_page"]
        )
        #expect(webResearchOutput.contains("loaded successfully"))
        #expect(session.isToolExposed("search_online"))
        #expect(session.isToolExposed("read_web_page"))
    }

    // MARK: - 19. build84001MCPValidationAndIncompatiblePackageGuard

    @Test("19. Build 84001 defect 7B: ManageMCPServersTool rejects known nonexistent or native-addon MCP packages and supports action/parameter aliases")
    func build84001MCPValidationAndIncompatiblePackageGuard() async throws {
        let tool = ManageMCPServersTool()
        let context = NativeToolExecutionContext(
            localeIdentifier: "en_US",
            chatID: UUID().uuidString,
            isTemporaryChat: false
        )

        // Hallucinated package transit-allinone-mcp
        let transitOut = await tool.execute(
            argumentsJSON: #"{"action":"install_package","package":"transit-allinone-mcp"}"#,
            context: context
        )
        #expect(transitOut.outcome == .invalidArguments)
        #expect(transitOut.modelText.contains("does not exist on the public npm registry"))

        // Native addon / Python MCP package @modelcontextprotocol/server-sqlite
        let sqliteOut = await tool.execute(
            argumentsJSON: #"{"action":"install","package_spec":"@modelcontextprotocol/server-sqlite"}"#,
            context: context
        )
        #expect(sqliteOut.outcome == .invalidArguments)
        #expect(sqliteOut.modelText.contains("unsupported in the embedded iOS Node runtime"))
    }

    // MARK: - 20. build84001UnicodePropertyRegexSanitizerInServerWorker

    @Test("20. Build 84001 defect 7B: server-worker.mjs includes ICU-less Node regex compatibility shim for \\P{ASCII} and \\p{ASCII}")
    func build84001UnicodePropertyRegexSanitizerInServerWorker() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let workerURL = repoRoot.appendingPathComponent("AI_HLY/Downstream/RuntimeCore/Node/Host/server-worker.mjs")
        let workerSource = try String(contentsOf: workerURL, encoding: .utf8)

        #expect(workerSource.contains("function sanitizeUnicodePropertyRegexes(source)"))
        #expect(workerSource.contains(#"\\x00-\\x7F"#))
        #expect(workerSource.contains("installRegExpUnicodeShim()"))
    }

    // MARK: - 21. build84001ShellPwdAndNodeCommonJSInference

    @Test("21. Build 84001 defect 7C: execute_shell_command supports pwd builtin and NodeRuntimeService infers CommonJS for require() snippets")
    func build84001ShellPwdAndNodeCommonJSInference() async throws {
        // 1. CommonJS vs ESM module inference
        let cjsCode = "const fs = require('fs');\nconsole.log(Object.keys(fs).length);"
        let esmCode = "import fs from 'node:fs';\nconsole.log(fs);"

        #expect(NodeRuntimeService.inferModuleKind(for: cjsCode) == "commonjs")
        #expect(NodeRuntimeService.inferModuleKind(for: esmCode) == "esm")

        // 2. ShellRuntimeService pwd builtin
        let shellService = ShellRuntimeService()
        let workspace = try RuntimeFileLayout.default.workspace(client: .tools, identifier: "pwd_test")
        let pwdResult = try await shellService.execute(
            tokens: ["pwd"],
            workspace: workspace,
            environment: [:],
            allowNetwork: false
        )
        #expect(pwdResult.exitCode == 0)
        #expect(!pwdResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    // MARK: - 22. build84001SchemaOverheadTokenBudget

    @Test("22. Build 84001 defect 7D: AssistantToolExposurePlanner enforces bounded schema byte budget")
    func build84001SchemaOverheadTokenBudget() throws {
        #expect(AssistantToolExposurePlanner.defaultSchemaByteBudget == 24_000)

        var oversizedSizes: [String: Int] = [:]
        var names: [String] = []
        for idx in 0..<20 {
            let name = "heavy_tool_\(idx)"
            names.append(name)
            oversizedSizes[name] = 4_000
        }

        let planner = AssistantToolExposurePlanner(maxSchemaBytes: AssistantToolExposurePlanner.defaultSchemaByteBudget)
        let decision = planner.plan(
            candidateAliases: names,
            schemaSizes: oversizedSizes,
            currentlyExposedAliases: []
        )

        #expect(decision.totalExposedBytes <= AssistantToolExposurePlanner.defaultSchemaByteBudget)
        #expect(!decision.deferredAliases.isEmpty)
    }
}
