import Foundation
import HanlinPlatformContracts
import Testing
import ZIPFoundation
@testable import AI_Hanlin

@MainActor
@Suite("MiniApp Authoring Tools", .serialized)
struct MiniAppAuthoringToolTests {
    @Test("Original installed SDK writes, typechecks, repairs and builds a source-preserving archive")
    func originalSDKWriteValidateBuildAndRepair() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "miniapp-authoring-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sdk = await execute(.sdk, ["engine": "nativescript"])
        try #require(sdk.outcome == .succeeded, Comment(rawValue: sdk.modelText))
        #expect(sdk.modelText.contains("@nativescript/core"))
        let files: [[String: String]] = [
            ["path": "script.json", "content": #"{"name":"Authoring Native Acceptance","version":"1.0.0","entry":"nativescript/app/bundle.mjs","runInApp":true,"hanlinRuntime":"hanlin-nativescript"}"#],
            ["path": "package.json", "content": #"{"name":"hanlin-authoring-native-acceptance","version":"1.0.0","private":true,"type":"module"}"#],
            ["path": "tsconfig.json", "content": #"{"compilerOptions":{"strict":true,"skipLibCheck":false},"include":["*.ts"]}"#],
            ["path": "hanlin.authoring.json", "content": #"{"schemaVersion":1,"engine":"nativescript","entry":"index.ts","tsconfig":"tsconfig.json"}"#],
            ["path": "index.ts", "content": "export const answer: number = \"wrong\";\n"]
        ]
        let created = await execute(.write, ["project_path": root.path, "files": files])
        try #require(created.outcome == .succeeded, Comment(rawValue: created.modelText))
        let invalid = await execute(.validate, ["engine": "nativescript", "project_path": root.path])
        #expect(invalid.outcome == .failed)
        let invalidReport = try decode(HanlinMiniAppAuthoringReport.self, invalid)
        let error = try #require(invalidReport.diagnostics.first { $0.code == "TS2322" })
        #expect(error.file == "index.ts")
        #expect(error.line == 1)
        #expect(error.column != nil)
        let fixedSource = "export const answer: number = 42;\n"
        let repaired = await execute(.write, ["project_path": root.path,
            "files": [["path": "index.ts", "content": fixedSource]]])
        try #require(repaired.outcome == .succeeded, Comment(rawValue: repaired.modelText))
        let built = await execute(.build, ["engine": "nativescript", "project_path": root.path])
        try #require(built.outcome == .succeeded, Comment(rawValue: built.modelText))
        let report = try decode(HanlinMiniAppAuthoringReport.self, built)
        let archive = URL(fileURLWithPath: try #require(report.archivePath))
        #expect(FileManager.default.fileExists(atPath: archive.path))
        let imported = root.appending(path: "extracted")
        try FileManager.default.createDirectory(at: imported, withIntermediateDirectories: true)
        try FileManager.default.unzipItem(at: archive, to: imported)
        #expect(try String(contentsOf: imported.appending(path: "source/index.ts"), encoding: .utf8) == fixedSource)
        let importedCheck = await execute(.validate, ["engine": "nativescript", "project_path": imported.path])
        #expect(importedCheck.outcome == .succeeded, Comment(rawValue: importedCheck.modelText))
        let changed = await execute(.write, ["project_path": imported.path,
            "files": [["path": "index.ts", "content": "export const answer: number = \"wrong\";\n"]]])
        try #require(changed.outcome == .succeeded, Comment(rawValue: changed.modelText))
        let receipt = try decode(HanlinMiniAppSourceWriteReport.self, changed)
        #expect(receipt.sourceRoot == imported.appending(path: "source").resolvingSymlinksInPath().path)
        let rechecked = await execute(.validate, ["engine": "nativescript", "project_path": imported.path])
        let recheckedReport = try decode(HanlinMiniAppAuthoringReport.self, rechecked)
        #expect(!recheckedReport.succeeded)
        #expect(recheckedReport.diagnostics.contains { $0.code == "TS2322" && $0.file == "index.ts" })
    }

    @Test("Source edits preserve unrelated files, target retained source and accept exact binary resources")
    func sourceWritePreservesUnrelatedFilesAndTargetsRetainedSource() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "miniapp-source-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(#"{"schemaVersion":1,"sourceRoot":"source"}"#.utf8).write(to: root.appending(path: "hanlin.authoring.json"))
        try Data("keep".utf8).write(to: root.appending(path: "unrelated.txt"))
        let result = await execute(.write, ["project_path": root.path, "files": [
            ["path": "index.ts", "content": ""], ["path": "assets/data.bin", "base64": "AAECAw=="]
        ]])
        try #require(result.outcome == .succeeded, Comment(rawValue: result.modelText))
        #expect(try Data(contentsOf: root.appending(path: "source/assets/data.bin")) == Data([0, 1, 2, 3]))
        #expect(try String(contentsOf: root.appending(path: "unrelated.txt"), encoding: .utf8) == "keep")
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "source/index.ts").path))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "index.ts").path))
        #expect(!MiniAppAuthoringTool(operation: .write).catalogEntry.isSensitive)
    }

    private func execute(_ operation: MiniAppAuthoringTool.Operation, _ arguments: [String: Any]) async -> NativeToolResult {
        do {
            let json = String(decoding: try JSONSerialization.data(withJSONObject: arguments), as: UTF8.self)
            return await MiniAppAuthoringTool(operation: operation).execute(argumentsJSON: json,
                context: NativeToolExecutionContext(localeIdentifier: "en"))
        } catch {
            Issue.record(error)
            return NativeToolResult(modelText: error.localizedDescription, userText: error.localizedDescription,
                outcome: .failed)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ result: NativeToolResult) throws -> T {
        try JSONDecoder().decode(type, from: Data(result.modelText.utf8))
    }
}
