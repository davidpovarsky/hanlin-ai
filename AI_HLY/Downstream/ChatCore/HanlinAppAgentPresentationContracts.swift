import Foundation
import HanlinAgentCore
import HanlinHostContracts
import HanlinPlatformContracts

/// Immutable, host-issued row identity. The canonical run comes from its actual stream,
/// never from the legacy UI run UUID or a current-selection/prose lookup.
struct HanlinAppAgentRowReference: Codable, Hashable, Sendable {
    let rowID: UUID
    let uiRunID: UUID
    let messageID: UUID
}

struct HanlinAppAgentRowBinding: Hashable, Sendable {
    let reference: HanlinAppAgentRowReference
    let session: HanlinHostSession
    let canonicalRunID: UUID
}

/// A2UI owns the implementation and the observable source/store projected into ChatView.
/// The application owner calls these hooks outside View.body and preserves their original keys.
@MainActor
protocol HanlinAppAgentPresentationConsumer: AnyObject {
    var modelInstructions: String? { get }
    func installed(session: HanlinAgentSession)
    func validateCompleteParts(_ parts: [HanlinChatStructuredPart]) throws
    func receive(_ event: HanlinAgentEvent, binding: HanlinAppAgentRowBinding) throws
    func completed(_ completion: HanlinAgentRunCompletion)
    func hostResult(_ result: HanlinHostResultEvent)
    func hostProgress(_ progress: HanlinHostProgressEvent)
    func invalidated(_ session: HanlinHostSession)
    func producerStreamDrained(runID: UUID)
    func replay(_ record: HanlinConversationRecord, bindings: [HanlinAppAgentRowBinding]) throws
}

extension HanlinAppAgentPresentationConsumer {
    var modelInstructions: String? { nil }
    func hostResult(_ result: HanlinHostResultEvent) {}
    func hostProgress(_ progress: HanlinHostProgressEvent) {}
}
