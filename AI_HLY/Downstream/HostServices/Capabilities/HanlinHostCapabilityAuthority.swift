import Foundation
import HanlinPlatformContracts

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
/// For scripting packages: delegates to existing `HanlinAtomicScriptStore` via
/// the `effectiveCapabilities` pre-populated in `HanlinHostCallContext`.
actor HanlinHostCapabilityAuthority {
    static let shared = HanlinHostCapabilityAuthority()

    /// Per-compiled-app grant tracking. Key is `appID.rawValue`.
    private var compiledAppGrants: [String: Set<String>] = [:]
    /// Per-package grant tracking. Key is `packageID.rawValue`.
    private var packageGrants: [String: Set<String>] = [:]

    private let persistenceKey = "hanlin.host-capability-grants.v1"
    private let packagePersistenceKey = "hanlin.host-package-capability-grants.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: persistenceKey),
           let decoded = try? JSONDecoder().decode([String: Set<String>].self, from: data) {
            self.compiledAppGrants = decoded
        }
        if let data = UserDefaults.standard.data(forKey: packagePersistenceKey),
           let decoded = try? JSONDecoder().decode([String: Set<String>].self, from: data) {
            self.packageGrants = decoded
        }
    }

    private func save() {
        if let encoded = try? JSONEncoder().encode(compiledAppGrants) {
            UserDefaults.standard.set(encoded, forKey: persistenceKey)
        }
        if let encoded = try? JSONEncoder().encode(packageGrants) {
            UserDefaults.standard.set(encoded, forKey: packagePersistenceKey)
        }
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
    ) -> HanlinHostCapabilityResult {
        let canonical = Self.canonicalCapabilityID(capability)

        // Agent context retains its intended privileged wildcard policy
        if context.origin == .assistantModel || context.storageScope == .agent || context.effectiveCapabilities.contains("all") {
            return .allowed
        }

        // 1. Check live grants for compiled app caller
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

        // 2. Check live grants for script package caller
        if let packageID = context.installedPackageID {
            let key = packageID.rawValue
            if packageGrants[key] == nil {
                let canonicalSet = Set(context.effectiveCapabilities.map(Self.canonicalCapabilityID))
                packageGrants[key] = canonicalSet
                save()
            }
            guard let liveGrants = packageGrants[key],
                  liveGrants.contains(canonical) || liveGrants.contains("all") else {
                return .notGranted
            }
            return .allowed
        }

        // 3. Fallback to canonical check against context capabilities
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

    // MARK: - Package Grant Management

    func grant(capability: String, for packageID: HanlinInstalledPackageID) {
        let key = packageID.rawValue
        var grants = packageGrants[key, default: []]
        grants.insert(Self.canonicalCapabilityID(capability))
        packageGrants[key] = grants
        save()
    }

    func revoke(capability: String, for packageID: HanlinInstalledPackageID) {
        let key = packageID.rawValue
        var grants = packageGrants[key, default: []]
        let canonical = Self.canonicalCapabilityID(capability)
        grants.remove(canonical)
        for (alias, target) in HanlinHostCapabilityMetadata.legacyAliases where target == canonical {
            grants.remove(alias)
        }
        packageGrants[key] = grants
        save()
    }

    func grantedCapabilities(for packageID: HanlinInstalledPackageID) -> Set<String> {
        packageGrants[packageID.rawValue] ?? []
    }

    func setGrants(_ grants: Set<String>, for packageID: HanlinInstalledPackageID) {
        let key = packageID.rawValue
        packageGrants[key] = Set(grants.map(Self.canonicalCapabilityID))
        save()
    }

    // MARK: - Legacy Alias Resolution

    /// Resolve legacy capability identifiers to canonical form.
    static func canonicalCapabilityID(_ raw: String) -> String {
        HanlinHostCapabilityMetadata.legacyAliases[raw] ?? raw
    }
}
