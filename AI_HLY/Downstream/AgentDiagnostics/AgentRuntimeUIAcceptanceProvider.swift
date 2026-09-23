import Foundation
import HanlinChatCore
import HanlinMiniAppCore
import HanlinPlatformContracts
import SwiftData
import SwiftUI

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
                            presentation: .sheet,
                            origin: .chatUI
                        )
                    )
                    var enrichedPayload = payload ?? HanlinEmbeddedResultPayload()
                    if enrichedPayload.actions.isEmpty {
                        enrichedPayload.actions = [action]
                    }
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

    static func reset() {
        lock.lock()
        responseIndex = 0
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        AgentRuntimeUIAcceptanceProvider.isEnabled && request.url?.host == "agent.acceptance"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
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

        let encoded = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
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

    override func stopLoading() {}
}
