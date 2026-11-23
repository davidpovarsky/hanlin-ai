import Foundation
import Testing
@testable import AI_Hanlin

@MainActor
@Suite("Original MCP embedding", .serialized)
struct HanlinMCPEmbeddingTests {
    @Test func conversationSelectionKeepsOriginalDefaultsExplicitEmptyAndOtherChats() async throws {
        let fixture = try await fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let firstChat = UUID(), otherChat = UUID()
        let valid = Set([firstChat, otherChat])
        let mcp = HanlinApplicationMCP(provider: fixture.provider) { id in
            guard valid.contains(id) else { throw HanlinApplicationError.conversationNotFound(id) }
        }
        try await mcp.load()
        #expect(Set(mcp.servers.map(\.id)) == Set(fixture.servers.map(\.id)))
        let defaults = Set(fixture.servers.map(\.id))
        #expect(try await mcp.selectedServers(for: firstChat) == defaults)
        _ = try await mcp.setServer(fixture.servers[0].id, selected: false, for: firstChat)
        _ = try await mcp.setServer(fixture.servers[1].id, selected: false, for: firstChat)
        #expect(try await mcp.selectedServers(for: firstChat).isEmpty)
        #expect(try await mcp.selectedServers(for: otherChat) == defaults)
        let store = MCPChatSelectionStore(fileLayout: fixture.layout)
        #expect(try await store.selection(chatID: firstChat) == [])
        #expect(try await store.selection(chatID: otherChat) == nil)
        let bytes = try Data(contentsOf: fixture.layout.chatSelections)
        do {
            _ = try await mcp.setServer(fixture.servers[0].id, selected: true, for: UUID())
            Issue.record("A foreign conversation must not get an MCP selection row.")
        } catch HanlinApplicationError.conversationNotFound {} catch { throw error }
        #expect(try Data(contentsOf: fixture.layout.chatSelections) == bytes)
        #expect(await fixture.provider.nodeRuntime.snapshot().state == .stopped)
    }

    @Test func failedSelectionReadCannotRestoreDefaultMCPAuthority() async throws {
        let fixture = try await fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        await fixture.provider.loadIfNeeded()
        try await fixture.provider.setEnabledReporting(true)
        let chat = UUID()
        // The real file store throws when its expected JSON path is a directory.
        try FileManager.default.createDirectory(at: fixture.layout.chatSelections,
            withIntermediateDirectories: true)
        do {
            _ = try await fixture.provider.readSelection(chatID: chat, temporary: false)
            Issue.record("The actual corrupted selection must throw.")
        } catch {}
        let scope = await fixture.provider.requestScope(chatID: chat, temporary: false)
        #expect(scope.mcpServerIDs.isEmpty)
        #expect(!scope.mcpGloballyEnabled)
        #expect(fixture.provider.lastError != nil)
        #expect(await fixture.provider.nodeRuntime.snapshot().state == .stopped)
    }

    @Test func failedFeatureCommitDoesNotPublishSuccessOrStartRuntime() async throws {
        let fixture = try await fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let mcp = HanlinApplicationMCP(provider: fixture.provider, validateConversation: { _ in })
        try await mcp.load()
        #expect(!mcp.configuration.isEnabled)
        try FileManager.default.createDirectory(at: fixture.layout.featureConfiguration,
            withIntermediateDirectories: true)
        do {
            try await mcp.setEnabled(true)
            Issue.record("A failed real configuration write must propagate its error.")
        } catch {}
        #expect(!mcp.configuration.isEnabled)
        #expect(mcp.lastError != nil)
        #expect(await fixture.provider.nodeRuntime.snapshot().state == .stopped)
    }

    @Test func staleEditableSettingsPreserveCurrentEnvironmentAndPackageIdentity() async throws {
        let fixture = try await fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let mcp = HanlinApplicationMCP(provider: fixture.provider, validateConversation: { _ in })
        try await mcp.load()
        let server = try #require(mcp.servers.first)
        var edits = MCPServerSettings(server: server)
        edits.displayName = "Host-edited display"
        edits.arguments = ["--current-work"]
        // Simulate another original writer committing after the settings were read.
        var newer = server
        newer.environment = [.init(name: "TOKEN", value: nil, secretReference: "synthetic-reference-only")]
        _ = try await MCPServerRegistryStore(fileLayout: fixture.layout).upsert(newer)
        let saved = try await mcp.updateServer(server.id, settings: edits)
        #expect(saved.displayName == "Host-edited display")
        #expect(saved.arguments == ["--current-work"])
        #expect(saved.environment == newer.environment)
        #expect(saved.environment.first?.value == nil)
        #expect(saved.resolvedVersion == newer.resolvedVersion)
        #expect(saved.integrity == newer.integrity)
        let disk = try await MCPServerRegistryStore(fileLayout: fixture.layout).load()
        #expect(disk.first(where: { $0.id == server.id }) == saved)
        var replaced = saved
        replaced.resolvedVersion = "2.0.0"
        replaced.integrity = "newer-installer-integrity"
        replaced.entryPoint = replaced.packageRoot + "/new-entry.js"
        _ = try await MCPServerRegistryStore(fileLayout: fixture.layout).upsert(replaced)
        do {
            _ = try await mcp.updateServer(server.id, settings: edits)
            Issue.record("Stale entry-point settings must not overwrite a replaced package.")
        } catch HanlinApplicationMCPError.installationChanged {} catch { throw error }
        let retained = try await MCPServerRegistryStore(fileLayout: fixture.layout).load()
        #expect(retained.first(where: { $0.id == server.id }) == replaced)
    }

    @Test func disabledRuntimeOperationsReturnTheirOwnFailure() async throws {
        let fixture = try await fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let mcp = HanlinApplicationMCP(provider: fixture.provider, validateConversation: { _ in })
        try await mcp.load()
        let id = fixture.servers[0].id
        for operation in 0..<4 {
            do {
                switch operation {
                case 0: try await mcp.start(id)
                case 1: try await mcp.restart(id)
                case 2: try await mcp.refreshTools(id)
                default: _ = try await mcp.tools(for: id)
                }
                Issue.record("A disabled original feature must not start a server.")
            } catch MCPError.featureDisabled {} catch { throw error }
        }
        #expect(!mcp.configuration.isEnabled)
        #expect(await fixture.provider.nodeRuntime.snapshot().state == .stopped)
    }

    @Test func selectionAcknowledgementRejectsAConversationDeletedDuringCommit() async throws {
        let delay = MCPEmbeddingSelectionDelay()
        let fixture = try await fixture(admission: { await delay.wait() })
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let conversation = UUID()
        var exists = true
        let mcp = HanlinApplicationMCP(provider: fixture.provider) { id in
            guard id == conversation, exists else {
                throw HanlinApplicationError.conversationNotFound(id)
            }
        }
        let operation = Task { @MainActor in
            try await mcp.setServer(fixture.servers[0].id, selected: false, for: conversation)
        }
        await delay.waitUntilArrived()
        exists = false
        await delay.release()
        do {
            _ = try await operation.value
            Issue.record("A stale conversation must not receive a successful selection acknowledgement.")
        } catch HanlinApplicationError.conversationNotFound {} catch { throw error }
    }

    @Test func overlappingAdministrationCannotReplaceCredentialsOrDisableAnAdmittedOperation() async throws {
        let delay = MCPEmbeddingSelectionDelay()
        let fixture = try await fixture(administration: { await delay.wait() })
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let mcp = HanlinApplicationMCP(provider: fixture.provider, validateConversation: { _ in })
        try await mcp.load()
        let original = try Data(contentsOf: fixture.layout.serverRegistry)
        let archive = try MCPPackageSpec(localArchive: fixture.root.appending(path: "missing.tgz"))
        let preview = Task { @MainActor in try await mcp.preview(archive) }
        await delay.waitUntilArrived()
        #expect(mcp.isPerformingAdministration)
        do {
            _ = try await mcp.updateEnvironment([], for: fixture.servers[0].id)
            Issue.record("Overlapping administration must not mutate credentials.")
        } catch HanlinApplicationMCPError.operationInProgress {} catch { throw error }
        do {
            try await mcp.setEnabled(true)
            Issue.record("Overlapping administration must not change runtime admission.")
        } catch HanlinApplicationMCPError.operationInProgress {} catch { throw error }
        #expect(try Data(contentsOf: fixture.layout.serverRegistry) == original)
        #expect(!mcp.configuration.isEnabled)
        await delay.release()
        do {
            _ = try await preview.value
            Issue.record("The missing original local archive must report a real I/O failure.")
        } catch {}
        #expect(!mcp.isPerformingAdministration)
        #expect(await fixture.provider.nodeRuntime.snapshot().state == .stopped)
    }

    @Test func cancellationBeforeInstallerProgressDoesNotStartRuntimeAndReleasesOnlyItsLease() async throws {
        let delay = MCPEmbeddingSelectionDelay()
        let fixture = try await fixture(administration: { await delay.wait() })
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let mcp = HanlinApplicationMCP(provider: fixture.provider, validateConversation: { _ in })
        let spec = try MCPPackageSpec(localArchive: fixture.root.appending(path: "missing.tgz"))
        let installation = Task { @MainActor in try await mcp.install(spec) }
        await delay.waitUntilArrived()
        #expect(mcp.isPerformingAdministration)
        await mcp.cancelInstall()
        await delay.release()
        do {
            _ = try await installation.value
            Issue.record("An early explicit cancellation must end this installation.")
        } catch is CancellationError {} catch { throw error }
        #expect(mcp.installState == .cancelled)
        #expect(!mcp.isPerformingAdministration)
        #expect(await fixture.provider.nodeRuntime.snapshot().state == .stopped)
        // The completed installation's control cannot prevent the next request.
        await mcp.cancelInstall()
        try await mcp.setEnabled(true)
        #expect(mcp.configuration.isEnabled)
    }

    @Test func duplicateEnvironmentNamesFailBeforePersistenceAndCannotCrashRuntimeAssembly() async throws {
        let fixture = try await fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let mcp = HanlinApplicationMCP(provider: fixture.provider, validateConversation: { _ in })
        try await mcp.load()
        let original = try Data(contentsOf: fixture.layout.serverRegistry)
        let values = [
            MCPEnvironmentDraft(name: " TOKEN ", value: "synthetic-first", isSecret: true),
            MCPEnvironmentDraft(name: "TOKEN", value: "synthetic-second", isSecret: true)
        ]
        do {
            _ = try await mcp.updateEnvironment(values, for: fixture.servers[0].id)
            Issue.record("Duplicate normalized names must fail before any environment commit.")
        } catch MCPError.duplicateEnvironmentName(let name) {
            #expect(name == "TOKEN")
        } catch { throw error }
        #expect(try Data(contentsOf: fixture.layout.serverRegistry) == original)
        var damaged = fixture.servers[0]
        damaged.environment = [
            .init(name: "TOKEN", value: "first", secretReference: nil),
            .init(name: "TOKEN", value: "second", secretReference: nil)
        ]
        do {
            _ = try MCPServerConfiguration.make(descriptor: damaged, resolvedPaths: .init(
                packageRoot: URL(fileURLWithPath: damaged.packageRoot),
                entryPoint: URL(fileURLWithPath: damaged.entryPoint),
                entryPointRelativePath: "index.js", requiredMigration: false))
            Issue.record("A damaged original environment must throw instead of trapping in Dictionary.")
        } catch MCPError.duplicateEnvironmentName(let name) {
            #expect(name == "TOKEN")
        } catch { throw error }
    }

    @Test func duplicatePersistentIdentitiesProduceErrorsInsteadOfTrapsOrAmbiguousRows() async throws {
        let fixture = try await fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        await fixture.provider.loadIfNeeded()
        let chat = UUID()
        let duplicateSelections = [
            MCPChatSelection(chatID: chat, serverIDs: [fixture.servers[0].id]),
            MCPChatSelection(chatID: chat, serverIDs: [fixture.servers[1].id])
        ]
        try JSONEncoder.mcp.encode(duplicateSelections).write(to: fixture.layout.chatSelections)
        do {
            _ = try await fixture.provider.readSelection(chatID: chat, temporary: false)
            Issue.record("Duplicate original conversation identities must not select an arbitrary row.")
        } catch DecodingError.dataCorrupted {} catch { throw error }
        let scope = await fixture.provider.requestScope(chatID: chat, temporary: false)
        #expect(scope.mcpServerIDs.isEmpty && !scope.mcpGloballyEnabled)
        let bytes = try Data(contentsOf: fixture.layout.serverRegistry)
        do {
            try await MCPServerRegistryStore(fileLayout: fixture.layout).save(
                [fixture.servers[0], fixture.servers[0]])
            Issue.record("An ambiguous server registry must not replace a valid generation.")
        } catch MCPServerRegistryError.writeVerificationFailed {} catch { throw error }
        #expect(try Data(contentsOf: fixture.layout.serverRegistry) == bytes)
    }

    private func fixture(
        admission: (@Sendable () async -> Void)? = nil,
        administration: (@Sendable () async -> Void)? = nil
    ) async throws -> (root: URL, layout: MCPFileLayout, provider: MCPRuntimeProvider,
                      servers: [MCPServerDescriptor]) {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "hanlin-mcp-embedding-" + UUID().uuidString, directoryHint: .isDirectory)
        let runtimeLayout = RuntimeFileLayout(root: root)
        let environment = RuntimeEnvironmentStore(fileLayout: runtimeLayout)
        let runtime = NodeRuntimeService(fileLayout: runtimeLayout, environment: environment)
        let layout = MCPFileLayout(root: root, legacyMigrationSource: nil)
        try layout.prepareIfNeeded()
        let servers = try (0..<2).map { index in
            let id = UUID()
            let directory = layout.serverDirectory(id: id)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("export {};".utf8).write(to: directory.appending(path: "index.js"))
            return MCPServerDescriptor(id: id, slug: "fixture-\(index)", displayName: "Fixture \(index)",
                packageName: "fixture-\(index)", resolvedVersion: "1.0.0",
                entryPoint: directory.appending(path: "index.js").path,
                entryPointRelativePath: "index.js", packageRoot: directory.path,
                compatibility: .init(verdict: .compatible, findings: [], runtimeProbePassed: false))
        }
        try await MCPServerRegistryStore(fileLayout: layout).save(servers)
        let provider = MCPRuntimeProvider(runtime: runtime, fileLayout: layout,
            runtimeEnvironment: environment, selectionIntentAdmission: admission,
            administrationAdmission: administration)
        return (root, layout, provider, servers)
    }
}

private actor MCPEmbeddingSelectionDelay {
    private var arrived = false
    private var released = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        arrived = true
        arrival?.resume()
        arrival = nil
        guard !released else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilArrived() async {
        guard !arrived else { return }
        await withCheckedContinuation { arrival = $0 }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}
