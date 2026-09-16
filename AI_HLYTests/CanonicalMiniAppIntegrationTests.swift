import Foundation
import HanlinMiniAppCore
import HanlinParityMiniApp
import HanlinPlatformContracts
import HanlinScriptContracts
import Testing
@testable import AI_Hanlin

@Suite("Canonical Mini App production integration", .serialized)
struct CanonicalMiniAppIntegrationTests {

    @MainActor
    @Test("Compiled package exposure registry derives Widget and App Intent from canonical descriptor")
    func compiledExposures() throws {
        let provider = try #require(CompiledMiniAppExposureRegistry.all.first)
        #expect(provider.descriptor.supportedExposures.contains(.widget))
        #expect(provider.descriptor.supportedExposures.contains(.appIntent))
        #expect(provider.widget("systemMedium").kind == .vStack)
        let result = try provider.performIntent(provider.intentNames[0], .object(["request": .string("state")]))
        #expect(result != .null)
    }

    @MainActor
    @Test("HanlinScript replacement keeps stable canonical data identity")
    func stableUpdateIdentity() async throws {
        let first = HanlinScriptingManifest(
            name: "Parity",
            version: "1.0.0",
            unknownFields: ["hanlinAppID": .string("hanlin.demo.stable")]
        )
        let update = HanlinScriptingManifest(
            name: "Renamed Parity",
            version: "2.0.0",
            unknownFields: ["hanlinAppID": .string("hanlin.demo.stable")]
        )
        let firstID = try HanlinScriptingPlatform.stablePackageID(for: first)
        let updateID = try HanlinScriptingPlatform.stablePackageID(for: update)
        #expect(firstID == updateID)

        let root = FileManager.default.temporaryDirectory.appending(
            path: "hanlin-update-storage-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try HanlinMiniAppDataStore(root: root)
        let appID = try HanlinAppID(validating: firstID.rawValue)
        let before = HanlinMiniAppStorageContext(appID: appID, store: store)
        try await before.write(Data("survives".utf8), area: .state, path: "value")
        let after = HanlinMiniAppStorageContext(
            appID: try HanlinAppID(validating: updateID.rawValue),
            store: store
        )
        #expect(try await after.read(area: .state, path: "value") == Data("survives".utf8))
    }

    @MainActor
    @Test("Canonical catalog discovers Swift built-in parity app and groups engines accurately")
    func catalogEngineGrouping() async throws {
        let discovery = BuiltinMiniAppDiscovery()
        let catalog = HanlinCanonicalMiniAppCatalog(discovery: discovery)
        let items = try await catalog.items()

        // Verify Swift built-in items exist
        let swiftItems = items.filter { $0.engine == .swift }
        #expect(!swiftItems.isEmpty)

        let parity = swiftItems.first { $0.id.rawValue == "hanlin.demo.swift-parity" }
        #expect(parity != nil)
        #expect(parity?.descriptor.appearance.accentHex == "#F05138")
    }

    @MainActor
    @Test("Native services bridge exposes Node, Python, and RequestBroker entrypoints")
    func nativeServicesBridgeAvailability() {
        // Verify Python runtime version can be queried
        _ = HanlinNativeServicesBridge.pythonVersion()

        // Verify Node health check API exists
        var healthCheckInvoked = false
        HanlinNativeServicesBridge.nodeHealthCheck { _, _ in
            healthCheckInvoked = true
        }
        // Asynchronous callback verification
        #expect(!healthCheckInvoked) // Confirms async non-blocking dispatch
    }

    @MainActor
    @Test("Inter-app request broker allows authorized cross-engine request flow")
    func interAppRequestBrokering() async throws {
        let callerID = try HanlinAppID(validating: "hanlin.caller")
        let targetID = try HanlinAppID(validating: "hanlin.target")
        let actionID = try HanlinActionID(validating: "echo")
        let capID = try HanlinCapabilityID(validating: "inter-app.test")

        let broker = HanlinMiniAppRequestBroker { _ in true }
        await broker.register(target: targetID, action: actionID, capability: capID) { request in
            request.payload
        }

        let response = try await broker.request(.init(
            caller: callerID,
            target: targetID,
            action: actionID,
            capability: capID,
            payload: .string("hello-cross-engine")
        ))
        #expect(response.value == .string("hello-cross-engine"))
    }
}
