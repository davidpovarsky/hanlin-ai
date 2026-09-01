import Foundation
import HanlinScriptCompiler
import HanlinScriptContracts
import Testing

@Suite("Scripting archive safety")
struct HanlinArchivePolicyTests {
    @Test("Accepts one wrapped Scripting manifest and ignores macOS metadata")
    func wrappedPackage() {
        let entries = [
            entry("Fixture/", kind: .directory),
            entry("Fixture/script.json"),
            entry("Fixture/index.tsx"),
            entry("__MACOSX/Fixture/._index.tsx")
        ]
        let result = HanlinArchivePolicy().inspect(
            entries: entries,
            centralDirectoryEntryCount: entries.count,
            archiveBytes: 200
        )
        #expect(result.isInstallable)
        #expect(result.wrapperDirectory == "Fixture")
        #expect(result.manifestPath == "Fixture/script.json")
    }

    @Test("Accepts prepared NativeScript ESM bundle artifacts")
    func nativeScriptMJSBundle() {
        let entries = [
            entry("script.json"),
            entry("nativescript/app/package.json"),
            entry("nativescript/app/bundle.mjs"),
            entry("nativescript/app/vendor.mjs"),
            entry("nativescript/app/rolldown-runtime.mjs")
        ]
        let result = HanlinArchivePolicy().inspect(
            entries: entries,
            centralDirectoryEntryCount: entries.count,
            archiveBytes: 500
        )
        #expect(result.isInstallable)
        #expect(!result.findings.contains { $0.code == .unsupportedFileType })
    }

    @Test(arguments: [
        "../script.json",
        "/script.json",
        "C:/script.json",
        "folder/../../script.json"
    ])
    func rejectsEscapingPaths(path: String) {
        let entries = [entry(path), entry("script.json")]
        let result = HanlinArchivePolicy().inspect(
            entries: entries,
            centralDirectoryEntryCount: entries.count,
            archiveBytes: 100
        )
        #expect(!result.isInstallable)
    }

    @Test("Rejects links, normalization collisions, bombs, and hidden encrypted entries")
    func hostileEntries() {
        let entries = [
            entry("script.json"),
            entry("link.ts", kind: .symbolicLink),
            entry("É.ts"),
            entry("É.ts"),
            HanlinArchiveEntryMetadata(
                path: "bomb.json",
                kind: .file,
                compressedBytes: 1,
                uncompressedBytes: 10_000
            )
        ]
        let result = HanlinArchivePolicy().inspect(
            entries: entries,
            centralDirectoryEntryCount: entries.count + 1,
            archiveBytes: 200
        )
        #expect(!result.isInstallable)
        let codes = Set(result.findings.map(\.code))
        #expect(codes.contains(.symbolicLink))
        #expect(codes.contains(.unicodeCollision))
        #expect(codes.contains(.compressionRatioLimit))
        #expect(codes.contains(.encryptedEntry))
    }

    @Test("Rejects ambiguous manifests and case collisions")
    func ambiguousManifest() {
        let entries = [entry("script.json"), entry("Nested/script.json"), entry("INDEX.TSX"), entry("index.tsx")]
        let result = HanlinArchivePolicy().inspect(
            entries: entries,
            centralDirectoryEntryCount: entries.count,
            archiveBytes: 100
        )
        #expect(!result.isInstallable)
        #expect(result.findings.contains { $0.code == .ambiguousManifest })
        #expect(result.findings.contains { $0.code == .caseCollision })
    }

    private func entry(
        _ path: String,
        kind: HanlinArchiveEntryKind = .file
    ) -> HanlinArchiveEntryMetadata {
        .init(path: path, kind: kind, compressedBytes: 10, uncompressedBytes: 10)
    }
}
