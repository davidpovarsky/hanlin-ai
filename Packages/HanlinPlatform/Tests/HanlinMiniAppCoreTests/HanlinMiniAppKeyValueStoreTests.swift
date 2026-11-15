import Foundation
import HanlinPlatformContracts
import Testing
@testable import HanlinMiniAppCore

@Suite("Canonical durable Mini App KV")
struct HanlinMiniAppKeyValueStoreTests {
    @Test func largeValuesReopenAndExplicitSharing() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let firstID = try HanlinAppID(validating: "first-app")
        let secondID = try HanlinAppID(validating: "second-app")
        let first = try HanlinMiniAppKeyValueStore(root: root, appID: firstID)
        let second = try HanlinMiniAppKeyValueStore(root: root, appID: secondID)
        let content = String(repeating: "שלום🙂", count: 300_000)
        #expect(content.utf8.count > 1_048_576)
        try first.set(.init(kind: .json, content: content), for: "large")
        #expect(try first.value(for: "large")?.content == content)
        #expect(try second.value(for: "large") == nil)
        let reopened = try HanlinMiniAppKeyValueStore(root: root, appID: firstID)
        #expect(try reopened.value(for: "large")?.content == content)
        let sharedA = try HanlinMiniAppKeyValueStore(root: root, appID: nil)
        let sharedB = try HanlinMiniAppKeyValueStore(root: root, appID: nil)
        let binary = Data((0..<2_100_000).map { UInt8(truncatingIfNeeded: $0) })
        try sharedA.set(.init(kind: .data, content: binary.base64EncodedString()), for: "binary")
        let stored = try sharedB.value(for: "binary")
        #expect(stored?.kind == .data)
        #expect(stored.flatMap { Data(base64Encoded: $0.content) } == binary)
        try first.clear()
        #expect(try reopened.contains(key: "large") == false)
        #expect(try sharedB.contains(key: "binary"))
        try sharedB.remove(key: "binary")
        #expect(try sharedA.contains(key: "binary") == false)
    }

    @Test func legacyMigrationPagesAllKeysAndDoesNotResurrectClearedValues() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = try HanlinAppID(validating: "migration-app")
        let store = try HanlinMiniAppKeyValueStore(root: root, appID: id)
        var legacy: [String: Any] = [:]
        for index in 0..<10_501 { legacy["key-\(index)"] = "\(index)" }
        legacy["__hanlin_data__:bytes"] = Data([0,127,255])
        try store.set(.init(kind: .json, content: "\"newer\""), for: "key-0")
        try store.migrateLegacy(legacy, identity: "original-suite")
        #expect(try store.keys().count == 10_502)
        #expect(try store.value(for: "key-0")?.content == "\"newer\"")
        #expect(try store.value(for: "bytes") == .init(kind: .data, content: "AH//"))
        #expect(legacy["__hanlin_data__:bytes"] as? Data == Data([0,127,255]))
        try store.clear()
        let reopened = try HanlinMiniAppKeyValueStore(root: root, appID: id)
        try reopened.migrateLegacy(legacy, identity: "original-suite")
        #expect(try reopened.keys().isEmpty)
        let invalid: [String: Any] = ["a-valid":"123", "z-unsupported":NSNumber(value:42)]
        #expect(throws: HanlinMiniAppKeyValueError.self) { try reopened.migrateLegacy(invalid, identity: "failed-suite") }
        #expect(try reopened.contains(key: "a-valid") == false)
        try reopened.migrateLegacy(["a-valid":"123"], identity: "failed-suite")
        #expect(try reopened.value(for: "a-valid")?.content == "123")
    }

    @Test func independentConnectionsPreserveConcurrentCommittedKeys() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = try HanlinAppID(validating: "concurrent-app")
        let original = try HanlinMiniAppKeyValueStore(root: root, appID: id)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for writer in 0..<8 {
                group.addTask {
                    let store = try HanlinMiniAppKeyValueStore(root: root, appID: id)
                    for index in 0..<75 { try store.set(.init(kind: .json, content: "\(index)"), for: "writer-\(writer)-\(index)") }
                }
            }
            try await group.waitForAll()
        }
        #expect(try original.keys().count == 600)
        for writer in 0..<8 { #expect(try original.value(for: "writer-\(writer)-74")?.content == "74") }
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "hanlin-kv-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}
