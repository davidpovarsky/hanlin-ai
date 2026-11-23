import Foundation

struct MCPChatSelectionScope: Hashable, Sendable {
    let chatID: UUID
    let temporary: Bool
}

struct MCPChatSelectionMutation: Sendable {
    let affectedScopes: Set<MCPChatSelectionScope>
    static let unchanged = Self(affectedScopes: [])
}

struct MCPChatServerSelectionIntent: Sendable {
    let serverID: UUID
    let isSelected: Bool
}

struct MCPChatSelectionIntentResult: Sendable {
    let serverIDs: Set<UUID>
    let mutation: MCPChatSelectionMutation
}

actor MCPChatSelectionStore {
    private let fileLayout: MCPFileLayout
    private var temporarySelections: [UUID: Set<UUID>] = [:]

    init(fileLayout: MCPFileLayout = .default) {
        self.fileLayout = fileLayout
    }

    func selection(chatID: UUID, temporary: Bool = false) throws -> Set<UUID>? {
        if temporary { return temporarySelections[chatID] }
        return try load()[chatID]?.serverIDs
    }

    @discardableResult
    func setSelection(_ serverIDs: Set<UUID>, chatID: UUID, temporary: Bool = false) throws -> MCPChatSelectionMutation {
        let scope = MCPChatSelectionScope(chatID: chatID, temporary: temporary)
        if temporary {
            guard temporarySelections[chatID] != serverIDs else { return .unchanged }
            temporarySelections[chatID] = serverIDs
            return .init(affectedScopes: [scope])
        }
        var selections = try load()
        // Absent means defaults; explicitly stored [] means disabled for this chat.
        guard selections[chatID]?.serverIDs != serverIDs else { return .unchanged }
        selections[chatID] = MCPChatSelection(chatID: chatID, serverIDs: serverIDs)
        try save(selections)
        return .init(affectedScopes: [scope])
    }

    /// Read/modify/commit is one non-suspending actor operation. Defaults seed
    /// only an absent record; an explicitly stored empty selection stays empty.
    func applySelectionIntent(
        _ intent: MCPChatServerSelectionIntent,
        chatID: UUID,
        temporary: Bool = false,
        defaultServerIDs: Set<UUID>
    ) throws -> MCPChatSelectionIntentResult {
        var selections = temporary ? [:] : try load()
        let stored = temporary ? temporarySelections[chatID] : selections[chatID]?.serverIDs
        var ids = stored ?? defaultServerIDs
        if intent.isSelected { ids.insert(intent.serverID) } else { ids.remove(intent.serverID) }
        // Absent -> explicit (even []) is a real storage transition, matching
        // setSelection. Repeating the same intent on that record is a no-op.
        guard stored != ids else { return .init(serverIDs: ids, mutation: .unchanged) }
        if temporary {
            temporarySelections[chatID] = ids
        } else {
            selections[chatID] = MCPChatSelection(chatID: chatID, serverIDs: ids)
            try save(selections)
        }
        return .init(serverIDs: ids, mutation: .init(affectedScopes: [.init(chatID: chatID, temporary: temporary)]))
    }

    @discardableResult
    func removeServer(_ serverID: UUID) throws -> MCPChatSelectionMutation {
        var selections = try load()
        var affected = Set<MCPChatSelectionScope>()
        for key in selections.keys where selections[key]?.serverIDs.contains(serverID) == true {
            selections[key]?.serverIDs.remove(serverID)
            affected.insert(.init(chatID: key, temporary: false))
        }
        // Retain explicit empty records, including a selection whose last server
        // was removed. Dropping it would silently restore default server selection.
        if !affected.isEmpty { try save(selections) }
        for key in temporarySelections.keys where temporarySelections[key]?.contains(serverID) == true {
            temporarySelections[key]?.remove(serverID)
            affected.insert(.init(chatID: key, temporary: true))
        }
        return .init(affectedScopes: affected)
    }

    @discardableResult
    func clearTemporary(chatID: UUID) -> MCPChatSelectionMutation {
        guard temporarySelections.removeValue(forKey: chatID) != nil else { return .unchanged }
        return .init(affectedScopes: [.init(chatID: chatID, temporary: true)])
    }

    private func load() throws -> [UUID: MCPChatSelection] {
        try fileLayout.prepareIfNeeded()
        guard FileManager.default.fileExists(atPath: fileLayout.chatSelections.path) else { return [:] }
        let values = try JSONDecoder.mcp.decode(
            [MCPChatSelection].self,
            from: Data(contentsOf: fileLayout.chatSelections)
        )
        var selections: [UUID: MCPChatSelection] = [:]
        for value in values {
            guard selections.updateValue(value, forKey: value.chatID) == nil else {
                throw DecodingError.dataCorrupted(.init(codingPath: [],
                    debugDescription: "The MCP selection store contains duplicate conversation identifiers."))
            }
        }
        return selections
    }

    private func save(_ selections: [UUID: MCPChatSelection]) throws {
        try JSONEncoder.mcp.encode(Array(selections.values))
            .write(to: fileLayout.chatSelections, options: .atomic)
    }
}
