import Foundation
import HanlinChatCore
import SwiftData

enum AgentRuntimeUIAcceptanceProvider {
    static let environmentKey = "HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE"
    static let modelName = "hanlin-agent-acceptance"
    static let chatName = "Agent Acceptance Chat"

    static var isEnabled: Bool {
#if targetEnvironment(simulator)
        ProcessInfo.processInfo.environment[environmentKey] == "1"
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
        if index == 0 {
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
