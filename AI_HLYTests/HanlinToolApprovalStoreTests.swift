import Foundation
import Testing
@testable import AI_Hanlin

@Suite @MainActor struct HanlinToolApprovalStoreTests {
    private func scope(account: String = "account-a", provider: String = "provider-a", tool: String = "write",
                       manifest: String = String(repeating: "a", count: 64),
                       permissions: String = String(repeating: "b", count: 64)) -> HanlinToolApprovalScope {
        .init(app: "hanlin", account: account, workspace: "library", providerID: provider, toolID: tool,
              manifestFingerprint: manifest, permissionFingerprint: permissions)
    }
    private func isolatedDefaults() throws -> (String, UserDefaults) {
        let name = "hanlin-tool-grants-test-" + UUID().uuidString
        return (name, try #require(UserDefaults(suiteName: name)))
    }

    @Test func firstGrantIsAvailableToAnotherConversationOwnerAndReload() throws {
        let (name, defaults) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let first = HanlinToolApprovalStore(defaults: defaults)
        let second = HanlinToolApprovalStore(defaults: defaults)
        #expect(!first.allows(scope()))
        #expect(first.remember(scope(), title: "Write"))
        #expect(second.allows(scope()))
        let reloaded = HanlinToolApprovalStore(defaults: try #require(UserDefaults(suiteName: name)))
        #expect(reloaded.allows(scope()))
        #expect(reloaded.grants.count == 1)
        #expect(reloaded.remember(scope(), title: "Write"))
        #expect(reloaded.grants.count == 1)
    }

    @Test func accountProviderToolManifestAndPermissionChangesDoNotBorrowGrants() throws {
        let (name, defaults) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = HanlinToolApprovalStore(defaults: defaults)
        #expect(store.remember(scope(), title: "Write"))
        for different in [
            scope(account: "account-b"), scope(provider: "provider-b"), scope(tool: "delete"),
            scope(manifest: String(repeating: "c", count: 64)),
            scope(permissions: String(repeating: "d", count: 64))
        ] { #expect(!store.allows(different)) }
    }

    @Test func revocationImmediatelyAffectsExistingOwners() throws {
        let (name, defaults) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let first = HanlinToolApprovalStore(defaults: defaults)
        let second = HanlinToolApprovalStore(defaults: defaults)
        #expect(first.remember(scope(), title: "Write"))
        let grant = try #require(second.grants.first)
        #expect(second.revoke(id: grant.id))
        #expect(!first.allows(scope()))
        #expect(first.remember(scope(), title: "Write"))
        #expect(second.revokeAll())
        #expect(first.grants.isEmpty)
    }

    @Test func historicalAllowOnceNeverBecomesPersistentConsent() throws {
        let (name, defaults) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(["tool":"write", "disposition":"allowedOnce"], forKey: "old-conversation-approval")
        let store = HanlinToolApprovalStore(defaults: defaults)
        #expect(!store.allows(scope()))
        #expect(store.grants.isEmpty)
    }

    @Test func corruptOrUnknownStorageVersionDoesNotGrant() throws {
        let (name, defaults) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let key = "grant-test"
        let store = HanlinToolApprovalStore(defaults: defaults, key: key)
        for bytes in [Data("not JSON".utf8), Data(#"{"version":99,"grants":[]}"#.utf8)] {
            defaults.set(bytes, forKey: key)
            #expect(!store.allows(scope()))
        }
        #expect(!store.remember(scope(manifest: "unverified"), title: "Write"))
    }
}
