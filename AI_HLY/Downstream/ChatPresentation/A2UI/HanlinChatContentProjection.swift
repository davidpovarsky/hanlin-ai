#if HANLIN_A2UI_POC
import Foundation
import SwiftUI

/// Read-only presentation of canonical, already-admitted model output. This is neither a
/// wire envelope nor transcript storage. The SDK adapter supplies order and stable IDs;
/// prose and fenced JSON never acquire Surface authority here.
@MainActor
final class HanlinChatContentProjection {
    struct Part: Identifiable {
        enum Content {
            case markdown(String)
            case surface(HanlinA2UIResultKey)
        }
        let id: UUID
        let content: Content
    }

    let runID: UUID
    let messageID: UUID
    let parts: [Part]
    let plainText: String
    private weak var store: HanlinA2UIResultStore?

    init?(runID: UUID, messageID: UUID, parts: [Part], store: HanlinA2UIResultStore) {
        guard !parts.isEmpty, parts.count <= 128, Set(parts.map(\.id)).count == parts.count else { return nil }
        var text = ""
        var bytes = 0
        for part in parts {
            switch part.content {
            case .markdown(let markdown):
                bytes += markdown.utf8.count
                guard bytes <= 1_048_576 else { return nil }
                text += markdown
            case .surface(let key):
                guard key.runID == runID, key.resultID == part.id,
                      key.origin == .model(messageID: messageID),
                      let projection = store.projection(for: key), !projection.isClosed else { return nil }
            }
        }
        self.runID = runID
        self.messageID = messageID
        self.parts = parts
        self.plainText = text
        self.store = store
    }

    func surface(for part: Part) -> HanlinA2UIResultProjection? {
        guard case .surface(let key) = part.content,
              parts.contains(where: { candidate in
                  guard candidate.id == part.id, case .surface(let registered) = candidate.content else { return false }
                  return registered == key
              }),
              let projection = store?.projection(for: key), !projection.isClosed else { return nil }
        return projection
    }
}

/// Injection only. Replacing this value for a new stream snapshot cannot revive a key's
/// discarded generation. The canonical session remains responsible for mutation/replay.
@MainActor
final class HanlinChatContentProjectionSource {
    private let messages: [UUID: HanlinChatContentProjection]

    init?(messages: [HanlinChatContentProjection]) {
        guard messages.count <= 256, Set(messages.map(\.messageID)).count == messages.count else { return nil }
        self.messages = Dictionary(uniqueKeysWithValues: messages.map { ($0.messageID, $0) })
    }

    func projection(runID: UUID?, messageID: UUID, text: String) -> HanlinChatContentProjection? {
        guard let runID, let message = messages[messageID], message.runID == runID,
              message.plainText == text else { return nil }
        return message
    }
}

extension EnvironmentValues {
    @Entry var hanlinChatContentProjectionSource: HanlinChatContentProjectionSource? = nil
}
#endif
