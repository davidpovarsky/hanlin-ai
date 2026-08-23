import Foundation
import HanlinScriptCompiler
import Testing
import ZIPFoundation

@Suite("Scripting Package Center")
struct HanlinPackageCenterTests {
    @Test("Stages, validates, extracts, and decodes without executing source")
    func validPackage() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let archiveURL = root.appending(path: "fixture.scripting", directoryHint: .notDirectory)
        try makeArchive(
            at: archiveURL,
            files: [
                "Fixture/script.json": Data(#"{"name":"Fixture","version":"1.0.0","entry":"index.tsx"}"#.utf8),
                "Fixture/index.tsx": Data("throw new Error('must not execute during preview')".utf8)
            ]
        )

        let package = try HanlinPackageCenter().stageAndInspect(
            sourceURL: archiveURL,
            stagingParent: root,
            importedAt: Date(timeIntervalSince1970: 4)
        )
        #expect(package.manifest.name == "Fixture")
        #expect(package.inspection.wrapperDirectory == "Fixture")
        #expect(FileManager.default.fileExists(
            atPath: package.packageRoot.appending(path: "index.tsx").path()
        ))
        try HanlinPackageCenter().discard(package)
        #expect(!FileManager.default.fileExists(atPath: package.stagingRoot.path()))
    }

    @Test("Malformed manifests fail before a staged package can escape")
    func malformedManifest() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let archiveURL = root.appending(path: "malformed.zip", directoryHint: .notDirectory)
        try makeArchive(
            at: archiveURL,
            files: [
                "script.json": Data("{".utf8),
                "index.tsx": Data("export default null".utf8)
            ]
        )
        #expect(throws: HanlinPackageCenterError.malformedManifest) {
            _ = try HanlinPackageCenter().stageAndInspect(
                sourceURL: archiveURL,
                stagingParent: root
            )
        }
        let leftovers = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("scripting-import-") }
        #expect(leftovers.isEmpty)
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "hanlin-package-center-tests-\(UUID().uuidString.lowercased())",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        return root
    }

    private func makeArchive(at url: URL, files: [String: Data]) throws {
        let archive = try Archive(url: url, accessMode: .create)
        for (path, data) in files.sorted(by: { $0.key < $1.key }) {
            try archive.addEntry(
                with: path,
                type: .file,
                uncompressedSize: Int64(data.count),
                compressionMethod: .deflate,
                provider: { position, size in
                    let start = Int(position)
                    let end = min(start + size, data.count)
                    return data.subdata(in: start ..< end)
                }
            )
        }
    }
}
