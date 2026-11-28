import Foundation
@MainActor struct PendingIdentity: Identifiable, Sendable {
    nonisolated let submissionID: UUID
    var status: Int
    nonisolated var id: UUID { submissionID }
}
nonisolated func readIdentity(_ value: PendingIdentity) -> UUID { value.id }
