import Foundation
import Testing
@testable import AI_Hanlin

@Suite("MCP immutable package generation paths")
struct MCPPackageGenerationTests {
    @Test func generationRelocatesWithoutMovingLegacyCode() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let resolver = MCPServerPathResolver(fileLayout: fixture.layout)
        var descriptor = fixture.descriptor
        let oldRoot = "/old-container/packages/mcp/\(descriptor.id.uuidString.lowercased())/.hanlin-generations/\(fixture.operationID.uuidString.lowercased())"
        descriptor.packageRoot = oldRoot
        descriptor.entryPoint = oldRoot + "/dist/index.mjs"
        let paths = try resolver.resolve(descriptor)
        #expect(paths.packageRoot == fixture.generation)
        #expect(paths.entryPoint == fixture.generation.appending(path: "dist/index.mjs"))
        #expect(paths.requiredMigration)
        let migrated = resolver.migratedDescriptor(descriptor, paths: paths)
        let reopened = try JSONDecoder.mcp.decode(MCPServerDescriptor.self, from: JSONEncoder.mcp.encode(migrated))
        #expect(try resolver.resolve(reopened).requiredMigration == false)
        #expect(try String(contentsOf: fixture.legacyFile, encoding: .utf8) == "legacy code remains")
    }

    @Test func rejectedGenerationsPreserveExistingCode() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let resolver = MCPServerPathResolver(fileLayout: fixture.layout)
        var wrongServer = fixture.descriptor
        wrongServer.id = UUID()
        #expect(throws: MCPServerPathResolutionError.self) { try resolver.resolve(wrongServer) }
        for state in ["rolledBack", "unknown"] {
            try fixture.writeMarker(state: state)
            #expect(throws: MCPServerPathResolutionError.self) { try resolver.resolve(fixture.descriptor) }
        }
        try fixture.writeMarker(state: "committed", serverID: UUID())
        #expect(throws: MCPServerPathResolutionError.self) { try resolver.resolve(fixture.descriptor) }
        #expect(FileManager.default.fileExists(atPath: fixture.generation.appending(path: "dist/index.mjs").path))
        #expect(try String(contentsOf: fixture.legacyFile, encoding: .utf8) == "legacy code remains")
    }

    private struct Fixture {
        let layout: MCPFileLayout
        let generation: URL
        let legacyFile: URL
        let operationID = UUID()
        let descriptor: MCPServerDescriptor

        init() throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "mcp-generation-\(UUID().uuidString)")
            layout = MCPFileLayout(root: root)
            let id = UUID()
            generation = layout.serverDirectory(id: id).appending(path: ".hanlin-generations/\(operationID.uuidString.lowercased())", directoryHint: .isDirectory)
            legacyFile = layout.serverDirectory(id: id).appending(path: "legacy.mjs")
            try FileManager.default.createDirectory(at: generation.appending(path: "dist"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: generation.appending(path: ".hanlin-runtime"), withIntermediateDirectories: true)
            try Data("export {};".utf8).write(to: generation.appending(path: "dist/index.mjs"))
            try Data("legacy code remains".utf8).write(to: legacyFile)
            descriptor = MCPServerDescriptor(id: id, slug: "fixture", displayName: "Fixture", packageName: "fixture",
                resolvedVersion: "1.0.0", entryPoint: generation.appending(path: "dist/index.mjs").path,
                entryPointRelativePath: "dist/index.mjs", packageRoot: generation.path,
                compatibility: .init(verdict: .compatible, findings: [], runtimeProbePassed: true))
            try writeMarker(state: "staged")
        }

        func writeMarker(state: String, serverID: UUID? = nil) throws {
            let value: [String: Any] = ["schemaVersion": 1, "serverID": (serverID ?? descriptor.id).uuidString.lowercased(),
                "operationID": operationID.uuidString.lowercased(), "state": state]
            try JSONSerialization.data(withJSONObject: value).write(to: generation.appending(path: ".hanlin-runtime/installation-transaction.json"))
        }

        func cleanup() { try? FileManager.default.removeItem(at: layout.root) }
    }
}
