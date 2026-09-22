import CryptoKit
import Foundation
import Testing
@testable import AI_Hanlin
import HanlinPlatformContracts
import HanlinMiniAppCore
import HanlinScriptContracts
import HanlinScriptStore
import HanlinExpoRuntime

@Suite("Unified Host Services E2E")
struct HanlinUnifiedHostServicesE2ETests {

    @Test func runtimeBrokerRespectsAvailabilityToggle() async throws {
        let store = RuntimeAvailabilityStore.shared
        let kind = RuntimeKind.shell
        let original = store.isAvailable(kind)
        defer { store.setAvailable(original, for: kind) }

        // Disable the runtime
        store.setAvailable(false, for: kind)

        let context = HanlinHostCallContext.forAgent()
        do {
            _ = try await HanlinHostServicesBroker.shared.executeRuntime(
                kind,
                source: "echo hello",
                context: context
            )
            Issue.record("Expected runtimeDisabledByUser when runtime is disabled")
        } catch let error as HanlinHostServiceError {
            if case .runtimeDisabledByUser = error {
                // Expected — the broker correctly prevented execution
            } else {
                Issue.record("Unexpected error type: \(error)")
            }
        }

        // Re-enable — should no longer throw the disabled error
        store.setAvailable(true, for: kind)
    }

    @Test func capabilityAuthorityGrantRevokePersists() async throws {
        let appID = try HanlinAppID(validating: "e2e-test-app")
        let authority = HanlinHostCapabilityAuthority.shared

        // Clean state
        let originalGrants = await authority.grantedCapabilities(for: appID)
        defer {
            Task {
                // Restore original state
                for cap in await authority.grantedCapabilities(for: appID) {
                    await authority.revoke(capability: cap, for: appID)
                }
                for cap in originalGrants {
                    await authority.grant(capability: cap, for: appID)
                }
            }
        }

        // Grant a capability
        await authority.grant(capability: "runtime.node", for: appID)
        let granted = await authority.grantedCapabilities(for: appID)
        #expect(granted.contains("runtime.node"))

        // Revoke it
        await authority.revoke(capability: "runtime.node", for: appID)
        let afterRevoke = await authority.grantedCapabilities(for: appID)
        #expect(!afterRevoke.contains("runtime.node"))
    }

    @Test func packageStoreGrantPrecedenceAndLiveRevocation() async throws {
        let fixture = try HostServicesPackageFixture()
        defer { fixture.remove() }

        let store = try HanlinAtomicScriptStore(root: fixture.storeRoot)
        _ = try await store.install(
            plan: fixture.plan,
            artifactDirectory: fixture.artifactRoot,
            artifactManifest: fixture.manifest
        )

        let authority = HanlinHostCapabilityAuthority.shared
        await authority.usePackageGrantStore(store)

        // Deliberately grant the compiled-app domain. Package identity must win.
        await authority.grant(capability: "network", for: fixture.appID)
        defer {
            Task {
                await authority.revoke(capability: "network", for: fixture.appID)
                await authority.clearPackageGrantStore()
            }
        }

        let context = HanlinHostCallContext.forMiniApp(
            appID: fixture.appID,
            installedPackageID: fixture.installedPackageID,
            origin: .scriptPackage,
            capabilities: ["network"],
            canPresentUI: true
        )

        let initial = await authority.authorize(capability: "network", context: context)
        #expect(initial == .notGranted)

        try await store.setCapabilityGranted(true, capability: fixture.networkCapability, for: fixture.installedPackageID)
        try await HanlinHostServicesBroker.shared.requireCapability("network", context: context)

        // Revoke through the real package store and reuse the exact same context.
        try await store.setCapabilityGranted(false, capability: fixture.networkCapability, for: fixture.installedPackageID)
        await #expect(throws: HanlinHostServiceError.self) {
            try await HanlinHostServicesBroker.shared.requireCapability("network", context: context)
        }
    }

    @Test @MainActor func crossCallerConcurrency() async throws {
        let appA = try HanlinAppID(validating: "app-concurrent-a")
        let appB = try HanlinAppID(validating: "app-concurrent-b")

        let swiftAdapter = SwiftMiniAppHostServicesAdapter(appID: appA, capabilities: ["sqlite", "files"])
        let nsAdapter = NativeScriptHostServicesAdapter(
            appID: appB,
            grantedCapabilities: ["javascript", "files"],
            sessionID: "ns-concurrent-session"
        )
        let expoAdapter = ExpoHostServicesAdapter(
            appID: appB,
            grantedCapabilities: ["javascript", "files"],
            sessionID: "expo-concurrent-session"
        )
        let agentContext = AgentHostServicesAdapter.makeContext()
        _ = nsAdapter // used for multi-session verification below

        // Submit concurrent operations across different caller domains
        async let r1 = HanlinRuntimeBroker.shared.execute(kind: .javaScriptCore, source: "100 + 1", context: agentContext)
        async let r2 = swiftAdapter.writeFile(path: "concurrent_a.txt", data: Data("swift-data".utf8))
        async let r3 = expoAdapter.executeRuntime(kind: "jscore", source: "200 + 2")

        let (res1, _, res3) = try await (r1, r2, r3)

        #expect(res1.value == .number(101))
        #expect(res3 == "202")

        let swiftRead = try await swiftAdapter.readFile(path: "concurrent_a.txt")
        #expect(String(data: swiftRead, encoding: .utf8) == "swift-data")
    }

    // MARK: - Storage Isolation Acceptance

    @Test func storageIsolationBetweenApps() async throws {
        let appA = try HanlinAppID(validating: "isolation-app-a")
        let appB = try HanlinAppID(validating: "isolation-app-b")

        let ctxA = HanlinHostCallContext.forMiniApp(
            appID: appA,
            origin: .system,
            capabilities: ["files", "sqlite"],
            canPresentUI: true
        )
        let ctxB = HanlinHostCallContext.forMiniApp(
            appID: appB,
            origin: .system,
            capabilities: ["files", "sqlite"],
            canPresentUI: true
        )

        let broker = HanlinHostServicesBroker.shared

        // Write same virtual path with different content
        try await broker.writeFile(virtualPath: "test.txt", area: .documents, data: Data("Value-A".utf8), context: ctxA)
        try await broker.writeFile(virtualPath: "test.txt", area: .documents, data: Data("Value-B".utf8), context: ctxB)

        let readA = try await broker.readFile(virtualPath: "test.txt", area: .documents, context: ctxA)
        let readB = try await broker.readFile(virtualPath: "test.txt", area: .documents, context: ctxB)

        #expect(String(data: readA ?? Data(), encoding: .utf8) == "Value-A")
        #expect(String(data: readB ?? Data(), encoding: .utf8) == "Value-B")
    }

    @Test func fileCapabilityRequired() async throws {
        let appID = try HanlinAppID(validating: "no-file-cap-app")
        let broker = HanlinHostServicesBroker.shared

        // Context WITHOUT files capability
        let ctxWithout = HanlinHostCallContext.forMiniApp(
            appID: appID,
            origin: .system,
            capabilities: [],
            canPresentUI: true
        )

        do {
            _ = try await broker.readFile(virtualPath: "test.txt", area: .data, context: ctxWithout)
            Issue.record("Expected capabilityNotGranted when files capability is absent")
        } catch let error as HanlinHostServiceError {
            if case .capabilityNotGranted = error {
                // Expected
            } else {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    // MARK: - SQLite Acceptance

    @Test func sqliteScopeAndTraversalRejection() async throws {
        let appID = try HanlinAppID(validating: "sqlite-test-app")
        let ctx = HanlinHostCallContext.forMiniApp(
            appID: appID,
            origin: .system,
            capabilities: ["sqlite"],
            canPresentUI: true
        )

        let adapter = HanlinSQLiteHostAdapter.shared

        // Traversal rejection
        do {
            _ = try await adapter.open(handle: "bad", name: "../../evil.db", context: ctx)
            Issue.record("Expected path traversal rejection in SQLite open")
        } catch let error as HanlinHostServiceError {
            if case .pathOutOfScope = error {
                // Expected
            } else {
                Issue.record("Unexpected error: \(error)")
            }
        }

        // Valid DB operations with bound parameters
        _ = try await adapter.open(handle: "valid", name: "app_data.db", context: ctx)
        try await adapter.execute(
            handle: "valid",
            sql: "CREATE TABLE IF NOT EXISTS items (id TEXT PRIMARY KEY, count INTEGER);",
            arguments: nil,
            context: ctx
        )
        try await adapter.execute(
            handle: "valid",
            sql: "INSERT OR REPLACE INTO items (id, count) VALUES (?, ?);",
            arguments: ["first", 42],
            context: ctx
        )
        let rowsJSON = try await adapter.fetchAllJSON(
            handle: "valid",
            sql: "SELECT * FROM items WHERE id = ?;",
            arguments: ["first"],
            context: ctx
        )
        let parsed = (try? JSONSerialization.jsonObject(with: Data(rowsJSON.utf8))) as? [[String: Any]]
        #expect(parsed?.isEmpty == false)
        #expect(parsed?.first?["id"] as? String == "first")
        try await adapter.close(handle: "valid", context: ctx)
    }

    // MARK: - NativeScript and Expo Multi-Session

    @Test func nativeScriptSessionsResolveExactlyAndTeardownIndependently() {
        let app1 = try! HanlinAppID(validating: "miniapp-one")
        let app2 = try! HanlinAppID(validating: "miniapp-two")

        let ns1 = NativeScriptHostServicesAdapter(appID: app1, grantedCapabilities: ["javascript"], sessionID: "session-1")
        let ns2 = NativeScriptHostServicesAdapter(appID: app2, grantedCapabilities: ["javascript"], sessionID: "session-2")

        HanlinNativeServicesBridge.register(ns1, forSessionID: "session-1")
        HanlinNativeServicesBridge.register(ns2, forSessionID: "session-2")
        HanlinNativeServicesBridge.register(ns2) // legacy fallback must not affect exact lookup

        let p1 = HanlinNativeServicesBridge.provider(forSessionID: "session-1")
        let p2 = HanlinNativeServicesBridge.provider(forSessionID: "session-2")

        #expect(p1 !== nil)
        #expect(p2 !== nil)
        #expect(p1 !== p2)
        #expect(HanlinNativeServicesBridge.provider(forSessionID: "missing-session") == nil)

        HanlinNativeServicesBridge.unregisterProvider(forSessionID: "session-1")
        #expect(HanlinNativeServicesBridge.provider(forSessionID: "session-1") == nil)
        #expect(HanlinNativeServicesBridge.provider(forSessionID: "session-2") === ns2)
        HanlinNativeServicesBridge.unregisterProvider(forSessionID: "session-2")
        HanlinNativeServicesBridge.register(nil)
    }

    @Test func expoAppContextsResolveExactlyAndTeardownIndependently() throws {
        let app1 = try HanlinAppID(validating: "expo-miniapp-one")
        let app2 = try HanlinAppID(validating: "expo-miniapp-two")
        let expo1 = ExpoHostServicesAdapter(appID: app1, grantedCapabilities: [], sessionID: "expo-session-1")
        let expo2 = ExpoHostServicesAdapter(appID: app2, grantedCapabilities: [], sessionID: "expo-session-2")
        let context1 = NSObject()
        let context2 = NSObject()
        let unboundContext = NSObject()

        HanlinExpoHostServicesBridge.register(provider: expo1, forSessionID: expo1.sessionID)
        HanlinExpoHostServicesBridge.register(provider: expo2, forSessionID: expo2.sessionID)
        HanlinExpoHostServicesBridge.register(provider: expo2) // legacy fallback only
        #expect(HanlinExpoHostServicesBridge.bind(sessionID: expo1.sessionID, toAppContext: context1))
        #expect(HanlinExpoHostServicesBridge.bind(sessionID: expo2.sessionID, toAppContext: context2))

        #expect(HanlinExpoHostServicesBridge.provider(forAppContext: context1) === expo1)
        #expect(HanlinExpoHostServicesBridge.provider(forAppContext: context2) === expo2)
        #expect(HanlinExpoHostServicesBridge.provider(forAppContext: unboundContext) == nil)

        HanlinExpoHostServicesBridge.unregister(sessionID: expo1.sessionID)
        #expect(HanlinExpoHostServicesBridge.provider(forAppContext: context1) == nil)
        #expect(HanlinExpoHostServicesBridge.provider(forAppContext: context2) === expo2)

        HanlinExpoHostServicesBridge.unregister(sessionID: expo2.sessionID)
        HanlinExpoHostServicesBridge.register(provider: nil)
    }
}

private struct HostServicesPackageFixture {
    let root: URL
    let storeRoot: URL
    let artifactRoot: URL
    let manifest: HanlinPackageArtifactManifest
    let installedPackageID: HanlinInstalledPackageID
    let appID: HanlinAppID
    let networkCapability: HanlinCapabilityID

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "hanlin-host-services-\(UUID().uuidString.lowercased())",
            directoryHint: .isDirectory
        )
        storeRoot = root.appending(path: "store", directoryHint: .isDirectory)
        artifactRoot = root.appending(path: "artifact", directoryHint: .isDirectory)
        installedPackageID = try HanlinInstalledPackageID(validating: "host-services-fixture")
        appID = try HanlinAppID(validating: "host-services-fixture-app")
        networkCapability = try HanlinCapabilityID(validating: "network")

        try FileManager.default.createDirectory(at: artifactRoot, withIntermediateDirectories: true)
        let source = Data("export default 1".utf8)
        try source.write(to: artifactRoot.appending(path: "main.js"))
        let file = HanlinArtifactFile(
            logicalPath: "main.js",
            sha256: SHA256.hash(data: source).map { String(format: "%02x", $0) }.joined(),
            byteCount: Int64(source.count),
            context: .app
        )
        manifest = HanlinPackageArtifactManifest(
            compilerVersion: "6.0.3",
            compilerIntegrity: "sha512-fixture",
            compilerOptionsHash: String(repeating: "a", count: 64),
            baselineID: "fixture",
            baselineDigest: String(repeating: "b", count: 64),
            hanlinABIVersion: "2",
            packageContentDigest: String(repeating: "c", count: 64),
            cacheFingerprint: String(repeating: "d", count: 64),
            files: [file]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(manifest).write(to: artifactRoot.appending(path: "artifact-manifest.json"))
    }

    var plan: HanlinInstallPlan {
        get throws {
            HanlinInstallPlan(
                installedPackageID: installedPackageID,
                packageID: try HanlinPackageID(validating: "host-services-package"),
                version: try HanlinPackageVersion(validating: "1.0.0"),
                sourceDigest: manifest.packageContentDigest,
                entrypoints: [],
                requestedCapabilities: [],
                grantedCapabilities: []
            )
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
