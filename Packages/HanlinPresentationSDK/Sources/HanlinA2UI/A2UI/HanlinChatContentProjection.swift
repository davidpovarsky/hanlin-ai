#if canImport(SwiftUI)
import Foundation
import SwiftUI

/// Read-only presentation of canonical, already-admitted model output. This is neither a
/// wire envelope nor transcript storage. The SDK adapter supplies order and stable IDs;
/// prose and fenced JSON never acquire Surface authority here.
@MainActor
public final class HanlinChatContentProjection {
    public struct Part: Identifiable {
        public enum Content {
            case markdown(String)
            case surface(HanlinA2UIResultKey)
            case unavailable
        }
        public let id: UUID
        public let content: Content

        public init(id: UUID, content: Content) {
            self.id = id
            self.content = content
        }
    }

    public let runID: UUID
    public let messageID: UUID
    public let parts: [Part]
    public let plainText: String
    private weak var store: HanlinA2UIResultStore?

    public init?(runID: UUID, messageID: UUID, parts: [Part], store: HanlinA2UIResultStore) {
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
            case .unavailable: break
            }
        }
        self.runID = runID
        self.messageID = messageID
        self.parts = parts
        self.plainText = text
        self.store = store
    }

    public func surface(for part: Part) -> HanlinA2UIResultProjection? {
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
public final class HanlinChatContentProjectionSource {
    private struct Identity: Hashable { let runID: UUID; let messageID: UUID }
    private let messages: [Identity: HanlinChatContentProjection]

    public init?(messages: [HanlinChatContentProjection]) {
        let entries = messages.map { (Identity(runID: $0.runID, messageID: $0.messageID), $0) }
        guard messages.count <= 256, Set(entries.map(\.0)).count == messages.count else { return nil }
        self.messages = Dictionary(uniqueKeysWithValues: entries)
    }

    public func projection(runID: UUID?, messageID: UUID, text: String) -> HanlinChatContentProjection? {
        guard let runID, let message = registeredProjection(runID: runID, messageID: messageID),
              message.plainText == text else { return nil }
        return message
    }

    public func registeredProjection(runID: UUID, messageID: UUID) -> HanlinChatContentProjection? {
        messages[Identity(runID: runID, messageID: messageID)]
    }
}

#endif
