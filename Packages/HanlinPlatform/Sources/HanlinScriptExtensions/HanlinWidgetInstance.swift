import Foundation
import HanlinPlatformContracts

public struct HanlinWidgetInstance: Codable, Hashable, Sendable, Identifiable {
    public var id: String { identity.variantID }
    public let identity: HanlinScriptExtensionIdentity
    public let engine: HanlinWidgetEngine
    public let displayName: String
    public let settings: [String: HanlinValue]

    public init(identity: HanlinScriptExtensionIdentity, engine: HanlinWidgetEngine,
                displayName: String, settings: [String: HanlinValue] = [:]) {
        self.identity = identity
        self.engine = engine
        self.displayName = displayName
        self.settings = settings
    }

    /// Exact, versioned and delimiter-safe. A stale generation never resolves
    /// by partial package name or by the first available widget.
    public var entityID: String {
        let fields = [identity.installedPackageID.rawValue, identity.packageID.rawValue,
                      String(identity.generation), identity.entrypointID, engine.rawValue, identity.variantID]
        return "widget-v2:" + fields.map { Data($0.utf8).base64EncodedString() }.joined(separator: ".")
    }
}

public struct HanlinWidgetInstanceState: Codable, Hashable, Sendable {
    public let identity: HanlinScriptExtensionIdentity
    public let engine: HanlinWidgetEngine
    public let artifactSHA256: String
    public var revision: UInt64
    public var values: [String: HanlinValue]
    public var committedNonces: [String]

    public init(identity: HanlinScriptExtensionIdentity, engine: HanlinWidgetEngine, artifactSHA256: String,
                revision: UInt64 = 0, values: [String: HanlinValue] = [:], committedNonces: [String] = []) {
        self.identity = identity
        self.engine = engine
        self.artifactSHA256 = artifactSHA256
        self.revision = revision
        self.values = values
        self.committedNonces = committedNonces
    }
}

extension HanlinScriptExtensionSnapshot {
    public func replacing(
        widgets: [HanlinScriptWidgetSnapshot]? = nil,
        instances: [HanlinWidgetInstance]? = nil,
        states: [HanlinWidgetInstanceState]? = nil,
        inactiveInstallations: [String]? = nil
    ) -> Self {
        .init(schemaVersion: schemaVersion, generatedAt: .now, widgets: widgets ?? self.widgets,
              intentEntities: intentEntities, liveActivities: liveActivities, translationApps: translationApps,
              widgetInstances: instances ?? widgetInstances, widgetStates: states ?? widgetStates, widgetEntityMigrations: widgetEntityMigrations,
              inactiveWidgetInstallations: inactiveInstallations ?? inactiveWidgetInstallations)
    }
}

extension HanlinScriptWidgetSnapshot {
    public func forInstance(_ instance: HanlinWidgetInstance) -> Self {
        let actionIdentity = actionIdentity.map {
            HanlinScriptExtensionIdentity(installedPackageID: $0.installedPackageID, packageID: $0.packageID,
                generation: $0.generation, entrypointID: $0.entrypointID, variantID: instance.identity.variantID)
        }
        return .init(identity: instance.identity, displayName: "\(displayName) · \(instance.displayName)", family: family,
            actionIdentity: actionIdentity, validUntil: validUntil, relevance: relevance, engine: engine, payload: payload, root: root, deepLink: deepLink)
    }
}

extension HanlinScriptExtensionStore {
    @discardableResult
    public func createWidgetInstance(from entityID: String, displayName: String) throws -> HanlinWidgetInstance {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.utf8.count <= 160 else { throw HanlinWidgetActionError.invalidIdentity }
        var result: HanlinWidgetInstance?
        try update { current in
            guard let current, current.widgetInstances.count < 128,
                  let source = current.widgetInstances.first(where: { $0.entityID == entityID }),
                  !current.inactiveWidgetInstallations.contains(source.identity.installedPackageID.rawValue) else { throw HanlinWidgetActionError.inactiveInstance }
            let identity = HanlinScriptExtensionIdentity(installedPackageID: source.identity.installedPackageID,
                packageID: source.identity.packageID, generation: source.identity.generation,
                entrypointID: source.identity.entrypointID, variantID: UUID().uuidString.lowercased())
            let instance = HanlinWidgetInstance(identity: identity, engine: source.engine, displayName: name, settings: source.settings)
            let templates = current.widgets.filter { $0.identity == source.identity && $0.engine == source.engine }
            guard !templates.isEmpty else { throw HanlinWidgetActionError.inactiveInstance }
            let widgets = templates.map { $0.forInstance(instance) }
            var states = current.widgetStates
            if let state = states.first(where: { $0.identity == source.identity && $0.engine == source.engine }) {
                states.append(.init(identity: identity, engine: source.engine, artifactSHA256: state.artifactSHA256, values: state.values))
            }
            result = instance
            return current.replacing(widgets: current.widgets + widgets, instances: current.widgetInstances + [instance], states: states)
        }
        guard let result else { throw HanlinWidgetActionError.inactiveInstance }
        return result
    }

    /// Host revokes extension authority before an async installed-store mutation.
    /// State remains archived for a verified rollback to the exact generation.
    public func invalidateWidgetActions(installedPackageID: HanlinInstalledPackageID) throws {
        try update { current in
            let current = current ?? .init(schemaVersion: 2, generatedAt: .now)
            return current.replacing(inactiveInstallations: Array(Set(current.inactiveWidgetInstallations + [installedPackageID.rawValue])).sorted())
        }
    }

    /// Publish host-derived active-generation templates while reading the latest
    /// committed states/instances under the same lock used by extension actions.
    /// Upgrade policy: keep configured variant IDs; state is generation-scoped.
    /// Rollback to a retained generation restores that generation's state.
    @discardableResult
    public func publishWidgetTemplates(
        _ templates: [HanlinScriptWidgetSnapshot], intentEntities: [HanlinScriptIntentEntityRecord],
        translationApps: [HanlinScriptTranslationUISnapshot], installedPackageIDs: Set<HanlinInstalledPackageID>
    ) throws -> HanlinScriptExtensionSnapshot {
        try update { current in
            let current = current ?? .init(schemaVersion: 2, generatedAt: .now)
            var instances: [HanlinWidgetInstance] = []
            var widgets: [HanlinScriptWidgetSnapshot] = []
            var migrations = current.widgetEntityMigrations
            var seen: Set<String> = []
            let activeIDs = Set(templates.map { $0.identity.installedPackageID })
            for template in templates {
                let base = HanlinWidgetInstance(identity: template.identity, engine: template.engine, displayName: "Default")
                guard seen.insert(base.entityID).inserted else { continue }
                let previous = current.widgetInstances.filter {
                    $0.identity.installedPackageID == template.identity.installedPackageID
                        && $0.identity.packageID == template.identity.packageID
                        && $0.identity.entrypointID == template.identity.entrypointID && $0.engine == template.engine
                }
                let variants = previous.isEmpty ? [base] : previous.map { old in
                    let identity = HanlinScriptExtensionIdentity(installedPackageID: template.identity.installedPackageID,
                        packageID: template.identity.packageID, generation: template.identity.generation,
                        entrypointID: template.identity.entrypointID, variantID: old.identity.variantID)
                    let migrated = HanlinWidgetInstance(identity: identity, engine: template.engine, displayName: old.displayName, settings: old.settings)
                    if migrated.entityID != old.entityID { migrations[old.entityID] = migrated.entityID }
                    return migrated
                }
                instances.append(contentsOf: variants)
                let families = templates.filter { $0.identity == template.identity && $0.engine == template.engine }
                for variant in variants { widgets.append(contentsOf: families.map { $0.forInstance(variant) }) }
            }
            // Disabled installs retain configuration; uninstall removes their
            // registry/state only after the host installed-store has removed them.
            instances.append(contentsOf: current.widgetInstances.filter {
                installedPackageIDs.contains($0.identity.installedPackageID) && !activeIDs.contains($0.identity.installedPackageID)
            })
            let retainedIDs = installedPackageIDs.union(activeIDs)
            let states = current.widgetStates.filter { retainedIDs.contains($0.identity.installedPackageID) }
            let entityIDs = Set(instances.map(\.entityID))
            if current.widgetInstances.isEmpty {
                // One-time migration from actual prior picker records only.
                var candidates: [String: Set<String>] = [:]
                for old in current.widgets {
                    for instance in instances where instance.identity.installedPackageID == old.identity.installedPackageID
                        && instance.identity.packageID == old.identity.packageID && instance.identity.entrypointID == old.identity.entrypointID
                        && instance.identity.variantID == old.identity.variantID {
                        for key in ["\(old.identity.packageID.rawValue)|\(old.identity.entrypointID)|\(old.identity.variantID)",
                                    "\(old.identity.packageID.rawValue)|\(old.identity.entrypointID)",
                                    "\(old.identity.installedPackageID.rawValue)|\(old.identity.entrypointID)"] {
                            candidates[key, default: []].insert(instance.entityID)
                        }
                    }
                }
                for (key, targets) in candidates where targets.count == 1 { migrations[key] = targets.first }
            }
            // Collapse exact recorded upgrade chains. Never perform partial-ID
            // matching during normal lookup.
            for (old, target) in migrations {
                var final = target
                var visited: Set<String> = [old]
                while let next = migrations[final], visited.insert(final).inserted { final = next }
                migrations[old] = entityIDs.contains(final) ? final : nil
            }
            return .init(schemaVersion: 2, generatedAt: .now, widgets: widgets, intentEntities: intentEntities,
                liveActivities: current.liveActivities, translationApps: translationApps, widgetInstances: instances,
                widgetStates: states, widgetEntityMigrations: migrations,
                inactiveWidgetInstallations: current.inactiveWidgetInstallations.filter { raw in !activeIDs.contains(where: { $0.rawValue == raw }) })
        }
    }
}
