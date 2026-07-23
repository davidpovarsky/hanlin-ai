import Foundation

struct MCPServerRegistryDocument: Codable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var generation: UInt64
    var servers: [MCPServerDescriptor]
}

enum MCPServerRegistryError: LocalizedError, Sendable {
    case bothCopiesCorrupt(primary: String, backup: String)
    case unsupportedSchema(Int)
    case writeVerificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .bothCopiesCorrupt(let primary, let backup):
            "The MCP server registry and its backup are both unreadable. Primary: \(primary). Backup: \(backup)."
        case .unsupportedSchema(let version):
            "The MCP server registry uses unsupported schema version \(version)."
        case .writeVerificationFailed(let reason):
            "The MCP server registry could not be verified before saving: \(reason)."
        }
    }
}

actor MCPServerRegistryStore {
    private enum Candidate {
        case missing
        case valid(document: MCPServerRegistryDocument, data: Data)
        case corrupt(String)
    }

    private let fileLayout: MCPFileLayout

    init(fileLayout: MCPFileLayout = .default) {
        self.fileLayout = fileLayout
    }

    func load() throws -> [MCPServerDescriptor] {
        try loadDocument(repairCopies: true).servers
    }

    func save(_ servers: [MCPServerDescriptor]) throws {
        try fileLayout.prepareIfNeeded()
        let current = try loadDocument(repairCopies: true)
        let sorted = servers.sorted { $0.id.uuidString < $1.id.uuidString }
        let document = MCPServerRegistryDocument(
            schemaVersion: MCPServerRegistryDocument.currentSchemaVersion,
            generation: current.generation &+ 1,
            servers: sorted
        )
        let data = try JSONEncoder.mcp.encode(document)
        let verified = try decodeDocument(data)
        guard verified == document else {
            throw MCPServerRegistryError.writeVerificationFailed("round-trip data did not match")
        }

        // The primary remains valid while the backup is replaced. Once the
        // backup is verified on disk, it protects the primary replacement.
        try data.write(to: fileLayout.serverRegistryBackup, options: .atomic)
        _ = try verifyCopy(at: fileLayout.serverRegistryBackup)
        try data.write(to: fileLayout.serverRegistry, options: .atomic)
        _ = try verifyCopy(at: fileLayout.serverRegistry)
    }

    func upsert(_ server: MCPServerDescriptor) throws -> [MCPServerDescriptor] {
        var servers = try load()
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
        } else {
            servers.append(server)
        }
        try save(servers)
        return servers.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    func remove(id: UUID) throws -> [MCPServerDescriptor] {
        var servers = try load()
        servers.removeAll { $0.id == id }
        try save(servers)
        return servers.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private func loadDocument(repairCopies: Bool) throws -> MCPServerRegistryDocument {
        try fileLayout.prepareIfNeeded()
        let primary = readCandidate(at: fileLayout.serverRegistry)
        let backup = readCandidate(at: fileLayout.serverRegistryBackup)

        switch (primary, backup) {
        case (.missing, .missing):
            return MCPServerRegistryDocument(
                schemaVersion: MCPServerRegistryDocument.currentSchemaVersion,
                generation: 0,
                servers: []
            )
        case (.corrupt(let primaryError), .corrupt(let backupError)):
            throw MCPServerRegistryError.bothCopiesCorrupt(
                primary: primaryError,
                backup: backupError
            )
        default:
            break
        }

        let selected: (document: MCPServerRegistryDocument, data: Data)
        switch (primary, backup) {
        case (.valid(let primaryDocument, let primaryData), .valid(let backupDocument, let backupData)):
            selected = primaryDocument.generation >= backupDocument.generation
                ? (primaryDocument, primaryData)
                : (backupDocument, backupData)
        case (.valid(let document, let data), _), (_, .valid(let document, let data)):
            selected = (document, data)
        case (.corrupt(let error), .missing):
            throw MCPServerRegistryError.bothCopiesCorrupt(
                primary: error,
                backup: "copy is missing"
            )
        case (.missing, .corrupt(let error)):
            throw MCPServerRegistryError.bothCopiesCorrupt(
                primary: "copy is missing",
                backup: error
            )
        case (.missing, .missing), (.corrupt, .corrupt):
            preconditionFailure("Handled above")
        }

        if repairCopies {
            try repairCopy(fileLayout.serverRegistry, candidate: primary, with: selected.data)
            try repairCopy(fileLayout.serverRegistryBackup, candidate: backup, with: selected.data)
        }
        return selected.document
    }

    private func readCandidate(at url: URL) -> Candidate {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        do {
            let data = try Data(contentsOf: url)
            return .valid(document: try decodeDocument(data), data: data)
        } catch {
            return .corrupt(sanitizedDiagnostic(error))
        }
    }

    private func decodeDocument(_ data: Data) throws -> MCPServerRegistryDocument {
        if let document = try? JSONDecoder.mcp.decode(MCPServerRegistryDocument.self, from: data) {
            guard document.schemaVersion == MCPServerRegistryDocument.currentSchemaVersion else {
                throw MCPServerRegistryError.unsupportedSchema(document.schemaVersion)
            }
            return document
        }
        let legacy = try JSONDecoder.mcp.decode([MCPServerDescriptor].self, from: data)
        return MCPServerRegistryDocument(schemaVersion: 0, generation: 0, servers: legacy)
    }

    private func repairCopy(_ url: URL, candidate: Candidate, with data: Data) throws {
        if case .valid(let document, _) = candidate,
           let selected = try? decodeDocument(data),
           document == selected {
            return
        }
        try data.write(to: url, options: .atomic)
        _ = try verifyCopy(at: url)
    }

    private func verifyCopy(at url: URL) throws -> MCPServerRegistryDocument {
        do {
            return try decodeDocument(Data(contentsOf: url))
        } catch {
            throw MCPServerRegistryError.writeVerificationFailed(sanitizedDiagnostic(error))
        }
    }

    private func sanitizedDiagnostic(_ error: Error) -> String {
        String(describing: error)
            .replacingOccurrences(
                of: #"(?i)(token|secret|password|api[_-]?key)\s*[:=]\s*[^\s,;]+"#,
                with: "$1=<redacted>",
                options: .regularExpression
            )
    }
}
