import Testing
@testable import AI_HLY
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

    @Test func sqliteHostAdapterRequiresAppContext() async throws {
        let agentContext = HanlinHostCallContext.forAgent()
        do {
            _ = try await HanlinSQLiteHostAdapter.shared.open(
                handle: "test-db",
                name: "test.db",
                context: agentContext
            )
            // Agent has "all" capabilities, so capability check passes.
            // But SQLite operations currently require app context.
            Issue.record("Expected invalidCallerContext error for agent context")
        } catch let error as HanlinHostServiceError {
            if case .invalidCallerContext = error {
                // Expected — SQLite requires an app ID
            } else {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }

    @Test func miniAppContextCapabilityEnforcement() async throws {
        let appID = try HanlinAppID(validating: "restricted-app")
        let context = HanlinHostCallContext.forMiniApp(
            appID: appID,
            origin: .scriptPackage,
            capabilities: ["files"], // No "sqlite" capability
            canPresentUI: false
        )
        do {
            _ = try await HanlinSQLiteHostAdapter.shared.open(
                handle: "test-db",
                name: "test.db",
                context: context
            )
            Issue.record("Expected capabilityNotGranted error")
        } catch let error as HanlinHostServiceError {
            if case .capabilityNotGranted = error {
                // Expected — missing "sqlite" capability
            } else {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }
}
