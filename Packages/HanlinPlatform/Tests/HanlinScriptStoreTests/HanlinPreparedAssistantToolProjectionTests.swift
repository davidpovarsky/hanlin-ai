import Foundation
import HanlinPlatformContracts
import HanlinScriptContracts
import HanlinScriptStore
import Testing

@Suite("Prepared mini app assistant tool projection")
struct HanlinPreparedAssistantToolProjectionTests {
    @Test("Both engines retain action schemas and the installed foreground handler",
          arguments: [HanlinRuntimeProfile.hanlinExpo, .hanlinNativeScript])
    func schemasAndActionCaseSurviveProjection(runtime: HanlinRuntimeProfile) throws {
        let snapshot = try package(runtime: runtime)
        let binding = try #require(snapshot.preparedAssistantTools().first)
        let action = try #require(snapshot.appDescriptor().actions.first)
        #expect(binding.actionID.rawValue == "LookupText")
        #expect(binding.tool.id.rawValue == "lookuptext")
        #expect(binding.tool.title == action.title)
        #expect(binding.tool.summary.values["en"] == "Find a saved text")
        #expect(binding.tool.inputSchema == action.inputSchema)
        #expect(binding.tool.outputSchema == action.outputSchema)
        #expect(binding.tool.inputSchema.root == .object([
            "$schema": .string(HanlinSchemaDialect.draft2020_12.rawValue),
            "type": .string("object"),
            "$defs": .object(["query": .object(["type": .string("string")])]),
            "properties": .object(["query": .object(["$ref": .string("#/$defs/query")])])
        ]))
        #expect(!binding.tool.requiresApproval)
        #expect(action.handler == binding.entrypoint.sourcePath)
    }

    @Test("Installation, generation, bytes and exact entrypoint/action bind tool identity")
    func changedInstallationsCannotReuseToolIdentity() throws {
        let original = try #require(package().preparedAssistantTools().first)
        let generation = try #require(package(generation: 2).preparedAssistantTools().first)
        let installation = try #require(package(installation: "installed.other").preparedAssistantTools().first)
        let digest = try #require(package(sourceDigest: String(repeating: "c", count: 64)).preparedAssistantTools().first)
        let otherCase = try #require(package(action: "lookuptext").preparedAssistantTools().first)
        for changed in [generation, installation, digest, otherCase] {
            #expect(original != changed)
            #expect(original.providerInstanceID != changed.providerInstanceID)
        }
        #expect(original.tool.id == otherCase.tool.id) // Alias collision is resolved by canonical authority.
        #expect(try package(enabled: false).preparedAssistantTools().isEmpty)
        #expect(try package(runtime: .scriptingJSC).preparedAssistantTools().isEmpty)
    }

    @Test("An old filename-convention entry never becomes a prepared native tool")
    func legacyConventionIsNotPreparedAuthorization() throws {
        let original = try package()
        let entrypoints = original.entrypoints.map { entry in
            HanlinPackageEntrypointDescriptor(id: entry.id, kind: entry.kind, sourcePath: entry.sourcePath,
                exportedSymbol: entry.exportedSymbol, supportedContexts: entry.supportedContexts,
                runtimePolicyID: entry.kind == .assistantTool ? "assistant-tool-v1" : entry.runtimePolicyID,
                runtimeProfile: entry.runtimeProfile, compatibility: entry.compatibility)
        }
        let legacy = HanlinStoredPackageSnapshot(record: original.record, entrypoints: entrypoints,
            enabled: true, availableGenerations: [1], manifest: original.manifest)
        #expect(try legacy.preparedAssistantTools().isEmpty)
    }

    @Test("Stored malformed declarations are rejected before catalog projection")
    func malformedStoredActionsAreNotProjected() throws {
        for count in [0, 2] {
            let snapshot = try package(actionCount: count)
            #expect(throws: HanlinPreparedAssistantToolError.invalidDeclaration) {
                try snapshot.preparedAssistantTools()
            }
        }
    }

    private func package(runtime: HanlinRuntimeProfile = .hanlinExpo, generation: UInt64 = 1,
                         installation: String = "installed.assistant", enabled: Bool = true,
                         sourceDigest: String = String(repeating: "a", count: 64),
                         action: String = "LookupText", actionCount: Int = 1) throws -> HanlinStoredPackageSnapshot {
        let path = runtime == .hanlinNativeScript ? "source/nativescript/app/bundle.mjs" : "source/bundle.js"
        let input: HanlinJSONValue = .object([
            "type": .string("object"),
            "$defs": .object(["query": .object(["type": .string("string")])]),
            "properties": .object(["query": .object(["$ref": .string("#/$defs/query")])])
        ])
        let row: HanlinJSONValue = .object([
            "id": .string(action), "title": .string("Look up text"), "description": .string("Find a saved text"),
            "handler": .string(String(path.dropFirst("source/".count))),
            "inputSchema": input, "outputSchema": .object(["type": .string("object")])
        ])
        return .init(record: .init(installedPackageID: try .init(validating: installation),
            packageID: try .init(validating: "test.assistant"), version: try .init(validating: "1.0.0"),
            sourceDigest: sourceDigest, artifactDigest: String(repeating: "b", count: 64),
            activeGeneration: generation, installedAt: .distantPast, updatedAt: .distantPast),
            entrypoints: [
                .init(id: "app", kind: .app, sourcePath: path, supportedContexts: [.mainApplication],
                    runtimePolicyID: "prepared-app-v1", runtimeProfile: runtime, compatibility: .supported),
                .init(id: "assistant.lookup", kind: .assistantTool, sourcePath: path, exportedSymbol: action,
                    supportedContexts: [.mainApplication], runtimePolicyID: "prepared-foreground-action-v1",
                    runtimeProfile: runtime, compatibility: .supported)
            ], enabled: enabled, availableGenerations: [generation],
            grantedCapabilities: [try .init(validating: "inter-app.share")],
            manifest: .init(name: "Assistant fixture", version: "1.0.0",
                unknownFields: ["hanlinRuntime": .string(runtime.rawValue),
                                "actions": .array(Array(repeating: row, count: actionCount))]))
    }
}
