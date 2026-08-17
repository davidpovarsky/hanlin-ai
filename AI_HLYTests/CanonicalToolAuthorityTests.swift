import Foundation
import HanlinPlatformContracts
import Testing
@testable import AI_Hanlin

@Suite("Canonical Native and MCP tool authority", .serialized)
struct CanonicalToolAuthorityTests {
    @MainActor
    @Test("Builds one canonical catalog with closed backend routes")
    func combinedCatalogAndRoutes() throws {
        let native = nativeSource(name: "quick_calculate")
        let mcp = TestFixtures.mcpTool()
        let authority = try HanlinCanonicalToolAuthority.build(
            nativeSources: [native],
            mcpTools: [mcp],
            generatedAt: Date(timeIntervalSince1970: 1)
        )

        #expect(authority.catalog.entries.count == 2)
        #expect(authority.routingTable.routes.count == 2)
        #expect(authority.backendRoutes.count == 2)
        #expect(authority.modelSchemas.count == 2)
        #expect(authority.catalog.revision == authority.routingTable.revision)
        #expect(authority.catalog.entries.compactMap(\.modelAlias) == [
            "quick_calculate",
            "mcp__test_server__echo"
        ])

        let nativeResolution = authority.resolution(alias: "quick_calculate")
        if case let .native(provider, toolName)? = nativeResolution?.backend {
            #expect(provider.rawValue == "native.system")
            #expect(toolName == "quick_calculate")
        } else {
            Issue.record("Native alias did not resolve to the Native backend")
        }
        let mcpResolution = authority.resolution(alias: "mcp__test_server__echo")
        if case let .mcp(serverID, toolName)? = mcpResolution?.backend {
            #expect(serverID == mcp.serverID)
            #expect(toolName == mcp.originalName)
        } else {
            Issue.record("MCP alias did not resolve to the MCP backend")
        }
        if case .some = authority.resolution(alias: "unknown") {
            Issue.record("Unknown alias unexpectedly resolved")
        }
    }

    @MainActor
    @Test("Supports empty, Native-only, and MCP-only catalogs")
    func catalogShapes() throws {
        let empty = try HanlinCanonicalToolAuthority.build(
            nativeSources: [],
            mcpTools: []
        )
        #expect(empty.catalog.entries.isEmpty)
        #expect(empty.routingTable.routes.isEmpty)
        #expect(empty.backendRouteIndex.records.isEmpty)

        let nativeOnly = try HanlinCanonicalToolAuthority.build(
            nativeSources: [nativeSource(name: "native_only")],
            mcpTools: []
        )
        #expect(nativeOnly.catalog.entries.count == 1)
        if case .native? = nativeOnly.resolution(alias: "native_only")?.backend {
            // Expected.
        } else {
            Issue.record("Native-only catalog did not retain its backend")
        }

        let mcpOnly = try HanlinCanonicalToolAuthority.build(
            nativeSources: [],
            mcpTools: [TestFixtures.mcpTool()]
        )
        #expect(mcpOnly.catalog.entries.count == 1)
        if case .mcp? = mcpOnly.resolution(alias: "mcp__test_server__echo")?.backend {
            // Expected.
        } else {
            Issue.record("MCP-only catalog did not retain its backend")
        }
    }

    @MainActor
    @Test("Catalog and aliases are deterministic across discovery order")
    func deterministicDiscoveryOrder() throws {
        let firstID = try #require(
            UUID(uuidString: "11111111-1111-4111-8111-111111111111")
        )
        let secondID = try #require(
            UUID(uuidString: "22222222-2222-4222-8222-222222222222")
        )
        let firstTool = mcpTool(serverID: firstID, exposedName: "legacy_first")
        let secondTool = mcpTool(serverID: secondID, exposedName: "legacy_second")
        let generatedAt = Date(timeIntervalSince1970: 2)

        let forward = try HanlinCanonicalToolAuthority.build(
            nativeSources: [],
            mcpTools: [firstTool, secondTool],
            generatedAt: generatedAt
        )
        let reverse = try HanlinCanonicalToolAuthority.build(
            nativeSources: [],
            mcpTools: [secondTool, firstTool],
            generatedAt: generatedAt
        )

        #expect(forward.catalog == reverse.catalog)
        #expect(forward.routingTable == reverse.routingTable)
        #expect(try canonicalJSON(forward.modelSchemas) == canonicalJSON(reverse.modelSchemas))
        let aliases = forward.catalog.entries.compactMap(\.modelAlias)
        #expect(aliases.first == "mcp__test_server__echo")
        #expect(aliases[1].hasPrefix("mcp__test_server__echo_"))
        #expect(aliases.count == Set(aliases).count)
        if case let .mcp(firstServerID, _)? = forward.resolution(alias: aliases[0])?.backend,
           case let .mcp(secondServerID, _)? = forward.resolution(alias: aliases[1])?.backend {
            #expect(firstServerID == firstID)
            #expect(secondServerID == secondID)
        } else {
            Issue.record("MCP collision aliases did not retain deterministic backends")
        }
    }

    @MainActor
    @Test("Native keeps a colliding alias and MCP receives a stable suffix")
    func nativeFirstCollisionPolicy() throws {
        let collidingName = "mcp__test_server__echo"
        let authority = try HanlinCanonicalToolAuthority.build(
            nativeSources: [nativeSource(
                name: "native_collision_fixture",
                preferredAlias: collidingName
            )],
            mcpTools: [TestFixtures.mcpTool()]
        )
        let aliases = authority.catalog.entries.compactMap(\.modelAlias)

        #expect(aliases.first == collidingName)
        #expect(aliases.count == 2)
        #expect(aliases[1].hasPrefix("mcp__test_server__echo_"))
        #expect(aliases[1].count <= 64)
        if case .native? = authority.resolution(alias: aliases[0])?.backend {
            // Expected.
        } else {
            Issue.record("The colliding Native alias lost precedence")
        }
        if case .mcp? = authority.resolution(alias: aliases[1])?.backend {
            // Expected.
        } else {
            Issue.record("The suffixed alias did not route to MCP")
        }
    }

    @MainActor
    @Test("Rejects duplicate logical tools and invalid model schemas")
    func rejectsInvalidAuthorityInputs() {
        let duplicate = TestFixtures.mcpTool()
        #expect(throws: HanlinCanonicalToolAuthorityError.self) {
            try HanlinCanonicalToolAuthority.build(
                nativeSources: [],
                mcpTools: [duplicate, duplicate]
            )
        }

        var duplicateLocalID = duplicate
        duplicateLocalID.exposedName = "a_different_discovery_alias"
        #expect(throws: HanlinCanonicalToolAuthorityError.self) {
            try HanlinCanonicalToolAuthority.build(
                nativeSources: [],
                mcpTools: [duplicate, duplicateLocalID]
            )
        }

        var invalid = nativeSource(name: "invalid_schema")
        invalid = .init(
            entry: invalid.entry,
            canonicalSchema: invalid.canonicalSchema,
            modelSchema: ["type": "function"]
        )
        #expect(throws: HanlinCanonicalToolAuthorityError.self) {
            try HanlinCanonicalToolAuthority.build(
                nativeSources: [invalid],
                mcpTools: []
            )
        }

        #expect(throws: HanlinCanonicalToolAuthorityError.self) {
            try HanlinCanonicalToolAuthority.build(
                nativeSources: [
                    nativeSource(name: "first", preferredAlias: "same_alias"),
                    nativeSource(name: "second", preferredAlias: "same_alias")
                ],
                mcpTools: []
            )
        }

        #expect(throws: HanlinContractError.self) {
            try HanlinCanonicalToolAuthority.build(
                nativeSources: [nativeSource(name: "")],
                mcpTools: []
            )
        }

        var malformedMCP = TestFixtures.mcpTool()
        malformedMCP.originalName = ""
        #expect(throws: HanlinContractError.self) {
            try HanlinCanonicalToolAuthority.build(
                nativeSources: [],
                mcpTools: [malformedMCP]
            )
        }

        var malformedMCPSchema = TestFixtures.mcpTool()
        malformedMCPSchema.inputSchemaJSON = Data("[]".utf8)
        #expect(throws: HanlinContractError.self) {
            try HanlinCanonicalToolAuthority.build(
                nativeSources: [],
                mcpTools: [malformedMCPSchema]
            )
        }
    }

    @MainActor
    @Test("Preserves model schema content except for canonical alias allocation")
    func preservesModelSchemas() throws {
        let serverID = try #require(
            UUID(uuidString: "33333333-3333-4333-8333-333333333333")
        )
        let tool = mcpTool(
            serverID: serverID,
            exposedName: "legacy_alias"
        )
        let authority = try HanlinCanonicalToolAuthority.build(
            nativeSources: [],
            mcpTools: [tool]
        )
        let source = try tool.openAIToolSchema()
        let output = try #require(authority.modelSchemas.first)
        let outputFunction = try #require(output["function"] as? [String: Any])
        let sourceFunction = try #require(source["function"] as? [String: Any])
        let outputParameters = try #require(outputFunction["parameters"])
        let sourceParameters = try #require(sourceFunction["parameters"])

        #expect(outputFunction["name"] as? String == "mcp__test_server__echo")
        #expect(outputFunction["description"] as? String == sourceFunction["description"] as? String)
        #expect(
            try canonicalJSON(outputParameters)
                == canonicalJSON(sourceParameters)
        )
    }

    @MainActor
    @Test("Matches the legacy model-facing schemas when no collision exists")
    func legacyModelFacingParity() throws {
        let native = nativeSource(name: "legacy_native")
        let mcp = TestFixtures.mcpTool()
        let legacySchemas = [native.modelSchema, try mcp.openAIToolSchema()]
        let authority = try HanlinCanonicalToolAuthority.build(
            nativeSources: [native],
            mcpTools: [mcp]
        )

        #expect(authority.modelSchemas.count == legacySchemas.count)
        #expect(try canonicalJSON(authority.modelSchemas) == canonicalJSON(legacySchemas))
        #expect(authority.catalog.entries.compactMap(\.modelAlias) == [
            "legacy_native",
            mcp.exposedName
        ])
        #expect(authority.catalog.entries[0].descriptor.summary.values["en"]
            == native.entry.summary)
        #expect(authority.catalog.entries[1].descriptor.summary.values["en"]
            == mcp.summary)
    }

    @MainActor
    @Test("Backend route index rejects missing, orphaned, duplicate, stale, and wrong-provider routes")
    func backendRouteIndexValidation() throws {
        let authority = try HanlinCanonicalToolAuthority.build(
            nativeSources: [nativeSource(name: "route_fixture")],
            mcpTools: []
        )
        let record = try #require(authority.backendRouteIndex.records.first)
        let provider = try HanlinProviderInstanceID(validating: "native.system")
        let unknownID = HanlinLogicalToolID(
            providerInstanceID: provider,
            localToolID: try HanlinToolID(validating: "unknown")
        )
        #expect(authority.backendRouteIndex.target(logicalToolID: unknownID) == nil)

        #expect(throws: HanlinCanonicalToolAuthorityError.self) {
            try HanlinCanonicalToolBackendRouteIndex(
                revision: authority.catalog.revision,
                catalog: authority.catalog,
                records: []
            )
        }
        #expect(throws: HanlinCanonicalToolAuthorityError.self) {
            try HanlinCanonicalToolBackendRouteIndex(
                revision: authority.catalog.revision,
                catalog: authority.catalog,
                records: [record, record]
            )
        }
        let orphan = HanlinCanonicalToolBackendRecord(
            logicalToolID: unknownID,
            target: .init(
                backend: .native(
                    providerInstanceID: provider,
                    toolName: "unknown"
                ),
                presentationProfile: .generic(toolName: "unknown"),
                resultTitle: nil
            )
        )
        #expect(throws: HanlinCanonicalToolAuthorityError.self) {
            try HanlinCanonicalToolBackendRouteIndex(
                revision: authority.catalog.revision,
                catalog: authority.catalog,
                records: [record, orphan]
            )
        }
        #expect(throws: HanlinCanonicalToolAuthorityError.self) {
            try HanlinCanonicalToolBackendRouteIndex(
                revision: HanlinCatalogRevision(
                    authority.catalog.revision.rawValue &+ 1
                ),
                catalog: authority.catalog,
                records: [record]
            )
        }
        let wrongProvider = HanlinCanonicalToolBackendRecord(
            logicalToolID: record.logicalToolID,
            target: .init(
                backend: .mcp(serverID: UUID(), toolName: "route_fixture"),
                presentationProfile: .generic(toolName: "route_fixture"),
                resultTitle: nil
            )
        )
        #expect(throws: HanlinCanonicalToolAuthorityError.self) {
            try HanlinCanonicalToolBackendRouteIndex(
                revision: authority.catalog.revision,
                catalog: authority.catalog,
                records: [wrongProvider]
            )
        }
    }

    @MainActor
    @Test("Canonical dispatch invokes exactly one selected backend and no fallback")
    func exactDispatch() async throws {
        let native = nativeSource(name: "dispatch_native")
        let mcp = TestFixtures.mcpTool()
        let authority = try HanlinCanonicalToolAuthority.build(
            nativeSources: [native],
            mcpTools: [mcp]
        )
        var nativeCalls = 0
        var mcpCalls = 0
        let prepared = AssistantToolBridge.PreparedTools(
            authority: authority,
            executors: .init(
                executeNative: { provider, toolName, _, _ in
                    nativeCalls += 1
                    #expect(provider.rawValue == "native.system")
                    #expect(toolName == "dispatch_native")
                    return NativeToolResult(modelText: "native-result")
                },
                executeMCP: { serverID, toolName, _, _ in
                    mcpCalls += 1
                    #expect(serverID == mcp.serverID)
                    #expect(toolName == "echo")
                    return NativeToolResult(modelText: "mcp-result")
                }
            )
        )
        let context = NativeToolExecutionContext(localeIdentifier: "en")

        let nativeResult = await prepared.execute(
            alias: "dispatch_native",
            argumentsJSON: #"{"value":"one"}"#,
            context: context
        )
        #expect(nativeResult?.modelText == "native-result")
        #expect(nativeCalls == 1)
        #expect(mcpCalls == 0)

        let mcpResult = await prepared.execute(
            alias: "mcp__test_server__echo",
            argumentsJSON: #"{"value":"two"}"#,
            context: context
        )
        #expect(mcpResult?.modelText == "mcp-result")
        #expect(nativeCalls == 1)
        #expect(mcpCalls == 1)

        let unknown = await prepared.execute(
            alias: "missing_alias",
            argumentsJSON: "{}",
            context: context
        )
        if case .some = unknown {
            Issue.record("Unknown alias executed a backend")
        }
        #expect(nativeCalls == 1)
        #expect(mcpCalls == 1)
    }

    @MainActor
    @Test("Canonical dispatch preserves an execution error exactly once")
    func executionErrorPropagatesOnce() async throws {
        let authority = try HanlinCanonicalToolAuthority.build(
            nativeSources: [nativeSource(name: "failing_native")],
            mcpTools: []
        )
        var nativeCalls = 0
        var mcpCalls = 0
        let prepared = AssistantToolBridge.PreparedTools(
            authority: authority,
            executors: .init(
                executeNative: { _, _, _, _ in
                    nativeCalls += 1
                    return NativeToolResult(
                        modelText: "backend-error",
                        userText: "Tool failed",
                        uiBlocks: [.init(
                            type: .error,
                            title: "Tool failed",
                            body: "Fixture failure",
                            systemImage: "exclamationmark.triangle"
                        )]
                    )
                },
                executeMCP: { _, _, _, _ in
                    mcpCalls += 1
                    return NativeToolResult(modelText: "wrong-backend")
                }
            )
        )

        let result = await prepared.execute(
            alias: "failing_native",
            argumentsJSON: "{}",
            context: .init(localeIdentifier: "en")
        )

        #expect(result?.modelText == "backend-error")
        #expect(result?.userText == "Tool failed")
        #expect(result?.uiBlocks.count == 1)
        #expect(nativeCalls == 1)
        #expect(mcpCalls == 0)
    }

    @MainActor
    @Test("Display labels and discovery aliases do not define logical identity")
    func identityIndependence() throws {
        let firstID = try #require(
            UUID(uuidString: "44444444-4444-4444-8444-444444444444")
        )
        let secondID = try #require(
            UUID(uuidString: "55555555-5555-4555-8555-555555555555")
        )
        var first = mcpTool(serverID: firstID, exposedName: "discovery_one")
        var second = mcpTool(serverID: secondID, exposedName: "discovery_two")
        first.title = "Same display label"
        second.title = "Same display label"
        second.originalName = "echo_two"
        let authority = try HanlinCanonicalToolAuthority.build(
            nativeSources: [],
            mcpTools: [first, second]
        )
        let identities = authority.catalog.entries.map(\.descriptor.logicalID)

        #expect(identities.count == Set(identities).count)
        #expect(authority.catalog.entries.map { $0.descriptor.title.values["en"] }
            == ["Same display label", "Same display label"])
        #expect(authority.catalog.entries.compactMap(\.modelAlias)
            == ["mcp__test_server__echo", "mcp__test_server__echo_two"])
    }

    @MainActor
    private func nativeSource(
        name: String,
        preferredAlias: String? = nil
    ) -> HanlinCanonicalToolAuthority.NativeSource {
        let profile = ToolPresentationProfile.generic(toolName: name)
        let canonicalSchema = NativeToolSchema.function(
            name: name,
            description: "Canonical fixture \(name)",
            parameters: NativeToolSchema.object(
                properties: ["value": NativeToolSchema.string(description: "Fixture value")],
                required: ["value"]
            )
        )
        return .init(
            entry: NativeToolCatalogEntry(
                name: name,
                title: name,
                summary: "Canonical authority fixture",
                presentationProfile: profile
            ),
            canonicalSchema: canonicalSchema,
            modelSchema: ToolSchemaDecorator.decorate(
                schema: canonicalSchema,
                profile: profile,
                progressSummaryRequired: false
            ),
            preferredAlias: preferredAlias
        )
    }

    private func mcpTool(
        serverID: UUID,
        exposedName: String
    ) -> MCPToolDescriptor {
        var tool = TestFixtures.mcpTool(serverID: serverID)
        tool.exposedName = exposedName
        return tool
    }

    private func canonicalJSON(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }
}
