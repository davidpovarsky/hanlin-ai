import Foundation
import HanlinChatCore
import HanlinMiniAppCore
import HanlinPlatformContracts
import SWCompression
import SwiftData
import SwiftUI
import ZIPFoundation

enum AgentRuntimeUIAcceptanceProvider {
    static let environmentKey = "HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE"
    static let skillsEnvironmentKey = "HANLIN_AGENT_SKILLS_EMBEDDED_ACCEPTANCE"
    static let modelName = "hanlin-agent-acceptance"
    static let chatName = "Agent Acceptance Chat"

    static var isSkillsEnabled: Bool {
#if targetEnvironment(simulator)
        ProcessInfo.processInfo.environment[skillsEnvironmentKey] == "1"
#else
        false
#endif
    }

    static var isEnabled: Bool {
#if targetEnvironment(simulator)
        ProcessInfo.processInfo.environment[environmentKey] == "1" || ProcessInfo.processInfo.environment[skillsEnvironmentKey] == "1"
#else
        false
#endif
    }

    static func sampleMCPArchiveURL() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hanlin-echo-mcp-acceptance.tgz")
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        let packageJSON = """
        {
          "name": "hanlin-echo-mcp",
          "version": "1.0.0",
          "type": "module",
          "main": "server.mjs"
        }
        """
        let serverMJS = """
        import { createInterface } from 'node:readline';
        createInterface({ input: process.stdin }).on('line', line => {
          if (!line.trim()) return;
          const req = JSON.parse(line);
          if (req.method === 'initialize') {
            respond(req.id, {
              protocolVersion: req.params?.protocolVersion ?? '2025-03-26',
              capabilities: { tools: {} },
              serverInfo: { name: 'hanlin-echo-mcp', version: '1.0.0' }
            });
          } else if (req.method === 'tools/list') {
            respond(req.id, {
              tools: [{
                name: 'echo_ping',
                description: 'Echoes a message back for acceptance testing.',
                inputSchema: {
                  type: 'object',
                  properties: { message: { type: 'string' } },
                  required: ['message']
                }
              }]
            });
          } else if (req.method === 'tools/call') {
            const msg = req.params?.arguments?.message ?? 'pong';
            respond(req.id, {
              content: [{ type: 'text', text: `ECHO_PONG_OK:${msg}` }],
              isError: false
            });
          }
        });
        function respond(id, result) {
          if (id === undefined || id === null) return;
          process.stdout.write(JSON.stringify({ jsonrpc: '2.0', id, result }) + '\\n');
        }
        """
        var entries: [TarEntry] = []
        let pkgData = Data(packageJSON.utf8)
        var pkgInfo = TarEntryInfo(name: "package/package.json", type: .regular)
        pkgInfo.permissions = Permissions(rawValue: 0o644)
        entries.append(TarEntry(info: pkgInfo, data: pkgData))

        let srvData = Data(serverMJS.utf8)
        var srvInfo = TarEntryInfo(name: "package/server.mjs", type: .regular)
        srvInfo.permissions = Permissions(rawValue: 0o755)
        entries.append(TarEntry(info: srvInfo, data: srvData))

        let tarData = TarContainer.create(from: entries)
        if let tgzData = try? GzipArchive.archive(data: tarData) {
            try? tgzData.write(to: url, options: .atomic)
        }
        return url
    }

    @MainActor
    static func configureIfRequested(context: ModelContext) {
        guard isEnabled else { return }
        do {
            for chat in try context.fetch(FetchDescriptor<ChatRecords>()) {
                context.delete(chat)
            }
            for model in try context.fetch(FetchDescriptor<AllModels>()) {
                context.delete(model)
            }
            for key in try context.fetch(FetchDescriptor<APIKeys>()) {
                context.delete(key)
            }
            for info in try context.fetch(FetchDescriptor<UserInfo>()) {
                context.delete(info)
            }
            context.insert(UserInfo(
                optimizationTextModel: modelName,
                optimizationVisualModel: modelName
            ))
            context.insert(AllModels(
                name: modelName,
                displayName: "Agent Acceptance",
                position: 0,
                company: "ACCEPTANCE",
                supportsTextGen: true,
                supportsMultimodal: true,
                supportsReasoning: true,
                supportReasoningChange: true,
                supportsToolUse: true
            ))
            context.insert(APIKeys(
                name: "Agent Acceptance",
                company: "ACCEPTANCE",
                key: "acceptance-only",
                requestURL: "https://agent.acceptance/v1/chat/completions",
                isHidden: false,
                apiType: .openAI
            ))
            context.insert(ChatRecords(
                name: chatName,
                type: "chat",
                useModel: 0
            ))
            if isSkillsEnabled {
                if let skillID = try? HanlinSkillID(validating: "acceptance_skill"),
                   let descriptor = try? HanlinSkillDescriptor(
                       id: skillID,
                       title: "Acceptance Skill",
                       summary: "Demonstrates agent skills and embedded result UI",
                       instructions: .inline("Always show embedded results for acceptance testing."),
                       preferredToolIDs: ["create_web_view"]
                   ) {
                    HanlinSkillCatalog.shared.register(skill: descriptor)
                }

                // Register test double for arbitrary embedded result handler in HanlinEmbeddedResultResolver
                HanlinEmbeddedResultResolver.shared.customSwiftResolver = { appID, handler, payload in
                    guard appID.rawValue == "acceptance.app" || appID.rawValue == "legacy.web" else { return nil }
                    let action = HanlinEmbeddedContentAction(
                        id: "open_acceptance_details",
                        title: "Open Details",
                        systemImage: "arrow.up.right.square",
                        launchRequest: HanlinLaunchRequest(
                            id: HanlinLaunchID(unchecked: "launch-acceptance"),
                            requestID: HanlinRequestID(unchecked: "req-acceptance"),
                            target: HanlinLaunchTarget(appID: appID),
                            presentation: .largeSheet,
                            origin: .assistantModel
                        )
                    )
                    let existingActions = payload?.actions ?? []
                    let enrichedPayload = HanlinEmbeddedResultPayload(
                        payload: payload?.payload,
                        resultReference: payload?.resultReference,
                        title: payload?.title,
                        metadata: payload?.metadata,
                        ownerID: payload?.ownerID ?? appID.rawValue,
                        actions: existingActions.isEmpty ? [action] : existingActions
                    )
                    return AnyEmbeddedResultSession(
                        engine: .swift,
                        appID: appID,
                        rootView: AnyView(
                            VStack(spacing: 8) {
                                Text("Acceptance Embedded Card Surface")
                                    .font(.headline)
                                    .accessibilityIdentifier("acceptance_embedded_surface")
                                Text("Arbitrary Mini App Result: \(handler)")
                                    .font(.caption)
                                    .accessibilityIdentifier("acceptance_embedded_detail")
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                        )
                    )
                }
            }
            try context.save()
            URLProtocol.registerClass(AgentRuntimeUIAcceptanceURLProtocol.self)
            AgentRuntimeUIAcceptanceURLProtocol.reset()
        } catch {
            NativeToolTraceLogger.shared.log(
                "agent_ui_acceptance_configuration_failed",
                ["error": error.localizedDescription]
            )
        }
    }

    static func makeSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        if isEnabled {
            configuration.protocolClasses = [AgentRuntimeUIAcceptanceURLProtocol.self]
        }
        return configuration
    }

    static func makeChatEngine() -> HanlinChatEngine {
        guard isEnabled else { return HanlinChatEngine() }
        let configuration = makeSessionConfiguration()
        return HanlinChatEngine(sessionConfiguration: configuration)
    }
}

final class AgentRuntimeUIAcceptanceURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var responseIndex = 0
    private nonisolated(unsafe) static var ui07FailCount = 0
    private var isStopped = false

    static func reset() {
        lock.lock()
        responseIndex = 0
        ui07FailCount = 0
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard AgentRuntimeUIAcceptanceProvider.isEnabled,
              let host = request.url?.host else { return false }
        return host == "agent.acceptance" || host == "skills.acceptance" || host == "emkc.org"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if request.url?.host == "skills.acceptance" {
            handleSkillsDownload()
            return
        }
        if request.url?.host == "emkc.org" {
            handlePistonExecute()
            return
        }
        if request.url?.host == "agent.acceptance",
           request.url?.path.hasPrefix("/wiki/") == true {
            handleWikiPage()
            return
        }

        let bodyData = Self.extractBodyData(from: request)
        let bodyString = String(decoding: bodyData, as: UTF8.self)

        // 1. Delayed Run A for stop cancellation test
        if bodyString.contains("START_DELAYED_RUN_A") {
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            DispatchQueue.global().async { [weak self] in
                for _ in 0..<80 {
                    guard let self, !self.isStopped else { return }
                    Thread.sleep(forTimeInterval: 0.1)
                }
                guard let self, !self.isStopped else { return }
                let payload: [String: Any] = [
                    "choices": [[
                        "delta": ["content": "RUN_A_LATE_GHOST"],
                        "finish_reason": "stop"
                    ]]
                ]
                if let data = try? JSONSerialization.data(withJSONObject: payload),
                   let json = String(data: data, encoding: .utf8) {
                    let sse = "data: \(json)\n\ndata: [DONE]\n\n"
                    self.client?.urlProtocol(self, didLoad: Data(sse.utf8))
                    self.client?.urlProtocolDidFinishLoading(self)
                }
            }
            return
        }

        // 2. Run B immediately completes
        if bodyString.contains("START_RUN_B") {
            emitFinalAnswer("RUN_B_COMPLETE")
            return
        }

        // 3. Next turn skill loading test
        if bodyString.contains("ui-next-turn-skill") || bodyString.contains("NEXT_TURN_SKILL") {
            let isContinuation = bodyString.contains("\"role\":\"tool\"") || bodyString.contains("\"role\": \"tool\"")
            if isContinuation {
                if bodyString.contains("NEXT_TURN_SKILL_MARKER") {
                    emitFinalAnswer("NEXT_TURN_SKILL_MARKER: Skill loaded successfully!")
                } else {
                    emitFinalAnswer("NEXT_TURN_SKILL_LOAD_FAILED")
                }
            } else {
                emitToolCall(id: "ui-next-turn-load", name: "load_skill", arguments: #"{"skill_id":"ui-next-turn-skill"}"#)
            }
            return
        }

        // 4. UI-04 Collapsed progress and inspector without raw CoT (must precede 6*7 check)
        if bodyString.contains("PROMPT_UI04_REASONING_INSPECTOR") {
            if bodyString.contains("ui04-progress-1") {
                emitFinalAnswer("Calculation verified: 42. UI04_REASONING_COMPLETE")
            } else {
                let payload: [String: Any] = [
                    "choices": [[
                        "delta": [
                            "reasoning_content": "<think>Step 1: Let me think privately about internal CoT</think>",
                            "tool_calls": [[
                                "index": 0,
                                "id": "ui04-progress-1",
                                "type": "function",
                                "function": [
                                    "name": "execute_local_python_code",
                                    "arguments": #"{"source":"print(6 * 7)","progress_summary":"<think>Let me think</think>"}"#
                                ]
                            ]]
                        ],
                        "finish_reason": "tool_calls"
                    ]]
                ]
                emitPayload(payload)
            }
            return
        }

        // 5. Calculate 6*7 without user nudge
        if bodyString.contains("6*7") || bodyString.contains("6 * 7") || bodyString.contains("compute 123 * 456") {
            if bodyString.contains("42") {
                emitFinalAnswer("42 / LOCAL_PYTHON_COMPLETE")
            } else if bodyString.contains("tool_call_id") || bodyString.contains("\"role\":\"tool\"") {
                emitToolCall(id: "ui-python-call", name: "execute_local_python_code", arguments: #"{"source":"print(6 * 7)"}"#)
            } else {
                emitToolCall(id: "ui-load-code-call", name: "load_skill", arguments: #"{"skill_id":"code"}"#)
            }
            return
        }

        // 6. UI-02 Classic user and assistant bubbles with direct action buttons
        if bodyString.contains("PROMPT_UI02_CLASSIC_BUBBLES") {
            emitFinalAnswer("### Classic Bubble Heading\nHere is **bold** markdown and inline math $E=mc^2$. UI02_CLASSIC_COMPLETE")
            return
        }

        // 7. UI-03 Search message and deduplicated citations
        if bodyString.contains("PROMPT_UI03_SEARCH_CITATIONS") {
            if bodyString.contains("ui03-read-2") {
                emitFinalAnswer("According to the Hanlin reference [1], classic search rows and citations are restored. UI03_SEARCH_COMPLETE")
            } else if bodyString.contains("ui03-read-1") {
                emitToolCall(
                    id: "ui03-read-2",
                    name: "read_web_page",
                    arguments: #"{"url":"https://agent.acceptance/wiki/hanlin#section"}"#
                )
            } else {
                emitToolCall(
                    id: "ui03-read-1",
                    name: "read_web_page",
                    arguments: #"{"url":"https://agent.acceptance/wiki/hanlin"}"#
                )
            }
            return
        }

        // 8. UI-05 Rich code block, HTML card, and attachments
        if bodyString.contains("PROMPT_UI05_RICH_CONTENT") {
            if bodyString.contains("ui05-html-1") {
                emitFinalAnswer("Rich content and attachments verified. UI05_RICH_COMPLETE")
            } else if bodyString.contains("ui05-code-1") {
                emitToolCall(
                    id: "ui05-html-1",
                    name: "create_web_view",
                    arguments: #"{"code":"<h1>UI05 Interactive Card</h1><p>Rendered HTML surface</p>"}"#
                )
            } else {
                emitToolCall(
                    id: "ui05-code-1",
                    name: "execute_local_python_code",
                    arguments: #"{"source":"print('Code output: 42')"}"#
                )
            }
            return
        }

        // 9. UI-07 Fail once then succeed on retry (status 400 avoids SwiftAISDK internal retry)
        if bodyString.contains("PROMPT_UI07_FAIL_ONCE") {
            Self.lock.lock()
            let currentFailCount = Self.ui07FailCount
            Self.ui07FailCount += 1
            Self.lock.unlock()
            if currentFailCount == 0 {
                let errorJSON = Data(#"{"error":{"message":"Simulated transient upstream failure","type":"invalid_request_error"}}"#.utf8)
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 400,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: errorJSON)
                client?.urlProtocolDidFinishLoading(self)
            } else {
                emitFinalAnswer("UI07_RETRY_RECOVERY_COMPLETE")
            }
            return
        }

        // 10. UI-08 Conversational MCP lifecycle Turn 1 & Turn 2
        if bodyString.contains("PROMPT_UI08_MCP_TURN_2") {
            if bodyString.contains("ui08-mcp-call-2") {
                emitFinalAnswer("UI08_MCP_TURN_2_COMPLETE: ECHO_PONG_OK:turn2")
            } else {
                emitToolCall(
                    id: "ui08-mcp-call-2",
                    name: "mcp__hanlin_echo_mcp__echo_ping",
                    arguments: #"{"message":"turn2"}"#
                )
            }
            return
        }

        if bodyString.contains("PROMPT_UI08_MCP_TURN_1") {
            if bodyString.contains("ui08-mcp-call-1") {
                emitFinalAnswer("UI08_MCP_TURN_1_COMPLETE: ECHO_PONG_OK:turn1")
            } else if bodyString.contains("ui08-mcp-install") {
                emitToolCall(
                    id: "ui08-mcp-call-1",
                    name: "mcp__hanlin_echo_mcp__echo_ping",
                    arguments: #"{"message":"turn1"}"#
                )
            } else {
                let archivePath = AgentRuntimeUIAcceptanceProvider.sampleMCPArchiveURL().path
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                emitToolCall(
                    id: "ui08-mcp-install",
                    name: "manage_mcp_servers",
                    arguments: "{\"action\":\"install\",\"package_spec\":\"\(archivePath)\",\"entry_point\":\"server.mjs\"}"
                )
            }
            return
        }

        Self.lock.lock()
        let index = Self.responseIndex
        Self.responseIndex += 1
        Self.lock.unlock()

        let payload: [String: Any]
        if AgentRuntimeUIAcceptanceProvider.isSkillsEnabled {
            if index == 0 {
                let arguments = #"{"skill_id":"acceptance_skill"}"#
                payload = [
                    "choices": [[
                        "delta": [
                            "tool_calls": [[
                                "index": 0,
                                "id": "ui-load-skill-call",
                                "type": "function",
                                "function": [
                                    "name": "load_skill",
                                    "arguments": arguments
                                ]
                            ]]
                        ],
                        "finish_reason": "tool_calls"
                    ]]
                ]
            } else if index == 1 {
                let arguments = #"{"query":"web"}"#
                payload = [
                    "choices": [[
                        "delta": [
                            "tool_calls": [[
                                "index": 0,
                                "id": "ui-tool-search-call",
                                "type": "function",
                                "function": [
                                    "name": "tool_search",
                                    "arguments": arguments
                                ]
                            ]]
                        ],
                        "finish_reason": "tool_calls"
                    ]]
                ]
            } else if index == 2 {
                let arguments = #"{"code":"<h1>Acceptance Web Surface</h1><p>Embedded result rendered</p>","result_presentation":"card"}"#
                payload = [
                    "choices": [[
                        "delta": [
                            "tool_calls": [[
                                "index": 0,
                                "id": "ui-web-call",
                                "type": "function",
                                "function": [
                                    "name": "create_web_view",
                                    "arguments": arguments
                                ]
                            ]]
                        ],
                        "finish_reason": "tool_calls"
                    ]]
                ]
            } else {
                payload = [
                    "choices": [[
                        "delta": ["content": "AGENT_SKILLS_EMBEDDED_ACCEPTANCE_COMPLETE"],
                        "finish_reason": "stop"
                    ]]
                ]
            }
        } else if index == 0 {
            let arguments = #"{"source":"print('should-not-run')","unexpected":true}"#
            payload = [
                "choices": [[
                    "delta": [
                        "tool_calls": [[
                            "index": 0,
                            "id": "ui-python-invalid-call",
                            "type": "function",
                            "function": [
                                "name": "execute_local_python_code",
                                "arguments": arguments
                            ]
                        ]]
                    ],
                    "finish_reason": "tool_calls"
                ]]
            ]
        } else if index == 1 {
            let arguments = #"{"source":"print('ui-tool-ok')"}"#
            payload = [
                "choices": [[
                    "delta": [
                        "tool_calls": [[
                            "index": 0,
                            "id": "ui-python-recovery-call",
                            "type": "function",
                            "function": [
                                "name": "execute_local_python_code",
                                "arguments": arguments
                            ]
                        ]]
                    ],
                    "finish_reason": "tool_calls"
                ]]
            ]
        } else {
            payload = [
                "choices": [[
                    "delta": ["content": "AGENT_UI_ACCEPTANCE_COMPLETE"],
                    "finish_reason": "stop"
                ]]
            ]
        }

        emitPayload(payload)
    }

    override func stopLoading() {
        isStopped = true
    }

    private func emitToolCall(id: String, name: String, arguments: String) {
        let payload: [String: Any] = [
            "choices": [[
                "delta": [
                    "tool_calls": [[
                        "index": 0,
                        "id": id,
                        "type": "function",
                        "function": [
                            "name": name,
                            "arguments": arguments
                        ]
                    ]]
                ],
                "finish_reason": "tool_calls"
            ]]
        ]
        emitPayload(payload)
    }

    private func emitFinalAnswer(_ text: String) {
        let payload: [String: Any] = [
            "choices": [[
                "delta": ["content": text],
                "finish_reason": "stop"
            ]]
        ]
        emitPayload(payload)
    }

    private func emitPayload(_ payload: [String: Any]) {
        guard let encoded = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return }
        let body = Data("data: \(String(decoding: encoded, as: UTF8.self))\n\ndata: [DONE]\n\n".utf8)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream", "x-request-id": "ui-acceptance"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    private func handlePistonExecute() {
        let body = Data(#"{"run":{"stdout":"Code output: 42\n","stderr":""}}"#.utf8)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    private func handleWikiPage() {
        let html = """
        <!doctype html>
        <html>
        <head><title>Hanlin Reference Source</title></head>
        <body>
        <article>Hanlin is an iOS and iPadOS native AI client supporting classic chat bubbles, web search citations, and MCP tools. Detailed citation paragraph for extraction with more than one hundred characters of content so SwiftSoup extracts the article tag cleanly.</article>
        </body>
        </html>
        """
        let body = Data(html.utf8)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/html; charset=utf-8"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    private func handleSkillsDownload() {
        let tempZip = FileManager.default.temporaryDirectory.appendingPathComponent("url-skill-\(UUID().uuidString).zip")
        if let archive = try? Archive(url: tempZip, accessMode: .create) {
            let skillMD = """
            ---
            name: ui-url-skill
            description: Deterministic skill downloaded from URL.
            ---

            # URL Skill Instructions
            Loaded from URL.
            """
            let skillMDData = Data(skillMD.utf8)
            try? archive.addEntry(with: "SKILL.md", type: .file, uncompressedSize: UInt32(skillMDData.count), provider: { position, size in
                skillMDData.subdata(in: position..<(position + size))
            })
            let refData = Data("URL Guide Content\n".utf8)
            try? archive.addEntry(with: "references/url-guide.md", type: .file, uncompressedSize: UInt32(refData.count), provider: { position, size in
                refData.subdata(in: position..<(position + size))
            })
        }
        let zipData = (try? Data(contentsOf: tempZip)) ?? Data()
        try? FileManager.default.removeItem(at: tempZip)

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "application/zip",
                "Content-Length": "\(zipData.count)"
            ]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: zipData)
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func extractBodyData(from request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}
