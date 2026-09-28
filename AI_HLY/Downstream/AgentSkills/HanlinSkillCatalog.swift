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

    public struct SkillDomainConfiguration: Sendable, Equatable {
        public var memoryEnabled: Bool
        public var mapEnabled: Bool
        public var calendarEnabled: Bool
        public var searchEnabled: Bool
        public var knowledgeEnabled: Bool
        public var codeEnabled: Bool
        public var healthEnabled: Bool
        public var weatherEnabled: Bool
        public var canvasEnabled: Bool

        public init(
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
            self.memoryEnabled = memoryEnabled
            self.mapEnabled = mapEnabled
            self.calendarEnabled = calendarEnabled
            self.searchEnabled = searchEnabled
            self.knowledgeEnabled = knowledgeEnabled
            self.codeEnabled = codeEnabled
            self.healthEnabled = healthEnabled
            self.weatherEnabled = weatherEnabled
            self.canvasEnabled = canvasEnabled
        }
    }

    public struct SkillSourceIdentity: Hashable, Sendable {
        public enum Kind: String, Sendable {
            case system
            case compiledMiniApp
            case installedPackage
            case userCustom
            case userOverride
        }
        public let kind: Kind
        public let identifier: String

        public init(kind: Kind, identifier: String) {
            self.kind = kind
            self.identifier = identifier
        }
    }

    private struct SkillEntry {
        let descriptor: HanlinSkillDescriptor
        let tier: SkillPrecedenceTier
        let isExplicitOverride: Bool
        let sourceIdentity: SkillSourceIdentity?
        let loader: (@MainActor @Sendable () async -> String)?
        let resourceResolver: (@MainActor @Sendable (String) -> URL?)?
    }

    private var skillEntries: [HanlinSkillID: SkillEntry] = [:]
    public private(set) var currentDomainConfiguration: SkillDomainConfiguration = SkillDomainConfiguration()

    public init() {
        synchronizeProductionSkills(configuration: currentDomainConfiguration)
    }

    /// Registers a skill with tier and optional custom instruction loader and resource resolver.
    public func register(
        skill: HanlinSkillDescriptor,
        tier: SkillPrecedenceTier = .userCustom,
        isExplicitOverride: Bool = false,
        sourceIdentity: SkillSourceIdentity? = nil,
        instructionLoader: (@MainActor @Sendable () async -> String)? = nil,
        resourceResolver: (@MainActor @Sendable (String) -> URL?)? = nil
    ) {
        if let existing = skillEntries[skill.id] {
            // Collision rule: userCustom cannot overwrite built-in or package skill without explicit override
            if tier == .userCustom && existing.tier < .userCustom && !isExplicitOverride {
                return
            }
            if tier < existing.tier {
                return
            }
            // Same-tier collision check: unrelated sources at same tier cannot silently shadow
            if tier == existing.tier && !isExplicitOverride {
                if let existingSource = existing.sourceIdentity,
                   let newSource = sourceIdentity,
                   existingSource != newSource {
                    return
                }
            }
        }
        skillEntries[skill.id] = SkillEntry(
            descriptor: skill,
            tier: tier,
            isExplicitOverride: isExplicitOverride,
            sourceIdentity: sourceIdentity,
            loader: instructionLoader,
            resourceResolver: resourceResolver
        )
    }

    /// Registers a skill descriptor (convenience alias).
    public func register(
        descriptor: HanlinSkillDescriptor,
        tier: SkillPrecedenceTier = .userCustom,
        isExplicitOverride: Bool = false,
        sourceIdentity: SkillSourceIdentity? = nil,
        instructionLoader: (@MainActor @Sendable () async -> String)? = nil,
        resourceResolver: (@MainActor @Sendable (String) -> URL?)? = nil
    ) {
        register(
            skill: descriptor,
            tier: tier,
            isExplicitOverride: isExplicitOverride,
            sourceIdentity: sourceIdentity,
            instructionLoader: instructionLoader,
            resourceResolver: resourceResolver
        )
    }

    /// Registers all skills declared in an app descriptor.
    public func register(app: HanlinAppDescriptor, tier: SkillPrecedenceTier = .compiledMiniApp) {
        let sourceID = SkillSourceIdentity(kind: .compiledMiniApp, identifier: app.id.rawValue)
        for skill in app.skills {
            register(skill: skill, tier: tier, sourceIdentity: sourceID)
        }
    }

    /// Synchronizes skills with a given domain configuration.
    func synchronizeProductionSkills(configuration: SkillDomainConfiguration, scriptingPlatform: HanlinScriptingPlatform? = nil) {
        self.currentDomainConfiguration = configuration
        skillEntries.removeAll()

        // 1. System Skills for enabled legacy domains
        let sysSkills = SystemSkillsProvider.systemSkills(
            memoryEnabled: configuration.memoryEnabled,
            mapEnabled: configuration.mapEnabled,
            calendarEnabled: configuration.calendarEnabled,
            searchEnabled: configuration.searchEnabled,
            knowledgeEnabled: configuration.knowledgeEnabled,
            codeEnabled: configuration.codeEnabled,
            healthEnabled: configuration.healthEnabled,
            weatherEnabled: configuration.weatherEnabled,
            canvasEnabled: configuration.canvasEnabled
        )
        for skill in sysSkills {
            register(
                skill: skill,
                tier: .system,
                sourceIdentity: SkillSourceIdentity(kind: .system, identifier: skill.id.rawValue)
            )
        }

        // 2. Compiled Swift Mini Apps
        BuiltinCanonicalRegistrations.ensureRegistered()
        for provider in HanlinCompiledMiniAppRegistry.shared.allProviders() {
            let appID = provider.descriptor.id.rawValue
            let sourceID = SkillSourceIdentity(kind: .compiledMiniApp, identifier: appID)
            for skill in provider.descriptor.skills {
                register(
                    skill: skill,
                    tier: .compiledMiniApp,
                    sourceIdentity: sourceID,
                    instructionLoader: {
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
                )
            }
        }

        // 3. Installed scripting packages (ScriptUI, NativeScript, Expo)
        let resolvedPlatform = scriptingPlatform ?? HanlinScriptingPlatform.shared
        for package in resolvedPlatform.installedPackages where package.enabled {
            guard let desc = try? package.appDescriptor() else { continue }
            let packageID = package.record.packageID
            let sourceID = SkillSourceIdentity(kind: .installedPackage, identifier: packageID.rawValue)
            for skill in desc.skills {
                register(
                    skill: skill,
                    tier: .installedPackage,
                    sourceIdentity: sourceID,
                    instructionLoader: { [weak resolvedPlatform] in
                        guard let currentPlatform = resolvedPlatform else {
                            return ""
                        }
                        guard let currentPackage = currentPlatform.installedPackages.first(where: { $0.record.packageID == packageID && $0.enabled }) else {
                            return ""
                        }
                        if case .resource(let path) = skill.instructions {
                            if let artifactURL = currentPlatform.activeArtifactURL(for: currentPackage) {
                                let candidateURL = artifactURL.appending(path: path)
                                if let content = try? String(contentsOf: candidateURL, encoding: .utf8) {
                                    return content
                                }
                                let sourceCandidate = artifactURL.appending(path: "source/\(path)")
                                if let content = try? String(contentsOf: sourceCandidate, encoding: .utf8) {
                                    return content
                                }
                            }
                            if let resURL = currentPlatform.resolveResourceURL(packageID: packageID, relativePath: path),
                               let content = try? String(contentsOf: resURL, encoding: .utf8) {
                                return content
                            }
                            if let url = Bundle.main.url(forResource: path, withExtension: nil),
                               let content = try? String(contentsOf: url, encoding: .utf8) {
                                return content
                            }
                        }
                        return "# \(skill.title.preferredValue())\n\n\(skill.summary.preferredValue())"
                    },
                    resourceResolver: { [weak resolvedPlatform] relPath in
                        guard let currentPlatform = resolvedPlatform else {
                            return nil
                        }
                        guard let currentPackage = currentPlatform.installedPackages.first(where: { $0.record.packageID == packageID && $0.enabled }) else {
                            return nil
                        }
                        let clean = relPath.replacingOccurrences(of: "\\", with: "/").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
                        guard !clean.isEmpty, !clean.contains("\0"), !clean.hasPrefix("/") else {
                            return nil
                        }
                        let components = clean.split(separator: "/")
                        guard !components.contains(".."), !components.contains(".") else {
                            return nil
                        }
                        return currentPlatform.resolveResourceURL(packageID: currentPackage.record.packageID, relativePath: clean)
                    }
                )
            }
        }

        // 4. Custom Skills and User Overrides from SkillStore
        // Precedence: User Override (4) > Custom Installed (3) > Scripting Package (2) > Mini App (1) > System (0)
        let store = SkillStore.shared
        for skill in store.allCustomSkillDescriptors() {
            register(
                skill: skill,
                tier: .userCustom,
                isExplicitOverride: false,
                sourceIdentity: SkillSourceIdentity(kind: .userCustom, identifier: skill.id.rawValue)
            ) {
                if case .inline(let text) = skill.instructions { return text }
                return "# \(skill.title.preferredValue())\n\n\(skill.summary.preferredValue())"
            }
        }

        for (baseID, overrideDesc) in store.allOverrideDescriptors() {
            register(
                skill: overrideDesc,
                tier: .userOverride,
                isExplicitOverride: true,
                sourceIdentity: SkillSourceIdentity(kind: .userOverride, identifier: baseID.rawValue)
            ) {
                if case .inline(let text) = overrideDesc.instructions { return text }
                return "# \(overrideDesc.title.preferredValue())\n\n\(overrideDesc.summary.preferredValue())"
            }
        }

        // Filter out disabled skills
        for disabledID in store.disabledSkillIDs() {
            skillEntries.removeValue(forKey: disabledID)
        }

        // Prune disabled domains
        if !configuration.memoryEnabled, let id = try? HanlinSkillID(validating: "memory") {
            skillEntries.removeValue(forKey: id)
        }
        if !configuration.codeEnabled, let id = try? HanlinSkillID(validating: "code") {
            skillEntries.removeValue(forKey: id)
        }
        if !configuration.mapEnabled, let id = try? HanlinSkillID(validating: "maps_location") {
            skillEntries.removeValue(forKey: id)
        }
        if !configuration.calendarEnabled, let id = try? HanlinSkillID(validating: "calendar") {
            skillEntries.removeValue(forKey: id)
        }
        if !configuration.searchEnabled, let id = try? HanlinSkillID(validating: "web_research") {
            skillEntries.removeValue(forKey: id)
        }
        if !configuration.knowledgeEnabled, let id = try? HanlinSkillID(validating: "knowledge") {
            skillEntries.removeValue(forKey: id)
        }
        if !configuration.healthEnabled, let id = try? HanlinSkillID(validating: "health") {
            skillEntries.removeValue(forKey: id)
        }
        if !configuration.weatherEnabled, let id = try? HanlinSkillID(validating: "weather") {
            skillEntries.removeValue(forKey: id)
        }
        if !configuration.canvasEnabled, let id = try? HanlinSkillID(validating: "canvas") {
            skillEntries.removeValue(forKey: id)
        }

        #if targetEnvironment(simulator)
        if AgentRuntimeUIAcceptanceProvider.isSkillsEnabled {
            if let skillID = try? HanlinSkillID(validating: "acceptance_skill"),
               let descriptor = try? HanlinSkillDescriptor(
                   id: skillID,
                   title: "Acceptance Skill",
                   summary: "Demonstrates agent skills and embedded result UI",
                   instructions: .inline("Always show embedded results for acceptance testing."),
                   preferredToolIDs: ["create_web_view"]
               ) {
                register(skill: descriptor)
            }
        }
        #endif
    }

    /// Synchronizes skills from built-in system providers, compiled Mini Apps, installed packages, and SkillStore.
    func synchronizeProductionSkills(
        memoryEnabled: Bool = true,
        mapEnabled: Bool = true,
        calendarEnabled: Bool = true,
        searchEnabled: Bool = true,
        knowledgeEnabled: Bool = true,
        codeEnabled: Bool = true,
        healthEnabled: Bool = true,
        weatherEnabled: Bool = true,
        canvasEnabled: Bool = true,
        scriptingPlatform: HanlinScriptingPlatform? = nil
    ) {
        let config = SkillDomainConfiguration(
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
        synchronizeProductionSkills(configuration: config, scriptingPlatform: scriptingPlatform)
    }

    /// Clears all registered skills (useful for isolated tests).
    public func reset() {
        skillEntries.removeAll()
    }

    /// Explicitly refreshes the catalog after store changes, preserving current domain settings.
    public func refreshFromStore() {
        synchronizeProductionSkills(configuration: currentDomainConfiguration)
    }

    /// Resolves a safe resource URL inside a skill directory, registered resolver, or main bundle.
    public func resolveResourceURL(skillID: HanlinSkillID, relativePath: String) -> URL? {
        if let storeURL = SkillStore.shared.safeResourceURL(for: skillID, relativePath: relativePath) {
            return storeURL
        }
        if let entry = skillEntries[skillID], let resolver = entry.resourceResolver {
            if let url = resolver(relativePath) {
                return url
            }
        }
        if let bundleURL = Bundle.main.url(forResource: relativePath, withExtension: nil) {
            return bundleURL
        }
        return nil
    }

    /// All registered skills for catalog discovery.
    public func allSkills() -> [HanlinSkillDescriptor] {
        if skillEntries.isEmpty {
            synchronizeProductionSkills(configuration: currentDomainConfiguration)
        }
        return Array(skillEntries.values.map(\.descriptor).sorted(by: { $0.id.rawValue < $1.id.rawValue }))
    }

    /// Resolves a skill descriptor by ID.
    public func resolve(id: HanlinSkillID) -> HanlinSkillDescriptor? {
        if skillEntries.isEmpty {
            synchronizeProductionSkills(configuration: currentDomainConfiguration)
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

public typealias SkillSourceIdentity = HanlinSkillCatalog.SkillSourceIdentity
