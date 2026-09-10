import Foundation
import HanlinPlatformContracts
import Testing
@testable import AI_Hanlin

@Suite("Canonical downstream adapters", .serialized)
struct CanonicalAdapterTests {
    @MainActor
    @Test("Native app projection is stable and rejects invalid identity")
    func nativeApplicationProjection() throws {
        let manifest = TestFixtures.nativeManifest()
        let revision = try HanlinDescriptorRevision(1)
        let version = try HanlinPackageVersion(validating: "0.7.3")
        let capabilities = [
            NativeCapabilityRequest.network(
                domain: "example.com",
                reason: "Read public reference data"
            )
        ]
        let first = try NativeAppCanonicalShadowAdapter.project(
            manifest: manifest,
            capabilities: capabilities,
            hostVersion: version,
            descriptorRevision: revision
        )
        let repeated = try NativeAppCanonicalShadowAdapter.project(
            manifest: manifest,
            capabilities: capabilities,
            hostVersion: version,
            descriptorRevision: revision
        )
        #expect(first.descriptor == repeated.descriptor)
        #expect(first.descriptor.id.rawValue == manifest.id)
        #expect(first.descriptor.capabilities.map(\.id.rawValue) == ["network.fetch"])

        let invalid = TestFixtures.nativeManifest(id: "Invalid App ID")
        #expect(throws: HanlinContractError.self) {
            try NativeAppCanonicalShadowAdapter.project(
                manifest: invalid,
                capabilities: [],
                hostVersion: version,
                descriptorRevision: revision
            )
        }
    }

    @MainActor
    @Test("ChatCard entry point projects to canonical embeddedResult")
    func chatCardProjectsToEmbeddedResult() throws {
        var manifest = TestFixtures.nativeManifest(id: "test.chatcard.app")
        manifest = NativeAppManifest(
            id: "test.chatcard.app",
            title: "Chat Card Test",
            subtitle: "Embedded presentation fixture",
            description: "Tests chatCard projection to embeddedResult.",
            systemImage: "bubble.left.and.bubble.right",
            category: .knowledge,
            entryPoints: [.fullApp, .assistantTool, .chatCard],
            keywords: ["test"],
            appearance: .init(startHex: "112233", endHex: "445566")
        )
        let projection = try NativeAppCanonicalShadowAdapter.project(
            manifest: manifest,
            capabilities: [],
            hostVersion: try HanlinPackageVersion(validating: "1.0.0"),
            descriptorRevision: try HanlinDescriptorRevision(1)
        )
        let entryPointKinds = projection.descriptor.entryPoints.map(\.kind)
        #expect(entryPointKinds.contains(.embeddedResult))
        #expect(entryPointKinds.contains(.app))
        #expect(entryPointKinds.contains(.assistantTool))
        let chatCardFindings = projection.findings.filter {
            $0.path.contains("chatCard")
        }
        #expect(chatCardFindings.isEmpty)
    }

    @MainActor
    @Test("Built-in canonical registrations validate cleanly and discover")
    func builtinCanonicalRegistrations() async throws {
        #expect(BuiltinCanonicalRegistrations.all.count == 3)

        for registration in BuiltinCanonicalRegistrations.all {
            let descriptor = try registration.appDescriptor()
            try descriptor.validate()
            #expect(descriptor.id.rawValue.hasPrefix("nativeapp."))
            #expect(descriptor.entryPoints.contains { $0.kind == .embeddedResult })
            #expect(descriptor.entryPoints.contains { $0.kind == .app })
            #expect(descriptor.entryPoints.contains { $0.kind == .assistantTool })
        }

        let discovery = BuiltinMiniAppDiscovery()
        let registrations = try await discovery.registrations()
        #expect(registrations.count == 3)

        let snapshot = try await discovery.catalogSnapshot(revision: .init(1))
        #expect(snapshot.apps.count == 3)
    }

    @MainActor
    @Test("NativeBuiltinRuntimeBinding resolves canonical tool IDs and card handlers")
    func builtinRuntimeBindings() {
        let tools = [
            "sefaria_search",
            "sefaria_get_source",
            "wikipedia_search",
            "wikipedia_get_summary",
            "text_analyze",
            "text_transform"
        ]
        for toolName in tools {
            let tool = NativeBuiltinRuntimeBinding.resolveTool(named: toolName)
            #expect(tool != nil)
            #expect(tool?.name == toolName)
        }

        let cards = [
            "nativeapp.sefaria.source.card",
            "nativeapp.wikipedia.summary.card",
            "nativeapp.textstudio.analysis.card"
        ]
        for cardHandler in cards {
            let card = NativeBuiltinRuntimeBinding.resolveChatCard(handler: cardHandler)
            #expect(card != nil)
            #expect(card?.id == cardHandler)
        }
    }

    @MainActor
    @Test("Native app modules derive manifest and capabilities from canonical descriptor")
    func appModulesDeriveFromCanonicalDescriptor() {
        let sefaria = NativeAppSefariaAppModule()
        #expect(sefaria.manifest.title == "Sefaria")
        #expect(sefaria.manifest.subtitle == "Search, read, save and revisit sources")
        #expect(sefaria.manifest.systemImage == "books.vertical.fill")
        #expect(sefaria.manifest.appearance.startHex == "5CB88A")
        #expect(!sefaria.capabilities(context: NativeAppContext()).isEmpty)

        let wikipedia = NativeAppWikipediaAppModule()
        #expect(wikipedia.manifest.title == "Wikipedia")
        #expect(wikipedia.manifest.subtitle == "Explore, save and revisit knowledge")
        #expect(wikipedia.manifest.systemImage == "globe.americas.fill")
        #expect(wikipedia.manifest.appearance.startHex == "4C83E8")
        #expect(!wikipedia.capabilities(context: NativeAppContext()).isEmpty)

        let textStudio = NativeAppTextStudioAppModule()
        #expect(textStudio.manifest.title == "Text Studio")
        #expect(textStudio.manifest.subtitle == "Write, inspect, transform and keep history")
        #expect(textStudio.manifest.systemImage == "textformat.alt")
        #expect(textStudio.manifest.appearance.startHex == "F06FB5")
    }

    @MainActor
    @Test("Native tool projection preserves qualified identity and rejects schema mismatch")
    func nativeToolProjection() throws {
        let tool = QuickCalculateTool()
        let revision = try HanlinDescriptorRevision(1)
        let first = try NativeToolCanonicalShadowAdapter.project(
            tool: tool,
            entry: tool.catalogEntry,
            descriptorRevision: revision
        )
        let repeated = try NativeToolCanonicalShadowAdapter.project(
            tool: tool,
            entry: tool.catalogEntry,
            descriptorRevision: revision
        )
        #expect(first.descriptor == repeated.descriptor)
        #expect(first.descriptor.logicalID.providerInstanceID.rawValue == "native.system")
        #expect(first.descriptor.logicalID.localToolID.rawValue == tool.name)
        #expect(first.descriptor.outputSchema == nil)
        #expect(first.findings.count == 2)

        var mismatchedEntry = tool.catalogEntry
        mismatchedEntry.name = "different_name"
        #expect(throws: HanlinContractError.self) {
            try NativeToolCanonicalShadowAdapter.project(
                tool: tool,
                entry: mismatchedEntry,
                descriptorRevision: revision
            )
        }
    }

    @Test("MCP projections preserve provider, tool, schema, alias, and runtime state")
    func mcpProjection() throws {
        let server = TestFixtures.mcpServer()
        let provider = try MCPCanonicalShadowAdapter.projectProvider(server)
        #expect(provider.id.rawValue == server.id.uuidString.lowercased())
        #expect(provider.providerID.rawValue == "mcp")
        #expect(provider.configuration.secretReferences == ["TOKEN": "keychain.token"])

        let tool = TestFixtures.mcpTool(serverID: server.id)
        let snapshot = try MCPCanonicalShadowAdapter.projectTools(
            [tool],
            revision: .init(1),
            descriptorRevision: HanlinDescriptorRevision(1)
        )
        #expect(snapshot.entries.count == 1)
        #expect(snapshot.entries[0].modelAlias == tool.exposedName)
        #expect(snapshot.entries[0].descriptor.logicalID.localToolID.rawValue == tool.originalName)

        let sessionID = try HanlinRuntimeSessionID(validating: "runtime.test.mcp")
        let runtime = try MCPCanonicalShadowAdapter.projectRuntime(
            .init(
                state: .running,
                nodeVersion: "24.5.0",
                protocolVersion: 1,
                activeWorkerCount: 2,
                message: nil
            ),
            sessionID: sessionID,
            createdAt: .distantPast,
            observedAt: .distantPast
        )
        #expect(runtime.kind == .mcp)
        #expect(runtime.state == .ready)
        #expect(runtime.activeExecutionCount == 2)
    }

    @Test("MCP projection rejects duplicate secret names and malformed schemas")
    func mcpRejections() {
        var duplicateSecrets = TestFixtures.mcpServer()
        duplicateSecrets.environment.append(
            .init(name: "TOKEN", value: nil, secretReference: "keychain.other")
        )
        #expect(throws: HanlinContractError.self) {
            try MCPCanonicalShadowAdapter.projectProvider(duplicateSecrets)
        }

        var invalidTool = TestFixtures.mcpTool(serverID: duplicateSecrets.id)
        invalidTool.inputSchemaJSON = Data(#"{"type":"object","x":1,"x":2}"#.utf8)
        #expect(throws: HanlinContractError.self) {
            try MCPCanonicalShadowAdapter.projectTools(
                [invalidTool],
                revision: .init(1),
                descriptorRevision: HanlinDescriptorRevision(1)
            )
        }
    }

    @Test("RuntimeCore projection is deterministic and does not invent integer provenance")
    func runtimeCoreProjection() throws {
        let source = RuntimeSnapshot(
            kind: .typeScript,
            state: .executing,
            version: "6.0.3",
            source: "bundled",
            lastHealthCheck: nil,
            lastErrorCode: nil,
            storageBytes: 10,
            cacheBytes: 20,
            activeExecutionCount: 1,
            packageCount: 3
        )
        let sessionID = try HanlinRuntimeSessionID(validating: "runtime.test.typescript")
        let providerID = try HanlinProviderInstanceID(validating: "runtime.typescript")
        let first = RuntimeCoreCanonicalShadowAdapter.project(
            source,
            sessionID: sessionID,
            providerInstanceID: providerID,
            createdAt: .distantPast,
            observedAt: .distantPast
        )
        let repeated = RuntimeCoreCanonicalShadowAdapter.project(
            source,
            sessionID: sessionID,
            providerInstanceID: providerID,
            createdAt: .distantPast,
            observedAt: .distantPast
        )
        #expect(first == repeated)
        #expect(first.kind == .typeScript)
        #expect(first.state == .executing)
        #expect(first.activeExecutionCount == 1)

        guard case let .number(number) = try RuntimeCoreCanonicalShadowAdapter.projectJSONValue(
            .number(1.0)
        ) else {
            Issue.record("Runtime binary64 value did not remain a canonical number.")
            return
        }
        #expect(number.bitPattern == 1.0.bitPattern)
        #expect(throws: HanlinContractError.self) {
            try RuntimeCoreCanonicalShadowAdapter.projectJSONValue(.number(.nan))
        }
    }
}

enum TestFixtures {
    static let serverID = UUID(uuid: (
        0x11, 0x11, 0x11, 0x11,
        0x22, 0x22,
        0x33, 0x33,
        0x44, 0x44,
        0x55, 0x55, 0x55, 0x55, 0x55, 0x55
    ))

    static func nativeManifest(id: String = "test.app") -> NativeAppManifest {
        NativeAppManifest(
            id: id,
            title: "Test App",
            subtitle: "Canonical fixture",
            description: "A deterministic native app fixture.",
            systemImage: "checkmark.circle",
            category: .developer,
            entryPoints: [.fullApp, .assistantTool],
            keywords: ["fixture"],
            appearance: .init(startHex: "112233", endHex: "445566")
        )
    }

    static func mcpServer() -> MCPServerDescriptor {
        MCPServerDescriptor(
            id: serverID,
            slug: "test_server",
            displayName: "Test Server",
            packageName: "test-server",
            resolvedVersion: "1.0.0",
            entryPoint: "/not-observed/server.mjs",
            environment: [
                .init(name: "TOKEN", value: nil, secretReference: "keychain.token")
            ],
            packageRoot: "/not-observed",
            compatibility: .pendingProbe
        )
    }

    static func mcpTool(serverID: UUID = TestFixtures.serverID) -> MCPToolDescriptor {
        MCPToolDescriptor(
            serverID: serverID,
            serverSlug: "test_server",
            serverDisplayName: "Test Server",
            originalName: "echo",
            exposedName: "mcp__test_server__echo",
            title: "Echo",
            summary: "Echo a value",
            inputSchemaJSON: Data(
                #"{"type":"object","properties":{"value":{"type":"string"}},"required":["value"]}"#.utf8
            )
        )
    }
}
