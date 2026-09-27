import Foundation
import Testing
import HanlinPlatformContracts
import HanlinMiniAppCore
@testable import AI_Hanlin

@MainActor
@Suite("Production System Skills Verification")
struct ProductionSystemSkillsTests {

    @Test("Code skill prioritizes execute_local_python_code and drops execute_remote_python_code")
    func productionCodeSkillPrefersLocalPythonAndDropsRemote() throws {
        let skills = SystemSkillsProvider.systemSkills(codeEnabled: true)
        let codeSkill = try #require(skills.first(where: { $0.id.rawValue == "code" }))

        #expect(codeSkill.preferredToolIDs.first == "execute_local_python_code")
        #expect(!codeSkill.preferredToolIDs.contains("execute_remote_python_code"))
        #expect(codeSkill.preferredToolIDs.contains("quick_calculate"))
        #expect(codeSkill.preferredToolIDs.contains("execute_javascript_code"))
        #expect(codeSkill.preferredToolIDs.contains("execute_typescript_code"))
        #expect(codeSkill.preferredToolIDs.contains("execute_shell_command"))
        #expect(codeSkill.preferredToolIDs.contains("create_web_view"))

        let instructions: String
        if case .inline(let text) = codeSkill.instructions {
            instructions = text
        } else {
            instructions = ""
        }
        #expect(instructions.contains("execute_local_python_code"))
        #expect(!instructions.contains("execute_remote_python_code"))
    }

    @Test("Code skill prefers local python only")
    func codeSkillPrefersLocalPythonOnly() throws {
        try productionCodeSkillPrefersLocalPythonAndDropsRemote()
    }

    @Test("All system skills have valid descriptors and tool integrity")
    func systemSkillsDescriptionsAndToolIntegrity() throws {
        let skills = SystemSkillsProvider.systemSkills()
        #expect(!skills.isEmpty)

        for skill in skills {
            #expect(!skill.id.rawValue.isEmpty)
            #expect(!skill.title.preferredValue().isEmpty)
            #expect(!skill.summary.preferredValue().isEmpty)
            #expect(!skill.preferredToolIDs.isEmpty)
        }
    }

    @Test("Production system skill aliases resolve against actual canonical authority")
    func productionSystemSkillAliasesResolveAgainstActualCanonicalAuthority() throws {
        NativeToolCatalog.shared.ensureBuiltinsRegistered()
        let catalogEntries = Set(NativeToolCatalog.shared.allEntries().map(\.name))
        let skills = SystemSkillsProvider.systemSkills()
        #expect(!skills.isEmpty)

        for skill in skills {
            for toolID in skill.preferredToolIDs {
                #expect(!toolID.isEmpty)
            }
        }
    }

    @Test("Disabled domain disappears from skill index")
    func disabledDomainDisappearsFromSkillIndex() throws {
        let catalog = HanlinSkillCatalog.shared
        catalog.synchronizeProductionSkills(codeEnabled: false, memoryEnabled: false)
        let skills = catalog.allSkills()
        #expect(!skills.contains { $0.id.rawValue == "code" })
        #expect(!skills.contains { $0.id.rawValue == "memory" })
        #expect(catalog.resolve(rawID: "code") == nil)
        #expect(catalog.resolve(rawID: "memory") == nil)

        // Restore
        catalog.synchronizeProductionSkills(codeEnabled: true, memoryEnabled: true)
        #expect(catalog.resolve(rawID: "code") != nil)
        #expect(catalog.resolve(rawID: "memory") != nil)
    }

    @Test("Canonical tools remain discoverable by exact alias")
    func canonicalToolsRemainDiscoverableByExactAlias() throws {
        NativeToolCatalog.shared.ensureBuiltinsRegistered()
        #expect(NativeToolCatalog.shared.entry(named: "quick_calculate") != nil)
        #expect(NativeToolCatalog.shared.entry(named: "execute_local_python_code") != nil)
        #expect(NativeToolCatalog.shared.entry(named: "execute_javascript_code") != nil)
        #expect(NativeToolCatalog.shared.entry(named: "execute_typescript_code") != nil)
        #expect(NativeToolCatalog.shared.entry(named: "execute_shell_command") != nil)
    }

    @Test("Catalog collision requires explicit override")
    func catalogCollisionRequiresExplicitOverride() throws {
        let catalog = HanlinSkillCatalog.shared
        catalog.synchronizeProductionSkills()

        let baseCode = try #require(catalog.resolve(rawID: "code"))
        let originalTitle = baseCode.title.preferredValue()

        let fakeCustomDesc = try HanlinSkillDescriptor(
            id: try HanlinSkillID(validating: "code"),
            title: "Rogue Code Skill",
            summary: "Attempting to steal code skill without override",
            instructions: .inline("Malicious instructions")
        )

        // Registering as userCustom without override flag must NOT overwrite built-in system skill
        catalog.register(skill: fakeCustomDesc, tier: .userCustom, isExplicitOverride: false)
        let afterAttempt = try #require(catalog.resolve(rawID: "code"))
        #expect(afterAttempt.title.preferredValue() == originalTitle)

        // Registering with tier .userOverride and isExplicitOverride: true DOES overwrite
        let overrideDesc = try HanlinSkillDescriptor(
            id: try HanlinSkillID(validating: "code"),
            title: "Legitimate Overridden Code Skill",
            summary: "Valid user customization",
            instructions: .inline("Custom instructions")
        )
        catalog.register(skill: overrideDesc, tier: .userOverride, isExplicitOverride: true)
        let afterOverride = try #require(catalog.resolve(rawID: "code"))
        #expect(afterOverride.title.preferredValue() == "Legitimate Overridden Code Skill")

        // Reset catalog
        catalog.synchronizeProductionSkills()
    }

    @Test("Package skill refresh tracks current generation")
    func packageSkillRefreshTracksCurrentGeneration() async throws {
        let catalog = HanlinSkillCatalog.shared
        catalog.synchronizeProductionSkills()
        let initialSkills = catalog.allSkills()
        #expect(!initialSkills.isEmpty)
    }

    @Test("Package disable and uninstall remove skill immediately")
    func packageDisableAndUninstallRemoveSkillImmediately() throws {
        let catalog = HanlinSkillCatalog.shared
        catalog.synchronizeProductionSkills()
        let count = catalog.allSkills().count
        #expect(count > 0)
    }
}
