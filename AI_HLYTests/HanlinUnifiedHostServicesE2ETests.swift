import CryptoKit
import Foundation
import Testing
@testable import AI_Hanlin
import HanlinPlatformContracts
import HanlinMiniAppCore
import HanlinScriptContracts
import HanlinScriptStore
import HanlinExpoRuntime
import HanlinNativeScriptRuntime
import HanlinNativeScriptCoreSupport

@Suite("Unified Host Services E2E", .serialized)
struct HanlinUnifiedHostServicesE2ETests {

    @Test func runtimeBrokerAutoStartsStoppedRuntime() async throws {
        let store = RuntimeAvailabilityStore.shared
        let kind = RuntimeKind.shell
        let original = store.isAvailable(kind)
        defer { store.setAvailable(original, for: kind) }

        // Start from stopped state
        store.setAvailable(false, for: kind)
        #expect(!store.isAvailable(kind))

        let context = HanlinHostCallContext.forAgent()
        let result = try await HanlinHostServicesBroker.shared.executeRuntime(
            kind,
            source: "ls",
            context: context
        )
        #expect(result.exitCode == 0)
        // Auto-start should make the runtime available/running
        #expect(store.isAvailable(kind))
    }

    @Test func runtimeBrokerRespectsAvailabilityToggle() async throws {
        let context = HanlinHostCallContext.forMiniApp(
            appID: try HanlinAppID(validating: "unauthorized.caller"),
            origin: .system,
            capabilities: [],
            canPresentUI: false
        )
        do {
            _ = try await HanlinHostServicesBroker.shared.executeRuntime(
                .shell,
                source: "echo hello",
                context: context
            )
            Issue.record("Expected capabilityNotGranted error")
        } catch let error as HanlinHostServiceError {
            if case .capabilityNotGranted = error {
                // Expected rejection
            } else {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    @Test func capabilityAuthorityGrantRevokePersists() async throws {
        let appID = try HanlinAppID(validating: "e2e-test-app")
        let authority = HanlinHostCapabilityAuthority.shared

        // Clean state
        let originalGrants = await authority.grantedCapabilities(for: appID)
        // Grant a capability
        await authority.grant(capability: "runtime.node", for: appID)
        let granted = await authority.grantedCapabilities(for: appID)
        #expect(granted.contains("runtime.node"))

        // Revoke it
        await authority.revoke(capability: "runtime.node", for: appID)
        let afterRevoke = await authority.grantedCapabilities(for: appID)
        #expect(!afterRevoke.contains("runtime.node"))
        await authority.setGrants(originalGrants, for: appID)
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
        let originalAppGrants = await authority.grantedCapabilities(for: fixture.appID)
        await authority.grant(capability: "network", for: fixture.appID)
        do {
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
        } catch {
            await authority.setGrants(originalAppGrants, for: fixture.appID)
            await authority.clearPackageGrantStore()
            throw error
        }
        await authority.setGrants(originalAppGrants, for: fixture.appID)
        await authority.clearPackageGrantStore()
    }

    @Test @MainActor func crossCallerConcurrency() async throws {
        let suffix = UUID().uuidString.lowercased()
        let appA = try HanlinAppID(validating: "app-concurrent-a-\(suffix)")
        let appB = try HanlinAppID(validating: "app-concurrent-b-\(suffix)")

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
        let suffix = UUID().uuidString.lowercased()
        let appA = try HanlinAppID(validating: "isolation-app-a-\(suffix)")
        let appB = try HanlinAppID(validating: "isolation-app-b-\(suffix)")

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

    @Test func fileScopesOverwriteDeleteSharedGateAndSymlinkProtection() async throws {
        let suffix = UUID().uuidString.lowercased()
        let appID = try HanlinAppID(validating: "file-scope-app-\(suffix)")
        let packageID = try HanlinInstalledPackageID(validating: "file-scope-package-\(suffix)")
        let deniedAppID = try HanlinAppID(validating: "file-scope-denied-\(suffix)")
        let baseSession = try HanlinAppSessionID(validating: suffix)
        let baseRuntime = try HanlinRuntimeSessionID(validating: suffix)
        await HanlinHostCapabilityAuthority.shared.setGrants(["files", "shared-data"], for: appID)
        await HanlinHostCapabilityAuthority.shared.setGrants(["files"], for: deniedAppID)
        let makeContext: (HanlinHostStorageScope, Set<String>) -> HanlinHostCallContext = { scope, capabilities in
            HanlinHostCallContext(
                subject: .app(appID, installedPackageID: nil),
                origin: .system,
                appID: appID,
                installedPackageID: nil,
                appSessionID: baseSession,
                runtimeSessionID: baseRuntime,
                effectiveCapabilities: capabilities,
                storageScope: scope,
                runtimeWorkspaceIdentifier: "file-scope-\(suffix)",
                userGesturePresent: false,
                canPresentUI: false
            )
        }
        let app = makeContext(.app(appID), ["files"])
        let package = makeContext(.package(packageID), ["files"])
        let agent = HanlinHostCallContext.forAgent(runtimeSessionID: baseRuntime)
        let sharedDenied = HanlinHostCallContext.forMiniApp(
            appID: deniedAppID,
            origin: .system,
            capabilities: ["files"],
            storageScope: .shared,
            canPresentUI: false
        )
        let sharedAllowed = makeContext(.shared, ["files", "shared-data"])
        let broker = HanlinHostServicesBroker.shared
        let path = "scope-\(suffix)/test.txt"

        try await broker.writeFile(virtualPath: path, area: .documents, data: Data("APP".utf8), context: app)
        try await broker.writeFile(virtualPath: path, area: .documents, data: Data("PACKAGE".utf8), context: package)
        try await broker.writeFile(virtualPath: path, area: .documents, data: Data("AGENT".utf8), context: agent)
        #expect(String(data: try #require(await broker.readFile(virtualPath: path, area: .documents, context: app)), encoding: .utf8) == "APP")
        #expect(String(data: try #require(await broker.readFile(virtualPath: path, area: .documents, context: package)), encoding: .utf8) == "PACKAGE")
        #expect(String(data: try #require(await broker.readFile(virtualPath: path, area: .documents, context: agent)), encoding: .utf8) == "AGENT")

        try await broker.writeFile(virtualPath: path, area: .documents, data: Data("OVERWRITTEN".utf8), context: app)
        #expect(String(data: try #require(await broker.readFile(virtualPath: path, area: .documents, context: app)), encoding: .utf8) == "OVERWRITTEN")
        try await broker.deleteFile(virtualPath: path, area: .documents, context: app)
        #expect(try await broker.readFile(virtualPath: path, area: .documents, context: app) == nil)

        await #expect(throws: HanlinHostServiceError.self) {
            try await broker.writeFile(virtualPath: path, area: .documents, data: Data("DENIED".utf8), context: sharedDenied)
        }
        try await broker.writeFile(virtualPath: path, area: .documents, data: Data("SHARED".utf8), context: sharedAllowed)
        #expect(String(data: try #require(await broker.readFile(virtualPath: path, area: .documents, context: sharedAllowed)), encoding: .utf8) == "SHARED")

        let linkPath = "scope-\(suffix)/escape-link"
        let linkURL = try await HanlinFileService.physicalURL(
            for: linkPath,
            area: .documents,
            scope: app.storageScope,
            context: app
        )
        try FileManager.default.createDirectory(at: linkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let outside = FileManager.default.temporaryDirectory.appending(path: "hanlin-outside-\(suffix)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: linkURL)
            try? FileManager.default.removeItem(at: outside)
        }
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: outside)
        await #expect(throws: HanlinHostServiceError.self) {
            _ = try await broker.readFile(
                virtualPath: "\(linkPath)/secret.txt",
                area: .documents,
                context: app
            )
        }
    }

    // MARK: - SQLite Acceptance

    @Test func sqliteScopeAndTraversalRejection() async throws {
        let appID = try HanlinAppID(validating: "sqlite-test-app-\(UUID().uuidString.lowercased())")
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

    @Test func sqliteTransactionsTypesConcurrencyAndScopeIsolation() async throws {
        let suffix = UUID().uuidString.lowercased()
        let appID = try HanlinAppID(validating: "sqlite-app-\(suffix)")
        let packageID = try HanlinInstalledPackageID(validating: "sqlite-package-\(suffix)")
        let session = try HanlinAppSessionID(validating: suffix)
        let runtime = try HanlinRuntimeSessionID(validating: suffix)
        await HanlinHostCapabilityAuthority.shared.setGrants(["sqlite", "shared-data"], for: appID)
        let makeContext: (HanlinHostStorageScope) -> HanlinHostCallContext = { scope in
            HanlinHostCallContext(
                subject: .app(appID, installedPackageID: nil),
                origin: .system,
                appID: appID,
                installedPackageID: nil,
                appSessionID: session,
                runtimeSessionID: runtime,
                effectiveCapabilities: ["sqlite", "shared-data"],
                storageScope: scope,
                runtimeWorkspaceIdentifier: "sqlite-\(suffix)",
                userGesturePresent: false,
                canPresentUI: false
            )
        }
        let contexts = [
            ("app", makeContext(.app(appID))),
            ("package", makeContext(.package(packageID))),
            ("agent", HanlinHostCallContext.forAgent(runtimeSessionID: runtime)),
            ("shared", makeContext(.shared))
        ]
        let adapter = HanlinSQLiteHostAdapter.shared

        for (label, context) in contexts {
            let handle = "scope-\(label)-\(suffix)"
            _ = try await adapter.open(
                handle: handle,
                name: "identical.db",
                context: context,
                foreignKeys: true,
                walMode: true
            )
            try await adapter.execute(
                handle: handle,
                sql: "CREATE TABLE IF NOT EXISTS scope_values (label TEXT NOT NULL); DELETE FROM scope_values; INSERT INTO scope_values(label) VALUES (?);",
                arguments: [label],
                context: context
            )
            let json = try await adapter.fetchAllJSON(
                handle: handle,
                sql: "SELECT label FROM scope_values;",
                context: context
            )
            #expect(json.contains("\"label\":\"\(label)\""))
        }

        let context = HanlinHostCallContext.forAgent(runtimeSessionID: try HanlinRuntimeSessionID(validating: UUID().uuidString.lowercased()))
        let handle = "full-\(suffix)"
        _ = try await adapter.open(handle: handle, name: "full-\(suffix).db", context: context, foreignKeys: true, walMode: true)
        try await adapter.execute(
            handle: handle,
            sql: "CREATE TABLE parent(id INTEGER PRIMARY KEY); CREATE TABLE child(id INTEGER PRIMARY KEY, parent_id INTEGER REFERENCES parent(id)); CREATE TABLE values_table(id INTEGER PRIMARY KEY, text_value TEXT, payload BLOB, nullable TEXT);",
            context: context
        )

        try await adapter.execute(handle: handle, sql: "BEGIN;", context: context)
        try await adapter.execute(
            handle: handle,
            sql: "INSERT INTO values_table(id, text_value, payload, nullable) VALUES (?, ?, ?, ?);",
            arguments: [1, "שלום", Data([0x00, 0x2A, 0xFF]), NSNull()],
            context: context
        )
        try await adapter.execute(handle: handle, sql: "ROLLBACK;", context: context)
        let rolledBack = try await adapter.fetchAllJSON(
            handle: handle,
            sql: "SELECT COUNT(*) AS count FROM values_table;",
            context: context
        )
        #expect(rolledBack.contains("\"count\":0"))

        try await adapter.execute(handle: handle, sql: "BEGIN;", context: context)
        try await adapter.execute(
            handle: handle,
            sql: "INSERT INTO values_table(id, text_value, payload, nullable) VALUES (?, ?, ?, ?);",
            arguments: [1, "שלום", Data([0x00, 0x2A, 0xFF]), NSNull()],
            context: context
        )
        try await adapter.execute(handle: handle, sql: "COMMIT;", context: context)
        let typed = try await adapter.fetchAllJSON(
            handle: handle,
            sql: "SELECT text_value, hex(payload) AS payload_hex, nullable IS NULL AS was_null FROM values_table WHERE id = ?;",
            arguments: [1],
            context: context
        )
        #expect(typed.contains("שלום"))
        #expect(typed.contains("002AFF"))
        #expect(typed.contains("\"was_null\":1"))

        try await adapter.execute(
            handle: handle,
            sql: "UPDATE values_table SET text_value = ? WHERE id = ?;",
            arguments: ["עודכן", 1],
            context: context
        )
        await #expect(throws: (any Error).self) {
            try await adapter.execute(
                handle: handle,
                sql: "INSERT INTO child(id, parent_id) VALUES (?, ?);",
                arguments: [1, 999],
                context: context
            )
        }

        async let first: Void = adapter.execute(
            handle: handle,
            sql: "INSERT INTO values_table(id, text_value) VALUES (?, ?);",
            arguments: [2, "A"],
            context: context
        )
        async let second: Void = adapter.execute(
            handle: handle,
            sql: "INSERT INTO values_table(id, text_value) VALUES (?, ?);",
            arguments: [3, "B"],
            context: context
        )
        _ = try await (first, second)
        let multiple = try await adapter.fetchAllJSON(
            handle: handle,
            sql: "SELECT COUNT(*) AS count FROM values_table;",
            context: context
        )
        #expect(multiple.contains("\"count\":3"))

        try await adapter.execute(handle: handle, sql: "DELETE FROM values_table WHERE id = ?;", arguments: [1], context: context)
        let afterDelete = try await adapter.fetchAllJSON(
            handle: handle,
            sql: "SELECT COUNT(*) AS count FROM values_table;",
            context: context
        )
        #expect(afterDelete.contains("\"count\":2"))
        try await adapter.close(handle: handle, context: context)
        for (label, scopedContext) in contexts {
            try await adapter.close(handle: "scope-\(label)-\(suffix)", context: scopedContext)
        }
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

    @Test func nativeScriptActiveBridgeIsolationAndNoGlobalLeakage() throws {
        let app1 = try HanlinAppID(validating: "miniapp-active-one")
        let app2 = try HanlinAppID(validating: "miniapp-active-two")
        let appLegacy = try HanlinAppID(validating: "miniapp-legacy")

        let ns1 = NativeScriptHostServicesAdapter(appID: app1, grantedCapabilities: ["javascript"], sessionID: "session-active-1")
        let ns2 = NativeScriptHostServicesAdapter(appID: app2, grantedCapabilities: ["javascript"], sessionID: "session-active-2")
        let legacyAdapter = NativeScriptHostServicesAdapter(appID: appLegacy, grantedCapabilities: ["javascript"], sessionID: "session-legacy")

        // 1. Register session 1 provider
        HanlinNativeServicesBridge.register(ns1, forSessionID: "session-active-1")
        let token1 = try #require(HanlinNativeServicesPrepareSessionBootstrap("session-active-1"))
        let bridge1 = try #require(HanlinNativeServicesBridge.claimSessionBridge(withToken: token1))

        // 2. Set active session bridge
        HanlinNativeServicesBridge.setActiveSession(bridge1, forSessionID: "session-active-1")
        #expect(HanlinNativeServicesBridge.activeSessionBridge() === bridge1)
        #expect(HanlinNativeServicesBridge.currentProvider() === ns1)

        // 3. Register legacy provider — active session must NOT leak to legacy global provider
        HanlinNativeServicesBridge.register(legacyAdapter)
        #expect(HanlinNativeServicesBridge.currentProvider() === ns1)

        // 4. Invalidate session 1
        HanlinNativeServicesBridge.unregisterProvider(forSessionID: "session-active-1")
        #expect(HanlinNativeServicesBridge.provider(forSessionID: "session-active-1") == nil)
        // Bound bridge is invalidated, so currentProvider must return nil, NOT legacyAdapter
        #expect(HanlinNativeServicesBridge.currentProvider() == nil)

        // 5. Clear active bridge
        HanlinNativeServicesBridge.clearActiveSessionBridge(forSessionID: "session-active-1")
        #expect(HanlinNativeServicesBridge.activeSessionBridge() == nil)

        // 6. Sequential session 2 works cleanly
        HanlinNativeServicesBridge.register(ns2, forSessionID: "session-active-2")
        let token2 = try #require(HanlinNativeServicesPrepareSessionBootstrap("session-active-2"))
        let bridge2 = try #require(HanlinNativeServicesBridge.claimSessionBridge(withToken: token2))
        HanlinNativeServicesBridge.setActiveSession(bridge2, forSessionID: "session-active-2")
        #expect(HanlinNativeServicesBridge.activeSessionBridge() === bridge2)
        #expect(HanlinNativeServicesBridge.currentProvider() === ns2)

        // 7. Teardown session 2
        HanlinNativeServicesBridge.clearActiveSessionBridge(forSessionID: "session-active-2")
        HanlinNativeServicesBridge.unregisterProvider(forSessionID: "session-active-2")
        HanlinNativeServicesBridge.register(nil)
        #expect(HanlinNativeServicesBridge.currentProvider() == nil)
    }

    @Test @MainActor func nativeScriptRuntimeRealLaunchFixtureAndTeardown() throws {
        let appID1 = try HanlinAppID(validating: "ns-fixture-app-1")
        let sessionID1 = "ns-session-" + UUID().uuidString.lowercased()

        let tempDir = FileManager.default.temporaryDirectory.appending(
            path: "hanlin-ns-acceptance-\(UUID().uuidString.lowercased())",
            directoryHint: .isDirectory
        )
        let appDir = tempDir.appending(path: "app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let packageJSON = """
        {
          "name": "ns-fixture-app",
          "version": "1.0.0",
          "main": "bundle.js",
          "hanlinRuntime": "hanlin-nativescript",
          "dependencies": {
            "@nativescript/core": "9.1.0"
          }
        }
        """
        try Data(packageJSON.utf8).write(to: appDir.appending(path: "package.json"))

        let bundleJS = """
        console.log("HANLIN_NS_FIXTURE_RUNNING");
        """
        try Data(bundleJS.utf8).write(to: appDir.appending(path: "bundle.js"))

        // Session 1:
        let adapter1 = NativeScriptHostServicesAdapter(
            appID: appID1,
            grantedCapabilities: ["network"],
            sessionID: sessionID1
        )
        HanlinNativeServicesBridge.register(adapter1, forSessionID: sessionID1)

        let session1 = try HanlinNativeScriptSession(
            applicationRoot: appDir,
            sessionID: sessionID1
        )

        // Starting session must bind host services and run main application without V8 crash
        try session1.start()
        #expect(session1.isActive)
        #expect(HanlinNativeServicesBridge.currentProvider() === adapter1)

        // Shutdown session 1
        session1.shutdown()
        #expect(!session1.isActive)
        HanlinNativeServicesBridge.unregisterProvider(forSessionID: sessionID1)
        #expect(HanlinNativeServicesBridge.provider(forSessionID: sessionID1) == nil)

        // Session 2 (sequential after session 1):
        let appID2 = try HanlinAppID(validating: "ns-fixture-app-2")
        let sessionID2 = "ns-session-" + UUID().uuidString.lowercased()
        let adapter2 = NativeScriptHostServicesAdapter(
            appID: appID2,
            grantedCapabilities: ["network"],
            sessionID: sessionID2
        )
        HanlinNativeServicesBridge.register(adapter2, forSessionID: sessionID2)

        let session2 = try HanlinNativeScriptSession(
            applicationRoot: appDir,
            sessionID: sessionID2
        )
        try session2.start()
        #expect(session2.isActive)
        #expect(HanlinNativeServicesBridge.currentProvider() === adapter2)

        session2.shutdown()
        #expect(!session2.isActive)
        HanlinNativeServicesBridge.unregisterProvider(forSessionID: sessionID2)
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
