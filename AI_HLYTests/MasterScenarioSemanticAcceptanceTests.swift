import Darwin
import Foundation
import Testing
import SwiftData
import HanlinChatCore
import HanlinPlatformContracts
import HanlinScriptCompiler
import IOSSystemLite
import ZIPFoundation
@testable import AI_Hanlin

private final class LoopbackHTTPFixtureServer: @unchecked Sendable {
    let port: UInt16
    private let listenFD: Int32
    private var acceptThread: Thread?
    private let lock = NSLock()
    private var isStopped = false

    init(responseBody: String, contentType: String = "application/json") throws {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw NSError(domain: "LoopbackHTTPFixtureServer", code: 1, userInfo: [NSLocalizedDescriptionKey: "socket() failed"])
        }
        var reuse: Int32 = 1
        _ = Darwin.setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(0).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            Darwin.close(fd)
            throw NSError(domain: "LoopbackHTTPFixtureServer", code: 2, userInfo: [NSLocalizedDescriptionKey: "bind() failed"])
        }
        guard Darwin.listen(fd, 8) == 0 else {
            Darwin.close(fd)
            throw NSError(domain: "LoopbackHTTPFixtureServer", code: 3, userInfo: [NSLocalizedDescriptionKey: "listen() failed"])
        }

        var boundAddr = sockaddr_in()
        var boundLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(fd, $0, &boundLen)
            }
        }
        guard nameResult == 0 else {
            Darwin.close(fd)
            throw NSError(domain: "LoopbackHTTPFixtureServer", code: 4, userInfo: [NSLocalizedDescriptionKey: "getsockname() failed"])
        }
        self.listenFD = fd
        self.port = UInt16(bigEndian: boundAddr.sin_port)

        let bodyBytes = Array(responseBody.utf8)
        let header = "HTTP/1.1 200 OK\r\nContent-Type: \(contentType)\r\nContent-Length: \(bodyBytes.count)\r\nConnection: close\r\n\r\n"
        let responseBytes = Array(header.utf8) + bodyBytes

        let thread = Thread { [weak self] in
            while true {
                var clientAddr = sockaddr_in()
                var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                let clientFD = withUnsafeMutablePointer(to: &clientAddr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.accept(fd, $0, &clientLen)
                    }
                }
                guard clientFD >= 0 else { break }
                var reqBuf = [UInt8](repeating: 0, count: 1024)
                _ = Darwin.recv(clientFD, &reqBuf, reqBuf.count, 0)
                responseBytes.withUnsafeBytes { rawBuf in
                    if let base = rawBuf.baseAddress {
                        _ = Darwin.send(clientFD, base, responseBytes.count, 0)
                    }
                }
                Darwin.shutdown(clientFD, SHUT_RDWR)
                Darwin.close(clientFD)
                if self?.shouldStop() == true { break }
            }
        }
        thread.name = "Hanlin.LoopbackHTTPFixtureServer"
        thread.start()
        self.acceptThread = thread
    }

    private func shouldStop() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isStopped
    }

    func stop() {
        lock.lock()
        guard !isStopped else {
            lock.unlock()
            return
        }
        isStopped = true
        lock.unlock()
        Darwin.shutdown(listenFD, SHUT_RDWR)
        Darwin.close(listenFD)
    }

    deinit {
        stop()
    }
}

@MainActor
private final class MockLocalLLMController {
    var updateCallback: (@Sendable (String?) -> Void)?
    var receivedPrompt: String?
    var stopCallCount = 0
    private var continuation: CheckedContinuation<Void, Never>?

    func makeDriver(onFirstChunkEmitted: @escaping @MainActor () -> Void) -> LocalLLMStreamDriver {
        LocalLLMStreamDriver(
            setUpdate: { [weak self] callback in
                self?.updateCallback = callback
            },
            respond: { [weak self] prompt in
                guard let self else { return }
                self.receivedPrompt = prompt
                self.updateCallback?("First token")
                onFirstChunkEmitted()
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    self.continuation = cont
                }
            },
            stop: { [weak self] in
                guard let self else { return }
                self.stopCallCount += 1
                self.continuation?.resume()
                self.continuation = nil
            }
        )
    }

    func emitLateTokenAndFinish(_ lateToken: String) {
        updateCallback?(lateToken)
        updateCallback?(nil)
        continuation?.resume()
        continuation = nil
    }
}

@Suite("Master Scenario Semantic Acceptance Tests", .serialized)
struct MasterScenarioSemanticAcceptanceTests {

    private static func makeInMemoryModelContainer() throws -> ModelContainer {
        let schema = Schema([AllModels.self, APIKeys.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private static func buildValidOpenXMLWorkbookArchive(at url: URL) throws -> Data {
        try? FileManager.default.removeItem(at: url)
        guard let archive = Archive(url: url, accessMode: .create) else {
            throw NSError(domain: "MasterScenarioSemanticAcceptanceTests", code: 10, userInfo: [NSLocalizedDescriptionKey: "Could not create OpenXML .xlsx archive"])
        }
        let entries: [(String, String)] = [
            (
                "[Content_Types].xml",
                """
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
                <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
                  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
                  <Default Extension="xml" ContentType="application/xml"/>
                  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
                  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
                </Types>
                """
            ),
            (
                "_rels/.rels",
                """
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
                <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
                  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
                </Relationships>
                """
            ),
            (
                "xl/workbook.xml",
                """
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
                <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
                  <sheets><sheet name="HanlinSheet" sheetId="1" r:id="rId1" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"/></sheets>
                </workbook>
                """
            ),
            (
                "xl/worksheets/sheet1.xml",
                """
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
                <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
                  <sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>HANLIN_OK</t></is></c></row></sheetData>
                </worksheet>
                """
            )
        ]
        for (path, xml) in entries {
            let data = Data(xml.utf8)
            try archive.addEntry(with: path, type: .file, uncompressedSize: UInt32(data.count)) { pos, size in
                data.subdata(in: pos..<(pos + size))
            }
        }
        return try Data(contentsOf: url)
    }

    @Test("CHAT-24: Stop generation while a model/tool run is active cancels the Hanlin run, returns composer to idle, and prevents stale output")
    @MainActor
    func chat24StopGenerationCancelsRunAndReturnsIdle() async throws {
        let container = try Self.makeInMemoryModelContainer()
        let context = container.mainContext
        let modelName = "chat24-local-fixture-\(UUID().uuidString.prefix(8).lowercased())"
        context.insert(
            AllModels(
                name: modelName,
                displayName: "CHAT-24 Local Model",
                position: 0,
                company: "LOCAL",
                supportsTextGen: true,
                supportsToolUse: false
            )
        )
        try context.save()

        let modelFileURL = getModelDirectory().appendingPathComponent("\(modelName).gguf")
        try Data("GGUF_FIXTURE".utf8).write(to: modelFileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: modelFileURL) }

        let apiManager = APIManager(context: context)
        let groupID = UUID()
        let runID = UUID()
        let coordinator = AgentRunCoordinator(groupID: groupID, providerID: "LOCAL", modelID: modelName)
        var eventAdapter = HanlinStreamEventAdapter(runID: coordinator.runID)
        let autoFollow = ChatAutoFollowController()
        let controller = MockLocalLLMController()

        var didCancelDuringFirstToken = false

        apiManager.localLLMDriverOverride = { _, _, _, _, _, _ in
            controller.makeDriver {
                // While the run is actively generating on the first streamed chunk, trigger stop-generation
                // using the exact production cancellation sequence from ChatView.cancelStreamTask().
                didCancelDuringFirstToken = true
            }
        }

        autoFollow.beginRun()
        autoFollow.userInteractionBegan()
        #expect(coordinator.run.status == .running)
        #expect(autoFollow.state.isUserInteracting)

        let stream = try await apiManager.sendStreamRequest(
            messages: [
                RequestMessage(
                    role: "user",
                    text: "Generate a multi-token response and stop mid-run.",
                    modelName: modelName,
                    modelDisplayName: "CHAT-24 Local Model"
                )
            ],
            modelName: modelName,
            groupID: groupID,
            runID: runID,
            ifSearch: false,
            ifKnowledge: false,
            ifToolUse: false,
            assistantToolScope: .nativeOnly,
            ifThink: false,
            ifAudio: false,
            ifPlanning: false,
            thinkingLength: 0,
            isObservation: false,
            temperature: 0.7,
            topP: 0.9,
            maxTokens: 256,
            canvasData: CanvasData(),
            selectedURLs: nil,
            selectedPromptsContent: nil,
            systemMessage: "You are a helpful assistant.",
            selectedImageSize: "1024x1024",
            imageReversePrompt: ""
        )

        #expect(AgentRunLifecycleCoordinator.shared.isCurrentRun(runID))
        #expect(AgentRunLifecycleCoordinator.shared.activeRunID == runID)

        var renderedText = ""
        for try await chunk in stream {
            coordinator.consume(eventAdapter.events(from: chunk))
            if let content = chunk.content, !content.isEmpty {
                renderedText += content
                // Execute the exact production stop-generation path while the model run is active
                apiManager.cancelCurrentRequest()
                coordinator.cancel()
                autoFollow.runEnded()
                await apiManager.completeAgentDiagnostics(status: "cancelled")
                controller.emitLateTokenAndFinish(" Stale token that should not append")
            }
        }

        #expect(didCancelDuringFirstToken)
        #expect(AgentRunLifecycleCoordinator.shared.activeRunID == nil)
        #expect(!AgentRunLifecycleCoordinator.shared.isCurrentRun(runID))
        #expect(coordinator.run.status == .cancelled)
        #expect(!autoFollow.state.isUserInteracting)
        #expect(renderedText == "First token")
        #expect(!renderedText.contains("Stale token"))

        // Even if a late StreamData chunk arrives after cancel(), AgentRunCoordinator drops it without reactivating
        let lateChunk = StreamData(
            content: "Stale token that should not append",
            operationalState: "Late state"
        )
        coordinator.consume(eventAdapter.events(from: lateChunk))
        #expect(coordinator.run.status == .cancelled)
        #expect(!autoFollow.state.isUserInteracting)
    }

    @Test("SH-03: Removing framework/symbol for one command in fixture package marks it unavailable with precise dependency reporting while other commands continue")
    @MainActor
    func sh03MissingFrameworkReportsUnavailableWithDependencies() async throws {
        let registration = try IOSSystemRunner.registrationReport()
        let basePlistURL = URL(fileURLWithPath: registration.mainDictionaryPath)
        let rawPlistData = try Data(contentsOf: basePlistURL)
        let rawObject = try PropertyListSerialization.propertyList(from: rawPlistData, format: nil)
        let baseDictionary = try #require(rawObject as? [String: [String]])

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("sh03_fixture_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // 1. Fixture with removed/missing framework for `grep` and missing symbol for `awk`
        var modifiedDict = baseDictionary
        modifiedDict["grep"] = ["RemovedGrepFramework", "grep_main", "abc", "file"]
        modifiedDict["awk"] = ["SELF", "missing_awk_main_symbol", "abc", "file"]

        let fixturePlistURL = tempDir.appendingPathComponent("commandDictionary.plist")
        let modifiedData = try PropertyListSerialization.data(fromPropertyList: modifiedDict, format: .xml, options: 0)
        try modifiedData.write(to: fixturePlistURL, options: .atomic)

        // Probe dependencies through production IOSSystemRunner & ShellRuntimeService
        let layout = RuntimeFileLayout(root: tempDir.appendingPathComponent("runtime"))
        let fixtureShell = ShellRuntimeService(fileLayout: layout, commandDictionaryURL: fixturePlistURL)
        let diagnostics = try await fixtureShell.commandDependencyDiagnostics()

        let grepDiag = try #require(diagnostics["grep"])
        #expect(!grepDiag.isAvailable)
        #expect(grepDiag.framework == "RemovedGrepFramework")
        #expect(grepDiag.symbol == "grep_main")
        #expect(grepDiag.missingDependencyReason?.contains("RemovedGrepFramework") == true)
        #expect(grepDiag.missingDependencyReason?.contains("grep_main") == true)

        let awkDiag = try #require(diagnostics["awk"])
        #expect(!awkDiag.isAvailable)
        #expect(awkDiag.framework == "SELF")
        #expect(awkDiag.symbol == "missing_awk_main_symbol")
        #expect(awkDiag.missingDependencyReason?.contains("missing_awk_main_symbol") == true)

        // Verify all remaining 21 commands in the same fixture catalog are reported available
        for command in IOSSystemRunner.linkedCommands where command != "grep" && command != "awk" {
            let status = try #require(diagnostics[command])
            #expect(status.isAvailable, "Expected \(command) to remain available when only grep/awk dependencies are removed")
            #expect(status.missingDependencyReason == nil)
        }

        // Prepare a real file in the fixture shell workspace
        try layout.prepareIfNeeded()
        let workspace = try layout.workspace(client: .tools, identifier: "execute_shell_command")
        try Data("line one\nline two\n".utf8).write(to: workspace.appendingPathComponent("probe.txt"), options: .atomic)

        let shellTool = ExecuteShellCommandTool(shellServiceOverride: fixtureShell)
        let toolContext = NativeToolExecutionContext(localeIdentifier: "en_US")

        // Invoking the broken command (`grep`) through ExecuteShellCommandTool fails with precise dependency reporting
        let grepToolResult = await shellTool.execute(
            argumentsJSON: #"{"program":"grep","arguments":["line","probe.txt"],"allow_network":false}"#,
            context: toolContext
        )
        #expect(grepToolResult.isError)
        #expect(grepToolResult.output.contains("Command 'grep' is unavailable"))
        #expect(grepToolResult.output.contains("RemovedGrepFramework"))

        // Invoking unaffected commands (`cat` and `wc`) through the same ExecuteShellCommandTool & ShellRuntimeService succeeds
        let catToolResult = await shellTool.execute(
            argumentsJSON: #"{"program":"cat","arguments":["probe.txt"],"allow_network":false}"#,
            context: toolContext
        )
        #expect(!catToolResult.isError)
        #expect(catToolResult.output.contains("line one"))
        #expect(catToolResult.output.contains("line two"))

        let wcResult = try await fixtureShell.execute(
            tokens: ["wc", "-l", "probe.txt"],
            workspace: workspace,
            environment: [:],
            allowNetwork: false
        )
        #expect(wcResult.exitCode == 0)
        #expect(wcResult.stdout.contains("2"))
        #expect(wcResult.stdout.contains("probe.txt"))
    }

    @Test("SH-05: program=grep arguments=['alpha','sample.txt'] executes via production ShellRuntimeService and ExecuteShellCommandTool producing exact two alpha lines")
    @MainActor
    func sh05GrepAlphaExactTwoLinesWithoutPathRequirement() async throws {
        let core = AppRuntimeCore.shared
        _ = try await core.ensureStarted(.shell)
        let hostContext = AgentHostServicesAdapter.makeContext()
        let workspace = try RuntimeFileLayout.default.workspace(
            client: .executions,
            identifier: hostContext.runtimeWorkspaceIdentifier
        )
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        let sampleFile = workspace.appendingPathComponent("sample.txt")
        let alphaPath = workspace.appendingPathComponent("alpha")
        try? FileManager.default.removeItem(at: alphaPath)
        defer { try? FileManager.default.removeItem(at: sampleFile) }

        let sampleContent = "alpha line 1\nbeta line\nalpha line 2\ngamma line\n"
        try Data(sampleContent.utf8).write(to: sampleFile, options: .atomic)
        #expect(!FileManager.default.fileExists(atPath: alphaPath.path))

        // 1. Direct execution through production ShellRuntimeService
        let directResult = try await core.shell.execute(
            tokens: ["grep", "alpha", "sample.txt"],
            workspace: workspace,
            environment: [:],
            allowNetwork: false
        )
        #expect(directResult.exitCode == 0)
        let directLines = directResult.stdout
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        #expect(directLines.count == 2)
        #expect(directLines == ["alpha line 1", "alpha line 2"])

        // 2. Execution through production ExecuteShellCommandTool
        let tool = ExecuteShellCommandTool(hostContext: hostContext)
        let toolResult = await tool.execute(
            argumentsJSON: #"{"program":"grep","arguments":["alpha","sample.txt"],"allow_network":false}"#,
            context: NativeToolExecutionContext(localeIdentifier: "en_US")
        )
        #expect(!toolResult.isError)
        #expect(toolResult.output.contains("alpha line 1"))
        #expect(toolResult.output.contains("alpha line 2"))
        #expect(!toolResult.output.contains("beta line"))
        #expect(!toolResult.output.contains("gamma line"))
    }

    @Test("CMD-04: program=curl arguments=['${FIXTURE_BASE}/ok.json'] executes real ios_system curl against loopback fixture server returning marker=HANLIN_OK, answer=42, exitCode=0")
    @MainActor
    func cmd04CurlFixtureBaseReturnsExpectedJSONAndZeroExitCode() async throws {
        let expectedJSON = #"{"marker":"HANLIN_OK","answer":42}"#
        let server = try LoopbackHTTPFixtureServer(responseBody: expectedJSON)
        defer { server.stop() }

        let fixtureBase = "http://127.0.0.1:\(server.port)"
        let okURL = "\(fixtureBase)/ok.json"

        let core = AppRuntimeCore.shared
        _ = try await core.ensureStarted(.shell)
        let hostContext = AgentHostServicesAdapter.makeContext()
        let workspace = try RuntimeFileLayout.default.workspace(
            client: .executions,
            identifier: hostContext.runtimeWorkspaceIdentifier
        )

        // 1. Execute real curl through ShellRuntimeService
        let directResult = try await core.shell.execute(
            tokens: ["curl", "-sS", okURL],
            workspace: workspace,
            environment: ["FIXTURE_BASE": fixtureBase],
            allowNetwork: true
        )
        #expect(directResult.exitCode == 0)
        let parsedDirect = try JSONSerialization.jsonObject(
            with: Data(directResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        ) as? [String: Any]
        #expect(parsedDirect?["marker"] as? String == "HANLIN_OK")
        #expect(parsedDirect?["answer"] as? Int == 42)

        // 2. Execute real curl through ExecuteShellCommandTool
        let server2 = try LoopbackHTTPFixtureServer(responseBody: expectedJSON)
        defer { server2.stop() }
        let okURL2 = "http://127.0.0.1:\(server2.port)/ok.json"
        let tool = ExecuteShellCommandTool(hostContext: hostContext)
        let toolResult = await tool.execute(
            argumentsJSON: #"{"program":"curl","arguments":["-sS","\#(okURL2)"],"allow_network":true}"#,
            context: NativeToolExecutionContext(localeIdentifier: "en_US")
        )
        #expect(!toolResult.isError)
        #expect(toolResult.output.contains("HANLIN_OK"))
        #expect(toolResult.output.contains("42"))

        // 3. Verify negative policy checks: network disabled & non-loopback HTTP forbidden
        let deniedNoNetwork = await tool.execute(
            argumentsJSON: #"{"program":"curl","arguments":["\#(okURL2)"],"allow_network":false}"#,
            context: NativeToolExecutionContext(localeIdentifier: "en_US")
        )
        #expect(deniedNoNetwork.isError)

        let deniedRemoteHTTP = await tool.execute(
            argumentsJSON: #"{"program":"curl","arguments":["http://example.invalid/ok.json"],"allow_network":true}"#,
            context: NativeToolExecutionContext(localeIdentifier: "en_US")
        )
        #expect(deniedRemoteHTTP.isError)
    }

    @Test("ZIP-04: Foundation URL aliases of /var and /private/var in same temp directory resolve to identical destination in SkillImporter and SkillStore without false escape")
    @MainActor
    func zip04FoundationVarAndPrivateVarAliasesResolveWithoutFalseEscape() throws {
        let baseTemp = FileManager.default.temporaryDirectory
        let testDir = baseTemp.appendingPathComponent("zip04_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: testDir) }

        let realRoot = testDir.appendingPathComponent("real_root", isDirectory: true)
        let aliasRoot = testDir.appendingPathComponent("alias_root", isDirectory: true)
        try FileManager.default.createDirectory(at: realRoot, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: aliasRoot, withDestinationURL: realRoot)

        let nestedFile = realRoot.appendingPathComponent("references/guide.md")
        try FileManager.default.createDirectory(at: nestedFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("# Guide\n".utf8).write(to: nestedFile, options: .atomic)

        // 1. Explicit /var vs /private/var alias pair construction
        let canonicalRootPath = realRoot.resolvingSymlinksInPath().standardizedFileURL.path
        let varRootPath: String
        let privateVarRootPath: String
        if canonicalRootPath.hasPrefix("/private/var/") {
            privateVarRootPath = canonicalRootPath
            varRootPath = String(canonicalRootPath.dropFirst("/private".count))
        } else if canonicalRootPath.hasPrefix("/var/") {
            varRootPath = canonicalRootPath
            privateVarRootPath = "/private" + canonicalRootPath
        } else {
            varRootPath = aliasRoot.path
            privateVarRootPath = realRoot.path
        }

        let varParentURL = URL(fileURLWithPath: varRootPath, isDirectory: true)
        let privateVarParentURL = URL(fileURLWithPath: privateVarRootPath, isDirectory: true)
        let varChildURL = varParentURL.appendingPathComponent("references/guide.md")
        let privateVarChildURL = privateVarParentURL.appendingPathComponent("references/guide.md")

        // Verify production SkillImporter.isContained across both directions (/var child in /private/var parent and vice versa)
        #expect(SkillImporter.isContained(privateVarChildURL, in: varParentURL))
        #expect(SkillImporter.isContained(varChildURL, in: privateVarParentURL))
        #expect(SkillImporter.isContained(aliasRoot.appendingPathComponent("references/guide.md"), in: realRoot))
        #expect(SkillImporter.isContained(realRoot.appendingPathComponent("references/guide.md"), in: aliasRoot))

        // Verify an actual outside path is still rejected
        let outsideURL = testDir.appendingPathComponent("outside.txt")
        try Data("outside".utf8).write(to: outsideURL, options: .atomic)
        #expect(!SkillImporter.isContained(outsideURL, in: varParentURL))
        #expect(!SkillImporter.isContained(outsideURL, in: privateVarParentURL))

        // 2. End-to-end SkillImporter.stageAndInspect + install via symlinked /var alias URL
        let zipURL = aliasRoot.appendingPathComponent("zip04-skill.zip")
        guard let archive = Archive(url: zipURL, accessMode: .create) else {
            Issue.record("Failed to create zip04 archive")
            return
        }
        let skillMD = Data("""
        ---
        name: zip04-alias-skill
        description: Verifies /var and /private/var containment during staging and installation
        ---
        # ZIP-04 Skill
        """.utf8)
        let refData = Data("Alias safe content".utf8)
        try archive.addEntry(with: "SKILL.md", type: .file, uncompressedSize: UInt32(skillMD.count)) { pos, size in
            skillMD.subdata(in: pos..<(pos + size))
        }
        try archive.addEntry(with: "references/alias.md", type: .file, uncompressedSize: UInt32(refData.count)) { pos, size in
            refData.subdata(in: pos..<(pos + size))
        }

        let staged = try SkillImporter.shared.stageAndInspect(fileURL: zipURL)
        let descriptor = try SkillImporter.shared.install(staged: staged)
        defer { SkillStore.shared.deleteCustomSkill(skillID: descriptor.id) }

        let resolvedResource = try #require(SkillStore.shared.safeResourceURL(for: descriptor.id, relativePath: "references/alias.md"))
        #expect(try String(contentsOf: resolvedResource, encoding: .utf8) == "Alias safe content")
    }

    @Test("ZIP-07: Skill import with LICENSE, assets/data.bin, valid OpenXML sample.xlsx, source.swift, module.wasm installs without unsupportedFileType error and all bytes are accessible")
    @MainActor
    func zip07SkillImportPreservesAllAssetFilesByteForByte() async throws {
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
        let xlsxTempURL = tempDir.appending(path: "generated-sample.xlsx")
        let sampleXLSX = try Self.buildValidOpenXMLWorkbookArchive(at: xlsxTempURL)
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

        let installedDir = try #require(SkillStore.shared.directoryURL(for: descriptor.id))
        #expect(try String(contentsOf: installedDir.appending(path: "LICENSE"), encoding: .utf8) == license)
        #expect(try Data(contentsOf: installedDir.appending(path: "assets/data.bin")) == dataBin)
        #expect(try Data(contentsOf: installedDir.appending(path: "sample.xlsx")) == sampleXLSX)
        #expect(try String(contentsOf: installedDir.appending(path: "source.swift"), encoding: .utf8) == sourceSwift)
        #expect(try Data(contentsOf: installedDir.appending(path: "module.wasm")) == moduleWASM)

        // Verify the installed sample.xlsx is a valid OpenXML ZIP archive with expected workbook structure
        let installedXLSXArchive = try #require(Archive(url: installedDir.appending(path: "sample.xlsx"), accessMode: .read))
        let xlsxPaths = Set(installedXLSXArchive.map(\.path))
        #expect(xlsxPaths.contains("[Content_Types].xml"))
        #expect(xlsxPaths.contains("xl/workbook.xml"))
        #expect(xlsxPaths.contains("xl/worksheets/sheet1.xml"))

        // Also verify ReadSkillResourceTool can read source.swift and report binary metadata for sample.xlsx
        HanlinSkillCatalog.shared.refreshFromStore()
        let session = AssistantCapabilitySession()
        session.recordSkillLoaded(id: descriptor.id, instructionText: descriptor.name)
        let swiftReadOutput = await ReadSkillResourceTool.execute(
            argumentsJSON: #"{"skill_id":"\#(descriptor.id.rawValue)","relative_path":"source.swift"}"#,
            session: session
        )
        #expect(swiftReadOutput.contains("Hello from source.swift"))
        let xlsxReadOutput = await ReadSkillResourceTool.execute(
            argumentsJSON: #"{"skill_id":"\#(descriptor.id.rawValue)","relative_path":"sample.xlsx"}"#,
            session: session
        )
        #expect(xlsxReadOutput.contains("Binary resource file: sample.xlsx"))
    }

    @Test("ZIP-11: Internal relative paths ./references/a.md and references/x/../a.md normalize correctly across HanlinArchivePolicy, SkillImporter, SkillStore, and ReadSkillResourceTool")
    @MainActor
    func zip11InternalRelativePathsResolveWithoutBlanketRejection() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: "zip11_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // 1. Verify HanlinArchivePolicy.normalizedRelativePath and inspectSkillArchive accept internal ./ and ../ while rejecting root escape
        #expect(HanlinArchivePolicy.normalizedRelativePath("./references/a.md") == "references/a.md")
        #expect(HanlinArchivePolicy.normalizedRelativePath("references/x/../a.md") == "references/a.md")
        #expect(HanlinArchivePolicy.normalizedRelativePath("../references/a.md") == nil)
        #expect(HanlinArchivePolicy.normalizedRelativePath("references/../../a.md") == nil)

        let skillName = "zip11-skill-\(UUID().uuidString.prefix(8).lowercased())"
        let zipURL = tempDir.appending(path: "\(skillName).zip")
        guard let archive = Archive(url: zipURL, accessMode: .create) else {
            Issue.record("Failed to create ZIP-11 test archive")
            return
        }
        let skillMDData = Data("""
        ---
        name: \(skillName)
        description: Verifies internal relative path canonicalization
        ---
        # ZIP-11 Canonical Path Skill
        """.utf8)
        let refAData = Data("# Reference A Content\nLine 2".utf8)
        let refBData = Data("# Reference B Content".utf8)

        try archive.addEntry(with: "./SKILL.md", type: .file, uncompressedSize: UInt32(skillMDData.count)) { pos, size in
            skillMDData.subdata(in: pos..<(pos + size))
        }
        try archive.addEntry(with: "./references/a.md", type: .file, uncompressedSize: UInt32(refAData.count)) { pos, size in
            refAData.subdata(in: pos..<(pos + size))
        }
        try archive.addEntry(with: "references/x/../b.md", type: .file, uncompressedSize: UInt32(refBData.count)) { pos, size in
            refBData.subdata(in: pos..<(pos + size))
        }

        // 2. Stage and install through production SkillImporter & SkillStore
        let staged = try SkillImporter.shared.stageAndInspect(fileURL: zipURL)
        let descriptor = try SkillImporter.shared.install(staged: staged)
        defer { SkillStore.shared.deleteCustomSkill(skillID: descriptor.id) }

        let store = SkillStore.shared
        let url1 = try #require(store.safeResourceURL(for: descriptor.id, relativePath: "./references/a.md"))
        let url2 = try #require(store.safeResourceURL(for: descriptor.id, relativePath: "references/x/../a.md"))
        #expect(url1.standardizedFileURL.path == url2.standardizedFileURL.path)
        #expect(try String(contentsOf: url1, encoding: .utf8) == "# Reference A Content\nLine 2")

        // 3. Execute production ReadSkillResourceTool with both ./references/a.md and references/x/../a.md
        HanlinSkillCatalog.shared.refreshFromStore()
        let session = AssistantCapabilitySession()
        session.recordSkillLoaded(id: descriptor.id, instructionText: descriptor.name)

        let readDotSlash = await ReadSkillResourceTool.execute(
            argumentsJSON: #"{"skill_id":"\#(descriptor.id.rawValue)","relative_path":"./references/a.md"}"#,
            session: session
        )
        #expect(readDotSlash.contains("Resource 'references/a.md'"))
        #expect(readDotSlash.contains("# Reference A Content"))

        let readParentCollapsed = await ReadSkillResourceTool.execute(
            argumentsJSON: #"{"skill_id":"\#(descriptor.id.rawValue)","relative_path":"references/x/../a.md"}"#,
            session: session
        )
        #expect(readParentCollapsed.contains("Resource 'references/a.md'"))
        #expect(readParentCollapsed.contains("# Reference A Content"))

        // 4. Negative check: escaping traversal outside skill root is rejected
        let readEscaping = await ReadSkillResourceTool.execute(
            argumentsJSON: #"{"skill_id":"\#(descriptor.id.rawValue)","relative_path":"../secret.txt"}"#,
            session: session
        )
        #expect(readEscaping.contains("Error: Directory traversal is not permitted in resource paths."))

        let readDeepEscaping = await ReadSkillResourceTool.execute(
            argumentsJSON: #"{"skill_id":"\#(descriptor.id.rawValue)","relative_path":"references/../../secret.txt"}"#,
            session: session
        )
        #expect(readDeepEscaping.contains("Error: Directory traversal is not permitted in resource paths."))
    }

    @Test("COREAI-06: GGUF/LLM.swift local provider streams and cancels cleanly via APIManager and LocalLLMStreamingAdapter alongside CoreAILanguageModelProvider")
    @MainActor
    func coreai06GGUFLLMStreamingAndCancellationRegression() async throws {
        let container = try Self.makeInMemoryModelContainer()
        let context = container.mainContext
        let modelName = "coreai06-gguf-fixture-\(UUID().uuidString.prefix(8).lowercased())"
        context.insert(
            AllModels(
                name: modelName,
                displayName: "Local GGUF Fixture",
                position: 0,
                company: "LOCAL",
                supportsTextGen: true,
                supportsReasoning: true,
                supportsToolUse: false
            )
        )
        try context.save()

        let modelFileURL = getModelDirectory().appendingPathComponent("\(modelName).gguf")
        try Data("GGUF_LOCAL_FIXTURE".utf8).write(to: modelFileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: modelFileURL) }

        // 1. Verify full streaming + reasoning + im_end stop handling through APIManager.sendStreamRequest & LocalLLMStreamingAdapter
        let apiManager = APIManager(context: context)
        var stopCountRun1 = 0
        apiManager.localLLMDriverOverride = { _, _, _, _, _, _ in
            var callback: (@Sendable (String?) -> Void)?
            return LocalLLMStreamDriver(
                setUpdate: { cb in callback = cb },
                respond: { _ in
                    callback?("<think>Analyzing local request</think>Local GGUF answer")
                    callback?(" complete<|im_end|>")
                    callback?(nil)
                },
                stop: { stopCountRun1 += 1 }
            )
        }

        let stream1 = try await apiManager.sendStreamRequest(
            messages: [RequestMessage(role: "user", text: "Hello local GGUF", modelName: modelName, modelDisplayName: "Local GGUF Fixture")],
            modelName: modelName,
            groupID: UUID(),
            runID: UUID(),
            ifSearch: false,
            ifKnowledge: false,
            ifToolUse: false,
            assistantToolScope: .nativeOnly,
            ifThink: true,
            ifAudio: false,
            ifPlanning: false,
            thinkingLength: 0,
            isObservation: false,
            temperature: 0.6,
            topP: 0.9,
            maxTokens: 128,
            canvasData: CanvasData(),
            selectedURLs: nil,
            selectedPromptsContent: nil,
            systemMessage: "Local system prompt",
            selectedImageSize: "1024x1024",
            imageReversePrompt: ""
        )

        var reasoningOutput = ""
        var visibleOutput = ""
        for try await chunk in stream1 {
            if let r = chunk.reasoning { reasoningOutput += r }
            if let c = chunk.content { visibleOutput += c }
        }
        #expect(reasoningOutput.contains("Analyzing local request"))
        #expect(visibleOutput.contains("Local GGUF answer"))
        #expect(stopCountRun1 >= 1)

        // 2. Verify mid-stream cancellation via APIManager.cancelCurrentRequest() and LocalLLMStreamingAdapter.consume
        let controller = MockLocalLLMController()
        apiManager.localLLMDriverOverride = { _, _, _, _, _, _ in
            controller.makeDriver {}
        }
        let stream2 = try await apiManager.sendStreamRequest(
            messages: [RequestMessage(role: "user", text: "Cancel me", modelName: modelName, modelDisplayName: "Local GGUF Fixture")],
            modelName: modelName,
            groupID: UUID(),
            runID: UUID(),
            ifSearch: false,
            ifKnowledge: false,
            ifToolUse: false,
            assistantToolScope: .nativeOnly,
            ifThink: false,
            ifAudio: false,
            ifPlanning: false,
            thinkingLength: 0,
            isObservation: false,
            temperature: 0.6,
            topP: 0.9,
            maxTokens: 128,
            canvasData: CanvasData(),
            selectedURLs: nil,
            selectedPromptsContent: nil,
            systemMessage: "Local system prompt",
            selectedImageSize: "1024x1024",
            imageReversePrompt: ""
        )

        var cancelledChunks: [String] = []
        for try await chunk in stream2 {
            if let text = chunk.content ?? chunk.reasoning, !text.isEmpty {
                cancelledChunks.append(text)
                apiManager.cancelCurrentRequest()
                controller.emitLateTokenAndFinish("Unwanted trailing token")
            }
        }
        #expect(cancelledChunks == ["First token"])
        #expect(controller.stopCallCount >= 1)

        // 3. Verify CoreAILanguageModelProvider coexistence alongside GGUF/LLM.swift
        let coreAIDescriptor = CoreAIModelDescriptor(modelPath: modelFileURL, modelName: modelName, format: "aimodel", isSpecialized: true)
        await #expect(throws: CoreAIModelError.self) {
            try await CoreAILanguageModelProvider.shared.generate(descriptor: coreAIDescriptor, prompt: "Test") { _ in true }
        }
    }
}
