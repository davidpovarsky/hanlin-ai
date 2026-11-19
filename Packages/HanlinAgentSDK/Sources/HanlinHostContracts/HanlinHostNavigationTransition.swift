import Foundation
import HanlinPlatformContracts

/// An original host acknowledgement correlated with the exact session that requested it.
/// A successor is issued by the same live host only after the requested native destination
/// is mounted and its resulting context is observed. It is not a permission grant.
public struct HanlinHostNavigationReceipt: Codable, Hashable, Sendable {
    public let originalSession: HanlinHostSession
    public let result: HanlinHostNavigationResult
    public let successorSession: HanlinHostSession?

    public init(originalSession: HanlinHostSession, result: HanlinHostNavigationResult,
                successorSession: HanlinHostSession? = nil) {
        self.originalSession = originalSession
        self.result = result
        self.successorSession = successorSession
    }

    public var presentationAcknowledged: Bool { result.presentationAcknowledged }

    /// Structural correlation only. The dispatcher separately checks the live host context
    /// after its await; a decoded receipt alone cannot establish current authority.
    public func validate(for destination: HanlinHostDestination, session: HanlinHostSession) throws {
        guard originalSession == session, destination.context == session.context else {
            throw HanlinHostError.resultMismatch
        }
        try result.validate(for: destination)
        if let successor = successorSession {
            guard result.presentationAcknowledged,
                  successor.id != session.id,
                  successor.conversationID == session.conversationID,
                  successor.context.namespace == session.context.namespace,
                  successor.context.sceneID == session.context.sceneID,
                  successor.context.generation != session.context.generation else {
                throw HanlinHostError.resultMismatch
            }
        }
    }
}

/// Additive Host API 1.2 capability for navigation that changes the content context.
/// Existing HostIntegration.open retains its strict unchanged-context contract.
///
/// The host must fence the ORIGINAL session at the last native mutation boundary, correlate
/// the exact request with its visible scene acknowledgement, and issue a successor only
/// from that observed result. Unrelated account/workspace/scene changes are never navigation.
/// Queued is not presented and must not issue a successor. Cancellation or a thrown result
/// after entry cannot establish that no effect occurred; retain the original host receipt.
///
/// The host owns session lifecycle: stop the old AgentSession and construct any continuation
/// using the existing engine/store with this new host-issued identity. Never mutate an
/// AgentSession identity, reuse its old catalog/consent, or silently retry an uncertain route.
public protocol HanlinHostNavigationTransitionSource: HanlinHostIntegration {
    func openWithContextTransition(_ destination: HanlinHostDestination,
                                   session: HanlinHostSession) async throws -> HanlinHostNavigationReceipt
}
