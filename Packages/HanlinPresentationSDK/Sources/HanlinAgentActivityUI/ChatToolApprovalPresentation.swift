import Foundation


/// An immutable presentation of the Host's verified request. Only its original
/// continuation can decide; an activity row never synthesizes permission.
public struct ChatToolApprovalPresentation {
    public let requestID: String
    public let callID: String
    public let toolName: String
    public let reviewText: String
    public var remembersDecision: Bool = false
    public let answer: (Bool) -> Void

    public init(
        requestID: String,
        callID: String,
        toolName: String,
        reviewText: String,
        remembersDecision: Bool = false,
        answer: @escaping (Bool) -> Void
    ) {
        self.requestID = requestID
        self.callID = callID
        self.toolName = toolName
        self.reviewText = reviewText
        self.remembersDecision = remembersDecision
        self.answer = answer
    }
}
