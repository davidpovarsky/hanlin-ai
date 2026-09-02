import Foundation
import HanlinScriptCompiler
import Testing
import ZIPFoundation

@Suite("Scripting Package Center")
struct HanlinPackageCenterTests {
    @Test("Production exporter round trips through production archive import")
    func exporterImporterContract() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "Export Fixture", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: false)
        try Data(#"{"name":"Export Fixture","version":"1.0.0","entry":"index.tsx"}"#.utf8)
            .write(to: source.appending(path: "script.json"), options: .atomic)
        try Data("export default null".utf8)
            .write(to: source.appending(path: "index.tsx"), options: .atomic)
        let archive = root.appending(path: "export-fixture.scripting", directoryHint: .notDirectory)

        try HanlinScriptingPackageExporter().exportPackage(at: source, to: archive)
        let imported = try HanlinPackageCenter().stageAndInspect(
            sourceURL: archive,
            stagingParent: root
        )

        #expect(imported.inspection.wrapperDirectory == "Export Fixture")
        #expect(imported.manifest.name == "Export Fixture")
        #expect(try String(
            contentsOf: imported.packageRoot.appending(path: "index.tsx"),
            encoding: .utf8
        ) == "export default null")
    }

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
            atPath: package.packageRoot.appending(path: "index.tsx").path(percentEncoded: false)
        ))
        try HanlinPackageCenter().discard(package)
        #expect(!FileManager.default.fileExists(atPath: package.stagingRoot.path(percentEncoded: false)))
    }

    @Test("Imports prepared NativeScript packages containing ESM bundles")
    func nativeScriptPackageWithMJS() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let archiveURL = root.appending(path: "nativescript.hanlinNativeScript", directoryHint: .notDirectory)
        try makeArchive(
            at: archiveURL,
            files: [
                "script.json": Data(#"{"name":"NativeScript Fixture","version":"1.0.0","entry":"nativescript/app/bundle.mjs","hanlinRuntime":"hanlin-nativescript"}"#.utf8),
                "nativescript/app/package.json": Data(#"{"name":"fixture","version":"1.0.0","main":"bundle.mjs","hanlinRuntime":"hanlin-nativescript"}"#.utf8),
                "nativescript/app/bundle.mjs": Data("console.log('native')".utf8),
                "nativescript/app/vendor.mjs": Data("export const value = 1".utf8),
                "nativescript/app/rolldown-runtime.mjs": Data("export const runtime = true".utf8)
            ]
        )

        let package = try HanlinPackageCenter().stageAndInspect(
            sourceURL: archiveURL,
            stagingParent: root
        )
        #expect(package.inspection.isInstallable)
        #expect(package.source.format == .scripting)
        #expect(package.manifest.entry == "nativescript/app/bundle.mjs")
        #expect(FileManager.default.fileExists(
            atPath: package.packageRoot.appending(path: "nativescript/app/bundle.mjs").path(percentEncoded: false)
        ))
    }

    @Test("Imports archives from File Provider paths containing spaces")
    func fileProviderPathWithSpaces() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let providerRoot = root.appending(path: "File Provider Storage", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: providerRoot, withIntermediateDirectories: false)
        let archiveURL = providerRoot.appending(path: "test.zip", directoryHint: .notDirectory)
        try makeArchive(
            at: archiveURL,
            files: [
                "script.json": Data(#"{"name":"File Provider Fixture","version":"1.0.0","entry":"index.tsx"}"#.utf8),
                "index.tsx": Data("export default null".utf8)
            ]
        )

        let package = try HanlinPackageCenter().stageAndInspect(
            sourceURL: archiveURL,
            stagingParent: root
        )
        #expect(package.source.originalFileName == "test.zip")
        #expect(package.manifest.name == "File Provider Fixture")
        #expect(!package.archiveURL.absoluteString.contains("%2520"))
    }

    @Test("Imports archives whose source paths contain Unicode and spaces")
    func unicodeSourcePath() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceRoot = root.appending(path: "scripts 2", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: false)
        let archiveURL = sourceRoot.appending(path: "אכילה חכמה.zip", directoryHint: .notDirectory)
        try makeArchive(
            at: archiveURL,
            files: [
                "script.json": Data(#"{"name":"Unicode Fixture","version":"1.0.0","entry":"index.tsx"}"#.utf8),
                "index.tsx": Data("export default null".utf8)
            ]
        )

        let package = try HanlinPackageCenter().stageAndInspect(
            sourceURL: archiveURL,
            stagingParent: root
        )
        #expect(package.source.originalFileName == "אכילה חכמה.zip")
        #expect(package.manifest.name == "Unicode Fixture")
        #expect(!package.archiveURL.absoluteString.contains("%2520"))
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
