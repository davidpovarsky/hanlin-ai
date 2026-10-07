// Packages/HanlinAgentUIAdapter/Sources/HanlinAgentUIAdapter/HanlinAgentUIRuntimeAdapter.swift
import Foundation
import AgentUI
import HanlinPlatformContracts

@MainActor
public final class HanlinAgentUIRuntimeAdapter: AgentUIRuntimeAdapter {
    public init() {}

    public func send(_ request: AgentSendRequest) -> AsyncThrowingStream<AgentUIEvent, Error> {
        let messageID = AgentMessageID()
        let requestID = request.requestID

        return AsyncThrowingStream { continuation in
            Task {
                continuation.yield(.requestStarted(requestID: requestID))
                continuation.yield(.assistantMessageStarted(messageID: messageID))

                // Hanlin Agent reasoning step
                continuation.yield(
                    .activityStarted(
                        messageID: messageID,
                        item: AgentActivityItem(
                            kind: .reasoning,
                            status: .running,
                            title: "Hanlin Agent evaluating prompt..."
                        )
                    )
                )

                try? await Task.sleep(nanoseconds: 80_000_000)

                continuation.yield(
                    .activityCompleted(messageID: messageID, itemID: AgentActivityID("reasoning"))
                )

                // If web search is requested
                if request.enableWebSearch {
                    continuation.yield(
                        .activityStarted(
                            messageID: messageID,
                            item: AgentActivityItem(
                                kind: .webSearch(query: request.prompt),
                                status: .completed,
                                title: "Searched Hanlin knowledge base and web",
                                sources: [
                                    AgentSource(title: "Hanlin Core Documentation", url: "https://hanlin.ai/docs")
                                ]
                            )
                        )
                    )
                }

                // Streaming answer text
                let responsePrefix = "Hanlin Agent response for: "
                continuation.yield(.assistantTextDelta(messageID: messageID, text: responsePrefix))
                continuation.yield(.assistantTextDelta(messageID: messageID, text: request.prompt))
                continuation.yield(.assistantTextDelta(messageID: messageID, text: "\n\nIntegrated via AgentUI SDK."))

                continuation.yield(.requestCompleted(requestID: requestID))
                continuation.finish()
            }
        }
    }

    public func cancel(requestID: AgentRequestID) async {}
}
