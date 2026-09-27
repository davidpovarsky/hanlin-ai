import Foundation
import Testing
import HanlinPlatformContracts
@testable import AI_Hanlin

@MainActor
@Suite("Skill Store, Markdown Parser, and Importer Tests")
struct SkillStoreAndImportTests {

    @Test("SkillMarkdownParser parses frontmatter and serializes roundtrip")
    func markdownParserRoundtrip() throws {
        let content = """
        ---
        name: data-analysis
        description: Analyze complex tabular data and generate summaries
        ---

        # Data Analysis Workflow
        1. Inspect schema.
        2. Run local Python.
        """

        let parsed = try SkillMarkdownParser.parse(content)
        #expect(parsed.name == "data-analysis")
        #expect(parsed.description == "Analyze complex tabular data and generate summaries")
        #expect(parsed.body.contains("Data Analysis Workflow"))

        let serialized = SkillMarkdownParser.serialize(
            name: parsed.name,
            description: parsed.description,
            body: parsed.body
        )
        let reparsed = try SkillMarkdownParser.parse(serialized)
        #expect(reparsed.name == parsed.name)
        #expect(reparsed.description == parsed.description)
        #expect(reparsed.body.contains("Data Analysis Workflow"))
    }

    @Test("SkillStore manages custom skill lifecycle and state")
    func customSkillLifecycle() throws {
        let store = SkillStore.shared
        let testID = try HanlinSkillID(validating: "unit-test-skill-\(UUID().uuidString.prefix(8).lowercased())")

        try store.saveCustomSkill(
            id: testID,
            title: "Unit Test Skill",
            description: "A test skill for store validation",
            instructions: "Step 1: run tests.",
            preferredToolIDs: ["execute_local_python_code"]
        )

        let customList = store.allCustomSkillDescriptors()
        #expect(customList.contains { $0.id == testID })

        #expect(store.isSkillEnabled(id: testID))
        store.setSkillEnabled(id: testID, enabled: false)
        #expect(!store.isSkillEnabled(id: testID))
        store.setSkillEnabled(id: testID, enabled: true)
        #expect(store.isSkillEnabled(id: testID))

        store.deleteCustomSkill(skillID: testID)
        let afterDelete = store.allCustomSkillDescriptors()
        #expect(!afterDelete.contains { $0.id == testID })
    }

    @Test("SkillStore override takes precedence and resets cleanly")
    func overridePrecedenceAndReset() async throws {
        let store = SkillStore.shared
        let catalog = HanlinSkillCatalog.shared
        catalog.synchronizeProductionSkills()

        let baseID = try HanlinSkillID(validating: "code")
        let baseSkill = try #require(catalog.resolve(id: baseID))

        let customInstructions = "Custom specialized code instructions for override test."
        try store.createOrUpdateOverride(
            for: baseSkill,
            newTitle: "Overridden Code Skill",
            newDescription: "Customized description",
            newInstructions: customInstructions
        )

        #expect(store.hasOverride(for: baseID))

        let overridden = try #require(catalog.resolve(id: baseID))
        #expect(overridden.title.preferredValue() == "Overridden Code Skill")
        let loadedInstructions = await catalog.loadInstructions(for: overridden)
        #expect(loadedInstructions == customInstructions)

        store.resetOverride(skillID: baseID)
        #expect(!store.hasOverride(for: baseID))

        let restored = try #require(catalog.resolve(id: baseID))
        #expect(restored.title.preferredValue() == "Code Execution")
    }

    @Test("SkillStore safeResourceURL rejects path traversal and outside paths")
    func pathTraversalRejected() throws {
        let store = SkillStore.shared
        let testID = try HanlinSkillID(validating: "test-safety-skill")
        try store.saveCustomSkill(
            id: testID,
            title: "Safety Skill",
            description: "Safety test",
            instructions: "Safe instructions"
        )
        defer { store.deleteCustomSkill(skillID: testID) }

        #expect(store.safeResourceURL(for: testID, relativePath: "../secret.txt") == nil)
        #expect(store.safeResourceURL(for: testID, relativePath: "../../etc/passwd") == nil)
        #expect(store.safeResourceURL(for: testID, relativePath: "sub/../../escape.txt") == nil)
        #expect(store.safeResourceURL(for: testID, relativePath: "/absolute/path") == nil)
        #expect(store.safeResourceURL(for: testID, relativePath: "null\0byte") == nil)
    }

    @Test("SkillImporter rejects non-HTTPS URLs")
    func rejectsNonHTTPSURL() async throws {
        let importer = SkillImporter.shared
        let httpURL = URL(string: "http://insecure.example.com/skill.zip")!

        await #expect(throws: SkillImportError.self) {
            _ = try await importer.installFromHTTPSURL(httpURL)
        }
    }
}
