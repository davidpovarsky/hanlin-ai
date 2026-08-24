import Foundation
import HanlinPlatformContracts
import HanlinScriptCompiler
import HanlinScriptContracts
import Testing

@Suite("Static Scripting analyzer")
struct HanlinScriptAnalyzerTests {
    @Test("Discovers entrypoints, resolves modules, and derives capabilities deterministically")
    func preview() throws {
        let fixture = try package(files: [
            "script.json": #"{"name":"Fixture","version":"1.0.0","entry":"index.tsx"}"#,
            "index.tsx": #"import { Storage, Assistant } from "scripting"; import { value } from "./lib/value"; export default value"#,
            "lib/value.ts": "export const value = 1",
            "assistant_tool.tsx": #"import { AssistantTool } from "scripting"; export default AssistantTool"#,
            "widget.tsx": #"import { Storage } from "scripting"; export default Storage"#
        ])
        defer { try? FileManager.default.removeItem(at: fixture.stagingRoot) }
        let inventory = HanlinCompatibilityInventory(
            baselineID: "fixture-baseline",
            baselineDigest: String(repeating: "a", count: 64),
            symbols: ["Storage", "Assistant", "AssistantTool"].map {
                .init(symbol: $0, state: .supported)
            }
        )
        let preview = try HanlinScriptAnalyzer(inventory: inventory).analyze(fixture)
        #expect(preview.canInstall)
        #expect(preview.entrypoints.map(\.kind) == [.app, .assistantTool, .widget])
        #expect(preview.entrypoints.allSatisfy { $0.runtimeProfile == .scriptingJSC })
        #expect(preview.dependencyGraph.unresolvedSpecifiers.isEmpty)
        #expect(Set(preview.requestedCapabilities.map { $0.capabilityID.rawValue }) == [
            "assistant", "storage"
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        #expect(try encoder.encode(preview) == encoder.encode(preview))
    }

    @Test("Routes original Python entrypoint deterministically without engine fallback")
    func pythonProfile() throws {
        let fixture = try package(files: [
            "script.json": #"{"name":"Python Fixture","version":"1.0.0","entry":"index.py"}"#,
            "index.py": "from scripting import Script\nScript.exit(0)"
        ])
        defer { try? FileManager.default.removeItem(at: fixture.stagingRoot) }
        let preview = try HanlinScriptAnalyzer(inventory: .init(
            baselineID: "fixture",
            baselineDigest: String(repeating: "d", count: 64),
            symbols: []
        )).analyze(fixture)
        let entrypoint = try #require(preview.entrypoints.first)
        #expect(entrypoint.sourcePath == "index.py")
        #expect(entrypoint.runtimeProfile == .hanlinPython)
        #expect(entrypoint.runtimeProfile.runtimeKind == .localPython)
    }

    @Test("Detects capability-bearing ambient Scripting globals")
    func ambientGlobals() throws {
        let fixture = try package(files: [
            "script.json": #"{"name":"Ambient Fixture","version":"1.0.0"}"#,
            "index.ts": "Storage.set('key', 'value'); FileManager.readAsString('file.txt')"
        ])
        defer { try? FileManager.default.removeItem(at: fixture.stagingRoot) }
        let preview = try HanlinScriptAnalyzer(inventory: .init(
            baselineID: "fixture",
            baselineDigest: String(repeating: "e", count: 64),
            symbols: [
                .init(symbol: "Storage", state: .partial),
                .init(symbol: "FileManager", state: .partial)
            ]
        )).analyze(fixture)
        #expect(Set(preview.requestedCapabilities.map { $0.capabilityID.rawValue }) == [
            "files", "storage"
        ])
        #expect(preview.findings.contains { $0.symbol == "Storage" })
        #expect(preview.findings.contains { $0.symbol == "FileManager" })
    }

    @Test("Rejects dynamic imports, eval, unresolved paths, and arbitrary bare modules")
    func forbiddenModules() throws {
        let fixture = try package(files: [
            "script.json": #"{"name":"Fixture","version":"1.0.0"}"#,
            "index.tsx": #"import thing from "arbitrary-npm"; import("./late"); eval("1"); import "./missing""#
        ])
        defer { try? FileManager.default.removeItem(at: fixture.stagingRoot) }
        let preview = try HanlinScriptAnalyzer(inventory: .init(
            baselineID: "fixture",
            baselineDigest: String(repeating: "b", count: 64),
            symbols: []
        )).analyze(fixture)
        #expect(!preview.canInstall)
        #expect(Set(preview.dependencyGraph.unresolvedSpecifiers) == ["./late", "./missing", "arbitrary-npm"])
        #expect(preview.findings.contains { $0.message.contains("Dynamic import") })
        #expect(preview.findings.contains { $0.message.contains("eval") })
    }

    private func package(files: [String: String]) throws -> HanlinStagedPackage {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "hanlin-analyzer-tests-\(UUID().uuidString.lowercased())",
            directoryHint: .isDirectory
        )
        let packageRoot = root.appending(path: "package", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: packageRoot, withIntermediateDirectories: true)
        for (path, source) in files {
            let url = packageRoot.appending(path: path, directoryHint: .notDirectory)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(source.utf8).write(to: url)
        }
        let manifest = try JSONDecoder().decode(
            HanlinScriptingManifest.self,
            from: Data((try #require(files["script.json"])).utf8)
        )
        return HanlinStagedPackage(
            source: .init(
                originalFileName: "fixture.scripting",
                format: .scripting,
                contentSHA256: String(repeating: "c", count: 64),
                byteCount: 100,
                importedAt: Date(timeIntervalSince1970: 1)
            ),
            stagingRoot: root,
            archiveURL: root.appending(path: "source.scripting"),
            packageRoot: packageRoot,
            inspection: .init(
                fileCount: files.count,
                directoryCount: 1,
                compressedBytes: 100,
                uncompressedBytes: 200,
                maximumDepth: 2,
                manifestPath: "script.json"
            ),
            manifest: manifest
        )
    }
}
