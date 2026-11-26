import Foundation
import HanlinChatCore
import HanlinLocalization
import SwiftData
import Testing
import UIKit
@testable import AI_Hanlin

@MainActor
@Suite("Conversation metadata and new chat")
struct HanlinConversationMetadataTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: ChatRecords.self, ChatMessages.self, AllModels.self, APIKeys.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    @Test
    func generatedTitleAndIconPersistTogetherWithoutSyntheticMessages() async throws {
        let container = try container()
        let context = container.mainContext
        let record = ChatRecords(name: HanlinConversationCreation.defaultTitle, type: "chat")
        let user = ChatMessages(role: "user", text: "תכנן מסלול באוטובוס לירושלים", record: record)
        context.insert(record)
        context.insert(user)
        try context.save()
        var requests = 0
        let updated = try await HanlinConversationAutoMetadata.generateIfNeeded(
            for: record, messages: [user], in: context) { history in
                requests += 1
                #expect(history.contains("ירושלים"))
                return try HanlinConversationMetadata(title: "נסיעה לירושלים", icon: "bus")
            }
        #expect(updated && requests == 1)
        let verification = ModelContext(container)
        let stored = try #require(verification.fetch(FetchDescriptor<ChatRecords>()).first)
        #expect(stored.name == "נסיעה לירושלים" && stored.icon == "bus")
        #expect(stored.color == "hlBlue")
        #expect(stored.messages?.count == 1)
        #expect(stored.messages?.first?.role == "user")
        #expect(!stored.metadataWasManuallyEdited)
        let repeated = try await HanlinConversationAutoMetadata.generateIfNeeded(
            for: record, messages: [user], in: context) { _ in
                requests += 1
                return try HanlinConversationMetadata(title: "Unexpected overwrite", icon: "car")
            }
        #expect(!repeated && requests == 1)
    }

    @Test
    func manualAppearanceWinsAgainstDelayedMetadataAndPersists() async throws {
        let container = try container()
        let context = container.mainContext
        let record = ChatRecords(name: "New Group Chat", type: "chat")
        let user = ChatMessages(role: "user", text: "A book recommendation", record: record)
        context.insert(record)
        context.insert(user)
        try context.save()
        let updated = try await HanlinConversationAutoMetadata.generateIfNeeded(
            for: record, messages: [user], in: context) { _ in
                try HanlinConversationMutation.updateAppearance(record,
                    title: HanlinConversationCreation.defaultTitle, icon: "heart", color: "hlRed", in: context)
                return try HanlinConversationMetadata(title: "Reading list", icon: "book")
            }
        #expect(!updated)
        #expect(record.name == HanlinConversationCreation.defaultTitle)
        #expect(record.icon == "heart" && record.color == "hlRed")
        #expect(record.metadataWasManuallyEdited)
        let reopened = try #require(ModelContext(container).fetch(FetchDescriptor<ChatRecords>()).first)
        #expect(reopened.metadataWasManuallyEdited)
        #expect(reopened.icon == "heart")
    }

    @Test
    func overlappingUIAndHeadlessRequestsShareOneMetadataJob() async throws {
        let container = try container()
        let context = container.mainContext
        let record = ChatRecords(name: "New chat", type: "chat")
        let user = ChatMessages(role: "user", text: "Plan a meeting", record: record)
        context.insert(record)
        context.insert(user)
        try context.save()
        var requests = 0
        let first = try await HanlinConversationAutoMetadata.generateIfNeeded(
            for: record, messages: [user], in: context) { _ in
                requests += 1
                let second = try await HanlinConversationAutoMetadata.generateIfNeeded(
                    for: record, messages: [user], in: context) { _ in
                        requests += 1
                        return try HanlinConversationMetadata(title: "Duplicate", icon: "clock")
                    }
                #expect(!second)
                return try HanlinConversationMetadata(title: "Meeting plan", icon: "calendar")
            }
        #expect(first && requests == 1)
        #expect(record.icon == "calendar")
    }

    @Test
    func deletionWhileGeneratingCannotResurrectTheConversation() async throws {
        let container = try container()
        let context = container.mainContext
        let record = ChatRecords(name: "New chat", type: "chat")
        let user = ChatMessages(role: "user", text: "A draft", record: record)
        context.insert(record)
        context.insert(user)
        try context.save()
        do {
            _ = try await HanlinConversationAutoMetadata.generateIfNeeded(
                for: record, messages: [user], in: context) { _ in
                    try HanlinConversationMutation.delete(record, in: context)
                    return try HanlinConversationMetadata(title: "Deleted draft", icon: "doc.text")
                }
            Issue.record("A deleted row must reject a delayed automatic update")
        } catch {
            #expect(try context.fetch(FetchDescriptor<ChatRecords>()).isEmpty)
        }
    }

    @Test
    func legacyCustomIconIsRetainedAndExplicitNamesDoNotGenerate() async throws {
        let container = try container()
        let context = container.mainContext
        let legacy = ChatRecords(name: "New Group Chat", type: "chat", icon: "heart", color: "hlRed")
        let user = ChatMessages(role: "user", text: "Travel", record: legacy)
        context.insert(legacy)
        context.insert(user)
        try context.save()
        #expect(try await HanlinConversationAutoMetadata.generateIfNeeded(
            for: legacy, messages: [user], in: context) { _ in
                try HanlinConversationMetadata(title: "Travel plans", icon: "airplane")
            })
        #expect(legacy.icon == "heart" && legacy.color == "hlRed")
        var called = false
        let second = try await HanlinConversationAutoMetadata.generateIfNeeded(
            for: legacy, messages: [user], in: context) { _ in
                called = true
                return try HanlinConversationMetadata(title: "Unexpected", icon: "map")
            }
        #expect(!second && !called)
    }


    @Test
    func sharedCreationStartsEmptyAndPreservesExplicitTitles() throws {
        let container = try container()
        let context = container.mainContext
        context.insert(APIKeys(company: "METADATA_FIXTURE", key: "synthetic-fixture", isHidden: false))
        context.insert(AllModels(name: "fixture-model", displayName: "Fixture", position: 0,
                                 company: "METADATA_FIXTURE"))
        try context.save()
        let automatic = try HanlinConversationCreation.create(in: context)
        #expect(automatic.name == String(localized: "New chat", bundle: HanlinLocalization.bundle))
        #expect(automatic.messages?.isEmpty ?? true)
        #expect(!automatic.metadataWasManuallyEdited)
        let explicit = try HanlinConversationCreation.create(in: context, title: "My own title")
        #expect(explicit.name == "My own title" && explicit.metadataWasManuallyEdited)
        #expect(try context.fetch(FetchDescriptor<ChatMessages>()).isEmpty)
    }

    @Test
    func allSuggestedSymbolsExistInTheNativeSDK() {
        for name in HanlinConversationMetadata.allowedIcons {
            #expect(UIImage(systemName: name) != nil, "Missing SF Symbol: \(name)")
        }
    }
}
