import Foundation
import HanlinChatCore
import HanlinLocalization
import SwiftData
import Testing
import UIKit
@testable import AI_Hanlin

private actor MetadataTestLatch {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

@MainActor
@Suite("Conversation metadata and new chat")
struct HanlinConversationMetadataTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(for: ChatRecords.self, ChatMessages.self, AllModels.self, APIKeys.self, UserInfo.self,
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
    func clearHistoryRejectsOldMetadataAndAllowsTheNewConversationSubject() async throws {
        let container = try container()
        let context = container.mainContext
        let record = ChatRecords(name: "New chat", type: "chat")
        let oldUser = ChatMessages(role: "user", text: "Old travel plans", record: record)
        context.insert(record)
        context.insert(oldUser)
        try context.save()
        let oldUpdated = try await HanlinConversationAutoMetadata.generateIfNeeded(
            for: record, messages: [oldUser], in: context) { _ in
                _ = try HanlinConversationMutation.clearHistory(record, in: context)
                return try HanlinConversationMetadata(title: "Old travel", icon: "airplane")
            }
        #expect(!oldUpdated)
        #expect(record.name == "New chat" && record.icon == HanlinConversationMetadata.defaultIcon)
        #expect(record.messages?.count == 1 && record.messages?.first?.role == "information")
        let newUser = ChatMessages(role: "user", text: "A reading list", record: record)
        context.insert(newUser)
        try context.save()
        #expect(try await HanlinConversationAutoMetadata.generateIfNeeded(
            for: record, messages: record.messages ?? [], in: context) { history in
                #expect(!history.contains("travel") && history.contains("reading"))
                return try HanlinConversationMetadata(title: "Reading list", icon: "book")
            })
        let reopened = try #require(ModelContext(container).fetch(FetchDescriptor<ChatRecords>()).first)
        #expect(reopened.name == "Reading list" && reopened.icon == "book")
    }

    @Test
    func oldJobFinishingAfterClearCannotReleaseTheNewJob() async throws {
        let container = try container()
        let context = container.mainContext
        let record = ChatRecords(name: "New chat", type: "chat")
        let oldUser = ChatMessages(role: "user", text: "Old travel", record: record)
        context.insert(record)
        context.insert(oldUser)
        try context.save()
        let oldStarted = MetadataTestLatch(), releaseOld = MetadataTestLatch()
        let newStarted = MetadataTestLatch(), releaseNew = MetadataTestLatch()
        defer { Task { await releaseOld.open(); await releaseNew.open() } }
        let oldJob = Task { @MainActor in
            defer { Task { await oldStarted.open() } }
            return try await HanlinConversationAutoMetadata.generateIfNeeded(
                for: record, messages: [oldUser], in: context) { _ in
                    await oldStarted.open()
                    await releaseOld.wait()
                    return try HanlinConversationMetadata(title: "Old travel", icon: "airplane")
                }
        }
        await oldStarted.wait()
        _ = try HanlinConversationMutation.clearHistory(record, in: context)
        let newUser = ChatMessages(role: "user", text: "Reading", record: record)
        context.insert(newUser)
        try context.save()
        let newJob = Task { @MainActor in
            defer { Task { await newStarted.open() } }
            return try await HanlinConversationAutoMetadata.generateIfNeeded(
                for: record, messages: [newUser], in: context) { _ in
                    await newStarted.open()
                    await releaseNew.wait()
                    return try HanlinConversationMetadata(title: "Reading list", icon: "book")
                }
        }
        await newStarted.wait()
        await releaseOld.open()
        #expect(try await oldJob.value == false)
        var duplicateCalled = false
        let duplicate = try await HanlinConversationAutoMetadata.generateIfNeeded(
            for: record, messages: [newUser], in: context) { _ in
                duplicateCalled = true
                return try HanlinConversationMetadata(title: "Unexpected duplicate", icon: "clock")
            }
        #expect(!duplicate && !duplicateCalled)
        await releaseNew.open()
        #expect(try await newJob.value)
        #expect(record.name == "Reading list" && record.icon == "book")
    }

    @Test
    func explicitRenameToSamePlaceholderCancelsAutomationWithoutAnnouncement() async throws {
        let container = try container()
        let context = container.mainContext
        let record = ChatRecords(name: "New chat", type: "chat")
        let user = ChatMessages(role: "user", text: "Reading", record: record)
        context.insert(record)
        context.insert(user)
        try context.save()
        let updated = try await HanlinConversationAutoMetadata.generateIfNeeded(
            for: record, messages: [user], in: context) { _ in
                let announcement = try HanlinConversationMutation.rename(record, title: "New chat",
                    announceChange: true, in: context)
                #expect(announcement == nil)
                return try HanlinConversationMetadata(title: "Reading list", icon: "book")
            }
        #expect(!updated && record.metadataWasManuallyEdited)
        let reopened = try #require(ModelContext(container).fetch(FetchDescriptor<ChatRecords>()).first)
        #expect(reopened.name == "New chat" && reopened.metadataWasManuallyEdited)
        #expect(reopened.messages?.count == 1)
    }

    @Test
    func separateModelContextsShareTheSameMetadataJob() async throws {
        let container = try container()
        let context = container.mainContext
        let record = ChatRecords(name: "New chat", type: "chat")
        let user = ChatMessages(role: "user", text: "Plan a meeting", record: record)
        context.insert(record)
        context.insert(user)
        try context.save()
        let secondContext = ModelContext(container)
        let secondRecord = try #require(secondContext.fetch(FetchDescriptor<ChatRecords>()).first)
        #expect(secondRecord !== record)
        var requests = 0
        let updated = try await HanlinConversationAutoMetadata.generateIfNeeded(
            for: record, messages: [user], in: context) { _ in
                requests += 1
                let duplicate = try await HanlinConversationAutoMetadata.generateIfNeeded(
                    for: secondRecord, messages: secondRecord.messages ?? [], in: secondContext) { _ in
                        requests += 1
                        return try HanlinConversationMetadata(title: "Duplicate", icon: "clock")
                    }
                #expect(!duplicate)
                return try HanlinConversationMetadata(title: "Meeting plan", icon: "calendar")
            }
        #expect(updated && requests == 1)
    }

    @Test
    func manualEditInAnotherContextWinsAgainstTheOriginalObject() async throws {
        let container = try container()
        let context = container.mainContext
        let record = ChatRecords(name: "New chat", type: "chat")
        let user = ChatMessages(role: "user", text: "Reading", record: record)
        context.insert(record)
        context.insert(user)
        try context.save()
        let editingContext = ModelContext(container)
        let editingRecord = try #require(editingContext.fetch(FetchDescriptor<ChatRecords>()).first)
        let updated = try await HanlinConversationAutoMetadata.generateIfNeeded(
            for: record, messages: [user], in: context) { _ in
                try HanlinConversationMutation.updateAppearance(editingRecord,
                    title: "My books", icon: "heart", color: "hlRed", in: editingContext)
                return try HanlinConversationMetadata(title: "Reading list", icon: "book")
            }
        #expect(!updated)
        let reopened = try #require(ModelContext(container).fetch(FetchDescriptor<ChatRecords>()).first)
        #expect(reopened.name == "My books" && reopened.icon == "heart" && reopened.metadataWasManuallyEdited)
    }

    @Test
    func fallbackUsesTheActualRequestModelInsteadOfSavedSelection() async throws {
        let container = try container()
        let context = container.mainContext
        let selected = AllModels(name: "saved-model", position: 0, company: "SAVED_FIXTURE")
        let requested = AllModels(name: "requested-model", position: 1, company: "REQUEST_FIXTURE")
        context.insert(selected)
        context.insert(requested)
        context.insert(APIKeys(company: "REQUEST_FIXTURE", key: "synthetic-fixture",
            requestURL: "https://metadata.invalid/v1/messages", isHidden: false, apiType: .anthropic))
        context.insert(UserInfo(optimizationTextModel: "unconfigured-optimizer"))
        let record = ChatRecords(name: "New chat", type: "chat", useModel: 0)
        let user = ChatMessages(role: "user", text: "Reading", modelName: requested.name, record: record)
        context.insert(record)
        context.insert(user)
        try context.save()
        let fallback = try HanlinConversationAutoMetadata.fallbackModel(for: record, messages: [user],
            requestedID: requested.id, in: context)
        #expect(fallback === requested)
        #expect(try HanlinConversationAutoMetadata.fallbackModel(for: record, messages: [user],
            requestedID: nil, in: context) === requested)
        var requests = 0
        let metadata = try await SystemOptimizer(context: context).autoChatMetadata(
            historyMessage: "Reading", fallbackModelID: fallback?.id) { target, history, _ in
                requests += 1
                guard case .sdk(let configuration) = target else {
                    Issue.record("The requested remote model was not selected")
                    throw HanlinConversationMetadata.ResponseError.invalidResponse
                }
                #expect(configuration.modelID == "requested-model")
                #expect(HanlinAISDKProviderFactory.descriptor(for: configuration).kind == .anthropic)
                #expect(history == "Reading" && !configuration.supportsToolUse)
                return try HanlinConversationMetadata(title: "Reading list", icon: "book")
            }
        #expect(requests == 1 && metadata.icon == "book")
    }

    @Test
    func configuredOptimizerWinsAndMissingCredentialsFallbackBeforeOneGeneration() async throws {
        let container = try container()
        let context = container.mainContext
        let preferred = AllModels(name: "preferred", position: 0, company: "PREFERRED_FIXTURE")
        let current = AllModels(name: "current", position: 1, company: "CURRENT_FIXTURE")
        let missing = APIKeys(company: "PREFERRED_FIXTURE", requestURL: "https://preferred.invalid/v1/responses",
            isHidden: false, apiType: .openAIResponse)
        context.insert(preferred)
        context.insert(current)
        context.insert(missing)
        context.insert(APIKeys(company: "CURRENT_FIXTURE", key: "synthetic-fixture",
            requestURL: "https://current.invalid/v1beta", isHidden: false, apiType: .gemini))
        context.insert(UserInfo(optimizationTextModel: "preferred"))
        try context.save()
        let optimizer = SystemOptimizer(context: context)
        guard case .sdk(let fallback) = try optimizer.metadataTarget(fallbackModelID: current.id) else {
            Issue.record("Missing preferred credentials did not use the valid current model"); return
        }
        #expect(fallback.modelID == "current")
        #expect(HanlinAISDKProviderFactory.descriptor(for: fallback).kind == .google)
        missing.key = "synthetic-preferred-fixture"
        try context.save()
        guard case .sdk(let configured) = try optimizer.metadataTarget(fallbackModelID: current.id) else {
            Issue.record("Configured optimizer was not selected"); return
        }
        #expect(configured.modelID == "preferred")
        #expect(HanlinAISDKProviderFactory.descriptor(for: configured).kind == .openAIResponses)
        var requests = 0
        do {
            _ = try await optimizer.autoChatMetadata(historyMessage: "Reading", fallbackModelID: current.id) { _, _, _ in
                requests += 1
                throw HanlinConversationMetadata.ResponseError.invalidResponse
            }
            Issue.record("A failed metadata request must remain failed")
        } catch { #expect(requests == 1) }
    }

    @Test
    func localModelUsesTheExistingFileWithoutRequiringAnAPIKey() async throws {
        let container = try container()
        let context = container.mainContext
        let name = "metadata-local-fixture-" + UUID().uuidString
        let modelURL = getModelDirectory().appendingPathComponent(name + ".gguf")
        try Data().write(to: modelURL)
        defer { try? FileManager.default.removeItem(at: modelURL) }
        let local = AllModels(name: name, position: 0, company: "LOCAL")
        context.insert(local)
        try context.save()
        var requests = 0
        _ = try await SystemOptimizer(context: context).autoChatMetadata(
            historyMessage: "Private reading", fallbackModelID: local.id) { target, _, _ in
                requests += 1
                guard case .local(let modelID, let url) = target else {
                    Issue.record("LOCAL selected a network path")
                    throw HanlinConversationMetadata.ResponseError.invalidResponse
                }
                #expect(modelID == name && url == modelURL && url.isFileURL)
                return try HanlinConversationMetadata(title: "Private reading", icon: "book")
            }
        #expect(requests == 1)
        #expect(try context.fetch(FetchDescriptor<APIKeys>()).isEmpty)
    }

    @Test
    func editedSourceTextCannotApplyDelayedMetadata() async throws {
        let container = try container()
        let context = container.mainContext
        let record = ChatRecords(name: "New chat", type: "chat")
        let user = ChatMessages(role: "user", text: "Old travel", record: record)
        context.insert(record)
        context.insert(user)
        try context.save()
        let updated = try await HanlinConversationAutoMetadata.generateIfNeeded(
            for: record, messages: [user], in: context) { _ in
                user.text = "A different subject"
                try context.save()
                return try HanlinConversationMetadata(title: "Old travel", icon: "airplane")
            }
        #expect(!updated && record.name == "New chat")
    }

    @Test
    func allSuggestedSymbolsExistInTheNativeSDK() {
        for name in HanlinConversationMetadata.allowedIcons {
            #expect(UIImage(systemName: name) != nil, "Missing SF Symbol: \(name)")
        }
    }
}
