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
    static let dockFixturesEnvironmentKey = "HANLIN_DOCK_ACCEPTANCE_FIXTURES"
    static let modelName = "hanlin-agent-acceptance"
    static let secondaryModelName = "hanlin-gpt4o-acceptance"
    static let chatName = "Agent Acceptance Chat"

    static var isDockFixturesEnabled: Bool {
#if targetEnvironment(simulator)
        ProcessInfo.processInfo.environment[dockFixturesEnvironmentKey] == "1"
#else
        false
#endif
    }

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

    /// A separate opt-in simulator account seed. It never enables the HTTP
    /// acceptance protocol: the canonical SDK contacts the actual Google service.
    static var isLiveProviderEnabled: Bool {
#if (DEBUG || HANLIN_TESTING) && targetEnvironment(simulator)
        ProcessInfo.processInfo.environment["HANLIN_LIVE_GEMINI_ACCEPTANCE"] == "1"
#else
        false
#endif
    }

    /// An opt-in, task-owned disk container for authentic cold-reopen UI proof.
    /// Shipping storage and legacy fixture resets retain their existing behavior.
    static var phase2StoreID: UUID? {
#if (DEBUG || HANLIN_TESTING) && targetEnvironment(simulator)
        guard isEnabled || isLiveProviderEnabled,
              let value = ProcessInfo.processInfo.environment["HANLIN_PHASE2_STORE_ID"] else { return nil }
        return UUID(uuidString: value)
#else
        nil
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
#if (DEBUG || HANLIN_TESTING) && targetEnvironment(simulator)
        if isLiveProviderEnabled {
            configureLiveProviderIfRequested(context: context)
            return
        }
#endif
        guard isEnabled else { return }
        do {
            if phase2StoreID != nil, try !context.fetch(FetchDescriptor<ChatRecords>()).isEmpty { return }
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
                apiType: .openAI,
                autoProbeCapabilities: phase2StoreID == nil
            ))
            let now = Date()
            let acceptanceChat = ChatRecords(
                name: chatName,
                type: "chat",
                lastEdited: now,
                useModel: 0
            )
#if (DEBUG || HANLIN_TESTING) && targetEnvironment(simulator)
            if ProcessInfo.processInfo.environment["HANLIN_CANVAS_ACCEPTANCE_FIXTURES"] == "1" {
                let code = "print('CANVAS_LOCAL_RESULT_' + str(6 * 7))"
                acceptanceChat.canvas = CanvasData(title: "Canvas runtime acceptance",
                    content: code, type: "python", history: [code], index: 0)
            }
#endif
            context.insert(acceptanceChat)
#if (DEBUG || HANLIN_TESTING) && targetEnvironment(simulator)
            if isSkillsEnabled,
               ProcessInfo.processInfo.environment["HANLIN_EMBEDDED_FALLBACK_FIXTURE"] == "1" {
                // Historical rendering fixture only: original message/AgentRun/
                // native fallback views, no live model or invented tool effect.
                let groupID = UUID()
                let item = AgentTranscriptItem(sequence: 0, kind: .userVisibleToolResult,
                    callID: "unresolved-original-result", toolName: "fixture_unavailable_handler",
                    resultRendererKind: .modernNative, completedAt: now, status: .completed,
                    nativeUIBlocks: [NativeUIBlock(type: .text,
                        body: "UNRESOLVED_HANDLER_NATIVE_FALLBACK_CONTENT")],
                    visibilityAfterCompletion: .remainInChat,
                    canonicalEmbeddedPresentation: HanlinEmbeddedPresentationDescriptor(
                        handler: "hanlin.acceptance.missing:card",
                        expansion: HanlinExpansionDescriptor(supportedModes: [.sheet, .fullScreen],
                            expandedHandler: "hanlin.acceptance.missing:expanded")),
                    embeddedResultPayload: HanlinEmbeddedResultPayload(ownerID: "hanlin.acceptance.missing"))
                let message = ChatMessages(role: "assistant", text: "UNRESOLVED_RESULT_ORIGINAL_MESSAGE",
                    modelDisplayName: "Historical rendering fixture", groupID: groupID, record: acceptanceChat)
                message.agentRun = AgentRun(groupID: groupID, completedAt: now, status: .completed,
                    transcriptItems: [item], finalAnswer: message.text)
                context.insert(message)
            }
            if ProcessInfo.processInfo.environment["HANLIN_CONTEXTUAL_TEXT_ACCEPTANCE"] == "1" {
                context.insert(ChatMessages(role: "assistant", text: "CONTEXT_TEXT_ORIGINAL_428: The selected message stays in its original conversation.",
                    modelDisplayName: "Agent Acceptance", record: acceptanceChat))
            }
#endif
            if isDockFixturesEnabled {
                for prompt in try context.fetch(FetchDescriptor<PromptRepo>()) {
                    context.delete(prompt)
                }
                context.insert(AllModels(
                    name: secondaryModelName,
                    displayName: "GPT-4o Acceptance",
                    position: 1,
                    company: "OPENAI",
                    supportsTextGen: true,
                    supportsMultimodal: true,
                    supportsReasoning: false,
                    supportReasoningChange: false,
                    supportsToolUse: true
                ))
                context.insert(APIKeys(
                    name: "OpenAI Acceptance",
                    company: "OPENAI",
                    key: "acceptance-only",
                    requestURL: "https://agent.acceptance/v1/chat/completions",
                    isHidden: false,
                    apiType: .openAI
                ))
                context.insert(ChatRecords(
                    name: "Architecture Review Notes",
                    type: "chat",
                    lastEdited: now.addingTimeInterval(-60),
                    useModel: 0
                ))
                context.insert(ChatRecords(
                    name: "MCP Server Diagnostics",
                    type: "chat",
                    lastEdited: now.addingTimeInterval(-120),
                    useModel: 0
                ))
                context.insert(ChatRecords(
                    name: "Older Archived Thread",
                    type: "chat",
                    lastEdited: now.addingTimeInterval(-3600),
                    isPinned: true,
                    useModel: 0
                ))
                context.insert(PromptRepo(
                    name: "Code Review Checklist",
                    content: "Review architecture boundaries and RTL layout parity.",
                    position: 0,
                    timestamp: now
                ))
                context.insert(PromptRepo(
                    name: "RTL Layout Audit",
                    content: "Verify leading and trailing margins in Hebrew and Arabic.",
                    position: 1,
                    timestamp: now.addingTimeInterval(-30)
                ))
            }
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
                                    .font(HanlinTypography.headline)
                                    .accessibilityIdentifier("acceptance_embedded_surface")
                                Text("Arbitrary Mini App Result: \(handler)")
                                    .font(HanlinTypography.caption)
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

#if (DEBUG || HANLIN_TESTING) && targetEnvironment(simulator)
    @MainActor
    private static func configureLiveProviderIfRequested(context: ModelContext) {
        guard isLiveProviderEnabled, !isEnabled, phase2StoreID != nil else {
            fatalError("Live acceptance requires its own store and cannot enable an HTTP fixture")
        }
        do {
            // Reopen the same real conversation without reseeding its account or history.
            if try !context.fetch(FetchDescriptor<ChatRecords>()).isEmpty { return }
            let support = try FileManager.default.url(for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: false)
            let file = support.appending(path: "HanlinLiveProviderAcceptance/provider.json")
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 8192 else {
                fatalError("Live acceptance credential input is not a bounded regular file")
            }
            let data = try Data(contentsOf: file)
            guard let input = try JSONSerialization.jsonObject(with: data) as? [String: String],
                  let key = input["apiKey"], !key.isEmpty,
                  input["model"] == "gemini-3.8-flash" else {
                fatalError("Live acceptance credential input is unavailable")
            }
            // Only the existing APIKeys model receives the secret. The input is
            // consumed once; the runner removes the entire owned simulator after proof.
            try FileManager.default.removeItem(at: file)
            context.insert(UserInfo())
            context.insert(AllModels(name: "gemini-3.8-flash", displayName: "Gemini 3.8 Flash",
                position: 0, company: "GOOGLE", supportsTextGen: true, supportsMultimodal: true,
                supportsReasoning: true, supportReasoningChange: true, supportsToolUse: true))
            context.insert(APIKeys(name: "Google live acceptance", company: "GOOGLE", key: key,
                requestURL: "https://generativelanguage.googleapis.com/v1beta",
                isHidden: false, apiType: .gemini, autoProbeCapabilities: false))
            context.insert(ChatRecords(name: chatName, type: "chat", useModel: 0,
                maxTokens: 4096, systemMessage: "Use the requested original tool with exactly the supplied arguments. Do not use remote execution, network, files, or other tools except tool_search to discover the requested tool. After its result, return the requested stdout verbatim.",
                useSystemMessage: false))
            try context.save()
        } catch {
            // Never print input, account fields, or a decoding error containing credentials.
            fatalError("Live acceptance could not configure its isolated account")
        }
    }
#endif

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
    private nonisolated(unsafe) static var phase2Requests = 0
    private var isStopped = false

    static var observedPhase2Requests: Int {
        lock.lock(); defer { lock.unlock() }
        return phase2Requests
    }

    static func reset() {
        lock.lock()
        responseIndex = 0
        ui07FailCount = 0
        phase2Requests = 0
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard AgentRuntimeUIAcceptanceProvider.isEnabled,
              let host = request.url?.host else { return false }
        return host == "agent.acceptance" || host == "skills.acceptance" || host == "emkc.org"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if AgentRuntimeUIAcceptanceProvider.phase2StoreID != nil {
            Self.lock.lock(); Self.phase2Requests += 1; Self.lock.unlock()
        }
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

        // Match only the current user turn; old markers can remain in history.
        let body = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any]
        let messages = body?["messages"] as? [[String: Any]]
        let content = messages?.last(where: { $0["role"] as? String == "user" })?["content"]
        let currentText = (content as? String) ?? (content as? [[String: Any]])?.compactMap { $0["text"] as? String }.joined(separator: "\n") ?? ""
        func toolResult(_ callID: String) -> String? {
            guard let message = (messages ?? []).last(where: {
                $0["role"] as? String == "tool" && $0["tool_call_id"] as? String == callID
            }) else { return nil }
            if let text = message["content"] as? String { return text }
            return (message["content"] as? [[String: Any]])?
                .compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
#if (DEBUG || HANLIN_TESTING) && targetEnvironment(simulator)
        if let marker = currentText.range(of: "SHARE_DRAFT_[0-9A-F-]{36}", options: .regularExpression) {
            let nonce = String(currentText[marker].suffix(36))
            let verified = currentText.contains("UNSENT_PREEXISTING_" + nonce)
                && bodyString.contains("SHARED_FILE_" + nonce)
                && currentText.contains("https://example.org/hanlin-share?case=" + nonce)
            emitFinalAnswer(verified ? "SHARED_DRAFT_DELIVERED_" + nonce : "SHARED_DRAFT_CONTENT_MISSING")
            return
        }
#endif
#if (DEBUG || HANLIN_TESTING) && targetEnvironment(simulator)
        if AgentRuntimeUIAcceptanceProvider.isSkillsEnabled,
           ProcessInfo.processInfo.environment["HANLIN_EMBEDDED_RESULT_STRICT_ACCEPTANCE"] == "1",
           currentText.contains("EMBEDDED_FLOW_ACCEPTANCE") {
            func result(_ callID: String) -> String? {
                guard let output = (messages ?? []).last(where: {
                    $0["role"] as? String == "tool" && $0["tool_call_id"] as? String == callID
                }) else { return nil }
                if let text = output["content"] as? String { return text }
                return (output["content"] as? [[String: Any]])?
                    .compactMap { $0["text"] as? String }.joined(separator: "\n")
            }
            if let web = result("ui-web-call") {
                let valid = web.lowercased().contains("successfully") && web.lowercased().contains("render")
                emitFinalAnswer(valid ? "AGENT_SKILLS_EMBEDDED_ACCEPTANCE_COMPLETE" : "EMBEDDED_WEB_RESULT_NOT_VERIFIED")
            } else if let search = result("ui-tool-search-call") {
                guard search.contains("create_web_view") else {
                    emitFinalAnswer("EMBEDDED_TOOL_DISCOVERY_NOT_VERIFIED"); return
                }
                // The original advertised schema requires progress_summary for
                // this tool-capable model. Keep the Host's pre-consent validation.
                emitToolCall(id: "ui-web-call", name: "create_web_view",
                    arguments: #"{"code":"<h1>Acceptance Web Surface</h1><p>Embedded result rendered</p>","result_presentation":"card","progress_summary":"Render the requested web preview."}"#)
            } else if let skill = result("ui-load-skill-call") {
                let names = ((body?["tools"] as? [[String: Any]]) ?? []).compactMap {
                    ($0["function"] as? [String: Any])?["name"] as? String
                }
                guard skill.contains("loaded successfully"), names.contains("create_web_view") else {
                    emitFinalAnswer("EMBEDDED_SKILL_EXPOSURE_NOT_VERIFIED"); return
                }
                emitToolCall(id: "ui-tool-search-call", name: "tool_search", arguments: #"{"query":"web"}"#)
            } else {
                emitToolCall(id: "ui-load-skill-call", name: "load_skill", arguments: #"{"skill_id":"acceptance_skill"}"#)
            }
            return
        }
#endif
        // Only the HTTP model response is controlled. The real Host, consent,
        // OS URL delivery, App Group, MiniApps process and canonical broker run.
        if let marker = currentText.range(of: "PAIRED_(?:OPEN|CANCEL)_[0-9A-F-]{36}", options: .regularExpression) {
            let command = String(currentText[marker])
            let nonce = String(command.suffix(36))
            let cancel = command.hasPrefix("PAIRED_CANCEL_")
            let callID = "paired-original-" + nonce
            if let output = (messages ?? []).last(where: {
                $0["role"] as? String == "tool" && $0["tool_call_id"] as? String == callID
            }) {
                let content = output["content"] as? String ?? ""
                let verified = cancel
                    ? content.contains("did not provide a successful operation receipt")
                    : content.contains("PAIRED_VALUE_" + nonce)
                if !verified {
                    let reason = Self.classifyPairedFailure(content: content)
                    let mode = cancel ? "cancel" : "open"
                    print("[AgentRuntimeUIAcceptanceProvider] paired_return_diagnostic mode=\(mode) reason=\(reason)")
                }
                emitFinalAnswer(verified
                    ? (cancel ? "PAIRED_CANCEL_RETURN_" : "PAIRED_RETURN_VERIFIED_") + nonce
                    : "PAIRED_RESULT_NOT_VERIFIED")
            } else {
                emitToolCall(id: callID, name: "open_mini_app",
                    arguments: #"{"target":"hanlin.demo.swift-parity","action":"share.value","payload":null}"#)
            }
            return
        }

        if let marker = bodyString.range(of: "PHASE2_TOOL_A2UI_[0-9A-F-]{36}", options: .regularExpression) {
            let nonce = String(bodyString[marker]).replacingOccurrences(of: "PHASE2_TOOL_A2UI_", with: "")
            let callID = "phase2-a2ui-" + nonce
            let searchID = "phase2-a2ui-search-" + nonce
            if currentText.contains("phase2-tool-submit"), currentText.contains("Grace"),
               !currentText.contains("UNSENT_TOOL_A2UI_") {
                emitFinalAnswer("PHASE2_TOOL_ACTION_VERIFIED_" + nonce)
            } else if (messages ?? []).contains(where: { $0["role"] as? String == "tool" && $0["tool_call_id"] as? String == callID }) {
                emitFinalAnswer("PHASE2_TOOL_SURFACE_READY_" + nonce)
            } else if !(messages ?? []).contains(where: { $0["role"] as? String == "tool" && $0["tool_call_id"] as? String == searchID }) {
                // Follow the real deferred-tool contract before calling the native
                // presenter. The fixture must not bypass canonical discovery.
                emitToolCall(id: searchID, name: "tool_search", arguments: #"{"query":"present_a2ui","limit":1}"#)
            } else {
                let frames = [
                    #"{"version":"1.0","createSurface":{"surfaceId":"tool-form","catalogId":"https://a2ui.org/specification/v1_0/catalogs/basic/catalog.json"}}"#,
                    #"{"version":"1.0","updateDataModel":{"surfaceId":"tool-form","path":"/","value":{"name":"Ada"}}}"#,
                    #"{"version":"1.0","updateComponents":{"surfaceId":"tool-form","components":[{"id":"root","component":"Column","children":["name","submit"]},{"id":"name","component":"TextField","label":"Tool name","value":{"@path":"/name"}},{"id":"submit","component":"Button","child":"submitLabel","action":{"event":{"name":"phase2-tool-submit","context":{"name":{"@path":"/name"}}}}},{"id":"submitLabel","component":"Text","text":"Submit tool form"}]}}"#
                ]
                let arguments: [String: Any] = ["messages": frames, "result_presentation": "card",
                    "progress_summary": "Present the native tool form for review."]
                guard let data = try? JSONSerialization.data(withJSONObject: arguments) else {
                    client?.urlProtocol(self, didFailWithError: URLError(.cannotDecodeContentData)); return
                }
                emitToolCall(id: callID, name: "present_a2ui", arguments: String(decoding: data, as: UTF8.self))
            }
            return
        }
        if let marker = currentText.range(of: "PHASE2_REAL_PYTHON_[0-9A-F-]{36}", options: .regularExpression) {
            let nonce = String(currentText[marker]).replacingOccurrences(of: "PHASE2_REAL_PYTHON_", with: "")
            let resultMarker = "PHASE2_RESULT_" + nonce + ":3.14.6:42"
            let toolID = "phase2-python-" + nonce, loadID = "phase2-code-" + nonce
            let outputs = (messages ?? []).filter { $0["role"] as? String == "tool" }
            if let output = outputs.last(where: { $0["tool_call_id"] as? String == toolID }) {
                let text = (output["content"] as? String) ?? ""
                emitFinalAnswer(text.contains(resultMarker) ? "PHASE2_VERIFIED_" + nonce + ":3.14.6:42" : "PHASE2_EXECUTION_NOT_VERIFIED")
            } else if outputs.contains(where: { $0["tool_call_id"] as? String == loadID }) {
                let source = "import sys; print('PHASE2_RESULT_\(nonce):' + sys.version.split()[0] + ':' + str(6*7))"
                let arguments = try? JSONSerialization.data(withJSONObject: ["source": source,
                    "progress_summary": "Run the reviewed Python calculation."])
                emitToolCall(id: toolID, name: "execute_local_python_code", arguments: String(decoding: arguments ?? Data(), as: UTF8.self))
            } else { emitToolCall(id: loadID, name: "load_skill", arguments: #"{"skill_id":"code"}"#) }
            return
        }

        if let marker = currentText.range(of: "DIAGNOSTIC_CAPTURE_[0-9A-F-]{36}", options: .regularExpression) {
            emitFinalAnswer("CAPTURED_" + String(currentText[marker]))
            return
        }

        if bodyString.contains("RENDER_CODE_FENCES") {
            emitFinalAnswer("""
            Local renderer acceptance

            ```mermaid
            flowchart LR
            A["שלום🙂"] --> B["OAuth"]
            ```

            ```diff
            --- a/auth.ts
            +++ b/auth.ts
            @@ -1 +1 @@
            -old("שלום")
            +updated("שלום🙂")
            ```
            """)
            return
        }

        // 1. Run B immediately completes (must precede START_DELAYED_RUN_A since Run A remains in conversation history)
        if bodyString.contains("START_RUN_B") {
            emitFinalAnswer("RUN_B_COMPLETE")
            return
        }

        // 2. Delayed Run A for stop cancellation test
        if bodyString.contains("START_DELAYED_RUN_A") {
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/event-stream"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            DispatchQueue.global().async { [weak self] in
                // Keep the cancellable request alive through XCTest's real
                // accessibility/idle round trips; completion is not a fake stop.
                for _ in 0..<1200 {
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

        if bodyString.contains("PROMPT_CHAT_PRESENTATION") {
            emitFinalAnswer("alpha beta gamma\n\nשלום 👋🏽 **bold** and \\(E=mc^2\\).\n\n[Example](https://example.com)\n\nCHAT_PRESENTATION_READY")
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
                            "reasoning_content": "<think>Step 1: Let me think privately about internal CoT</think>\nVerifying arithmetic expression 6 * 7",
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

        // The controlled model must verify a fresh original tool result. Merely
        // finding "42" in loaded Skill instructions never proves Python ran.
        if currentText.contains("6*7") || currentText.contains("6 * 7") {
            if let output = toolResult("ui-python-call") {
                emitFinalAnswer(output.contains("HANLIN_LOCAL_PYTHON_RESULT:42")
                    ? "42 / LOCAL_PYTHON_COMPLETE" : "LOCAL_PYTHON_EXECUTION_NOT_VERIFIED")
            } else if let loaded = toolResult("ui-load-code-call") {
                guard loaded.contains("loaded successfully") else {
                    emitFinalAnswer("LOCAL_PYTHON_SKILL_NOT_VERIFIED"); return
                }
                emitToolCall(id: "ui-python-call", name: "execute_local_python_code",
                    arguments: #"{"source":"print('HANLIN_LOCAL_PYTHON_RESULT:' + str(6 * 7))","progress_summary":"Calculate the requested result using local Python."}"#)
            } else {
                emitToolCall(id: "ui-load-code-call", name: "load_skill", arguments: #"{"skill_id":"code"}"#)
            }
            return
        }

        if currentText == "Run the local Python acceptance tool and report the result." {
            if let output = toolResult("ui-python-recovery-call") {
                emitFinalAnswer(output.contains("ui-tool-ok")
                    ? "AGENT_UI_ACCEPTANCE_COMPLETE" : "LOCAL_PYTHON_RECOVERY_NOT_VERIFIED")
            } else if toolResult("ui-python-invalid-call") != nil {
                emitToolCall(id: "ui-python-recovery-call", name: "execute_local_python_code",
                    arguments: #"{"source":"print('ui-' + 'tool-ok')","progress_summary":"Run the corrected local Python request."}"#)
            } else if let loaded = toolResult("ui-load-code-call") {
                guard loaded.contains("loaded successfully") else {
                    emitFinalAnswer("LOCAL_PYTHON_SKILL_NOT_VERIFIED"); return
                }
                // Deliberately invalid extra argument; the valid recovery keeps
                // the same advertised progress schema and original tool.
                emitToolCall(id: "ui-python-invalid-call", name: "execute_local_python_code",
                    arguments: #"{"source":"print('should-not-run')","unexpected":true,"progress_summary":"Validate the requested Python arguments."}"#)
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

        if bodyString.contains("PROMPT_FIRST_TURN_HOME") {
            emitFinalAnswer("FIRST_TURN_HOME_COMPLETE")
            return
        }

        if bodyString.contains("PROMPT_OBSERVE_ACCEPTANCE") {
            emitFinalAnswer("OBSERVE_TURN_COMPLETE")
            return
        }

        // 7. UI-03 Search message and deduplicated citations
        if bodyString.contains("PROMPT_UI03_SEARCH_CITATIONS") {
            let hebrew = bodyString.contains("PROMPT_UI03_SEARCH_CITATIONS_HE")
            if bodyString.contains("ui03-read-2") {
                emitFinalAnswer(hebrew
                    ? "לפי המקור של Hanlin, החיפוש מציג תוצאות מסודרות והמקורות משולבים בתוך ההודעה. [מקור](https://agent.acceptance/wiki/hanlin#section) אפשר לפתוח את המקור ולחזור לתשובה. UI03_SEARCH_COMPLETE"
                    : "According to the Hanlin reference, classic search rows and citations are restored. [source](https://agent.acceptance/wiki/hanlin#section) UI03_SEARCH_COMPLETE")
            } else if bodyString.contains("ui03-read-1") {
                emitToolCall(
                    id: "ui03-read-2",
                    name: "read_web_page",
                    arguments: #"{"url":"https://agent.acceptance/wiki/hanlin#section","progress_summary":"Read the referenced section."}"#
                )
            } else if let output = toolResult("ui03-python-consent") {
                guard output.contains("UI03_LOCAL_RESULT_42") else {
                    emitFinalAnswer("UI03_LOCAL_PYTHON_NOT_VERIFIED"); return
                }
                emitToolCall(
                    id: "ui03-read-1",
                    name: "read_web_page",
                    arguments: #"{"url":"https://agent.acceptance/wiki/hanlin","progress_summary":"Read the requested reference page."}"#
                )
            } else if let loaded = toolResult("ui03-load-code") {
                guard loaded.contains("loaded successfully") else {
                    emitFinalAnswer("UI03_CODE_SKILL_NOT_VERIFIED"); return
                }
                emitToolCall(id: "ui03-python-consent", name: "execute_local_python_code",
                    arguments: #"{"source":"print('UI03_LOCAL_RESULT_' + str(6 * 7))","progress_summary":"Verify the requested local calculation before reading the sources."}"#)
            } else {
                emitToolCall(id: "ui03-load-code", name: "load_skill", arguments: #"{"skill_id":"code"}"#)
            }
            return
        }

        // UI-05 follows the real Skill/discovery/schema contracts, and only
        // reports completion after both original execution results arrive.
        if currentText.contains("PROMPT_UI05_RICH_CONTENT") {
            if let html = toolResult("ui05-html-1") {
                let verified = html.lowercased().contains("successfully") && html.lowercased().contains("render")
                    && toolResult("ui05-code-1")?.contains("Code output: 42") == true
                emitFinalAnswer(verified ? "Rich content and attachments verified. UI05_RICH_COMPLETE"
                    : "UI05_RENDER_RESULT_NOT_VERIFIED")
            } else if let discovery = toolResult("ui05-web-discovery") {
                guard discovery.contains("create_web_view") else {
                    emitFinalAnswer("UI05_WEB_DISCOVERY_NOT_VERIFIED"); return
                }
                emitToolCall(id: "ui05-html-1", name: "create_web_view",
                    arguments: #"{"code":"<h1>UI05 Interactive Card</h1><p>Rendered HTML surface</p>","result_presentation":"card","progress_summary":"Render the requested interactive HTML card."}"#)
            } else if let code = toolResult("ui05-code-1") {
                guard code.contains("Code output: 42") else {
                    emitFinalAnswer("UI05_PYTHON_RESULT_NOT_VERIFIED"); return
                }
                emitToolCall(id: "ui05-web-discovery", name: "tool_search",
                    arguments: #"{"query":"create_web_view","limit":1}"#)
            } else if let loaded = toolResult("ui05-load-code") {
                guard loaded.contains("loaded successfully") else {
                    emitFinalAnswer("UI05_SKILL_NOT_VERIFIED"); return
                }
                emitToolCall(id: "ui05-code-1", name: "execute_local_python_code",
                    arguments: #"{"source":"print('Code output: ' + str(6 * 7))","result_presentation":"card","progress_summary":"Run local Python and present its code result."}"#)
            } else {
                emitToolCall(id: "ui05-load-code", name: "load_skill", arguments: #"{"skill_id":"code"}"#)
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
                let arguments = #"{"code":"<h1>Acceptance Web Surface</h1><p>Embedded result rendered</p>","result_presentation":"card","progress_summary":"Render the requested web preview."}"#
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
            let arguments = #"{"source":"print('ui-tool-ok')","progress_summary":"Run the corrected local Python request."}"#
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

    private static func classifyPairedFailure(content: String) -> String {
        if content.isEmpty { return "empty_tool_output" }
        if content.contains("outcome is uncertain") { return "uncertain_outcome" }
        if content.contains("was not dispatched") { return "not_dispatched" }
        if content.contains("did not provide a successful operation receipt") { return "missing_operation_receipt" }
        if content.contains("PAIRED_VALUE_") { return "mismatched_value_nonce" }
        return "unexpected_tool_output"
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
