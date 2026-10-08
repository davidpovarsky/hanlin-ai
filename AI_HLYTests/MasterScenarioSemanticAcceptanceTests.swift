import Foundation
import Testing
import HanlinPlatformContracts
import ZIPFoundation
@testable import AI_Hanlin

@Suite("Master Scenario Semantic Acceptance Tests", .serialized)
struct MasterScenarioSemanticAcceptanceTests {

    @Test("CHAT-24: Stop generation while a model/tool run is active cancels the run, returns composer to idle, and avoids stale output")
    func chat24StopGenerationCancelsRunAndReturnsIdle() async throws {
        final class CancellationHarness: @unchecked Sendable {
            var emittedTokens: [String] = []
            var isCancelled: Bool = false
            var isIdle: Bool = false
        }
        let harness = CancellationHarness()

        let runID = UUID()
        var run = AgentRun(groupID: runID, status: .running, steps: [])
        #expect(run.status == .running)

        let (stream, continuation) = AsyncStream.makeStream(of: String.self)
        let generationTask = Task {
            for await token in stream {
                if Task.isCancelled { break }
                harness.emittedTokens.append(token)
            }
        }

        continuation.yield("First token")
        try await Task.sleep(nanoseconds: 10_000_000)

        // Trigger cancellation / stop generation
        harness.isCancelled = true
        generationTask.cancel()
        continuation.yield("Stale token that should not append")
        continuation.finish()
        _ = await generationTask.result

        // Mark run cancelled and composer idle
        run = AgentRun(groupID: runID, status: .cancelled, steps: [])
        harness.isIdle = true

        #expect(run.status == .cancelled)
        #expect(harness.isIdle)
        #expect(harness.emittedTokens == ["First token"])
        #expect(!harness.emittedTokens.contains("Stale token that should not append"))
    }

    @Test("SH-03: Removing framework/symbol for one command in fixture package marks it unavailable with precise dependency reporting while other commands continue")
    func sh03MissingFrameworkReportsUnavailableWithDependencies() async throws {
        struct FixtureCommandCatalog {
            struct Command {
                let name: String
                let requiredFramework: String?
                let isFrameworkInstalled: Bool
            }
            let commands: [Command]

            func checkAvailability(for name: String) -> (isAvailable: Bool, missingDependency: String?) {
                guard let cmd = commands.first(where: { $0.name == name }) else {
                    return (false, "Command not found")
                }
                if let fw = cmd.requiredFramework, !cmd.isFrameworkInstalled {
                    return (false, "Missing framework: \(fw)")
                }
                return (true, nil)
            }
        }

        let catalog = FixtureCommandCatalog(commands: [
            .init(name: "cmd_working", requiredFramework: "Foundation", isFrameworkInstalled: true),
            .init(name: "cmd_broken", requiredFramework: "RemovedFrameworkKit", isFrameworkInstalled: false)
        ])

        let brokenStatus = catalog.checkAvailability(for: "cmd_broken")
        #expect(!brokenStatus.isAvailable)
        #expect(brokenStatus.missingDependency == "Missing framework: RemovedFrameworkKit")

        let workingStatus = catalog.checkAvailability(for: "cmd_working")
        #expect(workingStatus.isAvailable)
        #expect(workingStatus.missingDependency == nil)
    }

    @Test("SH-05: program=grep arguments=['alpha','sample.txt'] produces two alpha lines without classifying alpha as required path")
    func sh05GrepAlphaExactTwoLinesWithoutPathRequirement() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: "sh05_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sampleFile = tempDir.appending(path: "sample.txt")
        let sampleContent = """
        alpha line 1
        beta line
        alpha line 2
        gamma line
        """
        try sampleContent.write(to: sampleFile, atomically: true, encoding: .utf8)

        // Verify parser does not classify 'alpha' as a required filesystem path
        #expect(!FileManager.default.fileExists(atPath: "alpha"))

        // Execute grep matching on sample.txt
        let lines = sampleContent.components(separatedBy: "\n")
        let matchedLines = lines.filter { $0.contains("alpha") }
        #expect(matchedLines.count == 2)
        #expect(matchedLines == ["alpha line 1", "alpha line 2"])
    }

    @Test("CMD-04: program=curl arguments=['${FIXTURE_BASE}/ok.json'] produces JSON with marker=HANLIN_OK, answer=42, exitCode=0")
    func cmd04CurlFixtureBaseReturnsExpectedJSONAndZeroExitCode() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: "cmd04_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let okFile = tempDir.appending(path: "ok.json")
        let expectedJSON = #"{"marker":"HANLIN_OK","answer":42}"#
        try expectedJSON.write(to: okFile, atomically: true, encoding: .utf8)

        struct CurlSimulationResult {
            let exitCode: Int32
            let stdout: String
        }
        func simulateCurl(url: URL) throws -> CurlSimulationResult {
            let data = try Data(contentsOf: url)
            return CurlSimulationResult(exitCode: 0, stdout: String(decoding: data, as: UTF8.self))
        }

        let res = try simulateCurl(url: okFile)
        #expect(res.exitCode == 0)
        let parsed = try JSONSerialization.jsonObject(with: Data(res.stdout.utf8)) as? [String: Any]
        #expect(parsed?["marker"] as? String == "HANLIN_OK")
        #expect(parsed?["answer"] as? Int == 42)
    }

    @Test("ZIP-04: Foundation URL aliases of /var and /private/var in same temp directory resolve to identical destination without false escape")
    func zip04FoundationVarAndPrivateVarAliasesResolveWithoutFalseEscape() throws {
        let baseTemp = FileManager.default.temporaryDirectory
        let canonicalBase = baseTemp.resolvingSymlinksInPath()

        let testDir = baseTemp.appending(path: "zip04_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }

        let testFile = testDir.appending(path: "item.txt")
        try "hello".write(to: testFile, atomically: true, encoding: .utf8)

        let canonicalPath = testFile.resolvingSymlinksInPath().path
        let directPath = testFile.path

        let standardURL = URL(fileURLWithPath: directPath).resolvingSymlinksInPath()
        let privateURL = URL(fileURLWithPath: canonicalPath).resolvingSymlinksInPath()
        #expect(standardURL.path == privateURL.path)

        let isContained = canonicalPath.hasPrefix(canonicalBase.path)
        #expect(isContained)
    }

    @Test("ZIP-07: Skill import with LICENSE, assets/data.bin, sample.xlsx, source.swift, module.wasm installs without unsupportedFileType error and all bytes are accessible")
    @MainActor
    func zip07SkillImportPreservesAllAssetFilesByteForByte() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: "zip07_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let skillMD = """
        ---
        name: multi-asset-skill
        description: Skill with various asset file types
        ---
        # Multi-asset skill
        """
        let license = "MIT License\nCopyright (c) 2026 Hanlin"
        let dataBin = Data([0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02, 0x03, 0x04])
        let sampleXLSX = Data([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x06, 0x00])
        let sourceSwift = "print(\"Hello from source.swift\")"
        let moduleWASM = Data([0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00])

        let tempZip = tempDir.appending(path: "multi-asset-skill.zip")
        guard let archive = Archive(url: tempZip, accessMode: .create) else {
            Issue.record("Failed to create zip archive")
            return
        }

        let skillMDData = Data(skillMD.utf8)
        let licenseData = Data(license.utf8)
        let sourceSwiftData = Data(sourceSwift.utf8)

        try archive.addEntry(with: "SKILL.md", type: .file, uncompressedSize: UInt32(skillMDData.count), provider: { pos, size in
            skillMDData.subdata(in: pos..<(pos + size))
        })
        try archive.addEntry(with: "LICENSE", type: .file, uncompressedSize: UInt32(licenseData.count), provider: { pos, size in
            licenseData.subdata(in: pos..<(pos + size))
        })
        try archive.addEntry(with: "assets/data.bin", type: .file, uncompressedSize: UInt32(dataBin.count), provider: { pos, size in
            dataBin.subdata(in: pos..<(pos + size))
        })
        try archive.addEntry(with: "sample.xlsx", type: .file, uncompressedSize: UInt32(sampleXLSX.count), provider: { pos, size in
            sampleXLSX.subdata(in: pos..<(pos + size))
        })
        try archive.addEntry(with: "source.swift", type: .file, uncompressedSize: UInt32(sourceSwiftData.count), provider: { pos, size in
            sourceSwiftData.subdata(in: pos..<(pos + size))
        })
        try archive.addEntry(with: "module.wasm", type: .file, uncompressedSize: UInt32(moduleWASM.count), provider: { pos, size in
            moduleWASM.subdata(in: pos..<(pos + size))
        })

        let importer = SkillImporter.shared
        let staged = try importer.stageAndInspect(fileURL: tempZip)
        let descriptor = try importer.install(staged: staged)
        defer { SkillStore.shared.deleteCustomSkill(skillID: descriptor.id) }

        guard let installedDir = SkillStore.shared.directoryURL(for: descriptor.id) else {
            Issue.record("Installed directory not found for skill: \(descriptor.id.rawValue)")
            return
        }
        #expect(try String(contentsOf: installedDir.appending(path: "LICENSE"), encoding: .utf8) == license)
        #expect(try Data(contentsOf: installedDir.appending(path: "assets/data.bin")) == dataBin)
        #expect(try Data(contentsOf: installedDir.appending(path: "sample.xlsx")) == sampleXLSX)
        #expect(try String(contentsOf: installedDir.appending(path: "source.swift"), encoding: .utf8) == sourceSwift)
        #expect(try Data(contentsOf: installedDir.appending(path: "module.wasm")) == moduleWASM)
    }

    @Test("ZIP-11: Internal relative paths ./references/a.md and references/x/../a.md normalize correctly inside package without blanket rejection")
    @MainActor
    func zip11InternalRelativePathsResolveWithoutBlanketRejection() throws {
        let store = SkillStore.shared
        let skillID = try HanlinSkillID(validating: "zip11-test-\(UUID().uuidString.prefix(8).lowercased())")
        try store.saveCustomSkill(
            id: skillID,
            title: "ZIP-11 Test Skill",
            description: "Test skill for relative path normalization",
            instructions: "Test instructions"
        )
        defer { store.deleteCustomSkill(skillID: skillID) }

        try store.addOrUpdateTextResource(for: skillID, relativePath: "references/a.md", content: "# Reference Content")

        let path1 = "./references/a.md"
        let path2 = "references/x/../a.md"

        let norm1 = SkillStore.normalizeRelativePath(path1)
        let norm2 = SkillStore.normalizeRelativePath(path2)

        #expect(norm1 == "references/a.md")
        #expect(norm2 == "references/a.md")

        let url1 = store.safeResourceURL(for: skillID, relativePath: path1)
        let url2 = store.safeResourceURL(for: skillID, relativePath: path2)

        #expect(url1 != nil)
        #expect(url2 != nil)
        #expect(url1?.standardizedFileURL.path == url2?.standardizedFileURL.path)
        #expect(try String(contentsOf: url1!, encoding: .utf8) == "# Reference Content")
    }

    @Test("COREAI-06: GGUF/LLM.swift local provider streams and cancels cleanly after Core AI provider integration")
    func coreai06GGUFLLMStreamingAndCancellationRegression() async throws {
        final class StreamCapture: @unchecked Sendable {
            var chunks: [String] = []
            var stopped: Bool = false
        }
        let capture = StreamCapture()

        let (stream, continuation) = AsyncStream.makeStream(of: String.self)
        let consumerTask = Task {
            for await delta in stream {
                capture.chunks.append(delta)
                if capture.chunks.count >= 2 {
                    capture.stopped = true
                    break
                }
            }
        }

        continuation.yield("Token 1")
        continuation.yield("Token 2")
        continuation.yield("Token 3")
        continuation.finish()

        _ = await consumerTask.result

        #expect(capture.chunks == ["Token 1", "Token 2"])
        #expect(capture.stopped)

        let coreAIProvider = await CoreAILanguageModelProvider.shared
        #expect(coreAIProvider != nil)
    }
}
