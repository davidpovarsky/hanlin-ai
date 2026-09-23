import Foundation
import HanlinMiniAppCore
import HanlinPlatformContracts

@MainActor
public final class HanlinSkillCatalog {
    public static let shared = HanlinSkillCatalog()

    private var registeredSkills: [HanlinSkillID: HanlinSkillDescriptor] = [:]
    private var skillInstructionLoaders: [HanlinSkillID: @Sendable () async -> String] = [:]

    public init() {}

    /// Registers a skill with optional custom instruction loader.
    public func register(
        skill: HanlinSkillDescriptor,
        instructionLoader: (@Sendable () async -> String)? = nil
    ) {
        registeredSkills[skill.id] = skill
        if let instructionLoader {
            skillInstructionLoaders[skill.id] = instructionLoader
        }
    }

    /// Registers a skill descriptor (convenience alias).
    public func register(
        descriptor: HanlinSkillDescriptor,
        instructionLoader: (@Sendable () async -> String)? = nil
    ) {
        register(skill: descriptor, instructionLoader: instructionLoader)
    }

    /// Registers all skills declared in an app descriptor.
    public func register(app: HanlinAppDescriptor) {
        for skill in app.skills {
            register(skill: skill)
        }
    }

    /// Synchronizes skills from built-in system providers, compiled Mini Apps, and installed packages.
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
            register(skill: skill)
        }

        // 2. Compiled Swift Mini Apps
        BuiltinCanonicalRegistrations.ensureRegistered()
        for provider in HanlinCompiledMiniAppRegistry.shared.providers {
            for skill in provider.descriptor.skills {
                register(skill: skill) { [weak provider] in
                    if case .resource(let path) = skill.instructions, let provider {
                        if let url = Bundle(for: type(of: provider)).url(forResource: path, withExtension: nil)
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
            for skill in package.descriptor.skills {
                register(skill: skill) {
                    if case .resource(let path) = skill.instructions {
                        if let artifactURL = platform.activeArtifactURL(for: package) {
                            let candidateURL = artifactURL.appending(path: path)
                            if let content = try? String(contentsOf: candidateURL, encoding: .utf8) {
                                return content
                            }
                            let sourceCandidate = artifactURL.appending(path: "source/\(path)")
                            if let content = try? String(contentsOf: sourceCandidate, encoding: .utf8) {
                                return content
                            }
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
    }

    /// All registered skills for catalog discovery.
    public func allSkills() -> [HanlinSkillDescriptor] {
        if registeredSkills.isEmpty {
            synchronizeProductionSkills()
        }
        return Array(registeredSkills.values.sorted(by: { $0.id.rawValue < $1.id.rawValue }))
    }

    /// Resolves a skill descriptor by ID.
    public func resolve(id: HanlinSkillID) -> HanlinSkillDescriptor? {
        if registeredSkills.isEmpty {
            synchronizeProductionSkills()
        }
        return registeredSkills[id]
    }

    /// Resolves a skill descriptor by raw string ID.
    public func resolve(rawID: String) -> HanlinSkillDescriptor? {
        guard let id = try? HanlinSkillID(validating: rawID) else { return nil }
        return resolve(id: id)
    }

    /// Loads the full instruction text for a skill.
    public func loadInstructions(for skill: HanlinSkillDescriptor) async -> String {
        if let loader = skillInstructionLoaders[skill.id] {
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
