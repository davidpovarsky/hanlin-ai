import Foundation
import Testing
@testable import HanlinProductSplit

struct MiniAppAuthoringTransferTests {
    private func fixture() throws -> (URL, MiniAppAuthoringTransferStore, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "miniapp-authoring-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let archive = root.appending(path: "חיפוש טקסטים.hanlinExpo")
        try Data([0x50, 0x4b, 0, 1, 0xff]).write(to: archive)
        return (root, try .init(transportRoot: root), archive)
    }

    @Test func durableRequestRetainsOriginalBytesAndStructuredReport() throws {
        let (root, store, archive) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let request = MiniAppAuthoringTransfer(purpose: .repair,
            originalFileName: archive.lastPathComponent, archiveSHA256: String(repeating: "a", count: 64))
        let report = Data(#"{"diagnostics":[{"code":"TS2322","file":"src/App.tsx","line":4,"column":7}]}"#.utf8)
        try store.enqueue(request, archive: archive, diagnosticsJSON: report)
        let reopened = try MiniAppAuthoringTransferStore(transportRoot: root)
        #expect(try reopened.request(request.id) == request)
        #expect(try Data(contentsOf: reopened.archiveURL(for: request.id)) == Data(contentsOf: archive))
        #expect(try Data(contentsOf: reopened.diagnosticsURL(for: request.id)) == report)
        #expect(try reopened.receipt(for: request.id).status == .queued)
        #expect(MiniAppAuthoringTransfer.reference(in: request.wakeURL, purpose: .repair) == request.id)
        #expect(MiniAppAuthoringTransfer.reference(in: request.wakeURL, purpose: .install) == nil)
    }

    @Test func wakeURLDoesNotAcceptAnotherPurposeOrEmbeddedParameters() throws {
        let request = MiniAppAuthoringTransfer(purpose: .install,
            originalFileName: "demo.hanlinExpo", archiveSHA256: String(repeating: "b", count: 64))
        #expect(MiniAppAuthoringTransfer.reference(in: request.wakeURL, purpose: .install) == request.id)
        #expect(MiniAppAuthoringTransfer.reference(
            in: URL(string: request.wakeURL.absoluteString + "?file=other")!, purpose: .install) == nil)
        #expect(MiniAppAuthoringTransfer.reference(
            in: URL(string: request.wakeURL.absoluteString + "/extra")!, purpose: .install) == nil)
    }

    @Test func installedReceiptSurvivesRestartAndCannotRegressToQueued() throws {
        let (root, store, archive) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let request = MiniAppAuthoringTransfer(purpose: .install,
            originalFileName: archive.lastPathComponent, archiveSHA256: String(repeating: "c", count: 64))
        try store.enqueue(request, archive: archive, diagnosticsJSON: Data("{}".utf8))
        try store.record(.init(transferID: request.id, status: .received))
        let installed = MiniAppAuthoringTransferReceipt(transferID: request.id,
            status: .installed, installedPackageID: "install-demo")
        try store.record(installed)
        let reopened = try MiniAppAuthoringTransferStore(transportRoot: root)
        #expect(try reopened.receipt(for: request.id) == installed)
        #expect(throws: MiniAppAuthoringTransferStore.StoreError.self) {
            try reopened.record(.init(transferID: request.id, status: .queued))
        }
        #expect(try reopened.receipt(for: request.id) == installed)
    }

    @Test func duplicateTransferNeverReplacesOriginalPackage() throws {
        let (root, store, archive) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let request = MiniAppAuthoringTransfer(purpose: .repair,
            originalFileName: archive.lastPathComponent, archiveSHA256: String(repeating: "d", count: 64))
        let original = try Data(contentsOf: archive)
        try store.enqueue(request, archive: archive, diagnosticsJSON: Data("{}".utf8))
        try Data("different".utf8).write(to: archive)
        #expect(throws: (any Error).self) {
            try store.enqueue(request, archive: archive, diagnosticsJSON: Data("{}".utf8))
        }
        #expect(try Data(contentsOf: store.archiveURL(for: request.id)) == original)
    }

    @Test func missingPayloadAndReservedNameNeverPublishReadyRequest() throws {
        let (root, store, archive) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let reserved = MiniAppAuthoringTransfer(purpose: .repair,
            originalFileName: "diagnostics.json", archiveSHA256: String(repeating: "e", count: 64))
        #expect(throws: MiniAppAuthoringTransferStore.StoreError.self) {
            try store.enqueue(reserved, archive: archive, diagnosticsJSON: Data("{}".utf8))
        }
        #expect(throws: (any Error).self) { try store.request(reserved.id) }
        let missing = MiniAppAuthoringTransfer(purpose: .repair,
            originalFileName: "missing.zip", archiveSHA256: String(repeating: "e", count: 64))
        #expect(throws: (any Error).self) {
            try store.enqueue(missing, archive: root.appending(path: "missing.zip"), diagnosticsJSON: Data("{}".utf8))
        }
        #expect(throws: (any Error).self) { try store.request(missing.id) }
    }
}
