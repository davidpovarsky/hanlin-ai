import Foundation
import HanlinMiniAppCore
import HanlinPlatformContracts
import HanlinScriptContracts
import HanlinScriptStore
import XCTest
@testable import AI_Hanlin

/// Tests the actual catalog/typed broker adapter with an injected handler.
/// Native Expo/NativeScript engine execution remains a separate acceptance gate.
@MainActor
final class HanlinPreparedAssistantToolAdapterTests: XCTestCase {
    func testBothPreparedEnginesReturnTheAwaitedTypedBrokerValue() async throws {
        for runtime in [HanlinRuntimeProfile.hanlinExpo, .hanlinNativeScript] {
            let package = try fixture(runtime: runtime)
            let broker = HanlinMiniAppRequestBroker(limits: .personalHost)
            let appID = package.appID
            let capability = try HanlinCapabilityID(validating: "inter-app.share")
            let actionID = try HanlinActionID(validating: "LookupText")
            await broker.register(target: appID, action: actionID, capability: capability) { request in
                .object(["echo": request.payload, "action": .string(request.action.rawValue)])
            }
            let adapter = try HanlinPreparedAssistantToolAdapter(packages: [package],
                currentPackages: { [package] }, dispatch: { binding, parameters in
                    let response = try await broker.request(.init(
                        caller: try .init(validating: "hanlin.host"), target: appID,
                        action: binding.actionID, capability: capability, payload: parameters))
                    return response.value
                })
            let authority = try HanlinCanonicalToolAuthority.build(nativeSources: [], mcpTools: [],
                                                                    scriptSources: adapter.canonicalSources())
            let alias = try XCTUnwrap(authority.catalog.entries.first?.modelAlias)
            var legacyCalls = 0
            let prepared = AssistantToolBridge.PreparedTools(authority: authority,
                executors: .init(executeNative: { _, _, _, _ in
                    XCTFail("A prepared package is not a static native tool.")
                    return .init(modelText: "unexpected native route", outcome: .failed)
                }, executeScripting: { _, _ in
                    legacyCalls += 1
                    return .init(modelText: "unexpected legacy runtime", outcome: .failed)
                }), preparedTools: adapter)
            let executed = await prepared.execute(alias: alias,
                argumentsJSON: #"{"query":"טקסט","limit":2}"#,
                context: .init(localeIdentifier: "en"))
            let result = try XCTUnwrap(executed)
            XCTAssertEqual(result.outcome, .succeeded)
            XCTAssertEqual(try HanlinJSONValue.decodeCanonicalJSON(Data(result.modelText.utf8)),
                .object(["echo": try HanlinJSONValue.decodeCanonicalJSON(Data(#"{"query":"טקסט","limit":2}"#.utf8)),
                         "action": .string("LookupText")]))
            XCTAssertEqual(legacyCalls, 0)
            let audit = await broker.auditEvents()
            XCTAssertEqual(audit.map(\.outcome), ["success"])
        }
    }

    func testUpdatedDisabledAndRemovedInstallationsDoNotDispatchOldTools() async throws {
        let original = try fixture()
        var current = [original]
        var dispatches = 0
        let adapter = try HanlinPreparedAssistantToolAdapter(packages: current,
            currentPackages: { current }, dispatch: { _, _ in
                dispatches += 1
                return .string("must not run")
            })
        let source = try XCTUnwrap(adapter.canonicalSources().first)
        for packages in [[try fixture(generation: 2)], [try fixture(enabled: false)], []] {
            current = packages
            let result = await adapter.execute(route: source.backendRoute, argumentsJSON: "{}")
            XCTAssertEqual(result.outcome, .failed)
            XCTAssertTrue(result.modelText.contains("changed") || result.modelText.contains("enabled"))
        }
        XCTAssertEqual(dispatches, 0)
    }

    func testCaseCollidingActionNamesKeepDistinctRoutesAndOriginalDispatchSpelling() async throws {
        let package = try fixture(actions: ["LookupText", "lookuptext"])
        var observed: [String] = []
        let adapter = try HanlinPreparedAssistantToolAdapter(packages: [package],
            currentPackages: { [package] }, dispatch: { binding, _ in
                observed.append(binding.actionID.rawValue)
                return .string(binding.actionID.rawValue)
            })
        let sources = try adapter.canonicalSources()
        XCTAssertEqual(Set(sources.map(\.backendRoute.providerInstanceID)).count, 2)
        XCTAssertEqual(Set(sources.map(\.backendRoute.localToolID.rawValue)), ["lookuptext"])
        let authority = try HanlinCanonicalToolAuthority.build(nativeSources: [], mcpTools: [], scriptSources: sources)
        let aliases = authority.catalog.entries.compactMap(\.modelAlias)
        XCTAssertEqual(Set(aliases).count, 2)
        for alias in aliases {
            guard case let .scripting(route)? = authority.resolution(alias: alias)?.backend else {
                return XCTFail("Prepared alias lost its exact backend route.")
            }
            let result = await adapter.execute(route: route, argumentsJSON: "{}")
            XCTAssertEqual(result.outcome, .succeeded)
        }
        XCTAssertEqual(Set(observed), ["LookupText", "lookuptext"])
    }

    func testHandlerErrorsAndMalformedArgumentsRemainFailures() async throws {
        let package = try fixture()
        var calls = 0
        let adapter = try HanlinPreparedAssistantToolAdapter(packages: [package],
            currentPackages: { [package] }, dispatch: { _, _ in
                calls += 1
                throw HandlerError.rejected
            })
        let source = try XCTUnwrap(adapter.canonicalSources().first)
        let malformed = await adapter.execute(route: source.backendRoute, argumentsJSON: "{")
        XCTAssertEqual(malformed.outcome, .failed)
        XCTAssertEqual(calls, 0)
        for arguments in ["null", "[]", "\"text\""] {
            let nonObject = await adapter.execute(route: source.backendRoute, argumentsJSON: arguments)
            XCTAssertEqual(nonObject.outcome, .failed)
        }
        XCTAssertEqual(calls, 0)
        let rejected = await adapter.execute(route: source.backendRoute, argumentsJSON: "{}")
        XCTAssertEqual(rejected.outcome, .failed)
        XCTAssertTrue(rejected.modelText.contains("original handler failure"))
        XCTAssertEqual(calls, 1)
    }

    func testUnavailableMiniAppCatalogDoesNotThrowAwayOrdinarySources() async throws {
        let unavailable = await HanlinPreparedAssistantToolAdapter.catalogContribution {
            throw HandlerError.rejected
        }
        XCTAssertNil(unavailable.adapter)
        XCTAssertTrue(unavailable.sources.isEmpty)
        let native = try NativeToolBridge.canonicalSourcesForRequest()
        XCTAssertFalse(native.isEmpty)
        let ordinary = try HanlinCanonicalToolAuthority.build(nativeSources: native, mcpTools: [])
        let preserved = try HanlinCanonicalToolAuthority.build(nativeSources: native, mcpTools: [],
                                                               scriptSources: unavailable.sources)
        XCTAssertEqual(Set(ordinary.schemasByAlias.keys), Set(preserved.schemasByAlias.keys))
    }

    private enum HandlerError: LocalizedError {
        case rejected
        var errorDescription: String? { "original handler failure" }
    }

    private func fixture(runtime: HanlinRuntimeProfile = .hanlinExpo, generation: UInt64 = 1,
                         enabled: Bool = true, actions: [String] = ["LookupText"]) throws -> HanlinStoredPackageSnapshot {
        let path = runtime == .hanlinNativeScript ? "source/nativescript/app/bundle.mjs" : "source/bundle.js"
        var entrypoints = [HanlinPackageEntrypointDescriptor(id: "app", kind: .app, sourcePath: path,
            supportedContexts: [.mainApplication], runtimePolicyID: "prepared-app-v1",
            runtimeProfile: runtime, compatibility: .supported)]
        for (index, action) in actions.enumerated() {
            entrypoints.append(.init(id: "assistant.tool.\(index)", kind: .assistantTool, sourcePath: path,
                exportedSymbol: action, supportedContexts: [.mainApplication],
                runtimePolicyID: "prepared-foreground-action-v1", runtimeProfile: runtime, compatibility: .supported))
        }
        let declarations: [HanlinJSONValue] = actions.map {
            .object(["id": .string($0), "title": .string("Look up text"), "summary": .string("Read saved text"),
                     "handler": .string(String(path.dropFirst("source/".count))),
                     "inputSchema": .object(["type": .string("object")]),
                     "outputSchema": .object(["type": .string("object")])])
        }
        return .init(record: .init(installedPackageID: try .init(validating: "installed.assistant"),
            packageID: try .init(validating: "test.assistant"), version: try .init(validating: "1.0.0"),
            sourceDigest: String(repeating: "a", count: 64), artifactDigest: String(repeating: "b", count: 64),
            activeGeneration: generation, installedAt: .distantPast, updatedAt: .distantPast),
            entrypoints: entrypoints, enabled: enabled, availableGenerations: [generation],
            grantedCapabilities: [try .init(validating: "inter-app.share")],
            manifest: .init(name: "Assistant fixture", version: "1.0.0",
                unknownFields: ["hanlinRuntime": .string(runtime.rawValue), "actions": .array(declarations)]))
    }
}
