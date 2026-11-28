import Foundation
import HanlinPlatformContracts

/// Original live surface provenance. Codable replay of this value never restores admission.
public struct HanlinHostInteractionOrigin: Codable, Hashable, Sendable {
    public let session: HanlinHostSession
    public let runID: UUID
    public let messageID: UUID
    public let partID: UUID
    public init(session: HanlinHostSession, runID: UUID, messageID: UUID, partID: UUID) {
        self.session = session; self.runID = runID; self.messageID = messageID; self.partID = partID
    }
}

public struct HanlinHostInteractionRequest: Sendable {
    public let requestID: UUID
    public let origin: HanlinHostInteractionOrigin
    public let actionID: String
    public let arguments: HanlinJSONValue
    public init(requestID: UUID = UUID(), origin: HanlinHostInteractionOrigin, actionID: String, arguments: HanlinJSONValue) {
        self.requestID = requestID; self.origin = origin; self.actionID = actionID; self.arguments = arguments
    }
}

/// An authorized input projection, not a tool grant or completed effect.
public struct HanlinHostInteractionContinuation: Sendable {
    public let userMessage: String
    public init(userMessage: String) { self.userMessage = userMessage }
}

/// Optional host-owned action admission. Must validate action/schema/current policy and perform
/// no business mutation here. The resulting turn uses the existing canonical engine/tool authority.
public protocol HanlinHostInteractionSource: Sendable {
    func prepareInteraction(_ request: HanlinHostInteractionRequest) async throws -> HanlinHostInteractionContinuation
}
