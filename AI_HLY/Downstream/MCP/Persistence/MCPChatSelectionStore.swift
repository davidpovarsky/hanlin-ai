import Foundation

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

    func setSelection(_ serverIDs: Set<UUID>, chatID: UUID, temporary: Bool = false) throws {
        if temporary {
            temporarySelections[chatID] = serverIDs
            return
        }
        var selections = try load()
        selections[chatID] = MCPChatSelection(chatID: chatID, serverIDs: serverIDs)
        try save(selections)
    }

    func removeServer(_ serverID: UUID) throws {
        var selections = try load()
        for key in selections.keys {
            selections[key]?.serverIDs.remove(serverID)
        }
        selections = selections.filter { !$0.value.serverIDs.isEmpty }
        try save(selections)
        temporarySelections = temporarySelections.mapValues { ids in
            var updated = ids
            updated.remove(serverID)
            return updated
        }
    }

    func clearTemporary(chatID: UUID) {
        temporarySelections.removeValue(forKey: chatID)
    }

    private func load() throws -> [UUID: MCPChatSelection] {
        try fileLayout.prepareIfNeeded()
        guard FileManager.default.fileExists(atPath: fileLayout.chatSelections.path) else { return [:] }
        let values = try JSONDecoder.mcp.decode(
            [MCPChatSelection].self,
            from: Data(contentsOf: fileLayout.chatSelections)
        )
        return Dictionary(uniqueKeysWithValues: values.map { ($0.chatID, $0) })
    }

    private func save(_ selections: [UUID: MCPChatSelection]) throws {
        try JSONEncoder.mcp.encode(Array(selections.values))
            .write(to: fileLayout.chatSelections, options: .atomic)
    }
}
