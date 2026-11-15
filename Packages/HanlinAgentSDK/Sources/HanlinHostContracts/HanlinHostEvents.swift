import Foundation
import HanlinPlatformContracts

/// Immutable correlation captured before entering host execution. This is identity, not authority.
public struct HanlinHostCallIdentity: Codable, Hashable, Sendable {
    public let session: HanlinHostSession
    public let runID: UUID
    public let step: Int
    public let providerCallID: String
    public let invocationID: HanlinToolInvocationID
    public let logicalToolID: HanlinLogicalToolID

    public init(session: HanlinHostSession, runID: UUID, step: Int, providerCallID: String,
                invocationID: HanlinToolInvocationID, logicalToolID: HanlinLogicalToolID) {
        self.session = session; self.runID = runID; self.step = step
        self.providerCallID = providerCallID; self.invocationID = invocationID; self.logicalToolID = logicalToolID
    }
}

public struct HanlinHostProgressEvent: Sendable {
    public let call: HanlinHostCallIdentity
    public let progress: HanlinToolProgressEvent

    public init(call: HanlinHostCallIdentity, progress: HanlinToolProgressEvent) throws {
        guard call.invocationID == progress.invocationID else { throw HanlinHostError.resultMismatch }
        self.call = call; self.progress = progress
    }
}

/// The dispatcher assigns resultID once per reserved call, including duplicate receipt delivery.
/// Presentation generation is owned separately by the UI. Neither ID authorizes an action.
public struct HanlinHostResultEvent: Sendable {
    public let resultID: UUID
    public let call: HanlinHostCallIdentity
    public let result: HanlinHostExecutionResult

    public init(resultID: UUID, call: HanlinHostCallIdentity, result: HanlinHostExecutionResult) throws {
        guard result.context == call.session.context, result.result.invocationID == call.invocationID,
              result.result.logicalToolID == call.logicalToolID else { throw HanlinHostError.resultMismatch }
        self.resultID = resultID; self.call = call; self.result = result
    }
}
