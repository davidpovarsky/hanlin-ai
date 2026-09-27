import Foundation
import Testing
import HanlinPlatformContracts
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
}
