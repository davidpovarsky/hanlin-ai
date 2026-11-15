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
        let (root, provider, layout) = makeMCPFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        await provider.loadIfNeeded(startHost: false)
        #expect(provider.persistentLoadState == .loaded)
        let firstChat = UUID(), otherChat = UUID()
        let firstIDs: Set<UUID> = [UUID()], otherIDs: Set<UUID> = [UUID()]
        await provider.setSelection(otherIDs, chatID: otherChat, temporary: false)
        let revision = provider.selectionRevision
        let changes = CapabilityObservationCounter()
        withObservationTracking { _ = provider.selectionRevision } onChange: { changes.mark() }
        await provider.setSelection(firstIDs, chatID: firstChat, temporary: false)
        #expect(changes.count == 1)
        #expect(provider.selectionRevision == revision + 1)
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
        let (root, provider, layout) = makeMCPFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        await provider.loadIfNeeded(startHost: false)
        #expect(provider.persistentLoadState == .loaded)
        // A real directory at the JSON path makes the real actor store read fail.
        try FileManager.default.createDirectory(at: layout.chatSelections, withIntermediateDirectories: true)
        let changes = CapabilityObservationCounter()
        withObservationTracking { _ = provider.selectionRevision } onChange: { changes.mark() }
        await provider.setSelection([UUID()], chatID: UUID(), temporary: false)
        #expect(provider.selectionRevision == 0)
        #expect(changes.count == 0)
        #expect(provider.lastError != nil)
    }

    @Test func unloadedMCPSelectionKeepsTheExistingAdmissionGuard() async {
        let (root, provider, layout) = makeMCPFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        await provider.setSelection([UUID()], chatID: UUID(), temporary: false)
        #expect(provider.persistentLoadState == .notLoaded)
        #expect(provider.selectionRevision == 0)
        #expect(!FileManager.default.fileExists(atPath: layout.chatSelections.path))
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

    private func makeMCPFixture() -> (URL, MCPRuntimeProvider, MCPFileLayout) {
        let root = temporaryRoot()
        let runtimeLayout = RuntimeFileLayout(root: root)
        let environment = RuntimeEnvironmentStore(fileLayout: runtimeLayout)
        let runtime = NodeRuntimeService(fileLayout: runtimeLayout, environment: environment)
        let layout = MCPFileLayout(root: root, legacyMigrationSource: nil)
        return (root, MCPRuntimeProvider(runtime: runtime, fileLayout: layout, runtimeEnvironment: environment), layout)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "capability-observation-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func toolEntry() -> NativeToolCatalogEntry {
        NativeToolCatalogEntry(name: "unit_capability", title: "Unit tool", summary: "Unit summary",
            presentationProfile: .generic(toolName: "unit_capability"))
    }
}
