import Foundation
import HanlinHostContracts
import SwiftData
import Testing
@testable import AI_Hanlin

@MainActor
@Suite("Original conversation projection")
struct HanlinConversationProjectionTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: ChatRecords.self, ChatMessages.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    @Test
    func originalRichPayloadsAndFailureTextPersistInTheSameRows() throws {
        let container = try container()
        let context = container.mainContext
        let record = ChatRecords(name: "Projection fixture", type: "chat")
        let assistant = ChatMessages(role: "assistant", text: "", reasoning: "", record: record)
        context.insert(record)
        context.insert(assistant)
        let coordinator = AgentRunCoordinator(groupID: assistant.groupID, providerID: "fixture", modelID: "fixture")
        let projection = HanlinConversationStreamProjection(record: record, context: context,
            messages: [assistant], assistant: assistant, coordinator: coordinator)
        let event = EventItem(type: "calendar", title: "Original calendar result")
        let code = CodeBlock(codeType: "python", code: "1 + 1", output: "2")
        let source = Resource(icon: "link", title: "Original source", link: "https://example.org/source")
        projection.consume(StreamData(content: "Original answer", reasoning: "<think>Visible reasoning</think>",
            resources: [source], events: [event], code_info: [code]))
        try projection.finish()

        let verification = ModelContext(container)
        let id = assistant.id
        let stored = try #require(verification.fetch(
            FetchDescriptor<ChatMessages>(predicate: #Predicate { $0.id == id })).first)
        #expect(stored.text == "Original answer")
        #expect(stored.reasoning?.contains("Visible reasoning") == true)
        #expect(stored.reasoning?.contains("<think>") == false)
        #expect(stored.events?.first?.title == "Original calendar result")
        #expect(stored.codeBlockData?.first?.output == "2")
        #expect(stored.resources?.first?.link == source.link)

        struct FixtureFailure: LocalizedError {
            var errorDescription: String? { "Synthetic original failure" }
        }
        let failedAssistant = ChatMessages(role: "assistant", text: "", reasoning: "", record: record)
        context.insert(failedAssistant)
        let failingCoordinator = AgentRunCoordinator(groupID: failedAssistant.groupID,
            providerID: "fixture", modelID: "fixture")
        let failingProjection = HanlinConversationStreamProjection(record: record, context: context,
            messages: [assistant, failedAssistant], assistant: failedAssistant, coordinator: failingCoordinator)
        failingProjection.fail(FixtureFailure())
        let afterFailure = ModelContext(container)
        let failedID = failedAssistant.id
        let failed = try #require(afterFailure.fetch(
            FetchDescriptor<ChatMessages>(predicate: #Predicate { $0.id == failedID })).first)
        #expect(failed.role == "error")
        #expect(failed.text?.contains("Synthetic original failure") == true)
        #expect(failed.agentRun?.status == .failed)
    }

    @Test
    func staleRunLeaseCannotReleaseANewerUIOrHeadlessOwner() throws {
        let container = try container()
        let conversationID = UUID()
        let first = try HanlinConversationRunLease.acquire(container: container, conversationID: conversationID)
        #expect(throws: HanlinHostError.self) {
            try HanlinConversationRunLease.acquire(container: container, conversationID: conversationID)
        }
        first.release()
        let second = try HanlinConversationRunLease.acquire(container: container, conversationID: conversationID)
        defer { second.release() }
        first.release()
        #expect(throws: HanlinHostError.self) {
            try HanlinConversationRunLease.acquire(container: container, conversationID: conversationID)
        }
    }
}
