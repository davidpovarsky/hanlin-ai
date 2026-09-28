import Foundation
import Testing
import HanlinPlatformContracts
import HanlinMiniAppCore
import HanlinScriptCompiler
@testable import AI_Hanlin

@MainActor
@Suite("Production System Skills Verification", .serialized)
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
                #expect(catalogEntries.contains(toolID), "Skill '\(skill.id.rawValue)' advertises preferredToolID '\(toolID)' which is not registered in NativeToolCatalog!")
            }
        }
    }

    @Test("Disabled domain disappears from skill index")
    func disabledDomainDisappearsFromSkillIndex() throws {
        let catalog = HanlinSkillCatalog.shared
        catalog.synchronizeProductionSkills(memoryEnabled: false, codeEnabled: false)
        let skills = catalog.allSkills()
        #expect(!skills.contains { $0.id.rawValue == "code" })
        #expect(!skills.contains { $0.id.rawValue == "memory" })
        #expect(catalog.resolve(rawID: "code") == nil)
        #expect(catalog.resolve(rawID: "memory") == nil)

        // Restore
        catalog.synchronizeProductionSkills(memoryEnabled: true, codeEnabled: true)
        #expect(catalog.resolve(rawID: "code") != nil)
        #expect(catalog.resolve(rawID: "memory") != nil)
    }

    @Test("Canonical tools remain discoverable by exact alias")
    func canonicalToolsRemainDiscoverableByExactAlias() async throws {
        NativeToolCatalog.shared.ensureBuiltinsRegistered()
        let canonicalAliases = [
            "quick_calculate",
            "execute_local_python_code",
            "execute_javascript_code",
            "execute_typescript_code",
            "execute_shell_command"
        ]

        let session = AssistantCapabilitySession()
        let prepared = try await AssistantToolBridge.prepare(scope: .nativeOnly)

        for alias in canonicalAliases {
            let searchJson = "{\"query\":\"\(alias)\",\"limit\":5}"
            let result = ToolSearchTool.execute(
                argumentsJSON: searchJson,
                session: session,
                searchProvider: { q, l in
                    prepared.search(query: q, limit: l, preferredAliases: session.activeSkillToolHints)
                }
            )
            #expect(result.contains(alias), "ToolSearchTool failed to discover canonical alias '\(alias)'")
            #expect(session.exposedToolAliases.contains(alias), "ToolSearchTool did not expose alias '\(alias)' in session")
        }
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
        let tempDir = FileManager.default.temporaryDirectory.appending(path: "PackageGenTest-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let source = tempDir.appending(path: "Source", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source.appending(path: "references"), withIntermediateDirectories: true)
        try Data(#"{"name":"Gen Skill Package","version":"1.0.0","entry":"index.tsx","runInApp":true,"skills":[{"id":"gen-skill","title":"Gen Skill","summary":"Gen summary","instructions":{"resource":"references/doc.md"}}]}"#.utf8)
            .write(to: source.appending(path: "script.json"), options: .atomic)
        try Data(#"import { Text } from "scripting""#.utf8).write(to: source.appending(path: "index.tsx"), options: .atomic)
        try Data("GEN 1 DOC CONTENT".utf8).write(to: source.appending(path: "references/doc.md"), options: .atomic)

        let archive = tempDir.appending(path: "gen-skill.scripting", directoryHint: .notDirectory)
        try HanlinScriptingPackageExporter().exportPackage(at: source, to: archive)

        let platformRoot = tempDir.appending(path: "Platform", directoryHint: .isDirectory)
        let platform = HanlinScriptingPlatform(rootOverride: platformRoot)
        await platform.importPackage(from: archive)
        let preview = try #require(platform.preview)
        #expect(preview.canInstall)
        await platform.installPreview()
        let installed = try #require(platform.installedPackages.first)
        let installedID = installed.record.installedPackageID

        let catalog = HanlinSkillCatalog.shared
        catalog.synchronizeProductionSkills(scriptingPlatform: platform)

        let resolvedGen1 = try #require(catalog.resolve(rawID: "gen-skill"))
        let instructions1 = await catalog.loadInstructions(for: resolvedGen1)
        #expect(instructions1 == "GEN 1 DOC CONTENT")

        // Update to Generation 2
        try Data("GEN 2 UPDATED CONTENT".utf8).write(to: source.appending(path: "references/doc.md"), options: .atomic)
        let archive2 = tempDir.appending(path: "gen-skill-v2.scripting", directoryHint: .notDirectory)
        try HanlinScriptingPackageExporter().exportPackage(at: source, to: archive2)
        await platform.importPackage(from: archive2)
        await platform.installPreview()

        catalog.synchronizeProductionSkills(scriptingPlatform: platform)
        let resolvedGen2 = try #require(catalog.resolve(rawID: "gen-skill"))
        let instructions2 = await catalog.loadInstructions(for: resolvedGen2)
        #expect(instructions2 == "GEN 2 UPDATED CONTENT")

        // Rollback to Generation 1
        await platform.rollback(installedID, to: 1)
        catalog.synchronizeProductionSkills(scriptingPlatform: platform)
        let resolvedRollback = try #require(catalog.resolve(rawID: "gen-skill"))
        let instructionsRollback = await catalog.loadInstructions(for: resolvedRollback)
        #expect(instructionsRollback == "GEN 1 DOC CONTENT")

        // Clean up
        catalog.synchronizeProductionSkills()
    }

    @Test("Package disable and uninstall remove skill immediately")
    func packageDisableAndUninstallRemoveSkillImmediately() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: "PackageLifecycleTest-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let source = tempDir.appending(path: "Source", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source.appending(path: "references"), withIntermediateDirectories: true)
        try Data(#"{"name":"Lifecycle Skill Package","version":"1.0.0","entry":"index.tsx","runInApp":true,"skills":[{"id":"lifecycle-skill","title":"Lifecycle Skill","summary":"Lifecycle summary","instructions":{"resource":"references/doc.md"}}]}"#.utf8)
            .write(to: source.appending(path: "script.json"), options: .atomic)
        try Data(#"import { Text } from "scripting""#.utf8).write(to: source.appending(path: "index.tsx"), options: .atomic)
        try Data("LIFECYCLE DOC CONTENT".utf8).write(to: source.appending(path: "references/doc.md"), options: .atomic)

        let archive = tempDir.appending(path: "lifecycle-skill.scripting", directoryHint: .notDirectory)
        try HanlinScriptingPackageExporter().exportPackage(at: source, to: archive)

        let platformRoot = tempDir.appending(path: "Platform", directoryHint: .isDirectory)
        let platform = HanlinScriptingPlatform(rootOverride: platformRoot)
        await platform.importPackage(from: archive)
        let preview = try #require(platform.preview)
        #expect(preview.canInstall)
        await platform.installPreview()
        let installed = try #require(platform.installedPackages.first)
        let installedID = installed.record.installedPackageID

        let catalog = HanlinSkillCatalog.shared
        catalog.synchronizeProductionSkills(scriptingPlatform: platform)

        // 1. Skill resolves when package is installed and enabled
        let resolved = try #require(catalog.resolve(rawID: "lifecycle-skill"))
        #expect(resolved.id.rawValue == "lifecycle-skill")
        let resURL = catalog.resolveResourceURL(skillID: resolved.id, relativePath: "references/doc.md")
        #expect(resURL != nil)

        // 2. Disable package -> skill disappears immediately from catalog
        await platform.setEnabled(false, for: installedID)
        catalog.synchronizeProductionSkills(scriptingPlatform: platform)
        #expect(catalog.resolve(rawID: "lifecycle-skill") == nil)
        #expect(catalog.resolveResourceURL(skillID: resolved.id, relativePath: "references/doc.md") == nil)

        // 3. Re-enable package -> skill reappears immediately in catalog
        await platform.setEnabled(true, for: installedID)
        catalog.synchronizeProductionSkills(scriptingPlatform: platform)
        #expect(catalog.resolve(rawID: "lifecycle-skill") != nil)
        #expect(catalog.resolveResourceURL(skillID: resolved.id, relativePath: "references/doc.md") != nil)

        // 4. Uninstall package -> skill disappears and resource resolver fails
        await platform.uninstall(installedID)
        catalog.synchronizeProductionSkills(scriptingPlatform: platform)
        #expect(catalog.resolve(rawID: "lifecycle-skill") == nil)
        #expect(catalog.resolveResourceURL(skillID: resolved.id, relativePath: "references/doc.md") == nil)

        // Clean up
        catalog.synchronizeProductionSkills()
    }

    @Test("Same tier unrelated sources cannot silently shadow each other")
    func sameTierUnrelatedSourcesCannotSilentlyShadow() throws {
        let catalog = HanlinSkillCatalog.shared
        catalog.reset()

        let skillID = try HanlinSkillID(validating: "shadow-test-skill")
        let descA = try HanlinSkillDescriptor(
            id: skillID,
            title: "Source A Skill",
            summary: "Registered by Source A",
            instructions: .inline("Instructions A")
        )
        let sourceA = SkillSourceIdentity(kind: .installedPackage, identifier: "pkg-source-a")
        catalog.register(skill: descA, tier: .installedPackage, isExplicitOverride: false, sourceIdentity: sourceA)
        #expect(catalog.resolve(id: skillID)?.title.preferredValue() == "Source A Skill")

        // Unrelated source B tries to register same skill at same tier -> REJECTED
        let descB = try HanlinSkillDescriptor(
            id: skillID,
            title: "Source B Rogue Skill",
            summary: "Registered by Source B",
            instructions: .inline("Instructions B")
        )
        let sourceB = SkillSourceIdentity(kind: .installedPackage, identifier: "pkg-source-b")
        catalog.register(skill: descB, tier: .installedPackage, isExplicitOverride: false, sourceIdentity: sourceB)
        #expect(catalog.resolve(id: skillID)?.title.preferredValue() == "Source A Skill")

        // Same source A updates skill -> ACCEPTED
        let descAUpdated = try HanlinSkillDescriptor(
            id: skillID,
            title: "Source A Updated Skill",
            summary: "Registered by Source A Updated",
            instructions: .inline("Instructions A Updated")
        )
        catalog.register(skill: descAUpdated, tier: .installedPackage, isExplicitOverride: false, sourceIdentity: sourceA)
        #expect(catalog.resolve(id: skillID)?.title.preferredValue() == "Source A Updated Skill")

        // Explicit override -> ACCEPTED
        let descOverride = try HanlinSkillDescriptor(
            id: skillID,
            title: "Source B Explicit Override",
            summary: "Override by Source B",
            instructions: .inline("Instructions Override")
        )
        catalog.register(skill: descOverride, tier: .installedPackage, isExplicitOverride: true, sourceIdentity: sourceB)
        #expect(catalog.resolve(id: skillID)?.title.preferredValue() == "Source B Explicit Override")

        // Restore
        catalog.synchronizeProductionSkills()
    }

    @Test("Store refresh preserves disabled production domains")
    func storeRefreshPreservesDisabledProductionDomains() throws {
        let catalog = HanlinSkillCatalog.shared
        catalog.synchronizeProductionSkills(codeEnabled: false)
        #expect(catalog.resolve(rawID: "code") == nil)

        // Store refresh must retain codeEnabled: false!
        catalog.refreshFromStore()
        #expect(catalog.resolve(rawID: "code") == nil)

        // Restore
        catalog.synchronizeProductionSkills(codeEnabled: true)
        #expect(catalog.resolve(rawID: "code") != nil)
    }
}
