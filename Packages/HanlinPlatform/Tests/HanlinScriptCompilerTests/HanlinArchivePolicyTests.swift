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

    @Test("Autonomous Skills accept large resources while explicit budgets remain enforceable")
    func autonomousSkillResources() {
        let entries = [entry("SKILL.md"), HanlinArchiveEntryMetadata(
            path: "resources/model.bin", kind: .file,
            compressedBytes: 300_000_000, uncompressedBytes: 600_000_000)]
        let autonomous = HanlinArchivePolicy(limits: .autonomousSkillImport).inspectSkillArchive(
            entries: entries, centralDirectoryEntryCount: entries.count, archiveBytes: 300_000_100)
        #expect(autonomous.isInstallable)
        #expect(autonomous.uncompressedBytes == 600_000_010)
        let bounded = HanlinArchivePolicy().inspectSkillArchive(
            entries: entries, centralDirectoryEntryCount: entries.count, archiveBytes: 300_000_100)
        #expect(!bounded.isInstallable)
        #expect(bounded.findings.contains { $0.code == .compressedSizeLimit })
    }

    @Test("Autonomous Skills still reject invalid sizes, overflow, escaping paths and collisions")
    func autonomousSkillIntegrity() {
        let invalidSets: [[HanlinArchiveEntryMetadata]] = [
            [entry("SKILL.md"), .init(path: "bad.bin", kind: .file, compressedBytes: -1, uncompressedBytes: 0)],
            [entry("SKILL.md"), .init(path: "bad.bin", kind: .file, compressedBytes: .max, uncompressedBytes: .max)],
            [entry("SKILL.md"), entry("../escape.py")],
            [entry("SKILL.md"), entry("É.py"), entry("É.py")]
        ]
        let policy = HanlinArchivePolicy(limits: .autonomousSkillImport)
        for entries in invalidSets {
            let result = policy.inspectSkillArchive(entries: entries,
                centralDirectoryEntryCount: entries.count, archiveBytes: 100)
            #expect(!result.isInstallable)
        }
        let negative = policy.inspectSkillArchive(entries: [entry("SKILL.md")],
            centralDirectoryEntryCount: 1, archiveBytes: -1)
        #expect(negative.findings.contains { $0.code == .malformedArchive })
    }

    private func entry(
        _ path: String,
        kind: HanlinArchiveEntryKind = .file
    ) -> HanlinArchiveEntryMetadata {
        .init(path: path, kind: kind, compressedBytes: 10, uncompressedBytes: 10)
    }
}
