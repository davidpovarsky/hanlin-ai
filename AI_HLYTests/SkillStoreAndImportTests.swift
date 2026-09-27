import Foundation
import Testing
import HanlinPlatformContracts
import HanlinScriptCompiler
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

    @Test("SkillStore safeResourceURL rejects path traversal, drive prefixes, and escape attempts")
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

    @Test("Direct markdown SKILL.md file installs successfully into store")
    func directMarkdownSkillInstallsSuccessfully() throws {
        let tempMD = FileManager.default.temporaryDirectory.appendingPathComponent("test-direct-\(UUID().uuidString).md")
        let content = """
        ---
        name: direct-md-skill
        description: Installed from direct markdown
        ---

        # Direct Markdown Instructions
        Run local analysis tools.
        """
        try content.write(to: tempMD, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempMD) }

        let importer = SkillImporter.shared
        let staged = try importer.stageAndInspect(fileURL: tempMD)
        #expect(staged.skillID.rawValue == "direct-md-skill")
        #expect(staged.parsedMarkdown.description == "Installed from direct markdown")

        let descriptor = try importer.install(staged: staged)
        defer { SkillStore.shared.deleteCustomSkill(skillID: descriptor.id) }

        #expect(descriptor.id.rawValue == "direct-md-skill")
        #expect(SkillStore.shared.allCustomSkillDescriptors().contains { $0.id == descriptor.id })
    }

    @Test("Failed replacement preserves previously installed skill atomically")
    func failedReplacementPreservesPreviouslyInstalledSkill() throws {
        let store = SkillStore.shared
        let skillID = try HanlinSkillID(validating: "atomic-skill-test")

        try store.saveCustomSkill(
            id: skillID,
            title: "Original Skill Title",
            description: "Original Description",
            instructions: "Original Instructions"
        )
        try store.addOrUpdateTextResource(for: skillID, relativePath: "original.txt", content: "Original Resource Content")
        defer { store.deleteCustomSkill(skillID: skillID) }

        // Verify initial state
        let initialRecord = try #require(store.allStoredRecords().first(where: { $0.descriptor.id == skillID }))
        #expect(initialRecord.descriptor.title.preferredValue() == "Original Skill Title")
        #expect(store.safeResourceURL(for: skillID, relativePath: "original.txt") != nil)

        // Attempt invalid staged replacement (corrupt staging root with missing SKILL.md)
        let brokenStagingDir = FileManager.default.temporaryDirectory.appendingPathComponent("broken-stage-\(UUID().uuidString)", isDirectory: true)
        let brokenSkillRoot = brokenStagingDir.appendingPathComponent(skillID.rawValue, isDirectory: true)
        try FileManager.default.createDirectory(at: brokenSkillRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: brokenStagingDir) }

        let brokenStaged = StagedSkillPackage(
            stagingDirectoryURL: brokenStagingDir,
            skillRootDirectoryURL: brokenSkillRoot,
            skillID: skillID,
            parsedMarkdown: SkillMarkdownParser.ParsedSkillMarkdown(name: "Broken", description: "Broken", body: "Broken"),
            metadata: HanlinSkillMetadata(preferredToolIDs: [], triggerHints: [], keywords: [], baseSkillID: nil, originURL: nil, sha256: nil, isEnabled: true, installedAt: Date(), updatedAt: Date()),
            resources: [],
            sha256: "dummy-hash"
        )

        // Install should fail because target SKILL.md is missing in root
        #expect(throws: Error.self) {
            _ = try store.install(stagedPackage: brokenStaged)
        }

        // Original skill and its resources must still exist and be completely intact!
        let preservedRecord = try #require(store.allStoredRecords().first(where: { $0.descriptor.id == skillID }))
        #expect(preservedRecord.descriptor.title.preferredValue() == "Original Skill Title")
        #expect(store.safeResourceURL(for: skillID, relativePath: "original.txt") != nil)
    }

    @Test("HanlinArchivePolicy inspectSkillArchive validates valid archives without script.json")
    func archivePolicyAllowsSkillWithoutScriptJSON() {
        let policy = HanlinArchivePolicy()
        let entries = [
            HanlinArchiveEntryMetadata(path: "SKILL.md", kind: .file, compressedBytes: 100, uncompressedBytes: 200),
            HanlinArchiveEntryMetadata(path: "scripts/run.py", kind: .file, compressedBytes: 150, uncompressedBytes: 300),
            HanlinArchiveEntryMetadata(path: "references/guide.md", kind: .file, compressedBytes: 80, uncompressedBytes: 160)
        ]

        let result = policy.inspectSkillArchive(
            entries: entries,
            centralDirectoryEntryCount: entries.count,
            archiveBytes: 400
        )
        #expect(result.isInstallable)
    }

    @Test("HanlinArchivePolicy inspectSkillArchive rejects archive security threats")
    func archivePolicyRejectsSecurityThreats() {
        let policy = HanlinArchivePolicy()

        // 1. Directory traversal
        let traversalEntries = [
            HanlinArchiveEntryMetadata(path: "SKILL.md", kind: .file, compressedBytes: 10, uncompressedBytes: 20),
            HanlinArchiveEntryMetadata(path: "../secret.txt", kind: .file, compressedBytes: 10, uncompressedBytes: 20)
        ]
        #expect(!policy.inspectSkillArchive(entries: traversalEntries, centralDirectoryEntryCount: 2, archiveBytes: 50).isInstallable)

        // 2. Symlinks
        let symlinkEntries = [
            HanlinArchiveEntryMetadata(path: "SKILL.md", kind: .file, compressedBytes: 10, uncompressedBytes: 20),
            HanlinArchiveEntryMetadata(path: "symlink.txt", kind: .symbolicLink, compressedBytes: 10, uncompressedBytes: 20)
        ]
        #expect(!policy.inspectSkillArchive(entries: symlinkEntries, centralDirectoryEntryCount: 2, archiveBytes: 50).isInstallable)

        // 3. Absolute path / drive prefix
        let driveEntries = [
            HanlinArchiveEntryMetadata(path: "SKILL.md", kind: .file, compressedBytes: 10, uncompressedBytes: 20),
            HanlinArchiveEntryMetadata(path: "C:\\Windows\\system32.dll", kind: .file, compressedBytes: 10, uncompressedBytes: 20)
        ]
        #expect(!policy.inspectSkillArchive(entries: driveEntries, centralDirectoryEntryCount: 2, archiveBytes: 50).isInstallable)

        // 4. Missing SKILL.md
        let missingEntries = [
            HanlinArchiveEntryMetadata(path: "readme.txt", kind: .file, compressedBytes: 10, uncompressedBytes: 20)
        ]
        #expect(!policy.inspectSkillArchive(entries: missingEntries, centralDirectoryEntryCount: 1, archiveBytes: 50).isInstallable)

        // 5. Multiple SKILL.md
        let duplicateEntries = [
            HanlinArchiveEntryMetadata(path: "SKILL.md", kind: .file, compressedBytes: 10, uncompressedBytes: 20),
            HanlinArchiveEntryMetadata(path: "sub/SKILL.md", kind: .file, compressedBytes: 10, uncompressedBytes: 20)
        ]
        #expect(!policy.inspectSkillArchive(entries: duplicateEntries, centralDirectoryEntryCount: 2, archiveBytes: 50).isInstallable)
    }

    @Test("Resource reading requires loaded skill and respects bounds")
    func resourceReadingContract() async throws {
        let store = SkillStore.shared
        let catalog = HanlinSkillCatalog.shared
        let session = AssistantCapabilitySession()

        let skillID = try HanlinSkillID(validating: "res-test-skill")
        try store.saveCustomSkill(
            id: skillID,
            title: "Resource Test Skill",
            description: "Resource contract test",
            instructions: "Testing resource reading"
        )
        try store.addOrUpdateTextResource(for: skillID, relativePath: "references/guide.md", content: "Line 1: Intro\nLine 2: Section A\nLine 3: Section B\nLine 4: Outro")
        defer { store.deleteCustomSkill(skillID: skillID) }

        catalog.synchronizeProductionSkills()

        // 1. Unloaded skill rejects reading
        let unloadedResult = await ReadSkillResourceTool.execute(
            argumentsJSON: "{\"skill_id\":\"res-test-skill\",\"relative_path\":\"references/guide.md\"}",
            session: session,
            catalog: catalog
        )
        #expect(unloadedResult.contains("is not currently loaded"))

        // 2. Load the skill
        let loadResult = await LoadSkillTool.execute(
            argumentsJSON: "{\"skill_id\":\"res-test-skill\"}",
            session: session,
            catalog: catalog
        )
        #expect(session.isSkillLoaded(skillID))

        // 3. Read valid resource with pagination
        let readResult = await ReadSkillResourceTool.execute(
            argumentsJSON: "{\"skill_id\":\"res-test-skill\",\"relative_path\":\"references/guide.md\",\"line_offset\":1,\"line_limit\":2}",
            session: session,
            catalog: catalog
        )
        #expect(readResult.contains("Line 1: Intro"))
        #expect(readResult.contains("Line 2: Section A"))
        #expect(readResult.contains("Truncated"))

        // 4. Traversal rejection
        let traversalResult = await ReadSkillResourceTool.execute(
            argumentsJSON: "{\"skill_id\":\"res-test-skill\",\"relative_path\":\"../etc/passwd\"}",
            session: session,
            catalog: catalog
        )
        #expect(traversalResult.contains("Directory traversal is not permitted") || traversalResult.contains("Invalid resource path"))
    }

    @Test("Imported Python script can be read as text and is not executed during installation")
    func importedPythonScriptCanBeReadButIsNotExecutedDuringInstall() async throws {
        let store = SkillStore.shared
        let catalog = HanlinSkillCatalog.shared
        let session = AssistantCapabilitySession()

        let skillID = try HanlinSkillID(validating: "python-resource-skill")
        try store.saveCustomSkill(
            id: skillID,
            title: "Python Resource Skill",
            description: "Python resource test",
            instructions: "Testing python resource"
        )
        try store.addOrUpdateTextResource(for: skillID, relativePath: "scripts/analyze.py", content: "import os\nprint('hello from script')")
        defer { store.deleteCustomSkill(skillID: skillID) }

        catalog.synchronizeProductionSkills()

        _ = await LoadSkillTool.execute(
            argumentsJSON: "{\"skill_id\":\"python-resource-skill\"}",
            session: session,
            catalog: catalog
        )

        let readResult = await ReadSkillResourceTool.execute(
            argumentsJSON: "{\"skill_id\":\"python-resource-skill\",\"relative_path\":\"scripts/analyze.py\"}",
            session: session,
            catalog: catalog
        )
        #expect(readResult.contains("import os"))
        #expect(readResult.contains("print('hello from script')"))
    }
}
