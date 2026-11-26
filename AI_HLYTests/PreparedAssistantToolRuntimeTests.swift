import Foundation
import HanlinPlatformContracts
import HanlinScriptCompiler
import HanlinScriptContracts
import HanlinScriptStore
import Testing
@testable import AI_Hanlin

/// Shares the original serialized native-engine suite. These cases install real
/// packages and use the live catalog, platform and Host request broker.
@MainActor
extension HanlinUnifiedHostServicesE2ETests {
    @Test func installedExpoAssistantToolReturnsTheActualHermesHandlerResult() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "expo-assistant-tool-\(UUID().uuidString.lowercased())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = Bundle(for: HanlinExpoHostServicesAcceptanceTests.self)
        let resources = try #require(bundle.url(forResource: "HostServicesProbe", withExtension: "bundle",
                                                subdirectory: "Fixtures")
            ?? bundle.url(forResource: "HostServicesProbe", withExtension: "bundle"))
        let original = resources.appending(path: "ExpoSwiftUIProbeA.hanlinExpo")
        let staged = try HanlinPackageCenter().stageAndInspect(sourceURL: original, stagingParent: root)
        let manifestURL = staged.packageRoot.appending(path: "script.json")
        let originalExecutable = try Data(contentsOf: staged.packageRoot.appending(path: "bundle.js"))
        var manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL))
                                    as? [String: Any])
        let appID = "hanlin.assistant-expo-\(UUID().uuidString.lowercased())"
        manifest["name"] = appID
        manifest["hanlinAppID"] = appID
        var actions = try #require(manifest["actions"] as? [[String: Any]])
        for name in ["hostServicesEcho", "hostServicesFail"] {
            let index = try #require(actions.firstIndex { $0["id"] as? String == name })
            actions[index]["inputSchema"] = ["type": "object"]
            actions[index]["outputSchema"] = ["type": "object"]
        }
        manifest["actions"] = actions
        var entries = try #require(manifest["entrypoints"] as? [[String: Any]])
        entries += ["hostServicesEcho", "hostServicesFail"].map {
            ["id": "assistant.\($0)", "kind": "assistantTool",
             "sourcePath": "bundle.js", "exportedSymbol": $0]
        }
        manifest["entrypoints"] = entries
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]).write(to: manifestURL)
        // Only declarations change in this owned staging directory; the original
        // Metro output and its actual Host Services handler stay byte-identical.
        #expect(try Data(contentsOf: staged.packageRoot.appending(path: "bundle.js")) == originalExecutable)
        let archive = root.appending(path: "assistant-expo.scripting")
        try HanlinScriptingPackageExporter().exportPackage(at: staged.packageRoot, to: archive)
        try await withInstalledAssistantPackage(archive, appID: appID) { platform, installed in
            let prepared = try await liveAssistantCatalog(platform: platform)
            let echo = try assistantAlias(prepared, installed: installed.record.installedPackageID,
                                          action: "hostServicesEcho")
            let input = #"{"ordinal":41,"unicode":"שלום🙂","nested":[null,true]}"#
            let executed = await prepared.execute(alias: echo, argumentsJSON: input,
                                                  context: .init(localeIdentifier: "en"))
            let result = try #require(executed)
            #expect(result.outcome == .succeeded)
            let value = try HanlinJSONValue.decodeCanonicalJSON(Data(result.modelText.utf8))
            guard case let .object(reply) = value else {
                Issue.record("The installed Hermes action did not return its real typed object")
                return
            }
            #expect(reply["caller"] == .string("hanlin.host"))
            #expect(reply["action"] == .string("hostServicesEcho"))
            #expect(reply["parameters"] == (try HanlinJSONValue.decodeCanonicalJSON(Data(input.utf8))))
            #expect(reply["computed"] == .integer(42))
            #expect(reply["storageVerified"] == .bool(true))
            #expect(reply["status"] == nil)
            #expect(platform.activeApplicationID == installed.record.installedPackageID)
            #expect(platform.activeExpoController != nil)
            let fail = try assistantAlias(prepared, installed: installed.record.installedPackageID,
                                          action: "hostServicesFail")
            let failed = await prepared.execute(alias: fail, argumentsJSON: "{}",
                                                context: .init(localeIdentifier: "en"))
            let failure = try #require(failed)
            #expect(failure.outcome == .failed)
            #expect(failure.modelText.contains("HOST_SERVICES_EXPECTED_FAILURE:"))
            await platform.setEnabled(false, for: installed.record.installedPackageID)
            let stale = await prepared.execute(alias: echo, argumentsJSON: input,
                                               context: .init(localeIdentifier: "en"))
            #expect(try #require(stale).outcome == .failed)
        }
    }

    @Test func installedNativeScriptAssistantToolReturnsTheActualJavaScriptHandlerResult() async throws {
        let suffix = UUID().uuidString.lowercased()
        let root = FileManager.default.temporaryDirectory.appending(path: "ns-assistant-tool-\(suffix)")
        let source = root.appending(path: "Package")
        let app = source.appending(path: "nativescript/app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let appID = "hanlin.assistant-native-\(suffix)"
        let names = ["LookupText", "RejectText"]
        let manifest: [String: Any] = [
            "name": appID, "version": "1.0.0", "hanlinAppID": appID,
            "entry": "nativescript/app/bundle.mjs", "runInApp": true,
            "hanlinRuntime": "hanlin-nativescript", "capabilities": ["inter-app.share"],
            "entrypoints": names.map {
                ["id": "assistant.\($0)", "kind": "assistantTool",
                 "sourcePath": "nativescript/app/bundle.mjs", "exportedSymbol": $0]
            },
            "actions": names.map {
                ["id": $0, "title": $0, "handler": "nativescript/app/bundle.mjs",
                 "capability": "inter-app.share", "inputSchema": ["type": "object"],
                 "outputSchema": ["type": "object"]] as [String: Any]
            }
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
            .write(to: source.appending(path: "script.json"))
        try Data(#"{"name":"prepared-assistant-native","type":"module","main":"bundle.mjs","hanlinRuntime":"hanlin-nativescript","dependencies":{"@nativescript/core":"9.1.4"}}"#.utf8)
            .write(to: app.appending(path: "package.json"))
        try Data(#"""
        const bridge = HanlinNativeServicesBridge.activeSessionBridge();
        if (!bridge) throw new Error('No actual NativeScript Host bridge');
        let counter = 40;
        bridge.registerRequestHandlerCapabilityHandler('LookupText', 'inter-app.share', (caller, json, reply) => {
          counter += 1;
          const parameters = JSON.parse(json);
          reply(JSON.stringify({source:'actual-native-js-handler', caller, parameters, counter,
                                computed:parameters.ordinal + 1}), null);
        });
        bridge.registerRequestHandlerCapabilityHandler('RejectText', 'inter-app.share', (caller, json, reply) => {
          reply(null, 'ASSISTANT_NATIVE_EXPECTED_FAILURE');
        });
        """#.utf8).write(to: app.appending(path: "bundle.mjs"))
        let archive = root.appending(path: "assistant-native.scripting")
        try HanlinScriptingPackageExporter().exportPackage(at: source, to: archive)
        try await withInstalledAssistantPackage(archive, appID: appID) { platform, installed in
            let prepared = try await liveAssistantCatalog(platform: platform)
            let lookup = try assistantAlias(prepared, installed: installed.record.installedPackageID,
                                            action: "LookupText")
            let input = #"{"ordinal":41,"unicode":"שלום🙂","nested":[null,true]}"#
            for count in [Int64(41), Int64(42)] {
                let executed = await prepared.execute(alias: lookup, argumentsJSON: input,
                                                      context: .init(localeIdentifier: "en"))
                let result = try #require(executed)
                #expect(result.outcome == .succeeded)
                let value = try HanlinJSONValue.decodeCanonicalJSON(Data(result.modelText.utf8))
                guard case let .object(reply) = value else {
                    Issue.record("The installed NativeScript handler did not return its real typed object")
                    return
                }
                #expect(reply["source"] == .string("actual-native-js-handler"))
                #expect(reply["caller"] == .string("hanlin.host"))
                #expect(reply["parameters"] == (try HanlinJSONValue.decodeCanonicalJSON(Data(input.utf8))))
                #expect(reply["computed"] == .integer(42))
                #expect(reply["counter"] == .integer(count))
                #expect(reply["status"] == nil)
            }
            #expect(platform.activeApplicationID == installed.record.installedPackageID)
            #expect(platform.activeNativeScriptController != nil)
            let reject = try assistantAlias(prepared, installed: installed.record.installedPackageID,
                                            action: "RejectText")
            let rejected = await prepared.execute(alias: reject, argumentsJSON: "{}",
                                                  context: .init(localeIdentifier: "en"))
            let failure = try #require(rejected)
            #expect(failure.outcome == .failed)
            #expect(failure.modelText.contains("ASSISTANT_NATIVE_EXPECTED_FAILURE"))
            await platform.setEnabled(false, for: installed.record.installedPackageID)
            let stale = await prepared.execute(alias: lookup, argumentsJSON: input,
                                               context: .init(localeIdentifier: "en"))
            #expect(try #require(stale).outcome == .failed)
        }
    }

    private func withInstalledAssistantPackage(
        _ archive: URL, appID: String,
        body: @MainActor (HanlinScriptingPlatform, HanlinStoredPackageSnapshot) async throws -> Void
    ) async throws {
        let platform = HanlinScriptingPlatform.shared
        await platform.restore()
        #expect(platform.bootstrapError == nil)
        try #require(!platform.installedPackages.contains { $0.appID.rawValue == appID })
        await platform.importPackage(from: archive)
        try #require(platform.canInstallPreview,
                     "\(platform.importDiagnostics.map(\.message).joined(separator: "\n"))")
        await platform.installPreview()
        let installed = try #require(platform.installedPackages.first { $0.appID.rawValue == appID })
        do {
            try #require(installed.enabled)
            try #require(installed.preparedAssistantTools().count == 2)
            try await body(platform, installed)
        } catch {
            platform.dismissActiveApplication()
            await platform.uninstall(installed.record.installedPackageID)
            throw error
        }
        platform.dismissActiveApplication()
        await platform.uninstall(installed.record.installedPackageID)
        #expect(!platform.installedPackages.contains { $0.record.installedPackageID == installed.record.installedPackageID })
    }

    private func liveAssistantCatalog(platform: HanlinScriptingPlatform) async throws -> AssistantToolBridge.PreparedTools {
        // The live adapter's production dispatcher remains unchanged: this case
        // does not inject a broker handler or replace either native engine.
        let adapter = try await HanlinPreparedAssistantToolAdapter.live(platform: platform)
        let authority = try HanlinCanonicalToolAuthority.build(nativeSources: [], mcpTools: [],
                                                               scriptSources: adapter.canonicalSources())
        return .init(authority: authority, executors: .init(executeNative: { _, _, _, _ in
            Issue.record("Installed assistantTool incorrectly used the static native tool route")
            return .init(modelText: "unexpected native route", outcome: .failed)
        }, executeScripting: { _, _ in
            Issue.record("Installed assistantTool incorrectly used legacy JSC")
            return .init(modelText: "unexpected legacy route", outcome: .failed)
        }), preparedTools: adapter)
    }

    private func assistantAlias(_ prepared: AssistantToolBridge.PreparedTools,
                                installed: HanlinInstalledPackageID, action: String) throws -> String {
        let aliases = prepared.authority.catalog.entries.compactMap(\.modelAlias).filter { alias in
            guard case let .scripting(route)? = prepared.authority.resolution(alias: alias)?.backend else { return false }
            return route.installedPackageID == installed && route.localToolID.rawValue == action.lowercased()
        }
        try #require(aliases.count == 1)
        return try #require(aliases.first)
    }
}
