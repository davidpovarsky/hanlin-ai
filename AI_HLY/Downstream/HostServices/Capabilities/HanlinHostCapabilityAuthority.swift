import Foundation
import HanlinPlatformContracts
import HanlinScriptStore

/// Result of evaluating a capability authorization request.
public enum HanlinHostCapabilityResult: Equatable, Sendable {
    case allowed
    case notGranted
    case notDeclared
    case systemDenied(String)
    case unavailable(String)
}

/// Unified capability authority for all host service operations across all
/// execution clients (agent, Swift Mini Apps, ScriptUI, NativeScript, Expo).
///
/// Retains legacy grant metadata for existing callers/registries.
/// Runtime identity, package lifecycle and iOS system permissions remain separate.
actor HanlinHostCapabilityAuthority {
    static let shared = HanlinHostCapabilityAuthority()

    /// Per-compiled-app grant tracking. Key is `appID.rawValue`.
    private var compiledAppGrants: [String: Set<String>] = [:]
    private var packageGrantStore: HanlinAtomicScriptStore?

    private let persistenceKey = "hanlin.host-capability-grants.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: persistenceKey),
           let decoded = try? JSONDecoder().decode([String: Set<String>].self, from: data) {
            self.compiledAppGrants = decoded
        }
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(compiledAppGrants) {
            UserDefaults.standard.set(encoded, forKey: persistenceKey)
        }
    }

    /// Installs the authoritative scripting-package grant source.
    /// Registration is idempotent and does not copy or cache package grants.
    func usePackageGrantStore(_ store: HanlinAtomicScriptStore) {
        packageGrantStore = store
    }

    func clearPackageGrantStore() {
        packageGrantStore = nil
    }

    // MARK: - Authorization

    /// Check whether a capability is effectively allowed for the given context.
    ///
    /// Internal grants do not restrict ordinary host operations. Disabling or
    /// uninstalling a package still terminates its registered runtime session.
    func authorize(
        capability: String,
        context: HanlinHostCallContext
    ) async -> HanlinHostCapabilityResult {
        // Hanlin is a personal development host. Manifest/grant records are
        // compatibility metadata, not an additional authorization system.
        // iOS permission checks remain in the concrete device services.
        .allowed
    }

    // MARK: - App Grant Management

    func grant(capability: String, for appID: HanlinAppID) {
        let key = appID.rawValue
        var grants = compiledAppGrants[key, default: []]
        grants.insert(Self.canonicalCapabilityID(capability))
        compiledAppGrants[key] = grants
        save()
    }

    func revoke(capability: String, for appID: HanlinAppID) {
        let key = appID.rawValue
        var grants = compiledAppGrants[key, default: []]
        let canonical = Self.canonicalCapabilityID(capability)
        grants.remove(canonical)
        // Also remove legacy forms if present
        for (alias, target) in HanlinHostCapabilityMetadata.legacyAliases where target == canonical {
            grants.remove(alias)
        }
        compiledAppGrants[key] = grants
        save()
    }

    func grantedCapabilities(for appID: HanlinAppID) -> Set<String> {
        compiledAppGrants[appID.rawValue] ?? []
    }

    func setGrants(_ grants: Set<String>, for appID: HanlinAppID) {
        let key = appID.rawValue
        compiledAppGrants[key] = Set(grants.map(Self.canonicalCapabilityID))
        save()
    }

    // MARK: - Legacy Alias Resolution

    /// Resolve legacy capability identifiers to canonical form.
    static func canonicalCapabilityID(_ raw: String) -> String {
        HanlinHostCapabilityMetadata.legacyAliases[raw] ?? raw
    }
}
