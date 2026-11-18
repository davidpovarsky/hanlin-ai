import Foundation
import HanlinPlatformContracts
import Testing
@testable import HanlinMiniAppCore

@Suite("Original MiniApp visibility preserved with canonical data")
struct HanlinMiniAppVisibilityStoreTests {
    @Test func legacyMigrationAndExplicitUnhideSurviveReopening() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "visibility-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try HanlinAppID(validating: "first.app")
        let second = try HanlinAppID(validating: "second.app")
        let store = try HanlinMiniAppVisibilityStore(dataRoot: root, legacyHiddenIDs: [first])
        #expect(try store.hiddenIDs() == [first])
        try store.setHidden(false, appID: first)
        try store.setHidden(true, appID: second)
        let reopened = try HanlinMiniAppVisibilityStore(dataRoot: root, legacyHiddenIDs: [first])
        #expect(try reopened.hiddenIDs() == [second])
        #expect(try store.hiddenIDs() == [second])
    }

    @Test func corruptOrSymlinkedMarkersAreRetainedAndRejected() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "visibility-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let id = try HanlinAppID(validating: "saved.app")
        let store = try HanlinMiniAppVisibilityStore(dataRoot: root, legacyHiddenIDs: [id])
        let marker = root.appending(path: ".catalog-state/hidden/saved.app")
        try Data("unexpected".utf8).write(to: marker)
        #expect(throws: (any Error).self) { try store.hiddenIDs() }
        #expect(throws: (any Error).self) { try store.setHidden(false, appID: id) }
        #expect(try Data(contentsOf: marker) == Data("unexpected".utf8))
        let outside = root.appending(path: "outside.txt")
        try Data("hidden-v1\n".utf8).write(to: outside)
        try FileManager.default.removeItem(at: marker)
        try FileManager.default.createSymbolicLink(at: marker, withDestinationURL: outside)
        #expect(throws: (any Error).self) { try HanlinMiniAppVisibilityStore(dataRoot: root, legacyHiddenIDs: []) }
        #expect(try Data(contentsOf: outside) == Data("hidden-v1\n".utf8))
    }
}
