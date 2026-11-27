import Foundation
import HanlinAgentCore
import HanlinChatCore
import HanlinPlatformContracts

@MainActor
enum HanlinOriginalToolResultStorage {
    struct Prepared {
        let modelText: String
        let userText: String
        let resultReference: String?
        let embeddedPayload: HanlinEmbeddedResultPayload?
        func output(isError: Bool) -> HanlinAISDKToolExecutionOutput {
            .init(modelText: modelText, resultReference: resultReference, isError: isError)
        }
    }
    static func prepare(_ result: NativeToolResult, session: AssistantCapabilitySession) -> Prepared {
        var modelText = result.modelText
        let userText = result.userText ?? result.modelText
        var resultRef: String? = nil
        var embeddedPayload = result.embeddedPayload

        // Large result store handling
        let shouldStore = result.fullResultPayload != nil
            || (result.isStoreEligible && result.modelText.utf8.count > 1024)
        if shouldStore {
            let payloadToStore = result.fullResultPayload ?? result.modelText
            let mimeType = result.fullResultMIMEType ?? "text/plain"
            if let ref = session.resultStore.store(payloadToStore, mimeType: mimeType) {
                resultRef = ref
                if let currentPayload = embeddedPayload {
                    embeddedPayload = HanlinEmbeddedResultPayload(
                        payload: currentPayload.payload,
                        resultReference: ref,
                        title: currentPayload.title,
                        metadata: currentPayload.metadata,
                        ownerID: currentPayload.ownerID,
                        actions: currentPayload.actions
                    )
                }
                modelText = """
                [Large result stored behind reference: \(ref) (\(payloadToStore.utf8.count) bytes)]
                Summary: \(String(result.modelText.prefix(200)))
                To inspect or paginate this result, call `read_tool_result(reference: "\(ref)", offset: 0, limit: 4096)`.
                """
            } else {
                // A storage resource error must not silently replace the full result with a summary.
                modelText = "[Full result could not be persisted: \(session.resultStore.lastStorageError ?? "explicit storage budget exceeded")]\n" + payloadToStore
            }
        }

        return .init(modelText: modelText, userText: userText,
                     resultReference: resultRef, embeddedPayload: embeddedPayload)
    }
}
