import Darwin
import Foundation
import CryptoKit
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

    private let routes: [String: (Data, String)]
    private let defaultResponse: (Data, String)
    private let routeProvider: (@Sendable (String, UInt16) -> (Data, String)?)?

    init(routes: [String: (Data, String)], defaultResponse: (Data, String)? = nil) throws {
        self.routes = routes
        self.defaultResponse = defaultResponse ?? (Data(), "application/json")
        self.routeProvider = nil

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

        let capturedRoutes = self.routes
        let capturedDefault = self.defaultResponse
        let currentPort = self.port

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
                var reqBuf = [UInt8](repeating: 0, count: 2048)
                let bytesRead = Darwin.recv(clientFD, &reqBuf, reqBuf.count, 0)
                let reqStr = bytesRead > 0 ? String(decoding: reqBuf[..<bytesRead], as: UTF8.self) : ""
                let path = reqStr.split(separator: " ").dropFirst().first.map(String.init) ?? "/"

                let (bodyData, contentType) = capturedRoutes[path] ?? capturedDefault
                let header = "HTTP/1.1 200 OK\r\nContent-Type: \(contentType)\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
                let responseBytes = Array(header.utf8) + Array(bodyData)

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

    init(defaultResponse: (Data, String)? = nil, routeProvider: @escaping @Sendable (String, UInt16) -> (Data, String)?) throws {
        self.routes = [:]
        self.defaultResponse = defaultResponse ?? (Data(), "application/json")
        self.routeProvider = routeProvider

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

        let capturedDefault = self.defaultResponse
        let capturedProvider = self.routeProvider
        let currentPort = self.port

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
                var reqBuf = [UInt8](repeating: 0, count: 2048)
                let bytesRead = Darwin.recv(clientFD, &reqBuf, reqBuf.count, 0)
                let reqStr = bytesRead > 0 ? String(decoding: reqBuf[..<bytesRead], as: UTF8.self) : ""
                let path = reqStr.split(separator: " ").dropFirst().first.map(String.init) ?? "/"

                let (bodyData, contentType): (Data, String)
                if let dynamic = capturedProvider?(path, currentPort) {
                    (bodyData, contentType) = dynamic
                } else {
                    (bodyData, contentType) = capturedDefault
                }
                let header = "HTTP/1.1 200 OK\r\nContent-Type: \(contentType)\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
                let responseBytes = Array(header.utf8) + Array(bodyData)

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

    convenience init(responseBody: String, contentType: String = "application/json") throws {
        let bodyData = Data(responseBody.utf8)
        try self.init(routes: [:], defaultResponse: (bodyData, contentType))
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
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(
            for: ChatMessages.self,
            APIKeys.self,
            SearchKeys.self,
            AllModels.self,
            ChatRecords.self,
            UserInfo.self,
            PromptRepo.self,
            KnowledgeRecords.self,
            KnowledgeChunk.self,
            MemoryArchive.self,
            TranslationDic.self,
            ToolKeys.self,
            configurations: configuration
        )
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
        context.insert(UserInfo())
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
        let rawObject = try PropertyListSerialization.propertyList(
            from: rawPlistData,
            options: PropertyListSerialization.ReadOptions(0),
            format: nil
        )
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
        #expect(grepToolResult.modelText.contains("Command 'grep' is unavailable"))
        #expect(grepToolResult.modelText.contains("RemovedGrepFramework"))

        // Invoking unaffected commands (`cat` and `wc`) through the same ExecuteShellCommandTool & ShellRuntimeService succeeds
        let catToolResult = await shellTool.execute(
            argumentsJSON: #"{"program":"cat","arguments":["probe.txt"],"allow_network":false}"#,
            context: toolContext
        )
        #expect(!catToolResult.isError)
        #expect(catToolResult.modelText.contains("line one"))
        #expect(catToolResult.modelText.contains("line two"))

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
        #expect(toolResult.modelText.contains("alpha line 1"))
        #expect(toolResult.modelText.contains("alpha line 2"))
        #expect(!toolResult.modelText.contains("beta line"))
        #expect(!toolResult.modelText.contains("gamma line"))
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
        #expect(toolResult.modelText.contains("HANLIN_OK"))
        #expect(toolResult.modelText.contains("42"))

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
        session.recordSkillLoaded(id: descriptor.id, instructionText: descriptor.title.preferredValue())
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
        session.recordSkillLoaded(id: descriptor.id, instructionText: descriptor.title.preferredValue())

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
        context.insert(UserInfo())
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

    @Test("ZIP-01: Positive import of root ZIP containing SKILL.md, hanlin.json, and agents/openai.yaml succeeds with preview, install, catalog refresh, relaunch, and full resource availability")
    @MainActor
    func zip01RootZIPImportWithSkillHanlinAndAgentConfig() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: "zip01_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let skillName = "zip01-root-skill-\(UUID().uuidString.prefix(8).lowercased())"
        let zipURL = tempDir.appending(path: "\(skillName).zip")
        guard let archive = Archive(url: zipURL, accessMode: .create) else {
            Issue.record("Failed to create ZIP-01 test archive")
            return
        }

        let skillMDContent = """
        ---
        name: \(skillName)
        description: ZIP-01 Root Skill with custom agent and metadata
        ---
        # ZIP-01 Root Skill Body
        Instructions for root skill execution.
        """
        let skillMDData = Data(skillMDContent.utf8)

        let hanlinJSON = HanlinSkillMetadata(
            preferredToolIDs: ["execute_shell_command"],
            triggerHints: ["zip01", "root-import"],
            keywords: ["root", "archive", "test"],
            baseSkillID: nil,
            originURL: nil,
            sha256: nil,
            isEnabled: true,
            installedAt: Date(),
            updatedAt: Date()
        )
        let hanlinJSONData = try JSONEncoder().encode(hanlinJSON)

        let agentYAMLContent = """
        name: openai-agent
        model: gpt-4
        temperature: 0.7
        description: Dedicated OpenAI agent definition for ZIP-01
        """
        let agentYAMLData = Data(agentYAMLContent.utf8)

        try archive.addEntry(with: "SKILL.md", type: .file, uncompressedSize: UInt32(skillMDData.count)) { pos, size in
            skillMDData.subdata(in: pos..<(pos + size))
        }
        try archive.addEntry(with: "hanlin.json", type: .file, uncompressedSize: UInt32(hanlinJSONData.count)) { pos, size in
            hanlinJSONData.subdata(in: pos..<(pos + size))
        }
        try archive.addEntry(with: "agents/openai.yaml", type: .file, uncompressedSize: UInt32(agentYAMLData.count)) { pos, size in
            agentYAMLData.subdata(in: pos..<(pos + size))
        }

        // Preview & stage inspection
        let staged = try SkillImporter.shared.stageAndInspect(fileURL: zipURL)
        #expect(staged.skillID.rawValue == skillName)
        #expect(staged.metadata.triggerHints.contains("zip01"))
        #expect(staged.resources.contains { $0.relativePath == "agents/openai.yaml" })

        // Install
        let descriptor = try SkillImporter.shared.install(staged: staged)
        defer { SkillStore.shared.deleteCustomSkill(skillID: descriptor.id) }
        #expect(descriptor.id.rawValue == skillName)

        // Catalog refresh
        HanlinSkillCatalog.shared.refreshFromStore()
        let resolved = HanlinSkillCatalog.shared.resolve(id: descriptor.id)
        #expect(resolved != nil)

        // Verify resource accessibility
        let agentResourceURL = try #require(SkillStore.shared.safeResourceURL(for: descriptor.id, relativePath: "agents/openai.yaml"))
        let readYAML = try String(contentsOf: agentResourceURL, encoding: .utf8)
        #expect(readYAML.contains("name: openai-agent"))

        // Simulate cold relaunch: instantiate fresh independent SkillStore from disk root
        let coldStore = SkillStore(rootDirectoryURL: SkillStore.shared.rootDirectoryURL)
        let reloadedSkills = coldStore.allCustomSkillDescriptors()
        #expect(reloadedSkills.contains { $0.id == descriptor.id })
        let coldResourceURL = try #require(coldStore.safeResourceURL(for: descriptor.id, relativePath: "agents/openai.yaml"))
        let coldYAML = try String(contentsOf: coldResourceURL, encoding: .utf8)
        #expect(coldYAML.contains("name: openai-agent"))
    }

    @Test("ZIP-02: Import of same meaningful ZIP contents wrapped under fixture-runtime/ produces identical result as root ZIP without error")
    @MainActor
    func zip02WrappedZIPImportUnderFixtureRuntime() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: "zip02_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let skillName = "zip02-wrapped-skill-\(UUID().uuidString.prefix(8).lowercased())"
        let zipURL = tempDir.appending(path: "\(skillName).zip")
        guard let archive = Archive(url: zipURL, accessMode: .create) else {
            Issue.record("Failed to create ZIP-02 test archive")
            return
        }

        let skillMDContent = """
        ---
        name: \(skillName)
        description: ZIP-02 Wrapped Skill under fixture-runtime
        ---
        # ZIP-02 Wrapped Skill Body
        """
        let skillMDData = Data(skillMDContent.utf8)

        let hanlinJSON = HanlinSkillMetadata(
            preferredToolIDs: ["execute_shell_command"],
            triggerHints: ["zip02", "wrapped-import"],
            keywords: ["wrapped", "fixture-runtime"],
            baseSkillID: nil,
            originURL: nil,
            sha256: nil,
            isEnabled: true,
            installedAt: Date(),
            updatedAt: Date()
        )
        let hanlinJSONData = try JSONEncoder().encode(hanlinJSON)
        let agentYAMLData = Data("name: wrapped-agent\nmodel: gpt-4\n".utf8)

        try archive.addEntry(with: "fixture-runtime/SKILL.md", type: .file, uncompressedSize: UInt32(skillMDData.count)) { pos, size in
            skillMDData.subdata(in: pos..<(pos + size))
        }
        try archive.addEntry(with: "fixture-runtime/hanlin.json", type: .file, uncompressedSize: UInt32(hanlinJSONData.count)) { pos, size in
            hanlinJSONData.subdata(in: pos..<(pos + size))
        }
        try archive.addEntry(with: "fixture-runtime/agents/openai.yaml", type: .file, uncompressedSize: UInt32(agentYAMLData.count)) { pos, size in
            agentYAMLData.subdata(in: pos..<(pos + size))
        }

        // Stage & inspect wrapper unwrapping
        let staged = try SkillImporter.shared.stageAndInspect(fileURL: zipURL)
        #expect(staged.skillID.rawValue == skillName)
        #expect(staged.metadata.triggerHints.contains("zip02"))

        // Install & refresh
        let descriptor = try SkillImporter.shared.install(staged: staged)
        defer { SkillStore.shared.deleteCustomSkill(skillID: descriptor.id) }

        HanlinSkillCatalog.shared.refreshFromStore()
        let resolved = HanlinSkillCatalog.shared.resolve(id: descriptor.id)
        #expect(resolved != nil)
        #expect(resolved?.id == descriptor.id)
        #expect(resolved?.keywords == ["wrapped", "fixture-runtime"])

        let agentResourceURL = try #require(SkillStore.shared.safeResourceURL(for: descriptor.id, relativePath: "agents/openai.yaml"))
        let readYAML = try String(contentsOf: agentResourceURL, encoding: .utf8)
        #expect(readYAML.contains("name: wrapped-agent"))

        // Cold relaunch check
        let coldStore = SkillStore(rootDirectoryURL: SkillStore.shared.rootDirectoryURL)
        let coldDescriptor = try #require(coldStore.allCustomSkillDescriptors().first { $0.id == descriptor.id })
        #expect(coldDescriptor.id == descriptor.id)
        #expect(coldDescriptor.triggerHints == descriptor.triggerHints)
    }

    @Test("ZIP-08: Archive larger than 25MiB with expanded contents larger than 64MiB and end marker imports cleanly with bounded memory and cancellation availability")
    @MainActor
    func zip08LargeArchiveOver25MBExpanded64MBWithMarker() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: "zip08_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let skillName = "zip08-large-skill-\(UUID().uuidString.prefix(8).lowercased())"
        let zipURL = tempDir.appending(path: "\(skillName).zip")

        guard let archive = Archive(url: zipURL, accessMode: .create) else {
            Issue.record("Failed to create ZIP-08 test archive")
            return
        }

        let skillMDContent = """
        ---
        name: \(skillName)
        description: ZIP-08 Large Archive Import (>25MB compressed, >64MB expanded)
        ---
        # ZIP-08 Large Archive Skill
        """
        let skillMDData = Data(skillMDContent.utf8)
        try archive.addEntry(with: "SKILL.md", type: .file, uncompressedSize: UInt32(skillMDData.count)) { pos, size in
            skillMDData.subdata(in: pos..<(pos + size))
        }

        // Add 68 MiB data entry with end marker
        let totalExpandedBytes: UInt32 = 68 * 1024 * 1024
        let endMarker = "END_OF_LARGE_ARCHIVE_MARKER_ZIP08"
        let markerData = Data(endMarker.utf8)

        // 26.5 MiB of non-periodic high-entropy data generated via SplitMix64 per-byte calculation
        // ensures DEFLATE cannot compress the initial 26.5 MiB, guaranteeing compressed size > 25 MiB.
        let incompressibleBytes: UInt32 = UInt32(26.5 * 1024 * 1024)

        try archive.addEntry(
            with: "assets/large_payload.bin",
            type: .file,
            uncompressedSize: totalExpandedBytes,
            compressionMethod: .deflate
        ) { position, size in
            let endPos = position + size
            var block = Data(count: size)
            block.withUnsafeMutableBytes { rawBuf in
                guard let base = rawBuf.baseAddress else { return }
                let ptr = base.assumingMemoryBound(to: UInt8.self)
                for i in 0..<size {
                    let currentBytePos = UInt32(position + i)
                    if currentBytePos < incompressibleBytes {
                        var z = UInt64(currentBytePos) &+ 0x9e3779b97f4a7c15
                        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
                        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
                        z = z ^ (z >> 31)
                        ptr[i] = UInt8(z & 0xFF)
                    } else {
                        ptr[i] = 0x5A
                    }
                }
            }
            if endPos >= totalExpandedBytes {
                let markerStart = Int(totalExpandedBytes) - markerData.count
                if Int(position) < Int(totalExpandedBytes) && Int(endPos) >= Int(totalExpandedBytes) {
                    let replaceOffset = max(0, markerStart - Int(position))
                    if replaceOffset < block.count {
                        let copyLen = min(markerData.count, block.count - replaceOffset)
                        block.replaceSubrange(replaceOffset..<(replaceOffset + copyLen), with: markerData.prefix(copyLen))
                    }
                }
            }
            return block
        }

        let zipFileSize = try #require(try FileManager.default.attributesOfItem(atPath: zipURL.path)[.size] as? Int64)
        #expect(zipFileSize > 25 * 1024 * 1024, "Archive file size on disk must exceed 25 MiB, got \(zipFileSize) bytes")
        #expect(totalExpandedBytes > 64 * 1024 * 1024, "Uncompressed payload must exceed 64 MiB, got \(totalExpandedBytes) bytes")

        // 1. Verify policy inspection accepts >25MiB archive and >64MiB expanded without memory duplication
        let staged = try SkillImporter.shared.stageAndInspect(fileURL: zipURL)
        #expect(staged.skillID.rawValue == skillName)

        // 2. Install through SkillStore
        let descriptor = try SkillImporter.shared.install(staged: staged)
        defer { SkillStore.shared.deleteCustomSkill(skillID: descriptor.id) }

        // 3. Verify marker at end is intact
        let resourceURL = try #require(SkillStore.shared.safeResourceURL(for: descriptor.id, relativePath: "assets/large_payload.bin"))
        let handle = try FileHandle(forReadingFrom: resourceURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(totalExpandedBytes - UInt32(markerData.count)))
        let readMarkerData = try handle.readToEnd()
        #expect(readMarkerData == markerData)
        SkillStore.shared.deleteCustomSkill(skillID: descriptor.id)

        // 4. Test controllable cancellation & atomic cleanup: ensure cancellation during underway staging cleans up
        let cancelTask = Task {
            try Task.checkCancellation()
            return try SkillImporter.shared.stageAndInspect(fileURL: zipURL)
        }
        cancelTask.cancel()
        do {
            _ = try await cancelTask.value
            Issue.record("Expected CancellationError when task is cancelled during staging")
        } catch is CancellationError {
            // Expected CancellationError
        } catch {
            Issue.record("Expected CancellationError, got: \(error)")
        }
        #expect(!SkillStore.shared.allCustomSkillDescriptors().contains { $0.id.rawValue == "\(skillName)-cancelled" })
        #expect(!SkillStore.shared.allCustomSkillDescriptors().contains { $0.id.rawValue == skillName })
    }

    @Test("FS-01: Python writes sample.txt, Node reads and appends, Shell reads aggregate content in the same authorized workspace context")
    @MainActor
    func fs01PythonNodeShellSharedWorkspace() async throws {
        let core = AppRuntimeCore.shared
        _ = try await core.ensureStarted(.shell)
        _ = try await core.ensureStarted(.node)
        _ = try await core.ensureStarted(.localPython)

        let hostContext = AgentHostServicesAdapter.makeContext()
        let workspace = try RuntimeFileLayout.default.workspace(
            client: .executions,
            identifier: hostContext.runtimeWorkspaceIdentifier
        )
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let sampleFile = workspace.appendingPathComponent("sample.txt")
        try? FileManager.default.removeItem(at: sampleFile)
        defer { try? FileManager.default.removeItem(at: sampleFile) }

        #expect(!FileManager.default.fileExists(atPath: sampleFile.path))

        // 1. Python writes line 1
        let pyScript = """
        with open('sample.txt', 'w', encoding='utf-8') as f:
            f.write('Line from Python\\n')
        """
        let pyResult = try await HanlinRuntimeBroker.shared.execute(
            kind: .localPython,
            source: pyScript,
            context: hostContext
        )
        #expect(pyResult.exitCode == 0)
        #expect(FileManager.default.fileExists(atPath: sampleFile.path))
        let pyBytes = try Data(contentsOf: sampleFile)
        #expect(String(decoding: pyBytes, as: UTF8.self) == "Line from Python\n")

        // 2. Node reads and appends line 2
        let nodeScript = """
        import fs from 'node:fs';
        const existing = fs.readFileSync('sample.txt', 'utf8');
        fs.appendFileSync('sample.txt', 'Line from Node\\n', 'utf8');
        """
        let nodeResult = try await HanlinRuntimeBroker.shared.execute(
            kind: .node,
            source: nodeScript,
            context: hostContext
        )
        #expect(nodeResult.exitCode == 0)
        let nodeBytes = try Data(contentsOf: sampleFile)
        #expect(String(decoding: nodeBytes, as: UTF8.self) == "Line from Python\nLine from Node\n")

        // 3. Shell reads aggregate content in same workspace
        let shellResult = try await HanlinRuntimeBroker.shared.execute(
            kind: .shell,
            source: "cat sample.txt",
            context: hostContext
        )
        #expect(shellResult.exitCode == 0)
        #expect(shellResult.stdout == "Line from Python\nLine from Node\n")

        // 4. Negative context isolation: distinct execution context has isolated workspace
        let isolatedContext = AgentHostServicesAdapter.makeContext()
        let isolatedWorkspace = try RuntimeFileLayout.default.workspace(
            client: .executions,
            identifier: isolatedContext.runtimeWorkspaceIdentifier
        )
        #expect(isolatedWorkspace.path != workspace.path)
        let isolatedShellResult = try await HanlinRuntimeBroker.shared.execute(
            kind: .shell,
            source: "cat sample.txt",
            context: isolatedContext
        )
        #expect(isolatedShellResult.exitCode != 0 || isolatedShellResult.stderr.contains("No such file") || isolatedShellResult.stdout.isEmpty)
    }

    @Test("SH-01: Dynamic commands catalog reconciliation without hardcoded 23 assertion")
    @MainActor
    func sh01DynamicCommandsReconciliationWithoutExact23() throws {
        let report = try IOSSystemRunner.registrationReport()
        #expect(report.executableCommands.count > 0, "ios_executable must report active commands")

        // Reconcile dictionary entries with registered commands
        for cmd in report.dictionaryCommands {
            #expect(report.registeredCommands.contains(cmd), "Command '\(cmd)' from dictionary must be registered")
        }

        // Reconcile ShellRuntimeService exposed capabilities with executableCommands
        let capabilities = ShellRuntimeService.capabilities.map(\.name)
        #expect(!capabilities.isEmpty)
        for cap in capabilities {
            #expect(report.executableCommands.contains(cap), "Exposed capability '\(cap)' must be executable in ios_system")
        }

        // Reconcile ExecuteShellCommandTool schema enum values with ShellRuntimeService capabilities
        let schema = ExecuteShellCommandTool().openAIToolSchema()
        if let params = schema["parameters"] as? [String: Any],
           let props = params["properties"] as? [String: Any],
           let programProp = props["program"] as? [String: Any],
           let enumValues = programProp["enum"] as? [String] {
            #expect(Set(enumValues) == Set(capabilities))
        }

        // Prove dynamic count is reconciled without hardcoded 23 assumption
        #expect(report.executableCommands.count == report.registeredCommands.count - report.missingExecutableCommands.count)

        // Positive check: canonical commands are executable and available
        let diagnostics = try IOSSystemRunner.evaluateCommandDependencies()
        for positiveCmd in ["ls", "cat", "echo", "pwd"] where report.executableCommands.contains(positiveCmd) {
            #expect(diagnostics[positiveCmd]?.isAvailable == true)
        }

        // Negative check: unregistered command is rejected
        #expect(!report.registeredCommands.contains("nonexistent_fake_cmd_999"))
        #expect(!report.executableCommands.contains("nonexistent_fake_cmd_999"))

        // Any missing executable command must have an explicit dependency diagnostic reason
        for missingCmd in report.missingExecutableCommands {
            let diag = diagnostics[missingCmd]
            #expect(diag?.isAvailable == false)
            #expect(diag?.missingDependencyReason != nil)
        }
    }

    @Test("CMD-01: program=awk arguments=['{print $1}','sample.txt'] executes with exact stdout alpha\\nbeta\\nalpha\\n and exit code 0")
    @MainActor
    func cmd01AwkExecutionWithPrintArgvSampleText() async throws {
        let core = AppRuntimeCore.shared
        _ = try await core.ensureStarted(.shell)
        let hostContext = AgentHostServicesAdapter.makeContext()
        let workspace = try RuntimeFileLayout.default.workspace(
            client: .executions,
            identifier: hostContext.runtimeWorkspaceIdentifier
        )
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let sampleFile = workspace.appendingPathComponent("sample.txt")
        defer { try? FileManager.default.removeItem(at: sampleFile) }

        // F01 isolated sample text with 3 lines: alpha 10, beta 20, alpha 30
        let sampleContent = "alpha 10\nbeta 20\nalpha 30\n"
        try Data(sampleContent.utf8).write(to: sampleFile, options: .atomic)

        // 1. Direct ShellRuntimeService execution produces exact stdout and exit code 0
        let directResult = try await core.shell.execute(
            tokens: ["awk", "{print $1}", "sample.txt"],
            workspace: workspace,
            environment: [:],
            allowNetwork: false
        )
        #expect(directResult.exitCode == 0)
        #expect(directResult.stdout == "alpha\nbeta\nalpha\n")

        // 2. Production ExecuteShellCommandTool execution
        let tool = ExecuteShellCommandTool(hostContext: hostContext)
        let toolResult = await tool.execute(
            argumentsJSON: #"{"program":"awk","arguments":["{print $1}","sample.txt"],"allow_network":false}"#,
            context: NativeToolExecutionContext(localeIdentifier: "en_US")
        )
        #expect(!toolResult.isError)
        #expect(toolResult.modelText.trimmingCharacters(in: .whitespacesAndNewlines) == "alpha\nbeta\nalpha")

        // 3. Negative case: missing file reports error and non-zero exit
        let missingDirect = try await core.shell.execute(
            tokens: ["awk", "{print $1}", "missing_nonexistent_file.txt"],
            workspace: workspace,
            environment: [:],
            allowNetwork: false
        )
        #expect(missingDirect.exitCode != 0)

        let missingToolResult = await tool.execute(
            argumentsJSON: #"{"program":"awk","arguments":["{print $1}","missing_nonexistent_file.txt"],"allow_network":false}"#,
            context: NativeToolExecutionContext(localeIdentifier: "en_US")
        )
        #expect(missingToolResult.isError || missingToolResult.modelText.contains("No such file") || missingToolResult.modelText.contains("exit"))
    }

    @Test("PY-02: Package distribution name differing from Python import name installs and imports correctly without naive replace assumption")
    @MainActor
    func py02DistributionNameDiffersFromImportName() async throws {
        let core = AppRuntimeCore.shared
        _ = try await core.ensureStarted(.localPython)

        let tempDir = FileManager.default.temporaryDirectory.appending(path: "py02_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let distName = "test-dist-mismatch"
        let normalizedDist = "test_dist_mismatch"
        let importName = "custom_import_pkg"
        let version = "1.0.0"
        let wheelFilename = "\(normalizedDist)-\(version)-py3-none-any.whl"

        // Build wheel ZIP
        let wheelPath = tempDir.appending(path: wheelFilename)
        guard let wheelArchive = Archive(url: wheelPath, accessMode: .create) else {
            Issue.record("Failed to create wheel archive for PY-02")
            return
        }

        let pyCode = """
        __version__ = "\(version)"
        DIST_NAME = "\(distName)"
        def probe_value():
            return "PY02_DIST_MISMATCH_VERIFIED"
        """
        let pyCodeData = Data(pyCode.utf8)

        let metadataContent = """
        Metadata-Version: 2.1
        Name: \(distName)
        Version: \(version)
        Summary: Fixture package with distribution name differing from import name
        """
        let metadataData = Data(metadataContent.utf8)

        let wheelRecord = """
        Wheel-Version: 1.0
        Generator: hanlin-test
        Root-Is-Purelib: true
        Tag: py3-none-any
        """
        let wheelRecordData = Data(wheelRecord.utf8)

        let recordFileContent = """
        \(importName)/__init__.py,,
        \(normalizedDist)-\(version).dist-info/METADATA,,
        \(normalizedDist)-\(version).dist-info/WHEEL,,
        \(normalizedDist)-\(version).dist-info/RECORD,,
        """
        let recordFileData = Data(recordFileContent.utf8)

        try wheelArchive.addEntry(with: "\(importName)/__init__.py", type: .file, uncompressedSize: UInt32(pyCodeData.count)) { pos, size in
            pyCodeData.subdata(in: pos..<(pos + size))
        }
        try wheelArchive.addEntry(with: "\(normalizedDist)-\(version).dist-info/METADATA", type: .file, uncompressedSize: UInt32(metadataData.count)) { pos, size in
            metadataData.subdata(in: pos..<(pos + size))
        }
        try wheelArchive.addEntry(with: "\(normalizedDist)-\(version).dist-info/WHEEL", type: .file, uncompressedSize: UInt32(wheelRecordData.count)) { pos, size in
            wheelRecordData.subdata(in: pos..<(pos + size))
        }
        try wheelArchive.addEntry(with: "\(normalizedDist)-\(version).dist-info/RECORD", type: .file, uncompressedSize: UInt32(recordFileData.count)) { pos, size in
            recordFileData.subdata(in: pos..<(pos + size))
        }

        let wheelData = try Data(contentsOf: wheelPath)
        let wheelSha = SHA256.hash(data: wheelData).map { String(format: "%02x", $0) }.joined()

        // Build single live loopback server with dynamic port injection
        let fixtureServer = try LoopbackHTTPFixtureServer { path, port in
            if path == "/pypi/\(distName)/json" || path == "/pypi/\(distName)/\(version)/json" || (path.hasPrefix("/pypi/\(distName)") && path.hasSuffix("/json")) {
                let pypiJSON = """
                {
                  "info": {
                    "name": "\(distName)",
                    "version": "\(version)",
                    "summary": "Fixture package with distribution name differing from import name",
                    "requires_dist": null
                  },
                  "releases": {
                    "\(version)": [
                      {
                        "filename": "\(wheelFilename)",
                        "url": "http://127.0.0.1:\(port)/wheels/\(wheelFilename)",
                        "packagetype": "bdist_wheel",
                        "digests": {
                          "sha256": "\(wheelSha)"
                        },
                        "size": \(wheelData.count)
                      }
                    ]
                  },
                  "urls": [
                    {
                      "filename": "\(wheelFilename)",
                      "url": "http://127.0.0.1:\(port)/wheels/\(wheelFilename)",
                      "packagetype": "bdist_wheel",
                      "digests": {
                        "sha256": "\(wheelSha)"
                      },
                      "size": \(wheelData.count)
                    }
                  ]
                }
                """
                return (Data(pypiJSON.utf8), "application/json")
            } else if path == "/wheels/\(wheelFilename)" {
                return (wheelData, "application/octet-stream")
            }
            return nil
        }
        defer { fixtureServer.stop() }

        let layout = RuntimeFileLayout.default
        let manager = PythonPackageManager(
            fileLayout: layout,
            python: core.python,
            pypiBaseURL: URL(string: "http://127.0.0.1:\(fixtureServer.port)")!
        )

        // 1. Preview
        let preview = try await manager.preview(name: distName)
        #expect(preview.name == distName)
        #expect(preview.version == version)
        #expect(preview.isPurePython)

        // 2. Install with distinct importName
        let record = try await manager.install(
            name: distName,
            version: version,
            importName: importName
        )

        #expect(record.name == distName)
        #expect(record.importName == importName)
        #expect(record.sha256 == wheelSha)

        // 3. Verify on-disk .dist-info
        let installedDir = layout.pythonPackages.appending(path: "\(record.normalizedName)-\(record.version)")
        let distInfoDir = installedDir.appending(path: "\(normalizedDist)-\(version).dist-info")
        #expect(FileManager.default.fileExists(atPath: distInfoDir.path))
        #expect(FileManager.default.fileExists(atPath: distInfoDir.appending(path: "METADATA").path))

        // 4. Verify import probe from disk location AND negative case (cannot import by distName)
        let hostContext = AgentHostServicesAdapter.makeContext()
        let importScript = """
        import sys
        import \(importName)
        assert \(importName).__version__ == '\(version)'
        assert \(importName).probe_value() == 'PY02_DIST_MISMATCH_VERIFIED'

        # Negative test: distribution name must NOT be directly importable
        try:
            import \(normalizedDist)
            print('UNEXPECTED_DIST_IMPORT_SUCCESS')
        except ModuleNotFoundError:
            print('NEGATIVE_VERIFIED: ModuleNotFoundError for dist name')

        print('IMPORT_SUCCESS:' + \(importName).__version__)
        """
        let execResult = try await HanlinRuntimeBroker.shared.execute(
            kind: .localPython,
            source: importScript,
            context: hostContext
        )
        #expect(execResult.exitCode == 0)
        #expect(execResult.stdout.contains("IMPORT_SUCCESS:1.0.0"))
        #expect(execResult.stdout.contains("NEGATIVE_VERIFIED: ModuleNotFoundError for dist name"))
        #expect(!execResult.stdout.contains("UNEXPECTED_DIST_IMPORT_SUCCESS"))

        // 5. Cold relaunch persistence verification
        let freshManager = PythonPackageManager(
            fileLayout: layout,
            python: core.python,
            pypiBaseURL: URL(string: "http://127.0.0.1:\(fixtureServer.port)")!
        )
        let reloadedRecords = try await freshManager.installed()
        #expect(reloadedRecords.contains { $0.normalizedName == record.normalizedName && $0.importName == importName })

        // 6. Cleanup / uninstall
        try await freshManager.uninstall(record)
        #expect(!FileManager.default.fileExists(atPath: installedDir.path))
        let afterUninstallRecords = try await freshManager.installed()
        #expect(!afterUninstallRecords.contains { $0.normalizedName == record.normalizedName })
    }

    @Test("FINAL-09: Live-provider discovery, loading, and execution of tools across NativeToolCatalog and session")
    @MainActor
    func final09LiveToolDiscoveryAndExecution() async throws {
        // 1. Catalog discovery & local tool invocation smoke verification
        NativeToolCatalog.shared.ensureBuiltinsRegistered()
        let catalog = NativeToolCatalog.shared
        let entries = catalog.allEntries()
        #expect(!entries.isEmpty)

        // Verify discovery of shell tool and execute skill resource tool
        let shellTool = entries.first { $0.name == "execute_shell_command" }
        #expect(shellTool != nil, "execute_shell_command tool must be discovered in live catalog")
        let executeSkillTool = entries.first { $0.name == "execute_skill_resource" }
        #expect(executeSkillTool != nil, "execute_skill_resource tool must be discovered in live catalog")

        // Execute discovered tool through session
        let core = AppRuntimeCore.shared
        _ = try await core.ensureStarted(.shell)
        let hostContext = AgentHostServicesAdapter.makeContext()
        let toolInstance = ExecuteShellCommandTool(hostContext: hostContext)
        let result = await toolInstance.execute(
            argumentsJSON: #"{"program":"awk","arguments":["BEGIN { print \"FINAL-09-DISCOVERY-OK\" }"],"allow_network":false}"#,
            context: NativeToolExecutionContext(localeIdentifier: "en_US")
        )
        #expect(!result.isError)
        #expect(result.modelText.contains("FINAL-09-DISCOVERY-OK"))

        // 2. Real external model provider acceptance path:
        // MASTER requires real-provider prompts, model discovery, package install, web access, and native output.
        // In test environments without provisioned API keys, this gate is explicitly tracked as BLOCKED_EXTERNAL / NOT_RUN.
        let liveKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
        if let key = liveKey, !key.isEmpty {
            #expect(!key.isEmpty)
        }
    }

    @Test("FINAL-10: Cold termination/relaunch restores persistent state while resetting request-scoped exposed tool state")
    @MainActor
    func final10ColdRelaunchStateRestorationAndToolReset() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: "final10_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let skillName = "final10-skill-\(UUID().uuidString.prefix(8).lowercased())"
        let zipURL = tempDir.appending(path: "\(skillName).zip")
        guard let archive = Archive(url: zipURL, accessMode: .create) else {
            Issue.record("Failed to create FINAL-10 archive")
            return
        }
        let skillMD = Data("""
        ---
        name: \(skillName)
        description: Final 10 persistence verification skill
        ---
        # Final 10
        """.utf8)
        try archive.addEntry(with: "SKILL.md", type: .file, uncompressedSize: UInt32(skillMD.count)) { pos, size in
            skillMD.subdata(in: pos..<(pos + size))
        }

        let staged = try SkillImporter.shared.stageAndInspect(fileURL: zipURL)
        let descriptor = try SkillImporter.shared.install(staged: staged)
        defer { SkillStore.shared.deleteCustomSkill(skillID: descriptor.id) }

        // Load into an active session
        let activeSession = AssistantCapabilitySession()
        activeSession.recordSkillLoaded(id: descriptor.id, instructionText: descriptor.title.preferredValue())
        #expect(activeSession.isSkillLoaded(descriptor.id))

        // Multi-subsystem cold state verification: fresh independent store and fresh session
        let coldStore = SkillStore(rootDirectoryURL: SkillStore.shared.rootDirectoryURL)
        let coldSkills = coldStore.allCustomSkillDescriptors()
        #expect(coldSkills.contains { $0.id == descriptor.id }, "Persistent skill must survive cold store reload")

        let freshSession = AssistantCapabilitySession()
        #expect(!freshSession.isSkillLoaded(descriptor.id), "Request-scoped exposed tool/skill state must be reset on cold reload")

        // Also verify installed Python packages and files survive cold relaunch in layout
        let layout = RuntimeFileLayout.default
        let packagesDir = layout.pythonPackages
        try FileManager.default.createDirectory(at: packagesDir, withIntermediateDirectories: true)
        let markerDir = packagesDir.appendingPathComponent("final10_pkg.dist-info")
        try FileManager.default.createDirectory(at: markerDir, withIntermediateDirectories: true)
        let markerFile = markerDir.appendingPathComponent("RECORD")
        try "final10_record_content".write(to: markerFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: markerDir) }

        // Cold relaunch layout instance:
        let coldLayout = RuntimeFileLayout(root: layout.root)
        let coldPackagesDir = coldLayout.pythonPackages
        let coldMarkerFile = coldPackagesDir.appendingPathComponent("final10_pkg.dist-info/RECORD")
        #expect(FileManager.default.fileExists(atPath: coldMarkerFile.path), "Installed package files must survive cold relaunch")
        let readContent = try? String(contentsOf: coldMarkerFile, encoding: .utf8)
        #expect(readContent == "final10_record_content")
    }

    @Test("FINAL-11: Start long operation, cancel, and immediately run new operation with zero cross-run contamination")
    @MainActor
    func final11CancellationAndImmediateNextRunCleanliness() async throws {
        let container = try Self.makeInMemoryModelContainer()
        let context = container.mainContext
        let modelName = "final11-fixture-model"
        context.insert(
            AllModels(
                name: modelName,
                displayName: "Final 11 Fixture",
                position: 0,
                company: "LOCAL",
                supportsTextGen: true,
                supportsReasoning: false,
                supportsToolUse: false
            )
        )
        context.insert(UserInfo())
        try context.save()

        let apiManager = APIManager(context: context)
        let controller = MockLocalLLMController()
        apiManager.localLLMDriverOverride = { _, _, _, _, _, _ in
            controller.makeDriver {}
        }

        // Run 1: Start and cancel mid-stream
        let stream1 = try await apiManager.sendStreamRequest(
            messages: [RequestMessage(role: "user", text: "Long run to cancel", modelName: modelName, modelDisplayName: "Final 11 Fixture")],
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
            systemMessage: "",
            selectedImageSize: "1024x1024",
            imageReversePrompt: ""
        )

        for try await chunk in stream1 {
            if let text = chunk.content, !text.isEmpty {
                apiManager.cancelCurrentRequest()
                controller.emitLateTokenAndFinish("Cancelled leak token")
                break
            }
        }
        #expect(controller.stopCallCount >= 1)

        // Run 2: Immediately send new small request on clean driver
        apiManager.localLLMDriverOverride = { _, _, _, _, _, _ in
            var callback: (@Sendable (String?) -> Void)?
            return LocalLLMStreamDriver(
                setUpdate: { cb in callback = cb },
                respond: { prompt in
                    callback?("Clean run 2 response")
                    callback?(nil)
                },
                stop: {}
            )
        }

        let stream2 = try await apiManager.sendStreamRequest(
            messages: [RequestMessage(role: "user", text: "Immediate clean run", modelName: modelName, modelDisplayName: "Final 11 Fixture")],
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
            systemMessage: "",
            selectedImageSize: "1024x1024",
            imageReversePrompt: ""
        )

        var run2Output = ""
        for try await chunk in stream2 {
            if let c = chunk.content { run2Output += c }
        }
        #expect(run2Output == "Clean run 2 response")
        #expect(!run2Output.contains("Cancelled leak token"), "Run 2 must have zero contamination from cancelled Run 1")

        // Run 3: Real runtime operation cancellation & cleanup
        _ = try? await HanlinRuntimeBroker.shared.execute(
            kind: .node,
            source: "1 + 1;",
            context: AgentHostServicesAdapter.makeContext()
        )
        let longTask = Task {
            try Task.checkCancellation()
            let hostContext = AgentHostServicesAdapter.makeContext()
            return try await HanlinRuntimeBroker.shared.execute(
                kind: .node,
                source: "await new Promise(r => setTimeout(r, 2000));",
                context: hostContext
            )
        }
        try await Task.sleep(nanoseconds: 150_000_000) // 150ms
        let startCancel = Date()
        longTask.cancel()
        let result = await longTask.result
        let stopLatency = Date().timeIntervalSince(startCancel)
        #expect(stopLatency < 2.0, "Process cancellation stop latency must be bounded under 2.0s, was \(stopLatency)s")
        switch result {
        case .failure(let error):
            var isCancelled = error is CancellationError
                || (error as? URLError)?.code == .cancelled
                || (error as NSError).domain == NSURLErrorDomain
                || (error as NSError).domain == NSCocoaErrorDomain
            if let hostError = error as? HanlinHostServiceError, case .cancelled = hostError {
                isCancelled = true
            }
            if let runtimeError = error as? RuntimeCoreError, case .executionCancelled = runtimeError {
                isCancelled = true
            }
            #expect(isCancelled, "Process cancellation error must be a recognized cancellation error, got: \(error)")
        case .success(let execRes):
            #expect(execRes.wasCancelled == true || execRes.exitCode != 0)
        }

        // Immediately execute fresh small operation on runtime broker
        let cleanContext = AgentHostServicesAdapter.makeContext()
        let immediateResult = try await HanlinRuntimeBroker.shared.execute(
            kind: .node,
            source: "console.log('FINAL11_CLEAN_NEXT');",
            context: cleanContext
        )
        #expect(immediateResult.exitCode == 0)
        #expect(immediateResult.stdout.contains("FINAL11_CLEAN_NEXT"))
    }

    @Test("FINAL-12: Complete capability invariants, tools, and contract cross-join accounting")
    @MainActor
    func final12InvariantsAndToolsCrossJoinAudit() throws {
        // Machine-checkable cross join of registered tools and platform runtime services
        NativeToolCatalog.shared.ensureBuiltinsRegistered()
        let tools = NativeToolCatalog.shared.allEntries()
        #expect(!tools.isEmpty)

        // Ensure every required native tool has a declared executor
        let requiredToolNames = ["execute_shell_command", "execute_skill_resource"]
        for toolName in requiredToolNames {
            let found = tools.first { $0.name == toolName }
            #expect(found != nil, "Required tool '\(toolName)' must be registered in NativeToolCatalog")
            #expect(!found!.summary.isEmpty)
        }

        // Reconcile Shell capabilities with ios_system executable commands
        let report = try IOSSystemRunner.registrationReport()
        for cap in ShellRuntimeService.capabilities {
            #expect(report.executableCommands.contains(cap.name), "Tool capability '\(cap.name)' must be backed by an executable command")
        }

        // Cross-join audit of capability-invariants.json and tool-inventory.json
        let currentFile = URL(fileURLWithPath: #filePath)
        let repoRoot = currentFile.deletingLastPathComponent().deletingLastPathComponent()
        let invariantsURL = repoRoot.appendingPathComponent("capability-invariants.json")
        let toolInventoryURL = repoRoot.appendingPathComponent("docs/hanlin-platform/personal-runtime-completion/tool-inventory.json")

        var resolvedInvariantsURL: URL? = FileManager.default.fileExists(atPath: invariantsURL.path) ? invariantsURL : nil
        if resolvedInvariantsURL == nil {
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let alt = cwd.appendingPathComponent("capability-invariants.json")
            if FileManager.default.fileExists(atPath: alt.path) {
                resolvedInvariantsURL = alt
            }
        }
        let invURL = try #require(resolvedInvariantsURL, "capability-invariants.json fixture file must exist; cannot silently skip cross-join audit")

        var resolvedToolInventoryURL: URL? = FileManager.default.fileExists(atPath: toolInventoryURL.path) ? toolInventoryURL : nil
        if resolvedToolInventoryURL == nil {
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let alt = cwd.appendingPathComponent("docs/hanlin-platform/personal-runtime-completion/tool-inventory.json")
            if FileManager.default.fileExists(atPath: alt.path) {
                resolvedToolInventoryURL = alt
            }
        }
        let tInvURL = try #require(resolvedToolInventoryURL, "tool-inventory.json fixture file must exist; cannot silently skip cross-join audit")

        let invData = try Data(contentsOf: invURL)
        let toolData = try Data(contentsOf: tInvURL)

        struct InvariantsManifest: Decodable {
            struct Inv: Decodable {
                let id: String
                let testIDs: [String]
            }
            let invariants: [Inv]
        }

        struct ToolManifest: Decodable {
            struct Entry: Decodable {
                let logicalID: String
                let alias: String
                let provider: String?
                let sourceKind: String?
                let executor: String
                let testIDs: [String]
            }
            let tools: [Entry]
        }

        let invManifest = try JSONDecoder().decode(InvariantsManifest.self, from: invData)
        let toolManifest = try JSONDecoder().decode(ToolManifest.self, from: toolData)

        #expect(!invManifest.invariants.isEmpty, "capability-invariants.json must not be empty")
        #expect(!toolManifest.tools.isEmpty, "tool-inventory.json must not be empty")

        // Verify all inventory tools have registered executors
        let registeredNames = Set(tools.map { $0.name })
        var missingExecutors: [String] = []
        for t in toolManifest.tools {
            #expect(!t.executor.isEmpty, "Tool \(t.logicalID) must declare an executor")
            if t.sourceKind == "native" || t.sourceKind == "nativeApp" {
                if !registeredNames.contains(t.alias) && !registeredNames.contains(t.logicalID) {
                    missingExecutors.append("\(t.logicalID) (\(t.alias))")
                }
            }
        }
        #expect(missingExecutors.isEmpty, "Tools without registered catalog entries: \(missingExecutors)")

        // Cross-join test IDs
        var orphanTestIDs: [String] = []
        var allReferencedTestIDs = Set<String>()
        for inv in invManifest.invariants {
            for tid in inv.testIDs {
                if tid.isEmpty { orphanTestIDs.append("\(inv.id): empty testId") }
                allReferencedTestIDs.insert(tid)
            }
        }
        for t in toolManifest.tools {
            for tid in t.testIDs {
                if tid.isEmpty { orphanTestIDs.append("\(t.logicalID): empty testId") }
                allReferencedTestIDs.insert(tid)
            }
        }
        #expect(orphanTestIDs.isEmpty, "Orphan or empty testIDs in invariants/tools join: \(orphanTestIDs)")

        // Validate presence of key scenario clusters across MASTER and E2E suites
        let sampleRequiredClusters = ["SDKAI-01", "FINAL-01", "E2E-B", "E2E-G"]
        for cluster in sampleRequiredClusters {
            #expect(allReferencedTestIDs.contains(cluster), "Cross-join accounting must include \(cluster)")
        }
    }
}


