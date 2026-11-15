import HanlinProductSplit
import SwiftData
import SwiftUI

/// UI delivery of the same already-accepted request. No URL decoding, mailbox acceptance,
/// Session/scene reinterpretation, database creation or authority is performed by this port.
extension EnvironmentValues {
    @Entry var hanlinAcceptedSplitOrigin: SplitBridgeRequest? = nil
    @Entry var hanlinSplitOriginDidMount: (@MainActor (SplitBridgeRequest, Bool) -> Void)? = nil
}

@MainActor
enum HanlinSplitOriginNavigation {
    enum Failure: Error { case unavailable }

    static func originalConversation(_ request: SplitBridgeRequest, context: ModelContext) throws -> ChatRecords {
        let id = request.chat
        let rows = try context.fetch(FetchDescriptor<ChatRecords>(predicate: #Predicate { $0.id == id }))
        guard rows.count == 1, let original = rows.first,
              original.modelContext === context else { throw Failure.unavailable }
        return original
    }
}
