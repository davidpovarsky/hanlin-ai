import Foundation
import Testing
import HanlinPlatformContracts
import HanlinScriptCompiler
import ZIPFoundation
@testable import AI_Hanlin

private final class MockDownloaderURLProtocol: URLProtocol, @unchecked Sendable {
    struct MockResponse: Sendable {
        let statusCode: Int
        let headers: [String: String]
        let chunks: [Data]
        let redirectURL: URL?

        init(statusCode: Int, headers: [String: String] = [:], chunks: [Data] = [], redirectURL: URL? = nil) {
            self.statusCode = statusCode
            self.headers = headers
            self.chunks = chunks
            self.redirectURL = redirectURL
        }
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var handlers: [URL: MockResponse] = [:]

    static func reset() {
        lock.lock()
        handlers.removeAll()
        lock.unlock()
    }

    static func register(url: URL, response: MockResponse) {
        lock.lock()
        handlers[url] = response
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        lock.lock()
        defer { lock.unlock() }
        return handlers[url] != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.lock.lock()
        let mock = Self.handlers[url]
        Self.lock.unlock()

        guard let mock else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            return
        }

        if let redirect = mock.redirectURL {
            let resp = HTTPURLResponse(url: url, statusCode: mock.statusCode, httpVersion: "HTTP/1.1", headerFields: mock.headers)!
            let newReq = URLRequest(url: redirect)
            client?.urlProtocol(self, wasRedirectedTo: newReq, redirectResponse: resp)
            return
        }

        let resp = HTTPURLResponse(url: url, statusCode: mock.statusCode, httpVersion: "HTTP/1.1", headerFields: mock.headers)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)

        for chunk in mock.chunks {
            client?.urlProtocol(self, didLoad: chunk)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
@Suite("Skill Store, Markdown Parser, and Importer Tests", .serialized)
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
            parsedMarkdown: SkillMarkdownParser.ParsedSkillMarkdown(name: "Broken", description: "Broken", body: "Broken", rawFrontmatter: [:]),
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

        // 1. Root SKILL.md with various allowed file extensions (.py, .sh, .js, .ts, yaml/yml, csv, txt, binary png/pdf)
        // and ignored __MACOSX / ._AppleDouble entries
        let rootEntries = [
            HanlinArchiveEntryMetadata(path: "SKILL.md", kind: .file, compressedBytes: 100, uncompressedBytes: 200),
            HanlinArchiveEntryMetadata(path: "scripts/run.py", kind: .file, compressedBytes: 150, uncompressedBytes: 300),
            HanlinArchiveEntryMetadata(path: "scripts/deploy.sh", kind: .file, compressedBytes: 100, uncompressedBytes: 200),
            HanlinArchiveEntryMetadata(path: "scripts/helper.js", kind: .file, compressedBytes: 120, uncompressedBytes: 240),
            HanlinArchiveEntryMetadata(path: "scripts/bundle.ts", kind: .file, compressedBytes: 140, uncompressedBytes: 280),
            HanlinArchiveEntryMetadata(path: "configs/model.yaml", kind: .file, compressedBytes: 90, uncompressedBytes: 180),
            HanlinArchiveEntryMetadata(path: "configs/settings.yml", kind: .file, compressedBytes: 80, uncompressedBytes: 160),
            HanlinArchiveEntryMetadata(path: "data/table.csv", kind: .file, compressedBytes: 110, uncompressedBytes: 220),
            HanlinArchiveEntryMetadata(path: "references/guide.txt", kind: .file, compressedBytes: 80, uncompressedBytes: 160),
            HanlinArchiveEntryMetadata(path: "assets/logo.png", kind: .file, compressedBytes: 500, uncompressedBytes: 500),
            HanlinArchiveEntryMetadata(path: "assets/manual.pdf", kind: .file, compressedBytes: 1000, uncompressedBytes: 1000),
            HanlinArchiveEntryMetadata(path: "__MACOSX/SKILL.md", kind: .file, compressedBytes: 20, uncompressedBytes: 40),
            HanlinArchiveEntryMetadata(path: "._SKILL.md", kind: .file, compressedBytes: 20, uncompressedBytes: 40)
        ]

        let rootResult = policy.inspectSkillArchive(
            entries: rootEntries,
            centralDirectoryEntryCount: rootEntries.count,
            archiveBytes: 3000
        )
        #expect(rootResult.isInstallable)
        #expect(rootResult.ignoredEntries.contains("__MACOSX/SKILL.md"))
        #expect(rootResult.ignoredEntries.contains("._SKILL.md"))

        // 2. Single wrapper SKILL.md
        let wrapperEntries = [
            HanlinArchiveEntryMetadata(path: "my-skill/SKILL.md", kind: .file, compressedBytes: 100, uncompressedBytes: 200),
            HanlinArchiveEntryMetadata(path: "my-skill/scripts/run.py", kind: .file, compressedBytes: 150, uncompressedBytes: 300),
            HanlinArchiveEntryMetadata(path: "my-skill/references/guide.txt", kind: .file, compressedBytes: 80, uncompressedBytes: 160)
        ]
        let wrapperResult = policy.inspectSkillArchive(
            entries: wrapperEntries,
            centralDirectoryEntryCount: wrapperEntries.count,
            archiveBytes: 400
        )
        #expect(wrapperResult.isInstallable)
        #expect(wrapperResult.wrapperDirectory == "my-skill")
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

        // 6. NUL path
        let nulEntries = [
            HanlinArchiveEntryMetadata(path: "SKILL.md", kind: .file, compressedBytes: 10, uncompressedBytes: 20),
            HanlinArchiveEntryMetadata(path: "scripts/null\0byte.py", kind: .file, compressedBytes: 10, uncompressedBytes: 20)
        ]
        #expect(!policy.inspectSkillArchive(entries: nulEntries, centralDirectoryEntryCount: 2, archiveBytes: 50).isInstallable)

        // 7. Absolute Unix path
        let unixAbsoluteEntries = [
            HanlinArchiveEntryMetadata(path: "SKILL.md", kind: .file, compressedBytes: 10, uncompressedBytes: 20),
            HanlinArchiveEntryMetadata(path: "/etc/passwd", kind: .file, compressedBytes: 10, uncompressedBytes: 20)
        ]
        #expect(!policy.inspectSkillArchive(entries: unixAbsoluteEntries, centralDirectoryEntryCount: 2, archiveBytes: 50).isInstallable)

        // 8. Hardlink
        let hardlinkEntries = [
            HanlinArchiveEntryMetadata(path: "SKILL.md", kind: .file, compressedBytes: 10, uncompressedBytes: 20),
            HanlinArchiveEntryMetadata(path: "hardlink.txt", kind: .hardLink, compressedBytes: 10, uncompressedBytes: 20)
        ]
        #expect(!policy.inspectSkillArchive(entries: hardlinkEntries, centralDirectoryEntryCount: 2, archiveBytes: 50).isInstallable)

        // 9. Unicode NFC/NFD collision
        let unicodeCollisionEntries = [
            HanlinArchiveEntryMetadata(path: "SKILL.md", kind: .file, compressedBytes: 10, uncompressedBytes: 20),
            HanlinArchiveEntryMetadata(path: "resume\u{0301}.txt", kind: .file, compressedBytes: 10, uncompressedBytes: 20),
            HanlinArchiveEntryMetadata(path: "resum\u{00E9}.txt", kind: .file, compressedBytes: 10, uncompressedBytes: 20)
        ]
        let unicodeResult = policy.inspectSkillArchive(entries: unicodeCollisionEntries, centralDirectoryEntryCount: 3, archiveBytes: 100)
        #expect(!unicodeResult.isInstallable)
        #expect(unicodeResult.findings.contains { $0.code == .unicodeCollision })

        // 10. Case-insensitive collision
        let caseCollisionEntries = [
            HanlinArchiveEntryMetadata(path: "SKILL.md", kind: .file, compressedBytes: 10, uncompressedBytes: 20),
            HanlinArchiveEntryMetadata(path: "scripts/run.py", kind: .file, compressedBytes: 10, uncompressedBytes: 20),
            HanlinArchiveEntryMetadata(path: "scripts/RUN.py", kind: .file, compressedBytes: 10, uncompressedBytes: 20)
        ]
        let caseResult = policy.inspectSkillArchive(entries: caseCollisionEntries, centralDirectoryEntryCount: 3, archiveBytes: 100)
        #expect(!caseResult.isInstallable)
        #expect(caseResult.findings.contains { $0.code == .caseCollision })

        // 11. Duplicate exact path
        let duplicatePathEntries = [
            HanlinArchiveEntryMetadata(path: "SKILL.md", kind: .file, compressedBytes: 10, uncompressedBytes: 20),
            HanlinArchiveEntryMetadata(path: "scripts/run.py", kind: .file, compressedBytes: 10, uncompressedBytes: 20),
            HanlinArchiveEntryMetadata(path: "scripts/run.py", kind: .file, compressedBytes: 10, uncompressedBytes: 20)
        ]
        let dupResult = policy.inspectSkillArchive(entries: duplicatePathEntries, centralDirectoryEntryCount: 3, archiveBytes: 100)
        #expect(!dupResult.isInstallable)
        #expect(dupResult.findings.contains { $0.code == .unicodeCollision })

        // 12. Excessive depth
        let shallowPolicy = HanlinArchivePolicy(limits: HanlinArchiveLimits(maximumDepth: 3))
        let deepEntries = [
            HanlinArchiveEntryMetadata(path: "SKILL.md", kind: .file, compressedBytes: 10, uncompressedBytes: 20),
            HanlinArchiveEntryMetadata(path: "a/b/c/d/deep.py", kind: .file, compressedBytes: 10, uncompressedBytes: 20)
        ]
        let deepResult = shallowPolicy.inspectSkillArchive(entries: deepEntries, centralDirectoryEntryCount: 2, archiveBytes: 100)
        #expect(!deepResult.isInstallable)
        #expect(deepResult.findings.contains { $0.code == .depthLimit })

        // 13. Excessive file count
        let smallCountPolicy = HanlinArchivePolicy(limits: HanlinArchiveLimits(maximumFiles: 2))
        let manyFileEntries = [
            HanlinArchiveEntryMetadata(path: "SKILL.md", kind: .file, compressedBytes: 10, uncompressedBytes: 20),
            HanlinArchiveEntryMetadata(path: "f1.py", kind: .file, compressedBytes: 10, uncompressedBytes: 20),
            HanlinArchiveEntryMetadata(path: "f2.py", kind: .file, compressedBytes: 10, uncompressedBytes: 20)
        ]
        let countResult = smallCountPolicy.inspectSkillArchive(entries: manyFileEntries, centralDirectoryEntryCount: 3, archiveBytes: 100)
        #expect(!countResult.isInstallable)
        #expect(countResult.findings.contains { $0.code == .fileCountLimit })

        // 14. Uncompressed total limit
        let smallSizePolicy = HanlinArchivePolicy(limits: HanlinArchiveLimits(maximumUncompressedBytes: 100))
        let largeUncompressedEntries = [
            HanlinArchiveEntryMetadata(path: "SKILL.md", kind: .file, compressedBytes: 10, uncompressedBytes: 20),
            HanlinArchiveEntryMetadata(path: "large.py", kind: .file, compressedBytes: 50, uncompressedBytes: 150)
        ]
        let sizeResult = smallSizePolicy.inspectSkillArchive(entries: largeUncompressedEntries, centralDirectoryEntryCount: 2, archiveBytes: 100)
        #expect(!sizeResult.isInstallable)
        #expect(sizeResult.findings.contains { $0.code == .uncompressedSizeLimit })

        // 15. Compression ratio bomb
        let bombEntries = [
            HanlinArchiveEntryMetadata(path: "SKILL.md", kind: .file, compressedBytes: 10, uncompressedBytes: 20),
            HanlinArchiveEntryMetadata(path: "bomb.txt", kind: .file, compressedBytes: 1, uncompressedBytes: 1000)
        ]
        let bombResult = policy.inspectSkillArchive(entries: bombEntries, centralDirectoryEntryCount: 2, archiveBytes: 100)
        #expect(!bombResult.isInstallable)
        #expect(bombResult.findings.contains { $0.code == .compressionRatioLimit })

        // 16. Central-directory count mismatch / encrypted or unreadable entries
        // Note: The current ZIP metadata model represents unreadable or encrypted entries
        // through a discrepancy between the entry count extracted and the central directory count.
        let centralMismatchEntries = [
            HanlinArchiveEntryMetadata(path: "SKILL.md", kind: .file, compressedBytes: 10, uncompressedBytes: 20)
        ]
        let centralMismatchResult = policy.inspectSkillArchive(
            entries: centralMismatchEntries,
            centralDirectoryEntryCount: 3,
            archiveBytes: 100
        )
        #expect(!centralMismatchResult.isInstallable)
        #expect(centralMismatchResult.findings.contains { $0.code == .encryptedEntry })

        // 17. Entries outside single wrapper
        let outsideWrapperEntries = [
            HanlinArchiveEntryMetadata(path: "wrapper/SKILL.md", kind: .file, compressedBytes: 10, uncompressedBytes: 20),
            HanlinArchiveEntryMetadata(path: "wrapper/scripts/run.py", kind: .file, compressedBytes: 10, uncompressedBytes: 20),
            HanlinArchiveEntryMetadata(path: "outside_entry.txt", kind: .file, compressedBytes: 10, uncompressedBytes: 20)
        ]
        let outsideResult = policy.inspectSkillArchive(entries: outsideWrapperEntries, centralDirectoryEntryCount: 3, archiveBytes: 100)
        #expect(!outsideResult.isInstallable)
        #expect(outsideResult.findings.contains { $0.code == .ambiguousManifest })
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

        // Add binary resource
        let tempPNG = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).png")
        try Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]).write(to: tempPNG)
        defer { try? FileManager.default.removeItem(at: tempPNG) }
        try store.addResourceFile(for: skillID, relativePath: "assets/logo.png", sourceFileURL: tempPNG)
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
        _ = await LoadSkillTool.execute(
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

        // 5. Binary resource returns metadata only without dumping raw bytes
        let binaryResult = await ReadSkillResourceTool.execute(
            argumentsJSON: "{\"skill_id\":\"res-test-skill\",\"relative_path\":\"assets/logo.png\"}",
            session: session,
            catalog: catalog
        )
        #expect(binaryResult.contains("Binary resource file: assets/logo.png"))
        #expect(binaryResult.contains("MIME: image/png"))

        // 6. Large text pagination contract
        let largeLines = (1...300).map { "Line \($0): data row content" }.joined(separator: "\n")
        try store.addOrUpdateTextResource(for: skillID, relativePath: "references/large.txt", content: largeLines)
        let pageResult = await ReadSkillResourceTool.execute(
            argumentsJSON: "{\"skill_id\":\"res-test-skill\",\"relative_path\":\"references/large.txt\",\"line_offset\":51,\"line_limit\":50}",
            session: session,
            catalog: catalog
        )
        #expect(pageResult.contains("Line 51: data row content"))
        #expect(pageResult.contains("Line 100: data row content"))
        #expect(!pageResult.contains("Line 50: data row content"))
        #expect(!pageResult.contains("Line 101: data row content"))
        #expect(pageResult.contains("lines 51-100 of 300"))
    }

    @Test("SkillStore and ReadSkillResourceTool reject symlink escaping root")
    func resourceReadingSymlinkEscapeRejected() throws {
        let store = SkillStore.shared
        let skillID = try HanlinSkillID(validating: "symlink-escape-skill")
        try store.saveCustomSkill(
            id: skillID,
            title: "Symlink Skill",
            description: "Symlink security test",
            instructions: "Safe instructions"
        )
        defer { store.deleteCustomSkill(skillID: skillID) }

        guard let skillDir = store.directoryURL(for: skillID) else {
            Issue.record("Skill directory not found")
            return
        }

        let outsideFile = FileManager.default.temporaryDirectory.appendingPathComponent("outside-\(UUID().uuidString).txt")
        try "CONFIDENTIAL".write(to: outsideFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outsideFile) }

        let symlinkInside = skillDir.appendingPathComponent("escaped_link.txt")
        do {
            try FileManager.default.createSymbolicLink(at: symlinkInside, withDestinationURL: outsideFile)
            defer { try? FileManager.default.removeItem(at: symlinkInside) }

            // safeResourceURL must return nil because resolved path is outside skillDir!
            #expect(store.safeResourceURL(for: skillID, relativePath: "escaped_link.txt") == nil)
        } catch {
            // Symlink creation might be prohibited by OS or filesystem policy (e.g. non-developer Windows)
            #expect(store.safeResourceURL(for: skillID, relativePath: "../outside.txt") == nil)
        }
    }

    @Test("Imported Python script can be read as text and is not executed during installation")
    func importedPythonScriptCanBeReadButIsNotExecutedDuringInstall() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let sentinelURL = tempDir.appendingPathComponent("sentinel-\(UUID().uuidString).txt")
        let tempZip = tempDir.appendingPathComponent("danger-\(UUID().uuidString).zip")
        defer {
            try? FileManager.default.removeItem(at: tempZip)
            try? FileManager.default.removeItem(at: sentinelURL)
        }

        // Create genuine ZIP containing SKILL.md and scripts/danger.py
        guard let archive = try? Archive(url: tempZip, accessMode: .create) else {
            Issue.record("Failed to create test ZIP archive")
            return
        }

        let skillMD = """
        ---
        name: danger-python-skill
        description: Skill containing unexecuted danger script
        ---

        # Danger Python Skill Instructions
        Execute safely.
        """
        let skillMDData = Data(skillMD.utf8)
        try archive.addEntry(with: "SKILL.md", type: .file, uncompressedSize: UInt32(skillMDData.count), provider: { position, size in
            skillMDData.subdata(in: position..<(position + size))
        })

        let scriptCode = """
        import os
        with open('\(sentinelURL.path)', 'w') as f:
            f.write('HACKED')
        """
        let scriptData = Data(scriptCode.utf8)
        try archive.addEntry(with: "scripts/danger.py", type: .file, uncompressedSize: UInt32(scriptData.count), provider: { position, size in
            scriptData.subdata(in: position..<(position + size))
        })

        // Inspect and install staged ZIP
        let importer = SkillImporter.shared
        let staged = try importer.stageAndInspect(fileURL: tempZip)
        let descriptor = try importer.install(staged: staged)
        defer { SkillStore.shared.deleteCustomSkill(skillID: descriptor.id) }

        // Assert sentinel file was NOT created (script was not executed during install!)
        #expect(!FileManager.default.fileExists(atPath: sentinelURL.path))

        let catalog = HanlinSkillCatalog.shared
        catalog.synchronizeProductionSkills()

        let session = AssistantCapabilitySession()
        _ = await LoadSkillTool.execute(
            argumentsJSON: "{\"skill_id\":\"danger-python-skill\"}",
            session: session,
            catalog: catalog
        )

        let readResult = await ReadSkillResourceTool.execute(
            argumentsJSON: "{\"skill_id\":\"danger-python-skill\",\"relative_path\":\"scripts/danger.py\"}",
            session: session,
            catalog: catalog
        )
        #expect(readResult.contains("import os"))
        #expect(readResult.contains("HACKED"))

        // Still not executed after reading!
        #expect(!FileManager.default.fileExists(atPath: sentinelURL.path))
    }

    @Test("BoundedStreamDownloader enforces network limits and rejects non-HTTPS or oversize payloads")
    func boundedDownloaderEnforcesNetworkLimits() async throws {
        // Assert production max download constant is exactly 25 MiB
        #expect(SkillImporter.maxDownloadBytes == 25 * 1024 * 1024)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockDownloaderURLProtocol.self]
        let downloader = BoundedStreamDownloader(maxBytes: 100, sessionConfiguration: config)
        let importer = SkillImporter.shared

        // 1. HTTPS normal payload succeeds
        let okURL = URL(string: "https://mock.acceptance.test/valid-payload")!
        let okData = Data(repeating: 0x41, count: 50)
        MockDownloaderURLProtocol.register(
            url: okURL,
            response: .init(statusCode: 200, headers: ["Content-Length": "50"], chunks: [okData])
        )
        let (downloadedData, resp) = try await downloader.download(from: okURL)
        #expect(downloadedData == okData)
        #expect(resp.statusCode == 200)

        // 2. HTTP rejected
        let httpURL = URL(string: "http://insecure.acceptance.test/skill.zip")!
        await #expect(throws: SkillImportError.self) {
            _ = try await downloader.download(from: httpURL)
        }

        // 3. HTTPS -> HTTP redirect rejected
        let redirectURL = URL(string: "https://mock.acceptance.test/redirect-to-http")!
        MockDownloaderURLProtocol.register(
            url: redirectURL,
            response: .init(statusCode: 302, redirectURL: httpURL)
        )
        await #expect(throws: SkillImportError.self) {
            _ = try await downloader.download(from: redirectURL)
        }

        // 4. Non-2xx rejected
        let notFoundURL = URL(string: "https://mock.acceptance.test/not-found")!
        MockDownloaderURLProtocol.register(
            url: notFoundURL,
            response: .init(statusCode: 404)
        )
        await #expect(throws: SkillImportError.self) {
            _ = try await downloader.download(from: notFoundURL)
        }

        // 5. Content-Length above max rejected
        let headerOverflowURL = URL(string: "https://mock.acceptance.test/header-overflow")!
        MockDownloaderURLProtocol.register(
            url: headerOverflowURL,
            response: .init(statusCode: 200, headers: ["Content-Length": "150"], chunks: [Data(count: 150)])
        )
        await #expect(throws: SkillImportError.self) {
            _ = try await downloader.download(from: headerOverflowURL)
        }

        // 6. Stream/chunked payload crossing max rejected during receive
        let streamOverflowURL = URL(string: "https://mock.acceptance.test/stream-overflow")!
        MockDownloaderURLProtocol.register(
            url: streamOverflowURL,
            response: .init(
                statusCode: 200,
                headers: [:],
                chunks: [
                    Data(repeating: 0x41, count: 60),
                    Data(repeating: 0x42, count: 60)
                ]
            )
        )
        await #expect(throws: SkillImportError.self) {
            _ = try await downloader.download(from: streamOverflowURL)
        }

        // 7. Direct markdown MIME accepted where production importer supports it
        let mdURL = URL(string: "https://mock.acceptance.test/skill-endpoint")!
        let mdContent = """
        ---
        name: streamed-md-skill
        description: Streamed direct markdown skill
        ---

        # Streamed MD Instructions
        Step 1: run tests.
        """
        MockDownloaderURLProtocol.register(
            url: mdURL,
            response: .init(
                statusCode: 200,
                headers: ["Content-Type": "text/markdown; charset=utf-8"],
                chunks: [Data(mdContent.utf8)]
            )
        )
        let stagedMD = try await importer.downloadAndStage(from: mdURL, sessionConfiguration: config)
        defer { stagedMD.cleanup() }
        #expect(stagedMD.skillID.rawValue == "streamed-md-skill")
        #expect(stagedMD.parsedMarkdown.description == "Streamed direct markdown skill")

        // 8. ZIP response accepted
        let zipURL = URL(string: "https://mock.acceptance.test/archive-skill")!
        let tempZipURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-zip-\(UUID().uuidString).zip")
        guard let archive = try? Archive(url: tempZipURL, accessMode: .create) else {
            Issue.record("Failed to create temporary ZIP")
            return
        }
        let zipSkillMD = """
        ---
        name: streamed-zip-skill
        description: Streamed zip skill
        ---

        # Streamed Zip Instructions
        Step 1: run tests.
        """
        let zipSkillMDData = Data(zipSkillMD.utf8)
        try archive.addEntry(with: "SKILL.md", type: .file, uncompressedSize: UInt32(zipSkillMDData.count), provider: { position, size in
            zipSkillMDData.subdata(in: position..<(position + size))
        })
        let zipBytes = try Data(contentsOf: tempZipURL)
        try? FileManager.default.removeItem(at: tempZipURL)

        MockDownloaderURLProtocol.register(
            url: zipURL,
            response: .init(
                statusCode: 200,
                headers: ["Content-Type": "application/zip"],
                chunks: [zipBytes]
            )
        )
        let stagedZip = try await importer.downloadAndStage(from: zipURL, sessionConfiguration: config)
        defer { stagedZip.cleanup() }
        #expect(stagedZip.skillID.rawValue == "streamed-zip-skill")
        #expect(stagedZip.parsedMarkdown.description == "Streamed zip skill")
    }

    @Test("Temporary staging directory cleans up on success and failure")
    func tempStagingCleansUpOnSuccessAndFailure() throws {
        let stagingDir = FileManager.default.temporaryDirectory.appendingPathComponent("stage-test-\(UUID().uuidString)", isDirectory: true)
        let skillRoot = stagingDir.appendingPathComponent("test-skill", isDirectory: true)
        try FileManager.default.createDirectory(at: skillRoot, withIntermediateDirectories: true)

        let staged = StagedSkillPackage(
            stagingDirectoryURL: stagingDir,
            skillRootDirectoryURL: skillRoot,
            skillID: try HanlinSkillID(validating: "test-skill"),
            parsedMarkdown: SkillMarkdownParser.ParsedSkillMarkdown(name: "test-skill", description: "test", body: "body", rawFrontmatter: [:]),
            metadata: HanlinSkillMetadata(preferredToolIDs: [], triggerHints: [], keywords: [], baseSkillID: nil, originURL: nil, sha256: nil, isEnabled: true, installedAt: Date(), updatedAt: Date()),
            resources: [],
            sha256: "hash"
        )
        #expect(FileManager.default.fileExists(atPath: stagingDir.path))
        staged.cleanup()
        #expect(!FileManager.default.fileExists(atPath: stagingDir.path))
    }

    @Test("Skill editor rejects unknown preferred tool alias")
    func skillEditorRejectsUnknownPreferredToolAlias() {
        let available: Set<String> = ["quick_calculate", "execute_local_python_code"]
        let invalid = SkillEditorView.validatePreferredToolAliases("unknown_tool_xyz, execute_local_python_code", against: available)
        #expect(invalid == ["unknown_tool_xyz"])

        let valid = SkillEditorView.validatePreferredToolAliases("quick_calculate, execute_local_python_code", against: available)
        #expect(valid.isEmpty)
    }
}
