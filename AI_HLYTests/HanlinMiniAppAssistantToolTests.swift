import Foundation
import HanlinMiniAppCore
import HanlinNativeScriptRuntime
import HanlinPlatformContracts
import HanlinScriptContracts
import HanlinScriptStore
import Testing
@testable import AI_Hanlin

@MainActor
@Suite("MiniApp assistant attachment admission")
struct HanlinMiniAppAssistantToolTests {
    @Test func discoveryAndSelectionUseMetadataWithoutOpeningTheApp() throws {
        let package = try fixture()
        let active = HanlinNativeScriptSession.activeSessionIdentifier
        let descriptor = try #require(HanlinMiniAppAssistantToolExports.descriptors(in: [package]).first)
        let attachment = descriptor.makeAttachment(actionID: "echo")
        let tools = HanlinMiniAppAssistantToolExports.tools(attachments: [attachment], in: [package])
        #expect(descriptor.reference.sourceID == package.record.installedPackageID.rawValue)
        #expect(descriptor.reference.capabilityID == "assistant")
        #expect(descriptor.reference.revision == "7")
        #expect(tools.count == 1)
        #expect(tools.first?.name == HanlinMiniAppAssistantToolExports.toolName(
            installedPackageID: package.record.installedPackageID.rawValue,
            entrypointID: "assistant", actionID: "echo"))
        #expect(HanlinNativeScriptSession.activeSessionIdentifier == active)
        // No files exist at this fixture's paths: metadata selection cannot boot it.
        #expect(HanlinMiniAppAssistantToolExports.descriptors(in: [try fixture(enabled: false)]).isEmpty)
        #expect(HanlinMiniAppAssistantToolExports.descriptors(in: [try fixture(sourcePath: "app/bundle.mjs")]).isEmpty)
    }

    @Test func originalArgumentsAndSnapshotConfigurationHaveSeparateAuthorities() throws {
        let package = try fixture()
        let descriptor = try #require(HanlinMiniAppAssistantToolExports.descriptors(in: [package]).first)
        var attachment = descriptor.makeAttachment(actionID: "echo")
        attachment.configuration = .object(["catalog": .string("user-selected")])
        let entry = try #require(package.entrypoints.first { $0.id == "assistant" })
        let action = try #require(entry.assistantTool?.actions.first)
        let selection = HanlinMiniAppAssistantToolSelection(
            package: package, entrypoint: entry, action: action, attachment: attachment)
        let arguments = Data(#"{"query":"שלום","configuration":{"catalog":"model-overwrite"}}"#.utf8)
        let parameters = try selection.parameters(argumentsJSON: arguments)
        guard case let .object(envelope) = try parameters.jsonValue() else {
            Issue.record("Missing action parameters envelope"); return
        }
        #expect(envelope["arguments"] == (try HanlinJSONValue.decodeCanonicalJSON(arguments)))
        #expect(envelope["configuration"] == attachment.configuration)
        #expect(throws: (any Error).self) {
            try selection.parameters(argumentsJSON: Data(#"{"query":9007199254740993}"#.utf8))
        }
    }

    @Test func staleSelectionAndOverlappingDifferentConfigurationsAreRejected() throws {
        let package = try fixture()
        let descriptor = try #require(HanlinMiniAppAssistantToolExports.descriptors(in: [package]).first)
        let all = descriptor.makeAttachment()
        var specific = descriptor.makeAttachment(actionID: "echo")
        specific.configuration = .object(["catalog": .string("another")])
        #expect(HanlinMiniAppAssistantToolExports.tools(attachments: [all, specific], in: [package]).isEmpty)
        #expect(HanlinMiniAppAssistantToolExports.tools(attachments: [all], in: [try fixture(generation: 8)]).isEmpty)
        let entry = try #require(package.entrypoints.first { $0.id == "assistant" })
        let selection = HanlinMiniAppAssistantToolSelection(
            package: package, entrypoint: entry,
            action: try #require(entry.assistantTool?.actions.first), attachment: all)
        #expect(throws: (any Error).self) { try selection.currentPackage(in: [try fixture(generation: 8)]) }
        #expect(throws: (any Error).self) { try selection.currentPackage(in: []) }
        #expect(try selection.currentPackage(in: [package]) == package)
    }

    @Test func runtimeRootMustLoadTheDeclaredToolAndCannotFallBackToIndex() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "assistant-admission-" + UUID().uuidString)
        let toolRoot = root.appending(path: "tools/assistant")
        try FileManager.default.createDirectory(at: toolRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("// tool".utf8).write(to: toolRoot.appending(path: "bundle.mjs"))
        let package = try fixture()
        let entry = try #require(package.entrypoints.first { $0.id == "assistant" })
        let metadata = toolRoot.appending(path: "package.json")
        try Data(#"{"main":"index.js","hanlinRuntime":"hanlin-nativescript"}"#.utf8).write(to: metadata)
        #expect(throws: (any Error).self) {
            try HanlinMiniAppAssistantToolRuntime.dedicatedSourceURL(package: package, entrypoint: entry, artifactRoot: root)
        }
        try Data(#"{"main":"bundle.mjs","hanlinRuntime":"hanlin-nativescript"}"#.utf8).write(to: metadata)
        #expect(try HanlinMiniAppAssistantToolRuntime.dedicatedSourceURL(
            package: package, entrypoint: entry, artifactRoot: root) == toolRoot.appending(path: "bundle.mjs"))
        let outside = root.appending(path: "outside.mjs")
        try Data("// outside".utf8).write(to: outside)
        try FileManager.default.removeItem(at: toolRoot.appending(path: "bundle.mjs"))
        try FileManager.default.createSymbolicLink(at: toolRoot.appending(path: "bundle.mjs"), withDestinationURL: outside)
        #expect(throws: (any Error).self) {
            try HanlinMiniAppAssistantToolRuntime.dedicatedSourceURL(package: package, entrypoint: entry, artifactRoot: root)
        }
    }

    @Test func modernRenderersReceivePlainExactJavaScriptJSON() throws {
        let value: HanlinValue = .object([
            "query": .string("שלום"), "configuration": .object(["scope": .string("chosen")]),
            "count": .integer(42), "items": .array([.bool(true), .null])
        ])
        let expected = try value.jsonValue(destination: .javaScriptBinary64)
        let native = try NativeScriptEmbeddedResultAdapter.payloadJSON(value)
        #expect(try HanlinJSONValue.decodeCanonicalJSON(Data(native.utf8)) == expected)
        let expo = try ExpoEmbeddedResultAdapter.payloadProperty(value)
        let expoBytes = try JSONSerialization.data(withJSONObject: expo, options: [.fragmentsAllowed])
        #expect(try HanlinJSONValue.decodeCanonicalJSON(expoBytes) == expected)
        let integralDouble = try ExpoEmbeddedResultAdapter.payloadProperty(.number(42.0))
        #expect((integralDouble as? NSNumber)?.doubleValue == 42.0)
        for invalid in [HanlinValue.integer(9_007_199_254_740_992), .data(Data([1]))] {
            #expect(throws: (any Error).self) { try NativeScriptEmbeddedResultAdapter.payloadJSON(invalid) }
            #expect(throws: (any Error).self) { try ExpoEmbeddedResultAdapter.payloadProperty(invalid) }
        }
    }

    private func fixture(enabled: Bool = true, generation: UInt64 = 7,
                         sourcePath: String = "tools/assistant/bundle.mjs") throws -> HanlinStoredPackageSnapshot {
        let schema = try HanlinJSONSchemaDocument.decodeCanonicalJSON(
            Data(#"{"$schema":"https://json-schema.org/draft/2020-12/schema","type":"object","properties":{"query":{"type":"string"}},"required":["query"]}"#.utf8))
        let configuration = HanlinComposerConfiguration(panels: [
            .init(id: "search", title: "Search", fields: [
                .init(key: "catalog", title: "Catalog", kind: .text, defaultValue: .string("default"))
            ])
        ])
        let record = HanlinInstalledPackageRecord(
            installedPackageID: try .init(validating: "installed.assistant-test"),
            packageID: try .init(validating: "hanlin.assistant-test"),
            version: try .init(validating: "1.0.0"),
            sourceDigest: String(repeating: "b", count: 64),
            artifactDigest: String(repeating: "c", count: 64),
            activeGeneration: generation, installedAt: .distantPast, updatedAt: .distantPast)
        return .init(record: record, entrypoints: [
            .init(id: "app", kind: .app, sourcePath: "app/bundle.mjs",
                  supportedContexts: [.mainApplication], runtimePolicyID: "foreground-app-v1",
                  runtimeProfile: .hanlinNativeScript, compatibility: .supported),
            .init(id: "assistant", kind: .assistantTool, sourcePath: sourcePath,
                  supportedContexts: [.mainApplication], runtimePolicyID: "foreground-app-v1",
                  runtimeProfile: .hanlinNativeScript, compatibility: .supported,
                  assistantTool: .init(title: "Search", summary: "Search selected catalog",
                    actions: [.init(id: "echo", title: "Echo", summary: "Echo arguments", inputSchema: schema)],
                    configuration: configuration))
        ], enabled: enabled, availableGenerations: [generation])
    }
}

@MainActor
extension HanlinUnifiedHostServicesE2ETests {
    @Test func nativeScriptAssistantRepliesSettleOnceAndRejectMalformedJSON() async throws {
        let appID = try HanlinAppID(validating: "hanlin.assistant-reply")
        let action = try HanlinActionID(validating: "echo")
        let capability = try HanlinCapabilityID(validating: "assistant-tool")
        let adapter = NativeScriptHostServicesAdapter(appID: appID, grantedCapabilities: [])
        defer { adapter.invalidateRuntimeRequests() }
        adapter.registerRequestHandler("echo", capability: "assistant-tool") { _, _, reply in
            reply("1", nil)
            reply("2", nil)
        }
        let value = try await adapter.invokeRegisteredAction(action, capability: capability, caller: appID, payload: .null)
        #expect(value == .integer(1))
        adapter.registerRequestHandler("broken", capability: "assistant-tool") { _, _, reply in reply("{", nil) }
        await #expect(throws: (any Error).self) {
            try await adapter.invokeRegisteredAction(
                HanlinActionID(validating: "broken"), capability: capability, caller: appID, payload: .null)
        }
    }

    @Test func nativeScriptAssistantCancellationAndInvalidationReleaseWaiters() async throws {
        let appID = try HanlinAppID(validating: "hanlin.assistant-cancel")
        let action = try HanlinActionID(validating: "pending")
        let capability = try HanlinCapabilityID(validating: "assistant-tool")
        for invalidate in [false, true] {
            let adapter = NativeScriptHostServicesAdapter(appID: appID, grantedCapabilities: [])
            let started = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
            adapter.registerRequestHandler("pending", capability: "assistant-tool") { _, _, _ in
                started.continuation.yield(())
            }
            let task = Task { @MainActor in
                try await adapter.invokeRegisteredAction(action, capability: capability, caller: appID, payload: .null)
            }
            var iterator = started.stream.makeAsyncIterator()
            _ = await iterator.next()
            if invalidate { adapter.invalidateRuntimeRequests() } else { task.cancel() }
            await #expect(throws: CancellationError.self) { try await task.value }
            adapter.invalidateRuntimeRequests()
            started.continuation.finish()
        }
    }
}
