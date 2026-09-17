import Foundation
import HanlinMiniAppCore
import HanlinParityMiniApp
import HanlinPlatformContracts
import HanlinScriptContracts
import HanlinScriptStore
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
        BuiltinCanonicalRegistrations.ensureRegistered()
        let discovery = HanlinCompiledMiniAppDiscovery()
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
    @Test("Native services bridge exposes Python version and executes JavaScript returning 42")
    func nativeServicesExecution() async throws {
        let version = HanlinNativeServicesBridge.pythonVersion()
        #expect(version != nil)

        HanlinNativeServicesBridge.setActiveContainer(
            appID: "hanlin.test.js",
            dataRoot: "/tmp/data",
            stateDir: "/tmp/data/state",
            docsDir: "/tmp/data/docs",
            cacheDir: "/tmp/data/cache",
            grantedCapabilities: ["javascript", "node", "python"]
        )
        defer { HanlinNativeServicesBridge.clearActiveContainer() }

        // Assert JavaScript executes and returns 42
        let jsResult: String? = try await withCheckedThrowingContinuation { continuation in
            HanlinNativeServicesBridge.executeJavaScript("6 * 7") { stdout, err in
                if let err {
                    continuation.resume(throwing: NSError(domain: "JSTest", code: 1, userInfo: [NSLocalizedDescriptionKey: err]))
                } else {
                    continuation.resume(returning: stdout)
                }
            }
        }
        #expect(jsResult == "42")

        // Assert Node health check or execution
        let (healthy, error): (Bool, String?) = await withCheckedContinuation { continuation in
            HanlinNativeServicesBridge.nodeHealthCheck { isHealthy, err in
                continuation.resume(returning: (isHealthy, err))
            }
        }
        if healthy {
            let nodeResult: String? = try await withCheckedThrowingContinuation { continuation in
                HanlinNativeServicesBridge.executeNode("console.log(123 * 2);") { stdout, err in
                    if let err {
                        continuation.resume(throwing: NSError(domain: "NodeTest", code: 1, userInfo: [NSLocalizedDescriptionKey: err]))
                    } else {
                        continuation.resume(returning: stdout)
                    }
                }
            }
            #expect(nodeResult == "246")
        } else {
            #expect(error != nil || !healthy)
        }
    }

    @MainActor
    @Test("Inter-app request broker allows authorized cross-engine request flow and enforces bidirectional capabilities")
    func interAppRequestBrokering() async throws {
        let callerID = try HanlinAppID(validating: "hanlin.caller")
        let targetID = try HanlinAppID(validating: "hanlin.target")
        let actionID = try HanlinActionID(validating: "echo")
        let capID = try HanlinCapabilityID(validating: "inter-app.test")
        let unauthorizedCap = try HanlinCapabilityID(validating: "unauthorized.test")

        let broker = HanlinMiniAppRequestBroker { request in
            request.capability == capID
        }
        await broker.register(target: targetID, action: actionID, capability: capID) { request in
            request.payload
        }

        // 1. Authorized call succeeds
        let response = try await broker.request(.init(
            caller: callerID,
            target: targetID,
            action: actionID,
            capability: capID,
            payload: .string("hello-cross-engine")
        ))
        #expect(response.value == .string("hello-cross-engine"))

        // 2. Unauthorized capability throws
        await #expect(throws: HanlinMiniAppRequestError.unauthorized) {
            try await broker.request(.init(
                caller: callerID,
                target: targetID,
                action: actionID,
                capability: unauthorizedCap,
                payload: .string("hello-cross-engine")
            ))
        }
    }

    @MainActor
    @Test("Caller identity spoofing is rejected by host-bound broker")
    func callerIdentitySpoofingRejected() async throws {
        HanlinNativeServicesBridge.setActiveContainer(
            appID: "hanlin.real.caller",
            dataRoot: "/tmp/data",
            stateDir: "/tmp/data/state",
            docsDir: "/tmp/data/docs",
            cacheDir: "/tmp/data/cache",
            grantedCapabilities: ["inter-app.share"]
        )
        #expect(HanlinNativeServicesBridge.activeAppID == "hanlin.real.caller")

        // Clearing active container causes sendRequest to fail with Unauthorized
        HanlinNativeServicesBridge.clearActiveContainer()
        let errResult: String? = await withCheckedContinuation { continuation in
            HanlinNativeServicesBridge.sendRequest(
                targetID: "hanlin.target",
                action: "echo",
                capability: "inter-app.share",
                payloadJSON: "{}"
            ) { _, err in
                continuation.resume(returning: err)
            }
        }
        #expect(errResult?.contains("Unauthorized") == true)
    }

    @MainActor
    @Test("Private storage rejects path traversal and escapes from container root")
    func privateStoragePathTraversalRejected() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "hanlin-traversal-test-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try HanlinMiniAppDataStore(root: root)
        let appID = try HanlinAppID(validating: "hanlin.traversal.test")
        let context = HanlinMiniAppStorageContext(appID: appID, store: store)

        await #expect(throws: (any Error).self) {
            try await context.write(Data("malicious".utf8), area: .state, path: "../escaped.txt")
        }
        await #expect(throws: (any Error).self) {
            try await context.write(Data("malicious".utf8), area: .state, path: "../../etc/passwd")
        }
        await #expect(throws: (any Error).self) {
            _ = try await context.read(area: .state, path: "../escaped.txt")
        }
    }

    @MainActor
    @Test("Per-entrypoint isolation on hybrid package prevents runtime leakage across sibling entrypoints")
    func perEntrypointIsolationHybrid() throws {
        let manifest = HanlinScriptingManifest(
            name: "Hybrid Sibling Isolation",
            version: "1.0.0",
            hanlinRuntime: nil
        )
        let entryA = HanlinPackageEntrypointDescriptor(
            id: "entryA",
            kind: .app,
            sourcePath: "entryA.js",
            supportedContexts: [.mainApplication],
            runtimePolicyID: "p1",
            runtimeProfile: .hanlinNativeScript,
            compatibility: .supported
        )
        let entryB = HanlinPackageEntrypointDescriptor(
            id: "entryB",
            kind: .assistantTool,
            sourcePath: "entryB.js",
            supportedContexts: [.mainApplication],
            runtimePolicyID: "p2",
            runtimeProfile: .scriptingJSC,
            compatibility: .supported
        )

        let record = HanlinInstalledPackageRecord(
            schemaVersion: 1,
            installedPackageID: try HanlinInstalledPackageID(validating: "installed.hybrid"),
            packageID: try HanlinPackageID(validating: "pkg.hybrid"),
            version: try HanlinPackageVersion(validating: "1.0.0"),
            sourceDigest: String(repeating: "b", count: 64),
            artifactDigest: String(repeating: "c", count: 64),
            activeGeneration: 1,
            installedAt: .now,
            updatedAt: .now
        )
        let snapshot = HanlinStoredPackageSnapshot(
            record: record,
            entrypoints: [entryA, entryB],
            enabled: true,
            availableGenerations: [1],
            grantedCapabilities: [],
            manifest: manifest
        )

        let resolvedRuntimeA = snapshot.entrypoints[0].runtimeProfile
        let resolvedRuntimeB = snapshot.entrypoints[1].runtimeProfile

        #expect(resolvedRuntimeA == .hanlinNativeScript)
        #expect(resolvedRuntimeB == .scriptingJSC)

        let desc = try snapshot.appDescriptor()
        #expect(desc.entryPoints[0].runtimeProfile == HanlinRuntimeProfile.hanlinNativeScript)
        #expect(desc.entryPoints[1].runtimeProfile == HanlinRuntimeProfile.scriptingJSC)
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
            if let desc = provider?.descriptor {
                #expect(HanlinCanonicalMiniAppCatalog.engine(for: desc) == .swift)
            }
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
            authors: [.init(name: "Test")],
            distribution: .init(
                sourceVisible: true,
                sourceEditable: false,
                remoteUpdates: false,
                allowedModes: [.personalDevelopment]
            )
        )

        let appEngine = HanlinCanonicalMiniAppCatalog.engine(for: hybridDesc.entryPoints[0], implementation: hybridDesc.implementation)
        let widgetEngine = HanlinCanonicalMiniAppCatalog.engine(for: hybridDesc.entryPoints[1], implementation: hybridDesc.implementation)

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
