import CryptoKit
import SwiftData
import SwiftUI
import Testing
import UIKit
import SwiftStreamingMarkdown
@testable import AI_Hanlin

@MainActor
@Suite("Original chat presentation", .serialized)
struct ChatPresentationTests {
    @Test func parallelCallsWithSameToolAndArgumentsKeepTheirOwnIdentity() {
        let time = Date()
        let steps = [
            AgentActivityStep(externalID: "call:first", sequence: 0, kind: .toolCall, title: "Search", subtitle: "search", startedAt: time, input: "same"),
            AgentActivityStep(externalID: "call:second", sequence: 1, kind: .toolCall, title: "Search", subtitle: "search", startedAt: time, input: "same"),
            AgentActivityStep(externalID: "first:execution", sequence: 2, kind: .toolExecution, title: "Search", subtitle: "search", status: .completed, startedAt: time, input: "same", output: "first result"),
            AgentActivityStep(externalID: "second:execution", sequence: 3, kind: .toolExecution, title: "Search", subtitle: "search", status: .failed, startedAt: time, input: "same", errorDescription: "second failed")
        ]
        let timeline = AgentActivityComposer.compose(AgentRun(groupID: UUID(), steps: steps))
        #expect(timeline.activities.count == 2)
        #expect(Set(timeline.activities.map(\.id)) == ["first", "second"])
        #expect(timeline.activities.first(where: { $0.id == "first" })?.outputPreview == "first result")
        #expect(timeline.activities.first(where: { $0.id == "second" })?.errorDescription == "second failed")
    }

    @Test func actualCodeToolLifecycleKeepsOneRowPerCallAndRetainsItsFailureAfterRunCompletion() throws {
        var accumulator = AgentEventAccumulator(run: AgentRun(groupID: UUID()))
        let profile = ExecuteLocalPythonTool().catalogEntry.presentationProfile
        for (id, failed) in [("provider:execution", true), ("recovery", false)] {
            let call = AgentToolCall.parse(id: id, name: "execute_local_python_code",
                argumentsJSON: #"{"source":"print('same')"}"#, presentationProfile: profile)
            accumulator.apply(.toolCallStarted(call))
            accumulator.apply(.toolCallCompleted(call))
            accumulator.apply(.toolExecutionStarted(AgentToolExecution(id: id + ":execution", callID: id,
                name: call.name, startedAt: .now)))
            accumulator.apply(.toolExecutionCompleted(id: id + ":execution", result: AgentToolResult(
                modelText: failed ? "Invalid arguments: unexpected" : "ui-tool-ok", userText: failed ? "Invalid arguments: unexpected" : "ui-tool-ok",
                richResultBlocks: [], hasLegacyPresentationPayload: false, isError: failed,
                semanticOutcome: failed ? .invalidArguments : .succeeded, duration: 0.01)))
        }
        accumulator.apply(.answerSegmentStarted(AgentItemMetadata(id: "answer", title: "Answer", startedAt: .now)))
        accumulator.apply(.answerSegmentDelta(id: "answer", text: "The first tool failed; recovery succeeded."))
        accumulator.apply(.answerSegmentEnded(id: "answer", disposition: .final))
        accumulator.apply(.runCompleted)
        let run = accumulator.run
        let calls = AgentActivityComposer.compose(run).activities.filter { $0.id == "provider:execution" || $0.id == "recovery" }
        #expect(calls.count == 2)
        #expect(calls.first(where: { $0.id == "provider:execution" })?.status == .failed)
        #expect(calls.first(where: { $0.id == "provider:execution" })?.errorDescription?.contains("unexpected") == true)
        #expect(calls.first(where: { $0.id == "recovery" })?.status == .completed)
        let entries = ClassicChatAgentProjection.projectToolEntries(from: run)
        #expect(entries.count == 2)
        let failure = try #require(entries.first(where: { $0.callID == "provider:execution" }))
        #expect(failure.status == .failed && failure.output.contains("unexpected"))
        #expect(entries.first(where: { $0.callID == "recovery" })?.output == "ui-tool-ok")
    }

    @Test func actualStreamProjectionDoesNotLetEventDedupHideCanonicalOutputOrFreezeItsStatus() throws {
        let runID = UUID()
        let message = ChatMessages(id: UUID(), role: "assistant", text: "")
        var coordinator = AgentEventAccumulator(run: AgentRun(id: runID, groupID: UUID()))
        var projection = ClassicChatAgentProjection(runID: runID)
        let call = AgentToolCall.parse(id: "real-call", name: "execute_local_python_code",
            argumentsJSON: #"{"source":"print(42)"}"#, presentationProfile: ExecuteLocalPythonTool().catalogEntry.presentationProfile)
        let events: [AgentEvent] = [.toolCallStarted(call), .toolCallCompleted(call),
            .toolExecutionStarted(AgentToolExecution(id: "real-call:execution", callID: call.id, name: call.name, startedAt: .now))]
        var state = "", description = ""
        for event in events {
            let data = StreamData(agentEvents: [event])
            for filtered in projection.deduplicateEvents(data.agentEvents) { coordinator.apply(filtered) }
            _ = projection.applyStreamChunk(data, agentRun: coordinator.run, to: message,
                operationalState: &state, operationalDescription: &description)
        }
        #expect(projection.orderedToolEntries.count == 1)
        let terminal = AgentEvent.toolExecutionFailed(id: "real-call:execution", error: AgentSafeError(message: "actual failure"))
        for filtered in projection.deduplicateEvents([terminal]) { coordinator.apply(filtered) }
        _ = projection.applyStreamChunk(StreamData(toolContent: "actual failure", toolName: call.name),
            agentRun: coordinator.run, to: message, operationalState: &state, operationalDescription: &description)
        #expect(projection.orderedToolEntries.count == 1)
        #expect(projection.orderedToolEntries.first?.status == .failed)
        #expect(projection.orderedToolEntries.first?.callID == call.id)
        #expect(message.toolContent?.contains("actual failure") == true)
        var seen = Set<String>()
        var snapshot = coordinator.run
        ClassicChatAgentProjection.syncAgentRunProjection(snapshot, into: message, seenToolCallKeys: &seen)
        snapshot.steps[snapshot.steps.count - 1].errorDescription = "updated failure"
        ClassicChatAgentProjection.syncAgentRunProjection(snapshot, into: message, seenToolCallKeys: &seen)
        #expect(message.toolContent?.contains("updated failure") == true)
    }

    @Test func personalSaveUsesSelectedQuoteWithoutAddingKnowledge() throws {
        let container = try ModelContainer(for: ChatSavedExcerpt.self, KnowledgeRecords.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let context = container.mainContext
        let source = ChatExcerptSource(chatRecordID: UUID(), messageID: UUID(), groupID: UUID(), runID: UUID(), title: "עברית English")
        let body = "Before 👨‍👩‍👧‍👦 שלום עולם after **bold**"
        let saved = try ChatSavedExcerpt.save(source: source, markdown: body, quote: "שלום עולם", in: context)
        #expect(saved.quote == "שלום עולם")
        #expect(saved.sourceMarkdown == body)
        let range = NSRange(location: try #require(saved.utf16Location), length: try #require(saved.utf16Length))
        #expect((body as NSString).substring(with: range) == "שלום עולם")
        #expect(try context.fetchCount(FetchDescriptor<KnowledgeRecords>()) == 0)
        let duplicate = try ChatSavedExcerpt.save(source: source, markdown: body, quote: "שלום עולם", in: context)
        #expect(duplicate.id == saved.id)
        #expect(try context.fetchCount(FetchDescriptor<ChatSavedExcerpt>()) == 1)
    }

    @Test func ambiguousOrFormattedQuotesNeverInventOffsets() {
        let source = ChatExcerptSource(chatRecordID: UUID(), messageID: UUID(), groupID: nil, runID: nil, title: "Source")
        let repeated = ChatSavedExcerpt(source: source, markdown: "hello hello", quote: "hello")
        #expect(repeated.utf16Location == nil)
        let formatted = ChatSavedExcerpt(source: source, markdown: "**hello** world", quote: "hello world")
        #expect(formatted.quote == "hello world")
        #expect(formatted.utf16Location == nil)
    }

    @Test func savedSnapshotSurvivesStoreReopenAndSourceDeletion() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "saved.store")
        let source = ChatExcerptSource(chatRecordID: UUID(), messageID: UUID(), groupID: UUID(), runID: nil, title: "Deleted source")
        let snapshot = "# שלום\n\n$E=mc^2$ 👋🏽"
        do {
            let container = try ModelContainer(for: ChatSavedExcerpt.self, configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
            try ChatSavedExcerpt.save(source: source, markdown: snapshot, quote: snapshot, in: container.mainContext)
        }
        let reopened = try ModelContainer(for: ChatSavedExcerpt.self, configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        let saved = try #require(reopened.mainContext.fetch(FetchDescriptor<ChatSavedExcerpt>()).first)
        #expect(saved.quote == snapshot)
        #expect(saved.sourceDigest == ChatSavedExcerpt.digest(snapshot))
        #expect(saved.messageID == source.messageID)
        // No relationship/cascade requires the deleted original record to exist.
        reopened.mainContext.delete(saved)
        try reopened.mainContext.save()
        #expect(try reopened.mainContext.fetchCount(FetchDescriptor<ChatSavedExcerpt>()) == 0)
    }

    @Test func addingSavedExcerptsMigratesTheExistingApplicationSchemaWithoutDeletingChat() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "original.store")
        let chatID = UUID()
        let messageID = UUID()
        let legacyTypes: [any PersistentModel.Type] = [ChatMessages.self, APIKeys.self, SearchKeys.self,
            AllModels.self, ChatRecords.self, UserInfo.self, PromptRepo.self, KnowledgeRecords.self,
            KnowledgeChunk.self, MemoryArchive.self, TranslationDic.self, ToolKeys.self]
        do {
            let legacy = try ModelContainer(for: Schema(legacyTypes),
                configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
            let record = ChatRecords(id: chatID, name: "Existing conversation", type: "chat")
            let message = ChatMessages(id: messageID, role: "assistant", text: "Preserved שלום 👋🏽")
            record.messages = [message]
            legacy.mainContext.insert(record)
            try legacy.mainContext.save()
        }
        let migrated = try ModelContainer(for: Schema(legacyTypes + [ChatSavedExcerpt.self]),
            configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        let chats = try migrated.mainContext.fetch(FetchDescriptor<ChatRecords>())
        let record = try #require(chats.first(where: { $0.id == chatID }))
        let message = try #require(record.messages?.first(where: { $0.id == messageID }))
        #expect(message.text == "Preserved שלום 👋🏽")
        let source = ChatExcerptSource(chatRecordID: chatID, messageID: messageID, groupID: nil, runID: nil, title: record.name ?? "")
        try ChatSavedExcerpt.save(source: source, markdown: message.text ?? "", quote: "שלום 👋🏽", in: migrated.mainContext)
        #expect(try migrated.mainContext.fetchCount(FetchDescriptor<ChatSavedExcerpt>()) == 1)
        #expect(try migrated.mainContext.fetchCount(FetchDescriptor<ChatMessages>()) == 1)
        #expect(try migrated.mainContext.fetchCount(FetchDescriptor<KnowledgeRecords>()) == 0)
    }

    @Test func nativeSelectionPausesFollowingEvenWhenTheMessageIsNearTheBottom() {
        let controller = ChatAutoFollowController()
        controller.updateNearBottom(true)
        controller.pauseFollowing(reason: "textSelection")
        #expect(!controller.shouldRequestScrollForVisualUpdate())
        controller.updateNearBottom(true)
        #expect(controller.mode == .pausedByUser)
        controller.resumeFollowing()
        #expect(controller.shouldRequestScrollForVisualUpdate())
    }

    @Test func selectionSheetCallbacksUseUnicodeSelectedRange() {
        var selection: String?
        let text = "before 👋🏽 שלום after"
        let wrapper = TextSelectionTextView(text: text, shouldSelectAll: .constant(false), selectedText: Binding(get: { selection }, set: { selection = $0 }))
        let coordinator = wrapper.makeCoordinator()
        let view = UITextView()
        view.text = text
        view.selectedRange = (text as NSString).range(of: "👋🏽 שלום")
        coordinator.textViewDidChangeSelection(view)
        #expect(selection == "👋🏽 שלום")
        let emoji = (text as NSString).range(of: "👋🏽")
        view.selectedRange = NSRange(location: emoji.location + 1, length: 1)
        coordinator.textViewDidChangeSelection(view)
        #expect(selection == "👋🏽")
        view.selectedRange = NSRange(location: 0, length: 0)
        coordinator.textViewDidChangeSelection(view)
        #expect(selection == nil)
    }

    @Test(arguments: [320.0, 720.0])
    func mixedMarkdownMathAndStreamingHaveFiniteLayout(width: Double) async throws {
        let source = """
        # שלום Markdown
        Mixed **bold** and [a link](https://example.com).

        Inline $E=mc^2$ with English ועברית.

        $$\\int_0^1 x^2 dx = \\frac{1}{3}$$

        | Name | Value |
        | --- | --- |
        | שלום | 42 |

        ```swift
        print("👋🏽")
        ```
        """
        let probe = RenderProbe()
        let controller = UIHostingController(rootView: ChatMarkdownView(text: source, onRendered: { probe.count += 1 }))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 1000))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        for (index, text) in [source, source + "\n\nAn incomplete **stream"].enumerated() {
            controller.rootView = ChatMarkdownView(text: text, onRendered: { probe.count += 1 })
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            while probe.count < index + 1 && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            try #require(probe.count >= index + 1, "The actual Markdown parser must finish before layout is asserted")
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            let size = controller.sizeThatFits(in: CGSize(width: width, height: 10_000))
            #expect(size.height.isFinite && size.height > 0 && size.height < 10_000)
            #expect(size.width <= width + 1)
        }
    }

    @Test func rendererSelectionRetainsExactGraphemeAndNativeRange() throws {
        let text = "שלום 👨‍👩‍👧‍👦 e\u{301} end"
        let emoji = (text as NSString).range(of: "👨‍👩‍👧‍👦")
        let selection = MarkdownTextSelection(attributedText: NSAttributedString(string: text),
            selectedRange: NSRange(location: emoji.location + 1, length: 1), sourceBlockID: "2-0")
        #expect(selection.text == "👨‍👩‍👧‍👦")
        #expect(selection.range == emoji)
        #expect(selection.sourceBlockID == "2-0")
        #expect(MarkdownTextSelection(attributedText: NSAttributedString(string: text),
            selectedRange: NSRange(location: NSNotFound, length: 0)).text.isEmpty)
    }

    @Test func renderedRangesDisambiguateIdenticalSavedQuotes() throws {
        let container = try ModelContainer(for: ChatSavedExcerpt.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let source = ChatExcerptSource(chatRecordID: UUID(), messageID: UUID(), groupID: nil, runID: nil, title: "Source")
        let first = ChatTextQuote(text: "hello", renderedText: "hello hello", range: NSRange(location: 0, length: 5), sourceBlockID: "0")
        let second = ChatTextQuote(text: "hello", renderedText: "hello hello", range: NSRange(location: 6, length: 5), sourceBlockID: "0")
        let a = try ChatSavedExcerpt.save(source: source, markdown: "**hello** hello", quote: first.text, selection: first, in: container.mainContext)
        let b = try ChatSavedExcerpt.save(source: source, markdown: "**hello** hello", quote: second.text, selection: second, in: container.mainContext)
        #expect(a.id != b.id)
        #expect(ChatSourceDestination(excerpt: b)?.selection == second)
        #expect(a.utf16Location == nil)
    }

    @Test func internalBrowserAcceptsOnlyRealWebURLs() throws {
        #expect(ChatLinkPresentation.isWebURL(try #require(URL(string: "https://example.com/path"))))
        for value in ["file:///tmp/test", "mailto:test@example.com", "chavrusachat://open", "relative/path", "https:relative"] {
            #expect(!ChatLinkPresentation.isWebURL(try #require(URL(string: value))))
        }
    }

    @MainActor private final class RenderProbe { var count = 0 }
}
