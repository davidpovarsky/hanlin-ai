import Foundation
import HanlinChatCore
import HanlinMiniAppCore
import HanlinPlatformContracts
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
            context.insert(AllModels(
                name: modelName,
                displayName: "Agent Acceptance",
                position: 0,
                company: "ACCEPTANCE",
                supportsTextGen: true,
                supportsToolUse: true
            ))
            context.insert(APIKeys(
                name: "Agent Acceptance",
                company: "ACCEPTANCE",
                key: "acceptance-only",
                requestURL: "https://agent.acceptance/v1/chat/completions",
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

    static func makeChatEngine() -> HanlinChatEngine {
        guard isEnabled else { return HanlinChatEngine() }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AgentRuntimeUIAcceptanceURLProtocol.self]
        return HanlinChatEngine(sessionConfiguration: configuration)
    }
}

private final class AgentRuntimeUIAcceptanceURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var responseIndex = 0
    private var isStopped = false

    static func reset() {
        lock.lock()
        responseIndex = 0
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        AgentRuntimeUIAcceptanceProvider.isEnabled && (request.url?.host == "agent.acceptance" || request.url?.host == "skills.acceptance")
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if request.url?.host == "skills.acceptance" {
            handleSkillsDownload()
            return
        }

        let bodyData = Self.extractBodyData(from: request)
        let bodyString = String(decoding: bodyData, as: UTF8.self)

        // 1. Delayed Run A for stop cancellation test
        if bodyString.contains("START_DELAYED_RUN_A") {
            for _ in 0..<50 {
                if isStopped { return }
                Thread.sleep(forTimeInterval: 0.1)
            }
            if isStopped { return }
            emitFinalAnswer("RUN_A_UNEXPECTED_COMPLETION")
            return
        }

        // 2. Run B immediately completes
        if bodyString.contains("START_RUN_B") {
            emitFinalAnswer("RUN_B_COMPLETE")
            return
        }

        // 3. Next turn skill loading test
        if bodyString.contains("ui-next-turn-skill") || bodyString.contains("NEXT_TURN_SKILL") {
            if bodyString.contains("tool_calls") || bodyString.contains("NEXT_TURN_SKILL") {
                emitFinalAnswer("NEXT_TURN_SKILL_MARKER: Skill loaded successfully!")
            } else {
                emitToolCall(id: "ui-next-turn-load", name: "load_skill", arguments: #"{"skill_id":"ui-next-turn-skill"}"#)
            }
            return
        }

        // 4. Calculate 6*7 without user nudge
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
            try? archive.addEntry(with: "SKILL.md", type: .file, uncompressedSize: Int64(skillMDData.count), provider: { position, size in
                skillMDData.subdata(in: position..<(position + size))
            })
            let refData = Data("URL Guide Content\n".utf8)
            try? archive.addEntry(with: "references/url-guide.md", type: .file, uncompressedSize: Int64(refData.count), provider: { position, size in
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
