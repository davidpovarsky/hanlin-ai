import Foundation
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

    /// Registers all skills declared in an app descriptor.
    public func register(app: HanlinAppDescriptor) {
        for skill in app.skills {
            register(skill: skill)
        }
    }

    /// All registered skills for catalog discovery.
    public func allSkills() -> [HanlinSkillDescriptor] {
        Array(registeredSkills.values.sorted(by: { $0.id.rawValue < $1.id.rawValue }))
    }

    /// Resolves a skill descriptor by ID.
    public func resolve(id: HanlinSkillID) -> HanlinSkillDescriptor? {
        registeredSkills[id]
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
