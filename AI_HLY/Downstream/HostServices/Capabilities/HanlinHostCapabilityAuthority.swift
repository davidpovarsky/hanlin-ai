import Foundation
import HanlinPlatformContracts

/// Result of evaluating a capability authorization request.
public enum HanlinHostCapabilityResult: Sendable {
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

    // MARK: - Authorization

    /// Check whether a capability is effectively allowed for the given context.
    ///
    /// The `context.effectiveCapabilities` set is pre-populated by the engine
    /// adapter when constructing the `HanlinHostCallContext`, so this check is
    /// a straightforward membership test. The "all" wildcard bypasses checks.
    func authorize(
        capability: String,
        context: HanlinHostCallContext
    ) -> HanlinHostCapabilityResult {
        let canonical = Self.canonicalCapabilityID(capability)

        if context.effectiveCapabilities.contains("all") {
            return .allowed
        }

        guard context.effectiveCapabilities.contains(canonical) else {
            return .notGranted
        }

        return .allowed
    }

    // MARK: - Compiled App Grant Management

    func grant(capability: String, for appID: HanlinAppID) {
        let key = appID.rawValue
        var grants = compiledAppGrants[key, default: []]
        grants.insert(Self.canonicalCapabilityID(capability))
        compiledAppGrants[key] = grants
        save()
    }

    func revoke(capability: String, for appID: HanlinAppID) {
        let key = appID.rawValue
        guard var grants = compiledAppGrants[key] else { return }
        grants.remove(Self.canonicalCapabilityID(capability))
        compiledAppGrants[key] = grants
        save()
    }

    func grantedCapabilities(for appID: HanlinAppID) -> Set<String> {
        compiledAppGrants[appID.rawValue] ?? []
    }

    // MARK: - Legacy Alias Resolution

    /// Resolve legacy capability identifiers to canonical form.
    static func canonicalCapabilityID(_ raw: String) -> String {
        HanlinHostCapabilityMetadata.legacyAliases[raw] ?? raw
    }
}
