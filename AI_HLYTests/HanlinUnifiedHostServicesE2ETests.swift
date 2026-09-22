import Testing
@testable import AI_Hanlin
import HanlinPlatformContracts
import HanlinMiniAppCore

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
        // (may throw other errors depending on runtime state, but not .runtimeDisabledByUser)
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

    @Test func crossCallerConcurrency() async throws {
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

    // MARK: - Section 19: Storage Isolation Acceptance

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
        try await broker.writeFile(at: "test.txt", data: Data("Value-A".utf8), area: .documents, context: ctxA)
        try await broker.writeFile(at: "test.txt", data: Data("Value-B".utf8), area: .documents, context: ctxB)

        let readA = try await broker.readFile(at: "test.txt", area: .documents, context: ctxA)
        let readB = try await broker.readFile(at: "test.txt", area: .documents, context: ctxB)

        #expect(String(data: readA, encoding: .utf8) == "Value-A")
        #expect(String(data: readB, encoding: .utf8) == "Value-B")
    }

    @Test func sharedDataRequiresCapability() async throws {
        let appID = try HanlinAppID(validating: "shared-data-test-app")
        let broker = HanlinHostServicesBroker.shared

        // Context WITHOUT shared-data capability
        let ctxWithout = HanlinHostCallContext.forMiniApp(
            appID: appID,
            origin: .system,
            capabilities: ["files"],
            canPresentUI: true
        )

        do {
            _ = try await broker.readFile(at: "shared.txt", area: .data, scope: .shared, context: ctxWithout)
            Issue.record("Expected capabilityNotGranted for shared scope")
        } catch let error as HanlinHostServiceError {
            if case .capabilityNotGranted(let cap) = error {
                #expect(cap == "shared-data")
            } else {
                Issue.record("Unexpected error: \(error)")
            }
        }

        // Context WITH shared-data capability
        let ctxWith = HanlinHostCallContext.forMiniApp(
            appID: appID,
            origin: .system,
            capabilities: ["files", "shared-data"],
            canPresentUI: true
        )

        try await broker.writeFile(at: "shared.txt", data: Data("SharedContent".utf8), area: .data, scope: .shared, context: ctxWith)
        let readShared = try await broker.readFile(at: "shared.txt", area: .data, scope: .shared, context: ctxWith)
        #expect(String(data: readShared, encoding: .utf8) == "SharedContent")
    }

    // MARK: - Section 20: SQLite Acceptance

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
            if case .invalidPath = error {
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
        let rows = try await adapter.fetchAll(
            handle: "valid",
            sql: "SELECT * FROM items WHERE id = ?;",
            arguments: ["first"],
            context: ctx
        )
        #expect(!rows.isEmpty)
        #expect(rows.first?["id"] as? String == "first")
        try await adapter.close(handle: "valid", context: ctx)
    }

    // MARK: - Section 21: NativeScript and Expo Multi-Session

    @Test func multiSessionBridgeRegistration() {
        let app1 = try! HanlinAppID(validating: "miniapp-one")
        let app2 = try! HanlinAppID(validating: "miniapp-two")

        let ns1 = NativeScriptHostServicesAdapter(appID: app1, grantedCapabilities: ["javascript"], sessionID: "session-1")
        let ns2 = NativeScriptHostServicesAdapter(appID: app2, grantedCapabilities: ["javascript"], sessionID: "session-2")

        HanlinNativeServicesBridge.register(ns1, forSessionID: "session-1")
        HanlinNativeServicesBridge.register(ns2, forSessionID: "session-2")

        let p1 = HanlinNativeServicesBridge.provider(forSessionID: "session-1")
        let p2 = HanlinNativeServicesBridge.provider(forSessionID: "session-2")

        #expect(p1 !== nil)
        #expect(p2 !== nil)
        #expect(p1 !== p2)

        HanlinNativeServicesBridge.unregisterProvider(forSessionID: "session-1")
        HanlinNativeServicesBridge.unregisterProvider(forSessionID: "session-2")
    }
}
