import CryptoKit
import Foundation
import HanlinPlatformContracts
import HanlinScriptCompiler
import HanlinScriptContracts
import HanlinWidgetCompiler
import Testing

@Suite("Retained Expo widget artifact")
struct HanlinRetainedExpoWidgetArtifactTests {
    @Test("The retained widget materializes while all foreground and editable source bytes survive")
    func retainedExpoWidgetMaterializesWithOriginalArtifactWriter() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let archive = packageRoot.appending(path:
            "Fixtures/ImportRegressions/SurfaceExpo-39006.hanlinExpo")
        let archiveBytes = try Data(contentsOf: archive)
        let archiveSHA256 = digest(archiveBytes)
        try #require(archiveBytes.count == 2_018_717)
        try #require(archiveSHA256 == "dae2e23187170548f197f532a991aa26fc3fca1f394613499d2e24696f7199ed")

        let observationID = UUID().uuidString.lowercased()
        let root = FileManager.default.temporaryDirectory.appending(
            path: "hanlin-retained-expo-widget-" + observationID, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // These are all 15 members of the exact SHA-bound retained archive.
        // The original PackageCenter still performs archive-policy inspection
        // and extraction before the original Widget compiler receives bytes.
        let paths = [
            "bundle.js", "bundle.js.map", "hanlin.authoring.json", "hanlin.validation.json",
            "package.json", "script.json", "source/App.tsx", "source/hanlin.authoring.json",
            "source/index.ts", "source/package.json", "source/proof.ts", "source/script.json",
            "source/tsconfig.json", "source/widget.json", "widget.json"
        ]
        var resources: [FileFact] = []
        var programBytes: Int?
        var programSHA256: String?

        func retain(_ phase: String, error: String? = nil) throws {
            let observation = Observation(
                schemaVersion: 1, observationID: observationID,
                retainedArchiveRunID: "46065835197",
                retainedArchiveSourceCommit: "39006ce6586c1be056f53de9483bfd907cea6cbd",
                archiveSHA256: archiveSHA256, archiveBytes: archiveBytes.count,
                processID: ProcessInfo.processInfo.processIdentifier, observedAt: Date(),
                phase: phase, currentExpoSDKVersion: HanlinMiniAppHostVersions.expoSDKVersion,
                currentExpoUIVersion: HanlinMiniAppHostVersions.expoUIVersion,
                scope: "Original Widget compiler and artifact writer only; no native-version admission, foreground runtime, installed-store or OS acceptance",
                programBytes: programBytes, programSHA256: programSHA256,
                widgetResources: resources, error: error)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(observation)
            print("HANLIN_RETAINED_EXPO_WIDGET_OBSERVATION_BEGIN")
            print(String(decoding: data, as: UTF8.self))
            print("HANLIN_RETAINED_EXPO_WIDGET_OBSERVATION_END")
            if let directory = ProcessInfo.processInfo.environment["HANLIN_WIDGET_EVIDENCE_DIR"] {
                let evidence = URL(fileURLWithPath: directory, isDirectory: true)
                try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
                try data.write(to: evidence.appending(path:
                    "retained-expo-widget-" + observationID + "-" + phase + ".json"), options: .atomic)
            }
        }

        try retain("input-admitted")
        do {
            let staged = try HanlinPackageCenter().stageAndInspect(
                sourceURL: archive, stagingParent: root)
            try #require(staged.source.contentSHA256 == archiveSHA256)
            let files = try Dictionary(uniqueKeysWithValues: paths.map { path in
                (path, try Data(contentsOf: staged.packageRoot.appending(path: path)))
            })
            try #require(files["bundle.js.map"]?.count == 6_740_756)

            // The historical native host accepted this archive before its
            // artifact writer failed. Current Expo version authorities differ,
            // so this discriminator deliberately targets the unchanged Widget
            // compiler/writer subpipeline, without overriding any version/pin.
            let program = try HanlinWidgetCompiler.prepare(
                manifest: staged.manifest, entryPath: "widget.json", files: files)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let encoded = try encoder.encode(program)
            programBytes = encoded.count
            programSHA256 = digest(encoded)
            resources = program.resources.keys.sorted().map { path in
                let data = program.resources[path]!
                return FileFact(path: path, bytes: data.count, sha256: digest(data))
            }
            try retain("widget-prepared")

            // Use the existing installed-widget test's empty compiled carrier.
            // The actual Widget compiler has already run. General Scripting
            // compilation is forbidden here and cannot replace either engine.
            let baselineID = "retained-expo-widget-artifact"
            let baselineDigest = String(repeating: "a", count: 64)
            let compiled = HanlinScriptingBundle(manifest: .init(
                compilerVersion: "Widget-ABI-1", compilerIntegrity: archiveSHA256,
                compilerOptionsHash: String(repeating: "b", count: 64),
                baselineID: baselineID, baselineDigest: baselineDigest, hanlinABIVersion: "1",
                packageContentDigest: archiveSHA256, cacheFingerprint: archiveSHA256, files: []),
                modules: [], diagnostics: [])
            let bundler = HanlinScriptingBundler(
                baseline: .init(baselineID: baselineID, baselineDigest: baselineDigest, symbols: []),
                abiVersion: "1", scriptingDeclarations: [], compiler: ForbiddenScriptingCompiler())
            let artifactRoot = root.appending(path: "Artifact", directoryHint: .isDirectory)
            let installed = try bundler.writeInstallArtifact(compiled,
                packageRoot: staged.packageRoot, to: artifactRoot,
                preparedWidgetPrograms: ["widgets/retained-expo.json": encoded])

            // Correct Widget scoping must never discard the original editable
            // files or foreground source map from the source-inclusive artifact.
            for path in paths {
                let expected = try #require(files[path])
                let actual = try Data(contentsOf: artifactRoot.appending(path: "source/" + path))
                #expect(actual == expected, "Source bytes changed: \(path)")
                #expect(installed.files.contains {
                    $0.logicalPath == "source/" + path && $0.sha256 == digest(expected)
                }, "Source manifest entry is missing or changed: \(path)")
            }
            let installedProgram = try Data(contentsOf:
                artifactRoot.appending(path: "widgets/retained-expo.json"))
            #expect(installedProgram == encoded)
            try retain("artifact-materialized")
        } catch {
            try retain("threw", error: String(reflecting: error))
            throw error
        }
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private struct ForbiddenScriptingCompiler: HanlinTrustedCompilerClient {
        func compile(_ project: HanlinVirtualTypeScriptProject) async throws -> HanlinTrustedCompilerResult {
            throw HanlinWidgetProgramError.unsupportedImport
        }
    }

    private struct FileFact: Encodable {
        let path: String
        let bytes: Int
        let sha256: String
    }

    private struct Observation: Encodable {
        let schemaVersion: Int
        let observationID: String
        let retainedArchiveRunID: String
        let retainedArchiveSourceCommit: String
        let archiveSHA256: String
        let archiveBytes: Int
        let processID: Int32
        let observedAt: Date
        let phase: String
        let currentExpoSDKVersion: String
        let currentExpoUIVersion: String
        let scope: String
        let programBytes: Int?
        let programSHA256: String?
        let widgetResources: [FileFact]
        let error: String?
    }
}
