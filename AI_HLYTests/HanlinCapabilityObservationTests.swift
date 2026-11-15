import Foundation
import HanlinPlatformContracts
import Observation
import Testing
@testable import AI_Hanlin

private final class CapabilityObservationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0
    func mark() { lock.withLock { storage += 1 } }
    var count: Int { lock.withLock { storage } }
}

private actor CapabilitySelectionIntentDelay {
    private var hasArrived = false
    private var released = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var pending: CheckedContinuation<Void, Never>?

    func wait() async {
        hasArrived = true
        arrival?.resume()
        arrival = nil
        guard !released else { return }
        await withCheckedContinuation { pending = $0 }
    }

    func waitUntilArrived() async {
        guard !hasArrived else { return }
        await withCheckedContinuation { arrival = $0 }
    }

    func release() {
        released = true
        pending?.resume()
        pending = nil
    }
}

@MainActor
@Suite("Capability service observation", .serialized)
struct HanlinCapabilityObservationTests {
    @Test func skillEnabledMutationNotifiesAndReadsActualPersistedState() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let refreshes = CapabilityObservationCounter()
        let store = SkillStore(rootDirectoryURL: root, onCatalogChange: { refreshes.mark() })
        let id = try HanlinSkillID(validating: "unit_observed_skill")
        let changes = CapabilityObservationCounter()
        withObservationTracking { _ = store.isSkillEnabled(id: id) } onChange: { changes.mark() }
        store.setSkillEnabled(id: id, enabled: false)
        #expect(changes.count == 1)
        #expect(refreshes.count == 1)
        #expect(!store.isSkillEnabled(id: id))
        let reloaded = SkillStore(rootDirectoryURL: root, onCatalogChange: {})
        #expect(!reloaded.isSkillEnabled(id: id))
    }

    @Test func filesystemSkillQueriesObserveCommittedCatalogChanges() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SkillStore(rootDirectoryURL: root, onCatalogChange: {})
        let id = try HanlinSkillID(validating: "unit_filesystem_skill")
        let changes = CapabilityObservationCounter()
        withObservationTracking { _ = store.allCustomSkillDescriptors() } onChange: { changes.mark() }
        try store.saveCustomSkill(id: id, title: "Unit skill", description: "Unit summary", instructions: "Unit instructions")
        #expect(changes.count == 1)
        #expect(store.revision == 1)
        #expect(store.allCustomSkillDescriptors().map(\.id) == [id])
    }

    @Test func catalogNotificationsReadTheActualRegisteredEntries() throws {
        let catalog = HanlinSkillCatalog(loadProductionSkills: false)
        let skill = try HanlinSkillDescriptor(
            id: HanlinSkillID(validating: "unit_catalog_skill"), title: "Unit skill",
            summary: "Unit summary", instructions: .inline("Unit instructions")
        )
        let changes = CapabilityObservationCounter()
        withObservationTracking { _ = catalog.allSkills() } onChange: { changes.mark() }
        catalog.register(skill: skill)
        #expect(changes.count == 1)
        #expect(catalog.allSkills().map(\.id) == [skill.id])
        withObservationTracking { _ = catalog.allSkills() } onChange: { changes.mark() }
        catalog.reset()
        #expect(changes.count == 2)
        #expect(catalog.allSkills().isEmpty)
    }

    @Test func nativePreferenceChangesNotifyAndReadActualDefaults() throws {
        let suite = "hanlin.unit.capabilities." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let catalog = NativeToolCatalog(defaults: defaults, automaticallyRegistersBuiltins: false, trace: { _, _ in })
        let entry = toolEntry()
        let changes = CapabilityObservationCounter()
        withObservationTracking { _ = catalog.isEffectivelyEnabled(entry) } onChange: { changes.mark() }
        catalog.setEnabled(false, for: entry)
        #expect(changes.count == 1)
        #expect(catalog.preferenceRevision == 1)
        #expect(!catalog.isEffectivelyEnabled(entry))
        #expect(defaults.object(forKey: "toolEnabled." + entry.name) as? Bool == false)
        let reloaded = NativeToolCatalog(defaults: defaults, automaticallyRegistersBuiltins: false, trace: { _, _ in })
        #expect(!reloaded.isEnabled(entry))
        catalog.setEnabled(false, for: entry)
        #expect(catalog.preferenceRevision == 1)
    }

    @Test func nativeGroupObservationPreservesIndividualPreferences() throws {
        let suite = "hanlin.unit.capabilities." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let catalog = NativeToolCatalog(defaults: defaults, automaticallyRegistersBuiltins: false, trace: { _, _ in })
        let entry = toolEntry()
        let group = NativeAssistantToolGroup(id: "unit_group", title: "Unit group", subtitle: nil,
            summary: "Unit summary", systemImage: "wrench", category: .utility,
            isExperimental: false, isEnabledByDefault: true, toolEntries: [entry])
        let changes = CapabilityObservationCounter()
        withObservationTracking { _ = catalog.isGroupEnabled(group) } onChange: { changes.mark() }
        catalog.setGroupEnabled(false, for: group)
        #expect(changes.count == 1)
        #expect(!catalog.isGroupEnabled(group))
        #expect(catalog.isEnabled(entry))
        #expect(defaults.object(forKey: "toolGroupEnabled.unit_group") as? Bool == false)
    }

    @Test func mcpSelectionNotifiesAfterRealCommitAndPreservesOtherChats() async throws {
        let (root, provider, layout, _) = makeMCPFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        await provider.loadIfNeeded(startHost: false)
        #expect(provider.persistentLoadState == .loaded)
        let firstChat = UUID(), otherChat = UUID()
        let firstIDs: Set<UUID> = [UUID()], otherIDs: Set<UUID> = [UUID()]
        await provider.setSelection(otherIDs, chatID: otherChat, temporary: false)
        let revision = provider.selectionRevision(chatID: firstChat, temporary: false)
        let changes = CapabilityObservationCounter()
        withObservationTracking { _ = provider.selectionRevision(chatID: firstChat, temporary: false) } onChange: { changes.mark() }
        await provider.setSelection(firstIDs, chatID: firstChat, temporary: false)
        #expect(changes.count == 1)
        #expect(provider.selectionRevision(chatID: firstChat, temporary: false) == revision + 1)
        let actualStore = MCPChatSelectionStore(fileLayout: layout)
        #expect(try await actualStore.selection(chatID: firstChat) == firstIDs)
        #expect(try await actualStore.selection(chatID: otherChat) == otherIDs)
        await provider.setSelection([], chatID: firstChat, temporary: false)
        #expect(await provider.selection(chatID: firstChat, temporary: false).isEmpty)
        #expect(try await actualStore.selection(chatID: otherChat) == otherIDs)
        #expect(!provider.configuration.isEnabled)
        let runtime = await provider.nodeRuntime.snapshot()
        #expect(runtime.state == .stopped)
    }

    @Test func failedMCPSelectionDoesNotNotifyACommit() async throws {
        let (root, provider, layout, store) = makeMCPFixture()
        let firstChat = UUID()
        defer { try? FileManager.default.removeItem(at: root) }
        await provider.loadIfNeeded(startHost: false)
        #expect(provider.persistentLoadState == .loaded)
        let temporaryServer = UUID()
        await provider.setSelection([temporaryServer], chatID: firstChat, temporary: true)
        let temporaryChanges = CapabilityObservationCounter()
        withObservationTracking { _ = provider.selectionRevision(chatID: firstChat, temporary: true) } onChange: { temporaryChanges.mark() }
        // A real directory at the JSON path makes the real actor store read fail.
        try FileManager.default.createDirectory(at: layout.chatSelections, withIntermediateDirectories: true)
        let changes = CapabilityObservationCounter()
        withObservationTracking { _ = provider.selectionRevision(chatID: firstChat, temporary: false) } onChange: { changes.mark() }
        await provider.setSelection([UUID()], chatID: firstChat, temporary: false)
        #expect(provider.selectionRevision(chatID: firstChat, temporary: false) == 0)
        #expect(changes.count == 0)
        #expect(provider.lastError != nil)
        do {
            _ = try await provider.readSelection(chatID: firstChat, temporary: false)
            Issue.record("A failed real store read must not report successful default selection")
        } catch {}
        do {
            let mutation = try await store.removeServer(temporaryServer)
            provider.publishSelectionMutation(mutation)
            Issue.record("A failed real removal must not report committed mutation scopes")
        } catch {}
        #expect(temporaryChanges.count == 0)
        #expect(provider.selectionRevision(chatID: firstChat, temporary: true) == 1)
        #expect(try await provider.readSelection(chatID: firstChat, temporary: true) == [temporaryServer])
    }

    @Test func unloadedMCPSelectionKeepsTheExistingAdmissionGuard() async {
        let (root, provider, layout, _) = makeMCPFixture()
        let firstChat = UUID()
        defer { try? FileManager.default.removeItem(at: root) }
        for temporary in [false, true] {
            await provider.setSelection([UUID()], chatID: firstChat, temporary: temporary)
            #expect(provider.selectionRevision(chatID: firstChat, temporary: temporary) == 0)
            do {
                _ = try await provider.readSelection(chatID: firstChat, temporary: temporary)
                Issue.record("An unloaded store must report request-scoped failure")
            } catch MCPChatSelectionReadError.storageNotLoaded {} catch {
                Issue.record("Unexpected unloaded selection error")
            }
        }
        #expect(provider.persistentLoadState == .notLoaded)
        #expect(!FileManager.default.fileExists(atPath: layout.chatSelections.path))
    }

    @Test func mcpSignalsAreScopedAndNoopWritesDoNotNotify() async throws {
        let (root, provider, layout, store) = makeMCPFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        await provider.loadIfNeeded(startHost: false)
        let first = UUID(), second = UUID()
        for temporary in [false, true] {
            let changes = CapabilityObservationCounter()
            withObservationTracking { _ = provider.selectionRevision(chatID: first, temporary: temporary) } onChange: { changes.mark() }
            // Creating another token and committing another scope must not invalidate first.
            _ = provider.selectionRevision(chatID: second, temporary: temporary)
            await provider.setSelection([UUID()], chatID: second, temporary: temporary)
            #expect(changes.count == 0)
            #expect(try await store.selection(chatID: first, temporary: temporary) == nil)
            let oppositeMode = CapabilityObservationCounter()
            withObservationTracking { _ = provider.selectionRevision(chatID: first, temporary: !temporary) } onChange: { oppositeMode.mark() }
            await provider.setSelection([], chatID: first, temporary: temporary)
            #expect(oppositeMode.count == 0)
            #expect(changes.count == 1)
            #expect(provider.selectionRevision(chatID: first, temporary: temporary) == 1)
            let explicitEmpty = try #require(try await store.selection(chatID: first, temporary: temporary))
            #expect(explicitEmpty.isEmpty)
            let repeated = CapabilityObservationCounter()
            withObservationTracking { _ = provider.selectionRevision(chatID: first, temporary: temporary) } onChange: { repeated.mark() }
            await provider.setSelection([], chatID: first, temporary: temporary)
            #expect(repeated.count == 0)
            #expect(provider.selectionRevision(chatID: first, temporary: temporary) == 1)
        }
        let reopened = MCPChatSelectionStore(fileLayout: layout)
        let persisted = try #require(try await reopened.selection(chatID: first))
        #expect(persisted.isEmpty)
    }

    @Test func serverRemovalPreservesExplicitEmptyAndNotifiesOnlyAffectedScopes() async throws {
        let (root, provider, layout, store) = makeMCPFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        await provider.loadIfNeeded(startHost: false)
        let selected = UUID(), empty = UUID(), unaffected = UUID()
        let removedServer = UUID(), retainedServer = UUID()
        for temporary in [false, true] {
            await provider.setSelection([removedServer], chatID: selected, temporary: temporary)
            await provider.setSelection([], chatID: empty, temporary: temporary)
            await provider.setSelection([retainedServer], chatID: unaffected, temporary: temporary)
        }
        let selectedChanges = CapabilityObservationCounter(), emptyChanges = CapabilityObservationCounter(), otherChanges = CapabilityObservationCounter()
        withObservationTracking {
            _ = provider.selectionRevision(chatID: selected, temporary: false)
            _ = provider.selectionRevision(chatID: selected, temporary: true)
        } onChange: { selectedChanges.mark() }
        withObservationTracking {
            _ = provider.selectionRevision(chatID: empty, temporary: false)
            _ = provider.selectionRevision(chatID: empty, temporary: true)
        } onChange: { emptyChanges.mark() }
        withObservationTracking {
            _ = provider.selectionRevision(chatID: unaffected, temporary: false)
            _ = provider.selectionRevision(chatID: unaffected, temporary: true)
        } onChange: { otherChanges.mark() }
        let mutation = try await store.removeServer(removedServer)
        #expect(mutation.affectedScopes == [.init(chatID: selected, temporary: false), .init(chatID: selected, temporary: true)])
        provider.publishSelectionMutation(mutation)
        #expect(selectedChanges.count == 1)
        #expect(emptyChanges.count == 0)
        #expect(otherChanges.count == 0)
        for temporary in [false, true] {
            #expect(provider.selectionRevision(chatID: selected, temporary: temporary) == 2)
            #expect(provider.selectionRevision(chatID: empty, temporary: temporary) == 1)
            #expect(try await store.selection(chatID: selected, temporary: temporary) == [])
            #expect(try await store.selection(chatID: empty, temporary: temporary) == [])
            #expect(try await store.selection(chatID: unaffected, temporary: temporary) == [retainedServer])
            #expect(await provider.selection(chatID: empty, temporary: temporary).isEmpty)
        }
        let reopened = MCPChatSelectionStore(fileLayout: layout)
        #expect(try await reopened.selection(chatID: empty) == [])
        #expect(try await reopened.selection(chatID: selected) == [])
        #expect(try await store.removeServer(removedServer).affectedScopes.isEmpty)
    }

    @Test func concurrentMCPReadsKeepTheirRequestedChatAndStorageScope() async throws {
        let (root, provider, _, store) = makeMCPFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        await provider.loadIfNeeded(startHost: false)
        let first = UUID(), second = UUID()
        let persistent: Set<UUID> = [UUID()], temporary: Set<UUID> = [UUID()]
        await provider.setSelection(persistent, chatID: first, temporary: false)
        await provider.setSelection(temporary, chatID: second, temporary: true)
        async let firstRead = provider.readSelection(chatID: first, temporary: false)
        async let secondRead = provider.readSelection(chatID: second, temporary: true)
        let (firstValue, secondValue) = try await (firstRead, secondRead)
        #expect(firstValue == persistent)
        #expect(secondValue == temporary)
        #expect(try await store.selection(chatID: first, temporary: true) == nil)
        #expect(try await store.selection(chatID: second, temporary: false) == nil)
        #expect(try await provider.readSelection(chatID: first, temporary: true).isEmpty)
        await provider.setSelection([], chatID: first, temporary: false)
        #expect(try await provider.readSelection(chatID: first, temporary: false).isEmpty)
    }

    @Test func delayedConcurrentServerIntentsPreserveBothCanonicalSelections() async throws {
        let (root, provider, layout, store) = makeMCPFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        await provider.loadIfNeeded(startHost: false)
        let firstServer = UUID(), secondServer = UUID(), otherChat = UUID()
        for temporary in [false, true] {
            let chat = UUID()
            await provider.setSelection([UUID()], chatID: otherChat, temporary: temporary)
            let otherSelection = try await provider.readSelection(chatID: otherChat, temporary: temporary)
            // Both UI intents begin with the same real empty read. The delayed
            // first action must not replace the second action's committed IDs.
            #expect(try await provider.readSelection(chatID: chat, temporary: temporary) == [])
            let delay = CapabilitySelectionIntentDelay()
            let first = Task { @MainActor in
                await delay.wait()
                return try await provider.applySelectionIntent(
                    .init(serverID: firstServer, isSelected: true), chatID: chat, temporary: temporary)
            }
            await delay.waitUntilArrived()
            let second = Task { @MainActor in
                try await provider.applySelectionIntent(
                    .init(serverID: secondServer, isSelected: true), chatID: chat, temporary: temporary)
            }
            // Release even on a failed second action; no suspended test task leaks.
            let secondResult = await second.result
            await delay.release()
            let firstResult = await first.result
            #expect(try secondResult.get() == [secondServer])
            #expect(try firstResult.get() == [firstServer, secondServer])
            #expect(try await store.selection(chatID: chat, temporary: temporary) == [firstServer, secondServer])
            #expect(try await provider.readSelection(chatID: chat, temporary: temporary) == [firstServer, secondServer])
            #expect(try await provider.readSelection(chatID: otherChat, temporary: temporary) == otherSelection)
            #expect(provider.selectionRevision(chatID: chat, temporary: temporary) == 2)
            #expect(provider.selectionRevision(chatID: chat, temporary: !temporary) == 0)
            if !temporary {
                let reopened = MCPChatSelectionStore(fileLayout: layout)
                #expect(try await reopened.selection(chatID: chat) == [firstServer, secondServer])
            }
        }
        #expect(!provider.configuration.isEnabled)
        #expect(await provider.nodeRuntime.snapshot().state == .stopped)
    }

    @Test func concurrentActorIntentsCommitCurrentStateAndExactMutationScopes() async throws {
        let (root, _, layout, store) = makeMCPFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = UUID(), second = UUID(), defaultServer = UUID()
        for temporary in [false, true] {
            let chat = UUID()
            async let a = store.applySelectionIntent(.init(serverID: first, isSelected: true),
                chatID: chat, temporary: temporary, defaultServerIDs: [defaultServer])
            async let b = store.applySelectionIntent(.init(serverID: second, isSelected: true),
                chatID: chat, temporary: temporary, defaultServerIDs: [defaultServer])
            let (aResult, bResult) = try await (a, b)
            let expectedScope: Set<MCPChatSelectionScope> = [.init(chatID: chat, temporary: temporary)]
            #expect(aResult.mutation.affectedScopes == expectedScope)
            #expect(bResult.mutation.affectedScopes == expectedScope)
            #expect(try await store.selection(chatID: chat, temporary: temporary) == [first, second, defaultServer])
            let repeated = try await store.applySelectionIntent(.init(serverID: first, isSelected: true),
                chatID: chat, temporary: temporary, defaultServerIDs: [UUID()])
            #expect(repeated.mutation.affectedScopes.isEmpty)
            #expect(repeated.serverIDs == [first, second, defaultServer])
            if !temporary {
                let reopened = MCPChatSelectionStore(fileLayout: layout)
                #expect(try await reopened.selection(chatID: chat) == [first, second, defaultServer])
            }
        }
    }

    @Test func serverIntentsSeedActualDefaultsOnlyForAbsentRecordsAndPreserveEmpty() async throws {
        let (root, provider, layout, store) = makeMCPFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let enabled = try mcpServer(layout: layout)
        var optIn = try mcpServer(layout: layout)
        optIn.isEnabledForNewChats = false
        var globallyDisabled = try mcpServer(layout: layout)
        globallyDisabled.isGloballyEnabled = false
        try await MCPServerRegistryStore(fileLayout: layout).save([enabled, optIn, globallyDisabled])
        await provider.loadIfNeeded(startHost: false)
        #expect(provider.persistentLoadState == .loaded)
        #expect(provider.servers.count == 3)
        for temporary in [false, true] {
            let chat = UUID()
            #expect(try await store.selection(chatID: chat, temporary: temporary) == nil)
            #expect(try await provider.readSelection(chatID: chat, temporary: temporary) == [enabled.id])
            let on = try await provider.applySelectionIntent(.init(serverID: optIn.id, isSelected: true),
                chatID: chat, temporary: temporary)
            #expect(on == [enabled.id, optIn.id])
            let off = try await provider.applySelectionIntent(.init(serverID: enabled.id, isSelected: false),
                chatID: chat, temporary: temporary)
            #expect(off == [optIn.id])
            let empty = try await provider.applySelectionIntent(.init(serverID: optIn.id, isSelected: false),
                chatID: chat, temporary: temporary)
            #expect(empty.isEmpty)
            #expect(try await store.selection(chatID: chat, temporary: temporary) == [])
            let revision = provider.selectionRevision(chatID: chat, temporary: temporary)
            let changes = CapabilityObservationCounter()
            withObservationTracking { _ = provider.selectionRevision(chatID: chat, temporary: temporary) } onChange: { changes.mark() }
            let noop = try await provider.applySelectionIntent(.init(serverID: optIn.id, isSelected: false),
                chatID: chat, temporary: temporary)
            #expect(noop.isEmpty)
            #expect(changes.count == 0)
            #expect(provider.selectionRevision(chatID: chat, temporary: temporary) == revision)
            let afterEmpty = try await provider.applySelectionIntent(.init(serverID: optIn.id, isSelected: true),
                chatID: chat, temporary: temporary)
            #expect(afterEmpty == [optIn.id]) // Never resurrect enabled's default.
            await provider.setSelection([], chatID: chat, temporary: temporary) // Existing clear-all API.
            #expect(try await provider.readSelection(chatID: chat, temporary: temporary) == [])
            let absent = UUID()
            let explicit = try await provider.applySelectionIntent(.init(serverID: enabled.id, isSelected: true),
                chatID: absent, temporary: temporary)
            #expect(explicit == [enabled.id])
            #expect(provider.selectionRevision(chatID: absent, temporary: temporary) == 1)
            #expect(try await store.selection(chatID: absent, temporary: temporary) == [enabled.id])
        }
        #expect(!provider.configuration.isEnabled)
        #expect(await provider.nodeRuntime.snapshot().state == .stopped)
    }

    @Test func serverIntentFailuresBelongToTheirRequestAndDoNotPublishFalseCommits() async throws {
        let (root, provider, layout, _) = makeMCPFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let chat = UUID(), server = UUID()
        for temporary in [false, true] {
            do {
                _ = try await provider.applySelectionIntent(.init(serverID: server, isSelected: true),
                    chatID: chat, temporary: temporary)
                Issue.record("Unloaded intent must throw its own admission error")
            } catch MCPChatSelectionReadError.storageNotLoaded {} catch { Issue.record("Unexpected admission error") }
        }
        await provider.loadIfNeeded(startHost: false)
        try FileManager.default.createDirectory(at: layout.chatSelections, withIntermediateDirectories: true)
        await provider.setSelection([server], chatID: chat, temporary: false) // Existing legacy error surface.
        let oldGlobalError = try #require(provider.lastError)
        do {
            _ = try await provider.applySelectionIntent(.init(serverID: server, isSelected: true),
                chatID: chat, temporary: false)
            Issue.record("Real persistent read failure must throw, never fall back to defaults")
        } catch {}
        #expect(provider.selectionRevision(chatID: chat, temporary: false) == 0)
        #expect(provider.lastError == oldGlobalError)
        let temporary = try await provider.applySelectionIntent(.init(serverID: server, isSelected: true),
            chatID: chat, temporary: true)
        #expect(temporary == [server])
        #expect(provider.lastError == oldGlobalError) // Success is not inferred from a global error.
        #expect(provider.selectionRevision(chatID: chat, temporary: true) == 1)
    }

    @Test func serverIntentSaveFailureAfterSuccessfulReadPreservesBytesAndRevision() async throws {
        let (root, provider, layout, store) = makeMCPFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        await provider.loadIfNeeded(startHost: false)
        let chat = UUID(), retained = UUID(), added = UUID()
        await provider.setSelection([retained], chatID: chat, temporary: false)
        let originalBytes = try Data(contentsOf: layout.chatSelections)
        let attributes = try FileManager.default.attributesOfItem(atPath: layout.registry.path)
        let permissions = try #require(attributes[.posixPermissions])
        defer { try? FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: layout.registry.path) }
        // The existing JSON remains readable; its parent cannot create/rename
        // an atomic replacement. This exercises a save failure after real load.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: layout.registry.path)
        #expect(try await store.selection(chatID: chat) == [retained])
        let changes = CapabilityObservationCounter()
        withObservationTracking { _ = provider.selectionRevision(chatID: chat, temporary: false) } onChange: { changes.mark() }
        do {
            _ = try await provider.applySelectionIntent(.init(serverID: added, isSelected: true),
                chatID: chat, temporary: false)
            Issue.record("Atomic save must fail under the read-only parent")
        } catch {}
        #expect(changes.count == 0)
        #expect(provider.selectionRevision(chatID: chat, temporary: false) == 1)
        #expect(try await store.selection(chatID: chat) == [retained])
        #expect(try Data(contentsOf: layout.chatSelections) == originalBytes)
        #expect(provider.lastError == nil)
        let temporary = try await provider.applySelectionIntent(.init(serverID: added, isSelected: true),
            chatID: chat, temporary: true)
        #expect(temporary == [added])
    }

    @Test func migrationOverrideUsesOnlyItsOwnedSource() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "legacy", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source.appending(path: "registry"), withIntermediateDirectories: true)
        let bytes = Data("owned migration fixture".utf8)
        try bytes.write(to: source.appending(path: "registry/unit-sentinel.txt"))
        let enabled = MCPFileLayout(root: root.appending(path: "migrated"), legacyMigrationSource: source)
        try enabled.prepareIfNeeded()
        #expect(try Data(contentsOf: enabled.registry.appending(path: "unit-sentinel.txt")) == bytes)
        let isolated = MCPFileLayout(root: root.appending(path: "isolated"), legacyMigrationSource: nil)
        try isolated.prepareIfNeeded()
        #expect(!FileManager.default.fileExists(atPath: isolated.registry.appending(path: "unit-sentinel.txt").path))
    }

    private func makeMCPFixture() -> (URL, MCPRuntimeProvider, MCPFileLayout, MCPChatSelectionStore) {
        let root = temporaryRoot()
        let runtimeLayout = RuntimeFileLayout(root: root)
        let environment = RuntimeEnvironmentStore(fileLayout: runtimeLayout)
        let runtime = NodeRuntimeService(fileLayout: runtimeLayout, environment: environment)
        let layout = MCPFileLayout(root: root, legacyMigrationSource: nil)
        let selections = MCPChatSelectionStore(fileLayout: layout)
        return (root, MCPRuntimeProvider(runtime: runtime, fileLayout: layout, runtimeEnvironment: environment, selectionStore: selections), layout, selections)
    }

    private func mcpServer(layout: MCPFileLayout) throws -> MCPServerDescriptor {
        let id = UUID()
        let directory = layout.serverDirectory(id: id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let entry = directory.appending(path: "index.js")
        try Data("export {};".utf8).write(to: entry)
        return MCPServerDescriptor(id: id, slug: "unit-\(id.uuidString.lowercased())", displayName: "Unit server",
            packageName: "unit-server", resolvedVersion: "1.0.0", entryPoint: entry.path,
            entryPointRelativePath: "index.js", packageRoot: directory.path,
            compatibility: .init(verdict: .compatible, findings: [], runtimeProbePassed: false))
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "capability-observation-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func toolEntry() -> NativeToolCatalogEntry {
        NativeToolCatalogEntry(name: "unit_capability", title: "Unit tool", summary: "Unit summary",
            presentationProfile: .generic(toolName: "unit_capability"))
    }
}
