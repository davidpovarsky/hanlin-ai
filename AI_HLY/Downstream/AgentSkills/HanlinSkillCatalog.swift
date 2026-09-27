import Foundation
import HanlinMiniAppCore
import HanlinPlatformContracts

@MainActor
public final class HanlinSkillCatalog {
    public static let shared = HanlinSkillCatalog()

    public enum SkillPrecedenceTier: Int, Comparable, Sendable {
        case system = 0
        case compiledMiniApp = 1
        case installedPackage = 2
        case userCustom = 3
        case userOverride = 4

        public static func < (lhs: SkillPrecedenceTier, rhs: SkillPrecedenceTier) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    private struct SkillEntry {
        let descriptor: HanlinSkillDescriptor
        let tier: SkillPrecedenceTier
        let isExplicitOverride: Bool
        let loader: (@Sendable () async -> String)?
    }

    private var skillEntries: [HanlinSkillID: SkillEntry] = [:]

    public init() {}

    /// Registers a skill with tier and optional custom instruction loader.
    public func register(
        skill: HanlinSkillDescriptor,
        tier: SkillPrecedenceTier = .userCustom,
        isExplicitOverride: Bool = false,
        instructionLoader: (@Sendable () async -> String)? = nil
    ) {
        if let existing = skillEntries[skill.id] {
            // Collision rule: userCustom cannot overwrite built-in or package skill without explicit override
            if tier == .userCustom && existing.tier < .userCustom && !isExplicitOverride {
                return
            }
            if tier < existing.tier {
                return
            }
        }
        skillEntries[skill.id] = SkillEntry(
            descriptor: skill,
            tier: tier,
            isExplicitOverride: isExplicitOverride,
            loader: instructionLoader
        )
    }

    /// Registers a skill descriptor (convenience alias).
    public func register(
        descriptor: HanlinSkillDescriptor,
        tier: SkillPrecedenceTier = .userCustom,
        isExplicitOverride: Bool = false,
        instructionLoader: (@Sendable () async -> String)? = nil
    ) {
        register(skill: descriptor, tier: tier, isExplicitOverride: isExplicitOverride, instructionLoader: instructionLoader)
    }

    /// Registers all skills declared in an app descriptor.
    public func register(app: HanlinAppDescriptor, tier: SkillPrecedenceTier = .compiledMiniApp) {
        for skill in app.skills {
            register(skill: skill, tier: tier)
        }
    }

    /// Synchronizes skills from built-in system providers, compiled Mini Apps, installed packages, and SkillStore.
    public func synchronizeProductionSkills(
        memoryEnabled: Bool = true,
        mapEnabled: Bool = true,
        calendarEnabled: Bool = true,
        searchEnabled: Bool = true,
        knowledgeEnabled: Bool = true,
        codeEnabled: Bool = true,
        healthEnabled: Bool = true,
        weatherEnabled: Bool = true,
        canvasEnabled: Bool = true
    ) {
        skillEntries.removeAll()

        // 1. System Skills for enabled legacy domains
        let sysSkills = SystemSkillsProvider.systemSkills(
            memoryEnabled: memoryEnabled,
            mapEnabled: mapEnabled,
            calendarEnabled: calendarEnabled,
            searchEnabled: searchEnabled,
            knowledgeEnabled: knowledgeEnabled,
            codeEnabled: codeEnabled,
            healthEnabled: healthEnabled,
            weatherEnabled: weatherEnabled,
            canvasEnabled: canvasEnabled
        )
        for skill in sysSkills {
            register(skill: skill, tier: .system)
        }

        // 2. Compiled Swift Mini Apps
        BuiltinCanonicalRegistrations.ensureRegistered()
        for provider in HanlinCompiledMiniAppRegistry.shared.allProviders() {
            for skill in provider.descriptor.skills {
                register(skill: skill, tier: .compiledMiniApp) {
                    if case .resource(let path) = skill.instructions {
                        let providerBundle: Bundle? = (type(of: provider) as? AnyClass).map { Bundle(for: $0) }
                        if let url = providerBundle?.url(forResource: path, withExtension: nil)
                            ?? Bundle.main.url(forResource: path, withExtension: nil),
                           let content = try? String(contentsOf: url, encoding: .utf8) {
                            return content
                        }
                    }
                    return "# \(skill.title.preferredValue())\n\n\(skill.summary.preferredValue())"
                }
            }
        }

        // 3. Installed scripting packages (ScriptUI, NativeScript, Expo)
        let platform = HanlinScriptingPlatform.shared
        for package in platform.installedPackages where package.enabled {
            guard let desc = try? package.appDescriptor() else { continue }
            let packageID = package.record.packageID
            for skill in desc.skills {
                register(skill: skill, tier: .installedPackage) {
                    guard let currentPackage = HanlinScriptingPlatform.shared.installedPackages.first(where: { $0.record.packageID == packageID && $0.enabled }) else {
                        return ""
                    }
                    if case .resource(let path) = skill.instructions {
                        if let artifactURL = HanlinScriptingPlatform.shared.activeArtifactURL(for: currentPackage) {
                            let candidateURL = artifactURL.appending(path: path)
                            if let content = try? String(contentsOf: candidateURL, encoding: .utf8) {
                                return content
                            }
                            let sourceCandidate = artifactURL.appending(path: "source/\(path)")
                            if let content = try? String(contentsOf: sourceCandidate, encoding: .utf8) {
                                return content
                            }
                        }
                        if let resURL = HanlinScriptingPlatform.shared.resolveResourceURL(packageID: packageID, relativePath: path),
                           let content = try? String(contentsOf: resURL, encoding: .utf8) {
                            return content
                        }
                        if let url = Bundle.main.url(forResource: path, withExtension: nil),
                           let content = try? String(contentsOf: url, encoding: .utf8) {
                            return content
                        }
                    }
                    return "# \(skill.title.preferredValue())\n\n\(skill.summary.preferredValue())"
                }
            }
        }

        // 4. Custom Skills and User Overrides from SkillStore
        // Precedence: User Override (4) > Custom Installed (3) > Scripting Package (2) > Mini App (1) > System (0)
        let store = SkillStore.shared
        for skill in store.allCustomSkillDescriptors() {
            register(skill: skill, tier: .userCustom, isExplicitOverride: false) {
                if case .inline(let text) = skill.instructions { return text }
                return "# \(skill.title.preferredValue())\n\n\(skill.summary.preferredValue())"
            }
        }

        for (baseID, overrideDesc) in store.allOverrideDescriptors() {
            register(skill: overrideDesc, tier: .userOverride, isExplicitOverride: true) {
                if case .inline(let text) = overrideDesc.instructions { return text }
                return "# \(overrideDesc.title.preferredValue())\n\n\(overrideDesc.summary.preferredValue())"
            }
        }

        // Filter out disabled skills
        for disabledID in store.disabledSkillIDs() {
            skillEntries.removeValue(forKey: disabledID)
        }
    }

    /// Clears all registered skills (useful for isolated tests).
    public func reset() {
        skillEntries.removeAll()
    }

    /// Explicitly refreshes the catalog after store changes.
    public func refreshFromStore() {
        synchronizeProductionSkills()
    }

    /// Resolves a safe resource URL inside a skill directory or main bundle.
    public func resolveResourceURL(skillID: HanlinSkillID, relativePath: String) -> URL? {
        if let storeURL = SkillStore.shared.safeResourceURL(for: skillID, relativePath: relativePath) {
            return storeURL
        }
        if let bundleURL = Bundle.main.url(forResource: relativePath, withExtension: nil) {
            return bundleURL
        }
        return nil
    }

    /// All registered skills for catalog discovery.
    public func allSkills() -> [HanlinSkillDescriptor] {
        if skillEntries.isEmpty {
            synchronizeProductionSkills()
        }
        return Array(skillEntries.values.map(\.descriptor).sorted(by: { $0.id.rawValue < $1.id.rawValue }))
    }

    /// Resolves a skill descriptor by ID.
    public func resolve(id: HanlinSkillID) -> HanlinSkillDescriptor? {
        if skillEntries.isEmpty {
            synchronizeProductionSkills()
        }
        return skillEntries[id]?.descriptor
    }

    /// Resolves a skill descriptor by raw string ID.
    public func resolve(rawID: String) -> HanlinSkillDescriptor? {
        guard let id = try? HanlinSkillID(validating: rawID) else { return nil }
        return resolve(id: id)
    }

    /// Loads the full instruction text for a skill.
    public func loadInstructions(for skill: HanlinSkillDescriptor) async -> String {
        if let loader = skillEntries[skill.id]?.loader {
            return await loader()
        }
        switch skill.instructions {
        case .inline(let text):
            return text
        case .resource(let path):
            // Check main bundle or return title + summary fallback
            if let url = Bundle.main.url(forResource: path, withExtension: nil),
               let content = try? String(contentsOf: url, encoding: .utf8) {
                return content
            }
            return "# \(skill.title.preferredValue())\n\n\(skill.summary.preferredValue())"
        }
    }
}
