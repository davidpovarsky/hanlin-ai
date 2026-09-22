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
/// For compiled Swift apps: manages grants directly in `UserDefaults`.
/// For scripting packages: delegates to the active `HanlinAtomicScriptStore`,
/// which remains the single persisted source of truth for package grants.
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
    /// Evaluates live persisted grants dynamically at call time so that
    /// permissions revoked by the user or system take immediate effect on the
    /// very next privileged operation without requiring session recreation.
    func authorize(
        capability: String,
        context: HanlinHostCallContext
    ) async -> HanlinHostCapabilityResult {
        let canonical = Self.canonicalCapabilityID(capability)

        // Agent context retains its intended privileged wildcard policy
        if context.origin == .assistantModel || context.storageScope == .agent {
            return .allowed
        }

        // Package identity takes precedence because scripting callers also have
        // an appID. Read the store on every operation so revocation is immediate.
        if let packageID = context.installedPackageID {
            guard let packageGrantStore,
                  let persisted = try? await packageGrantStore.grantedCapabilities(for: packageID) else {
                return .notGranted
            }
            let liveGrants = Set(persisted.map { Self.canonicalCapabilityID($0.rawValue) })
            return liveGrants.contains(canonical) || liveGrants.contains("all")
                ? .allowed
                : .notGranted
        }

        // Check live grants for a compiled app caller.
        if let appID = context.appID {
            let key = appID.rawValue
            // If live grants have not been registered yet, seed from context
            if compiledAppGrants[key] == nil {
                let canonicalSet = Set(context.effectiveCapabilities.map(Self.canonicalCapabilityID))
                compiledAppGrants[key] = canonicalSet
                save()
            }
            guard let liveGrants = compiledAppGrants[key],
                  liveGrants.contains(canonical) || liveGrants.contains("all") else {
                return .notGranted
            }
            return .allowed
        }

        // Fallback for trusted callers without persisted app/package identity.
        let canonicalSet = Set(context.effectiveCapabilities.map(Self.canonicalCapabilityID))
        guard canonicalSet.contains(canonical) || canonicalSet.contains("all") else {
            return .notGranted
        }

        return .allowed
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
