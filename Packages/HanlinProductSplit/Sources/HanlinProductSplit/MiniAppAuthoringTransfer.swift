import Foundation

/// Durable original bytes shared by Hanlin AI and MiniApps. URLs contain only
/// the transfer identifier; all package data remains in the existing App Group.
public struct MiniAppAuthoringTransfer: Codable, Hashable, Sendable, Identifiable {
    public enum Purpose: String, Codable, Sendable { case repair, install }
    public let schemaVersion: Int
    public let id: UUID
    public let purpose: Purpose
    public let originalFileName: String
    public let archiveSHA256: String
    public let createdAt: Date

    public init(id: UUID = UUID(), purpose: Purpose, originalFileName: String,
                archiveSHA256: String, createdAt: Date = .now) {
        schemaVersion = 1
        self.id = id
        self.purpose = purpose
        self.originalFileName = originalFileName
        self.archiveSHA256 = archiveSHA256
        self.createdAt = createdAt
    }

    public var wakeURL: URL {
        let scheme = purpose == .repair ? "chavrusachat" : "hanlinminiapps"
        return URL(string: "\(scheme)://miniapp-authoring/v1/\(purpose.rawValue)/\(id.uuidString.lowercased())")!
    }

    public static func reference(in url: URL, purpose: Purpose) -> UUID? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == (purpose == .repair ? "chavrusachat" : "hanlinminiapps"),
              parts.host == "miniapp-authoring",
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.query == nil, parts.fragment == nil else { return nil }
        let prefix = "/v1/\(purpose.rawValue)/"
        guard parts.percentEncodedPath.hasPrefix(prefix),
              let id = UUID(uuidString: String(parts.percentEncodedPath.dropFirst(prefix.count))),
              url.absoluteString == MiniAppAuthoringTransfer(
                id: id, purpose: purpose, originalFileName: "", archiveSHA256: ""
              ).wakeURL.absoluteString else { return nil }
        return id
    }
}

public struct MiniAppAuthoringTransferReceipt: Codable, Hashable, Sendable {
    public enum Status: String, Codable, Sendable {
        case queued, received, submitted, installed, failed
    }
    public let transferID: UUID
    public let status: Status
    public let conversationID: UUID?
    public let userMessageID: UUID?
    public let installedPackageID: String?
    public let message: String?
    public let updatedAt: Date

    public init(transferID: UUID, status: Status, conversationID: UUID? = nil,
                userMessageID: UUID? = nil, installedPackageID: String? = nil,
                message: String? = nil, updatedAt: Date = .now) {
        self.transferID = transferID
        self.status = status
        self.conversationID = conversationID
        self.userMessageID = userMessageID
        self.installedPackageID = installedPackageID
        self.message = message
        self.updatedAt = updatedAt
    }
}

public struct MiniAppAuthoringTransferStore: Sendable {
    public enum StoreError: LocalizedError {
        case invalidRequest, missingPayload, invalidReceipt
        public var errorDescription: String? {
            switch self {
            case .invalidRequest: "The saved MiniApp request could not be read."
            case .missingPayload: "The original MiniApp package is missing."
            case .invalidReceipt: "The MiniApp delivery result does not match its request."
            }
        }
    }

    public let root: URL

    public init(transportRoot: URL) throws {
        root = transportRoot.appending(path: "Authoring/v1", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw StoreError.invalidRequest }
    }

    /// Writes an isolated directory and publishes it only after every byte has
    /// been copied. A failed copy never leaves a ready request.
    public func enqueue(_ transfer: MiniAppAuthoringTransfer, archive: URL,
                        diagnosticsJSON: Data) throws {
        guard transfer.schemaVersion == 1,
              transfer.originalFileName == URL(filePath: transfer.originalFileName).lastPathComponent,
              !transfer.originalFileName.isEmpty,
              !["request.json", "diagnostics.json", "receipt.json"].contains(transfer.originalFileName),
              !transfer.originalFileName.contains("\\"),
              transfer.archiveSHA256.count == 64,
              transfer.archiveSHA256.allSatisfy({ $0.isHexDigit }) else { throw StoreError.invalidRequest }
        let values = try archive.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw StoreError.missingPayload }
        let final = directory(transfer.id)
        let staging = root.appending(path: ".staging-\(UUID().uuidString.lowercased())", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: staging) }
        try FileManager.default.copyItem(at: archive, to: staging.appending(path: transfer.originalFileName))
        try diagnosticsJSON.write(to: staging.appending(path: "diagnostics.json"), options: .atomic)
        try encoder.encode(transfer).write(to: staging.appending(path: "request.json"), options: .atomic)
        try encoder.encode(MiniAppAuthoringTransferReceipt(transferID: transfer.id, status: .queued))
            .write(to: staging.appending(path: "receipt.json"), options: .atomic)
        try FileManager.default.moveItem(at: staging, to: final)
    }

    public func request(_ id: UUID) throws -> MiniAppAuthoringTransfer {
        let value = try JSONDecoder().decode(MiniAppAuthoringTransfer.self,
            from: Data(contentsOf: directory(id).appending(path: "request.json")))
        guard value.id == id, value.schemaVersion == 1,
              value.originalFileName == URL(filePath: value.originalFileName).lastPathComponent,
              !value.originalFileName.isEmpty, !value.originalFileName.contains("\\"),
              !["request.json", "diagnostics.json", "receipt.json"].contains(value.originalFileName)
        else { throw StoreError.invalidRequest }
        return value
    }

    public func archiveURL(for id: UUID) throws -> URL {
        let request = try request(id)
        let url = directory(id).appending(path: request.originalFileName)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw StoreError.missingPayload }
        return url
    }

    public func diagnosticsURL(for id: UUID) throws -> URL {
        _ = try request(id)
        return directory(id).appending(path: "diagnostics.json")
    }

    public func receipt(for id: UUID) throws -> MiniAppAuthoringTransferReceipt {
        let receipt = try JSONDecoder().decode(MiniAppAuthoringTransferReceipt.self,
            from: Data(contentsOf: directory(id).appending(path: "receipt.json")))
        guard receipt.transferID == id else { throw StoreError.invalidReceipt }
        return receipt
    }

    public func record(_ receipt: MiniAppAuthoringTransferReceipt) throws {
        _ = try request(receipt.transferID)
        let previous = try self.receipt(for: receipt.transferID)
        if previous.status == .submitted || previous.status == .installed {
            guard receipt == previous else { throw StoreError.invalidReceipt }
            return
        }
        try encoder.encode(receipt).write(
            to: directory(receipt.transferID).appending(path: "receipt.json"), options: .atomic)
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private func directory(_ id: UUID) -> URL {
        root.appending(path: id.uuidString.lowercased(), directoryHint: .isDirectory)
    }
}
