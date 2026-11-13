import Foundation
import Testing
@testable import HanlinScriptingApplicationRuntime

@Suite("Original file resources and preservation", .serialized)
struct HanlinScriptingFileAutonomyTests {
    @Test("Original file bridge preserves files beyond former payload, per-file and total quotas on reopen")
    func fullFilesAndReopen() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "file-autonomy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        func open() throws -> HanlinScriptingPackageFileSystem {
            try .init(installedPackageID: "file-proof", allowed: true, runtimeRoot: root, packageSourceDirectory: nil)
        }
        let files = try open()
        var bytes = Data(repeating: 0xA7, count: 17 * 1_024 * 1_024)
        bytes.replaceSubrange(0..<16, with: UUID().uuidString.utf8.prefix(16))
        let encoded = bytes.base64EncodedString()
        for index in 0..<5 {
            let request = try JSONSerialization.data(withJSONObject: ["path": "/documents/full-\(index).bin", "base64": encoded])
            let payload = try HanlinScriptingNativeJSON.decodeObject(String(decoding: request, as: UTF8.self))
            _ = try files.perform(operation: "file.writeData", payload: payload)
        }
        let reopened = try open()
        let result = try #require(reopened.perform(operation: "file.readData", payload: ["path": "/documents/full-4.bin"]) as? String)
        #expect(Data(base64Encoded: result) == bytes)
        let tail = Data("\0שלום-tail".utf8)
        _ = try reopened.perform(operation: "file.appendData", payload: ["path": "/documents/full-4.bin", "base64": tail.base64EncodedString()])
        let appended = try #require(reopened.perform(operation: "file.readData", payload: ["path": "/documents/full-4.bin"]) as? String)
        #expect(Data(base64Encoded: appended) == bytes + tail)
        let staged = try reopened.stageExportFiles((0..<65).map { (name: "file-\($0).bin", data: Data([UInt8($0)])) })
        #expect(staged.urls.count == 65)
        #expect(try Data(contentsOf: #require(staged.urls.last)) == Data([64]))
    }

    @Test("Explicit file budgets fail before replacement and permissions and source errors still preserve data")
    func explicitBudgetsAndReadFailure() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "file-budgets-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let files = try HanlinScriptingPackageFileSystem(installedPackageID: "budget-proof", allowed: true, runtimeRoot: root, packageSourceDirectory: nil, resourceLimits: .init(maximumReadBytes: 4, maximumStorageBytes: 8))
        func write(_ path: String, _ data: Data) throws {
            _ = try files.perform(operation: "file.writeData", payload: ["path": path, "base64": data.base64EncodedString()])
        }
        let kept = Data([1,2,3,4])
        try write("/documents/.kept", kept)
        try write("/documents/other", kept)
        #expect(throws: (any Error).self) { try write("/documents/other", Data(repeating: 0, count: 5)) }
        #expect(throws: (any Error).self) { try write("/documents/excess", Data([9])) }
        #expect(try Data(contentsOf: root.appending(path: "Documents/other")) == kept)
        // Moving an existing managed file does not count its bytes twice.
        _ = try files.perform(operation: "file.rename", payload: ["path": "/documents/other", "newPath": "/documents/moved"])
        #expect(try Data(contentsOf: root.appending(path: "Documents/moved")) == kept)
        #expect(throws: (any Error).self) { try files.stageExportFiles([(name: "excess", data: Data([9]))]) }
        let denied = try HanlinScriptingPackageFileSystem(installedPackageID: "denied", allowed: false, runtimeRoot: root, packageSourceDirectory: nil)
        #expect(throws: (any Error).self) { try denied.perform(operation: "file.readData", payload: ["path": "/documents/.kept"]) }
        #expect(throws: (any Error).self) { try files.perform(operation: "file.readData", payload: ["path": "/documents/../../outside"]) }
        // A directory deterministically fails Data(contentsOf:), without relying
        // on the runner's UNIX permission bypass privileges.
        let directory = root.appending(path: "Documents/folder")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try kept.write(to: directory.appending(path: "original"))
        #expect(throws: (any Error).self) { try files.perform(operation: "file.appendData", payload: ["path": "/documents/folder", "base64": "CQ=="]) }
        #expect(try Data(contentsOf: directory.appending(path: "original")) == kept)
    }
}
