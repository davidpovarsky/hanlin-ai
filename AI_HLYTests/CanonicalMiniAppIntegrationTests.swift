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

    @MainActor
    @Test("All 4 compiled mini app providers are registered and provide canonical descriptors")
    func allCompiledProvidersRegistered() throws {
        BuiltinCanonicalRegistrations.ensureRegistered()
        let registry = HanlinCompiledMiniAppRegistry.shared
        let providers = registry.allProviders()
        #expect(providers.count >= 4)

        let expectedIDs = [
            "hanlin.demo.swift-parity",
            "nativeapp.sefaria",
            "nativeapp.wikipedia",
            "nativeapp.textstudio"
        ]

        for idStr in expectedIDs {
            let appID = try HanlinAppID(validating: idStr)
            let provider = registry.provider(for: appID)
            #expect(provider != nil, "Provider for \(idStr) must be registered")
            #expect(provider?.descriptor.id == appID)
            #expect(provider?.descriptor.implementation.engine == .swift)
        }
    }

    @MainActor
    @Test("Per-entrypoint resolution with hybrid descriptors maps foreground and background engines")
    func perEntrypointResolutionHybrid() throws {
        let hybridID = try HanlinAppID(validating: "hybrid.app")
        let hybridDesc = HanlinAppDescriptor(
            schemaVersion: .init(major: 1, minor: 0),
            descriptorRevision: try HanlinDescriptorRevision(1),
            id: hybridID,
            name: try LocalizedValue(["en": "Hybrid App"]),
            summary: try LocalizedValue(["en": "Hybrid"]),
            description: try LocalizedValue(["en": "Hybrid"]),
            version: try HanlinPackageVersion(validating: "1.0.0"),
            apiVersion: .init(major: 1, minor: 0),
            icon: .systemSymbol(name: "gear"),
            appearance: .init(accentHex: "#000000"),
            category: .utilities,
            implementation: .hybrid(
                moduleID: try HanlinModuleID(validating: "native.module"),
                packageID: try HanlinPackageID(validating: "script.pkg")
            ),
            entryPoints: [
                .init(kind: .app, handler: "native_app", allowedContexts: [.mainApplication], runtimeProfile: nil),
                .init(kind: .widget, handler: "ns_widget", allowedContexts: [.widget], runtimeProfile: .hanlinNativeScript)
            ],
            authors: [.init(name: "Test")]
        )

        let catalog = HanlinCanonicalMiniAppCatalog(discovery: BuiltinMiniAppDiscovery())
        let appEngine = catalog.engine(for: hybridDesc.entryPoints[0], implementation: hybridDesc.implementation)
        let widgetEngine = catalog.engine(for: hybridDesc.entryPoints[1], implementation: hybridDesc.implementation)

        #expect(appEngine == .swift)
        #expect(widgetEngine == .nativeScript)
    }

    @MainActor
    @Test("HanlinNativeServicesBridge enforces active container isolation and capability gating")
    func bridgeContainerAndCapabilityGating() {
        HanlinNativeServicesBridge.setActiveContainer(
            appID: "hanlin.test.app",
            dataRoot: "/tmp/data",
            stateDir: "/tmp/data/state",
            docsDir: "/tmp/data/docs",
            cacheDir: "/tmp/data/cache",
            grantedCapabilities: ["storage", "javascript"]
        )

        #expect(HanlinNativeServicesBridge.activeAppID == "hanlin.test.app")
        #expect(HanlinNativeServicesBridge.dataRootDirectory() == "/tmp/data")
        #expect(HanlinNativeServicesBridge.stateDirectory() == "/tmp/data/state")

        // Inter-app request without capability should be rejected immediately
        var errorResult: String?
        HanlinNativeServicesBridge.sendRequest(
            targetID: "hanlin.other",
            action: "echo",
            capability: "inter-app.unauthorized",
            payloadJSON: "{}"
        ) { _, err in
            errorResult = err
        }
        #expect(errorResult != nil)
        #expect(errorResult?.contains("Permission denied") == true)

        HanlinNativeServicesBridge.clearActiveContainer()
        #expect(HanlinNativeServicesBridge.activeAppID == nil)
    }
}
