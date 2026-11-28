import Foundation
import HanlinPlatformContracts
import Testing
@testable import AI_Hanlin

@Suite("Canonical Scripting tool authority")
struct ScriptingCanonicalAuthorityTests {
    @MainActor
    @Test("Projects Script-only tools with stable provider-qualified identity")
    func scriptOnlyCatalog() throws {
        let source = try scriptSource(
            provider: "script.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            tool: "echo"
        )
        let generatedAt = Date(timeIntervalSince1970: 4)
        let first = try HanlinCanonicalToolAuthority.build(
            nativeSources: [],
            mcpTools: [],
            scriptSources: [source],
            generatedAt: generatedAt
        )
        let second = try HanlinCanonicalToolAuthority.build(
            nativeSources: [],
            mcpTools: [],
            scriptSources: [source],
            generatedAt: generatedAt
        )

        #expect(first.catalog == second.catalog)
        #expect(first.routingTable == second.routingTable)
        #expect(first.catalog.entries.count == 1)
        let entry = try #require(first.catalog.entries.first)
        #expect(entry.descriptor.logicalID.providerInstanceID.rawValue
            == "script.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
        #expect(entry.descriptor.logicalID.localToolID.rawValue == "echo")
        #expect(entry.modelAlias == "script__fixture__echo")
        if case let .scripting(route)? = first.resolution(
            alias: "script__fixture__echo"
        )?.backend {
            #expect(route.localToolID.rawValue == "echo")
            #expect(route.providerInstanceID == entry.descriptor.logicalID.providerInstanceID)
        } else {
            Issue.record("Script alias did not resolve to its backend route")
        }
    }

    @MainActor
    @Test("Preserves Native and MCP precedence across all Script collision shapes")
    func threeProviderCollisionPolicy() throws {
        let mcp = TestFixtures.mcpTool()
        let establishedAlias = "mcp__test_server__echo"
        let firstScript = try scriptSource(
            provider: "script.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            tool: "echo",
            preferredAlias: establishedAlias
        )
        let secondScript = try scriptSource(
            provider: "script.bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            tool: "echo",
            preferredAlias: establishedAlias
        )
        let native = nativeSource(
            name: "native_collision",
            preferredAlias: establishedAlias
        )

        let forward = try HanlinCanonicalToolAuthority.build(
            nativeSources: [native],
            mcpTools: [mcp],
            scriptSources: [firstScript, secondScript],
            generatedAt: Date(timeIntervalSince1970: 5)
        )
        let reverse = try HanlinCanonicalToolAuthority.build(
            nativeSources: [native],
            mcpTools: [mcp],
            scriptSources: [secondScript, firstScript],
            generatedAt: Date(timeIntervalSince1970: 5)
        )
        let aliases = forward.catalog.entries.compactMap(\.modelAlias)

        #expect(forward.catalog == reverse.catalog)
        #expect(forward.routingTable == reverse.routingTable)
        #expect(aliases.count == 4)
        #expect(aliases.count == Set(aliases).count)
        #expect(aliases[0] == establishedAlias)
        if case .native? = forward.resolution(alias: aliases[0])?.backend {
            // Native retains the established alias.
        } else {
            Issue.record("Native lost collision precedence")
        }
        if case .mcp? = forward.resolution(alias: aliases[1])?.backend {
            // MCP remains ahead of Script.
        } else {
            Issue.record("MCP lost collision precedence to Script")
        }
        for alias in aliases.dropFirst(2) {
            if case .scripting? = forward.resolution(alias: alias)?.backend {
                #expect(alias.hasPrefix("mcp__test_server__echo_"))
            } else {
                Issue.record("A Script collision alias resolved to another backend")
            }
        }
    }

    @MainActor
    @Test("Rejects duplicate Script logical IDs and wrong-provider routes")
    func rejectsInvalidScriptAuthorityInputs() throws {
        let source = try scriptSource(
            provider: "script.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            tool: "echo"
        )
        #expect(throws: HanlinCanonicalToolAuthorityError.self) {
            try HanlinCanonicalToolAuthority.build(
                nativeSources: [],
                mcpTools: [],
                scriptSources: [source, source]
            )
        }

        let wrongRoute = HanlinCanonicalToolAuthority.ScriptSource(
            descriptor: source.descriptor,
            preferredAlias: source.preferredAlias,
            modelSchema: source.modelSchema,
            backendRoute: .init(
                providerInstanceID: try HanlinProviderInstanceID(
                    validating: "script.bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
                ),
                installedPackageID: source.backendRoute.installedPackageID,
                entrypointPath: source.backendRoute.entrypointPath,
                localToolID: source.backendRoute.localToolID
            ),
            presentationProfile: source.presentationProfile,
            resultTitle: source.resultTitle
        )
        #expect(throws: HanlinCanonicalToolAuthorityError.self) {
            try HanlinCanonicalToolAuthority.build(
                nativeSources: [],
                mcpTools: [],
                scriptSources: [wrongRoute]
            )
        }
    }

    @MainActor
    @Test("Prepared dispatch selects Script exactly once with no fallback")
    func exactScriptDispatch() async throws {
        let source = try scriptSource(
            provider: "script.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            tool: "echo"
        )
        let authority = try HanlinCanonicalToolAuthority.build(
            nativeSources: [nativeSource(name: "native")],
            mcpTools: [TestFixtures.mcpTool()],
            scriptSources: [source]
        )
        var nativeCalls = 0
        var mcpCalls = 0
        var scriptCalls = 0
        let prepared = AssistantToolBridge.PreparedTools(
            authority: authority,
            executors: .init(
                executeNative: { _, _, _, _ in
                    nativeCalls += 1
                    return NativeToolResult(modelText: "wrong-native")
                },
                executeMCP: { _, _, _, _ in
                    mcpCalls += 1
                    return NativeToolResult(modelText: "wrong-mcp")
                },
                executeScripting: { route, arguments in
                    scriptCalls += 1
                    #expect(route == source.backendRoute)
                    #expect(arguments == #"{"text":"value"}"#)
                    return NativeToolResult(modelText: "script-result")
                }
            )
        )

        #expect(prepared.schemas.count == 3)
        let result = await prepared.execute(
            alias: "script__fixture__echo",
            argumentsJSON: #"{"text":"value"}"#,
            context: .init(localeIdentifier: "en")
        )
        #expect(result?.modelText == "script-result")
        #expect(nativeCalls == 0)
        #expect(mcpCalls == 0)
        #expect(scriptCalls == 1)
    }

    @MainActor
    private func nativeSource(
        name: String,
        preferredAlias: String? = nil
    ) -> HanlinCanonicalToolAuthority.NativeSource {
        let profile = ToolPresentationProfile.generic(toolName: name)
        let canonicalSchema = NativeToolSchema.function(
            name: name,
            description: "Fixture",
            parameters: NativeToolSchema.object(properties: [:], required: [])
        )
        return .init(
            entry: .init(
                name: name,
                title: name,
                summary: "Fixture",
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

    @MainActor
    private func scriptSource(
        provider: String,
        tool: String,
        preferredAlias: String = "script__fixture__echo"
    ) throws -> HanlinCanonicalToolAuthority.ScriptSource {
        let providerID = try HanlinProviderInstanceID(validating: provider)
        let localToolID = try HanlinToolID(validating: tool)
        let schema = try HanlinJSONSchemaDocument(
            dialect: .draft2020_12,
            root: .object([
                "additionalProperties": .bool(false),
                "properties": .object([:]),
                "type": .string("object")
            ])
        )
        let route = HanlinScriptBackendRoute(
            providerInstanceID: providerID,
            installedPackageID: try HanlinInstalledPackageID(
                validating: "script-package.aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
            ),
            entrypointPath: "assistant_tool.js",
            localToolID: localToolID
        )
        return .init(
            descriptor: .init(
                logicalID: .init(
                    providerInstanceID: providerID,
                    localToolID: localToolID
                ),
                descriptorRevision: try HanlinDescriptorRevision(1),
                owner: .package(try HanlinPackageID(validating: "com.hanlin.fixture")),
                title: try LocalizedValue(["en": "Script fixture"]),
                summary: try LocalizedValue(["en": "Script fixture"]),
                inputSchema: schema,
                risk: .passive,
                presentation: .init(compactStyle: .automatic)
            ),
            preferredAlias: preferredAlias,
            modelSchema: [
                "type": "function",
                "function": [
                    "name": preferredAlias,
                    "description": "Script fixture",
                    "parameters": [
                        "type": "object",
                        "properties": [String: Any](),
                        "additionalProperties": false
                    ] as [String: Any]
                ] as [String: Any]
            ],
            backendRoute: route,
            presentationProfile: .generic(toolName: tool),
            resultTitle: "Script fixture"
        )
    }
}
