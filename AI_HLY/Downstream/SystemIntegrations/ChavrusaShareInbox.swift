import Foundation
import CryptoKit
import Darwin
import UniformTypeIdentifiers
import HanlinScriptStore
import HanlinScriptExtensions
import HanlinPlatformContracts

struct ChavrusaSharedItem: Codable, Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    let text: String?
    let url: URL?
    let fileName: String?
}

struct ChavrusaSharedDraft: Sendable {
    let text: String
    let files: [URL]
    let stagingDirectory: URL?
}

enum ChavrusaShareDraftError: LocalizedError, Sendable {
    case fileLimit, incompleteBatch
    nonisolated var errorDescription: String? {
        switch self {
        case .fileLimit:
            return String(localized: "A draft can include up to five files. Remove an attachment before adding this batch.")
        case .incompleteBatch:
            return String(localized: "This batch contains an item that could not be shared. The original items were kept.")
        }
    }
}

actor ChavrusaShareInbox {
    static let shared = ChavrusaShareInbox()

    private let groupID = "group.com.itorah.chavrusachat"
    private let fileName = "share-inbox.json"

    func batch(_ id: UUID) throws -> HanlinShareBatch {
        try ownedStore().batch(id)
    }

    func actionPayload(_ command: HanlinScriptResumeCommand) throws -> HanlinValue {
        try HanlinShareInvocation.payload(for: command, inbox: ownedStore())
    }

    /// Prepare a whole batch before the main actor changes the original Composer.
    /// Source batches stay immutable; cancellation removes only this operation's copy.
    func prepareDraft(batchID: UUID, availableFileSlots: Int) throws -> ChavrusaSharedDraft {
        try Task.checkCancellation()
        let store = try ownedStore()
        let batch = try store.batch(batchID)
        guard !batch.items.contains(where: { $0.content == .rejected }) else {
            throw ChavrusaShareDraftError.incompleteBatch
        }
        let attachments = batch.items.filter { $0.content == .file }
        guard attachments.count <= max(0, min(5, availableFileSlots)) else {
            throw ChavrusaShareDraftError.fileLimit
        }
        let text = batch.items.compactMap { item in
            item.content == .text || item.content == .url ? item.text : nil
        }.joined(separator: "\n\n")
        var staging: URL?
        var files: [URL] = []
        var complete = false
        defer {
            if !complete, let staging { try? FileManager.default.removeItem(at: staging) }
        }
        if !attachments.isEmpty {
            // Original ChatMessages stores attachment URLs; keep accepted copies
            // in application support so a sent message survives temporary-file eviction.
            let support = try FileManager.default.url(for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: true)
            let parent = support.appending(path: "SharedChatAttachments", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let values = try parent.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw HanlinShareInboxError.invalidPath
            }
            let directory = parent.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700, .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            staging = directory
            for item in attachments {
                try Task.checkCancellation()
                let source = try store.ownedFile(batchID: batchID, itemID: item.id)
                let itemDirectory = directory.appending(path: item.id.uuidString, directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: itemDirectory, withIntermediateDirectories: false,
                    attributes: [.posixPermissions: 0o700])
                var name = (item.name ?? "").replacingOccurrences(of: "\\", with: "/")
                    .components(separatedBy: "/").last ?? ""
                name = String(name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
                    .map(String.init).joined().prefix(180))
                if name.isEmpty || name == "." || name == ".." { name = "shared-file" }
                if (name as NSString).pathExtension.isEmpty,
                   let suffix = UTType(item.typeIdentifier)?.preferredFilenameExtension {
                    name += "." + suffix
                }
                let destination = itemDirectory.appending(path: name)
                try copyVerifiedFile(source, item: item, to: destination)
                files.append(destination)
            }
        }
        try Task.checkCancellation()
        complete = true
        return ChavrusaSharedDraft(text: text, files: files, stagingDirectory: staging)
    }

    func discardPreparedDraft(_ draft: ChavrusaSharedDraft) {
        if let directory = draft.stagingDirectory {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func copyVerifiedFile(_ source: URL, item: HanlinShareItem, to destination: URL) throws {
        // Reopen without following links, and verify the bytes actually copied.
        // The store's earlier verification alone cannot protect a subsequent copy.
        let inputFD = open(source.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard inputFD >= 0 else { throw HanlinShareInboxError.invalidFile }
        let input = FileHandle(fileDescriptor: inputFD, closeOnDealloc: true)
        defer { try? input.close() }
        var info = stat()
        guard fstat(inputFD, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_nlink == 1, info.st_size == item.bytes else { throw HanlinShareInboxError.invalidFile }
        let outputFD = open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard outputFD >= 0 else { throw HanlinShareInboxError.invalidFile }
        let output = FileHandle(fileDescriptor: outputFD, closeOnDealloc: true)
        defer { try? output.close() }
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
        var hash = SHA256(), count: Int64 = 0
        while let bytes = try input.read(upToCount: 1024 * 1024), !bytes.isEmpty {
            try Task.checkCancellation()
            count += Int64(bytes.count)
            guard count <= (item.bytes ?? -1) else { throw HanlinShareInboxError.integrityMismatch }
            hash.update(data: bytes)
            try output.write(contentsOf: bytes)
        }
        guard count == item.bytes,
              hash.finalize().map({ String(format: "%02x", $0) }).joined() == item.sha256 else {
            throw HanlinShareInboxError.integrityMismatch
        }
        try output.synchronize()
    }

#if (DEBUG || HANLIN_TESTING) && targetEnvironment(simulator)
    /// Test input only: real original App Group/store APIs; not an OS share-sheet claim.
    func seedDraftAcceptanceIfRequested(_ nonce: UUID) throws {
        let environment = ProcessInfo.processInfo.environment
        guard Bundle.main.bundleIdentifier == "com.itorah.chavrusachat",
              environment["HANLIN_AGENT_RUNTIME_UI_ACCEPTANCE"] == "1",
              environment["HANLIN_PHASE2_STORE_ID"] == nonce.uuidString else { return }
        let marker = "SHARE_DRAFT_" + nonce.uuidString
        let store = try ownedStore()
        if try store.scan().batches.contains(where: { $0.items.contains(where: { $0.text == marker }) }) { return }
        let id = try store.begin()
        let source = FileManager.default.temporaryDirectory.appending(path: "share-source-" + nonce.uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: source); try? store.abort(id) }
        try Data(("SHARED_FILE_" + nonce.uuidString).utf8).write(to: source)
        let file = try store.copyFile(source, batchID: id, ordinal: 2,
            typeIdentifier: UTType.plainText.identifier, suggestedName: "shared-note.txt")
        _ = try store.commit(id, items: [
            .text(marker, ordinal: 0, typeIdentifier: UTType.plainText.identifier),
            .text("https://example.org/hanlin-share?case=" + nonce.uuidString,
                  ordinal: 1, typeIdentifier: UTType.url.identifier, isURL: true), file
        ])
    }
#endif

    private func ownedStore() throws -> HanlinShareInboxStore {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupID
        ) else { throw HanlinShareInboxError.invalidPath }
        return try HanlinShareInboxStore(container: container)
    }

    func pendingItems() throws -> [ChavrusaSharedItem] {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupID
        ) else { return [] }
        let url = container.appending(path: fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([ChavrusaSharedItem].self, from: Data(contentsOf: url))
    }

    func pendingBatches() throws -> (batches: [HanlinShareBatch], rejected: [UUID?]) {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupID
        ) else { throw HanlinShareInboxError.invalidPath }
        return try HanlinShareInboxStore(container: container).scan()
    }

    func ownedFile(batchID: UUID, itemID: UUID) throws -> URL {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupID
        ) else { throw HanlinShareInboxError.invalidPath }
        return try HanlinShareInboxStore(container: container).ownedFile(batchID: batchID, itemID: itemID)
    }
}
