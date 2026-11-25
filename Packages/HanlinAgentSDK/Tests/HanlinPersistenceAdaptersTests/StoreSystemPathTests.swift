import Foundation
import HanlinHostContracts
import HanlinPersistenceAdapters
import Testing

@Suite struct StoreSystemPathTests {
    private func fixtureRoot() -> URL {
        var path = FileManager.default.temporaryDirectory.path(percentEncoded: false)
        #if canImport(Darwin)
        if path == "/var" || path.hasPrefix("/var/") ||
            path == "/tmp" || path.hasPrefix("/tmp/") {
            path = "/private" + path
        }
        #endif
        return URL(filePath: path, directoryHint: .isDirectory)
            .appending(path: "HanlinSystemPath-" + UUID().uuidString, directoryHint: .isDirectory)
    }

    #if canImport(Darwin)
    @Test func systemAliasCreatesReloadsUpdatesAndDeletesSameConversation() async throws {
        let root = fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let physical = root.appending(path: "Application Support/GSDHanlinConversations", directoryHint: .isDirectory)
        let physicalPath = physical.path(percentEncoded: false)
        #expect(physicalPath.hasPrefix("/private/var/") || physicalPath.hasPrefix("/private/tmp/"))
        let alias = URL(filePath: String(physicalPath.dropFirst("/private".count)), directoryHint: .isDirectory)
        let store = try HanlinPrivateConversationStore(directory: alias)
        let sameStore = try HanlinPrivateConversationStore(directory: physical)
        let ns = try HanlinConversationNamespace(app: "gsd", account: "fixture", workspace: "local", space: "tasks")
        let id = UUID()
        #expect(try await store.load(id, namespace: ns) == nil)
        let original = HanlinConversationRecord(namespace: ns, conversationID: id, revision: 0,
            draft: "שלום", entries: [.init(runID: UUID(), step: 0, sequence: 0,
                timestamp: Date(timeIntervalSince1970: 1_800_000_000), payload: .text("First reply"))])
        try await store.save(original, replacing: nil)
        #expect(try await sameStore.load(id, namespace: ns) == original)
        let next = HanlinConversationRecord(namespace: ns, conversationID: id, revision: 1,
            draft: "Updated", entries: original.entries)
        try await sameStore.save(next, replacing: 0)
        #expect(try await store.load(id, namespace: ns) == next)
        try await store.delete(id, namespace: ns, replacing: 1)
        #expect(try await sameStore.load(id, namespace: ns) == nil)
    }

    @Test func systemAliasReadsExistingVersionOneWithoutRewriting() async throws {
        let root = fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let physical = root.appending(path: "Conversations", directoryHint: .isDirectory)
        let originalStore = try HanlinPrivateConversationStore(directory: physical)
        let ns = try HanlinConversationNamespace(app: "lorvex", account: "fixture", workspace: "local", space: "tasks")
        let original = HanlinConversationRecord(formatVersion: 1, namespace: ns,
            conversationID: UUID(), revision: 0, draft: "Retained history")
        try await originalStore.save(original, replacing: nil)
        let file = try recordFile(in: physical)
        let before = try Data(contentsOf: file)
        let path = physical.path(percentEncoded: false)
        #expect(path.hasPrefix("/private/var/") || path.hasPrefix("/private/tmp/"))
        let reopened = try HanlinPrivateConversationStore(
            directory: URL(filePath: String(path.dropFirst("/private".count)), directoryHint: .isDirectory))
        #expect(try await reopened.load(original.conversationID, namespace: ns) == original)
        #expect(try Data(contentsOf: file) == before)
    }
    #endif

    @Test(arguments: ["root", "ancestor", "namespace", "record", "dangling-root"])
    func privateSymlinksRemainRejected(position: String) async throws {
        let root = fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appending(path: "parent/Conversations", directoryHint: .isDirectory)
        let store = try HanlinPrivateConversationStore(directory: directory)
        let ns = try HanlinConversationNamespace(app: "a", account: "a", workspace: "w", space: "one")
        let original = HanlinConversationRecord(namespace: ns, conversationID: UUID(), revision: 0, draft: "Keep me")
        try await store.save(original, replacing: nil)
        var protectedFile = try recordFile(in: directory)
        let originalBytes = try Data(contentsOf: protectedFile)
        var candidate = directory
        switch position {
        case "root":
            candidate = root.appending(path: "root-link", directoryHint: .isDirectory)
            try FileManager.default.createSymbolicLink(at: candidate, withDestinationURL: directory)
        case "ancestor":
            let parent = directory.deletingLastPathComponent()
            let moved = root.appending(path: "original-parent", directoryHint: .isDirectory)
            let relative = String(protectedFile.path.dropFirst(parent.path.count + 1))
            try FileManager.default.moveItem(at: parent, to: moved)
            try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: moved)
            protectedFile = moved.appending(path: relative)
        case "namespace":
            let parent = protectedFile.deletingLastPathComponent()
            let moved = root.appending(path: "original-namespace", directoryHint: .isDirectory)
            let filename = protectedFile.lastPathComponent
            try FileManager.default.moveItem(at: parent, to: moved)
            try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: moved)
            protectedFile = moved.appending(path: filename)
        case "record":
            let moved = root.appending(path: "original-record.json")
            try FileManager.default.moveItem(at: protectedFile, to: moved)
            try FileManager.default.createSymbolicLink(at: protectedFile, withDestinationURL: moved)
            protectedFile = moved
        default:
            candidate = root.appending(path: "dangling-root", directoryHint: .isDirectory)
            try FileManager.default.createSymbolicLink(at: candidate,
                withDestinationURL: root.appending(path: "missing", directoryHint: .isDirectory))
        }
        let rejected = try HanlinPrivateConversationStore(directory: candidate)
        do {
            _ = try await rejected.load(original.conversationID, namespace: ns)
            Issue.record("A private symbolic link was followed during load")
        } catch { #expect(error as? HanlinHostError == .invalidRecord) }
        do {
            try await rejected.save(.init(namespace: ns, conversationID: original.conversationID,
                revision: 1, draft: "Must not be written"), replacing: 0)
            Issue.record("A private symbolic link was followed during save")
        } catch { #expect(error as? HanlinHostError == .invalidRecord) }
        do {
            try await rejected.delete(original.conversationID, namespace: ns, replacing: 0)
            Issue.record("A private symbolic link was followed during delete")
        } catch { #expect(error as? HanlinHostError == .invalidRecord) }
        #expect(try Data(contentsOf: protectedFile) == originalBytes)
    }

    private func recordFile(in directory: URL) throws -> URL {
        let enumerator = try #require(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
        return try #require(enumerator.allObjects.compactMap { $0 as? URL }.first { $0.pathExtension == "json" })
    }
}
