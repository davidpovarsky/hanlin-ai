import CryptoKit
import Foundation
import HanlinPlatformContracts
import HanlinScriptCompiler
import HanlinScriptContracts
import Testing

@Suite("Retained NativeScript surface import")
struct HanlinRetainedSurfaceImportTests {
    @Test("The actual prepared NativeScript surface archive remains installable with its retained sources")
    func retainedNativeScriptSurfaceArchivePassesOriginalImportAnalysis() throws {
        let expectedSHA256 = "3441747a86120c936135f6a472be1a8e029f1b3480ea020a484585d25225d4b3"
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let archive = packageRoot.appending(path:
            "Fixtures/ImportRegressions/SurfaceNativeScript-39006.hanlinNativeScript")
        let bytes = try Data(contentsOf: archive)
        let archiveSHA256 = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        try #require(bytes.count == 33_751)
        try #require(archiveSHA256 == expectedSHA256)

        let observationID = UUID().uuidString.lowercased()
        let stagingParent = FileManager.default.temporaryDirectory.appending(
            path: "hanlin-retained-surface-import-" + observationID, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: stagingParent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stagingParent) }

        func retain(phase: String, preview: HanlinImportPreview? = nil, error: String? = nil) throws {
            let observation = Observation(
                schemaVersion: 1, observationID: observationID,
                sourceRunID: "46065801730", sourceCommit: "39006ce6586c1be056f53de9483bfd907cea6cbd",
                archiveSHA256: archiveSHA256, archiveBytes: bytes.count,
                processID: ProcessInfo.processInfo.processIdentifier, observedAt: Date(), phase: phase,
                nativeScriptRuntimeVersion: HanlinMiniAppHostVersions.nativeScriptRuntimeVersion,
                nativeScriptCoreVersion: HanlinMiniAppHostVersions.nativeScriptCoreVersion,
                nativeScriptSwiftUIVersion: HanlinMiniAppHostVersions.nativeScriptSwiftUIVersion,
                preview: preview, error: error)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(observation)
            print("HANLIN_RETAINED_SURFACE_IMPORT_OBSERVATION_BEGIN")
            print(String(decoding: data, as: UTF8.self))
            print("HANLIN_RETAINED_SURFACE_IMPORT_OBSERVATION_END")
            if let directory = ProcessInfo.processInfo.environment["HANLIN_WIDGET_EVIDENCE_DIR"] {
                let root = URL(fileURLWithPath: directory, isDirectory: true)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                try data.write(to: root.appending(path:
                    "retained-surface-import-" + observationID + "-" + phase + ".json"), options: .atomic)
            }
        }

        try retain(phase: "input-admitted")
        // A different native version admission must not be misclassified as a
        // widget compiler result. These are the original compatibility helpers.
        try #require(HanlinPreparedRuntimeVersion.supportsCompatiblePatch("9.1.1",
            installed: HanlinMiniAppHostVersions.nativeScriptRuntimeVersion))
        try #require(HanlinPreparedRuntimeVersion.supportsMinimum("9.1.4",
            installed: HanlinMiniAppHostVersions.nativeScriptCoreVersion))

        do {
            let staged = try HanlinPackageCenter().stageAndInspect(
                sourceURL: archive, stagingParent: stagingParent)
            try #require(staged.source.contentSHA256 == expectedSHA256)
            let analyzer = HanlinScriptAnalyzer(inventory: .init(
                baselineID: "retained-surface-import", baselineDigest: String(repeating: "a", count: 64),
                symbols: []))
            let preview = try analyzer.analyze(staged)
            try retain(phase: "analyzed", preview: preview)
            #expect(preview.canInstall, "Original import findings: \(preview.findings)")
            #expect(preview.findings.filter { $0.severity == .error }.isEmpty,
                "Original import findings: \(preview.findings)")
        } catch {
            try retain(phase: "threw", error: String(reflecting: error))
            throw error
        }
    }

    private struct Observation: Encodable {
        let schemaVersion: Int
        let observationID: String
        let sourceRunID: String
        let sourceCommit: String
        let archiveSHA256: String
        let archiveBytes: Int
        let processID: Int32
        let observedAt: Date
        let phase: String
        let nativeScriptRuntimeVersion: String
        let nativeScriptCoreVersion: String
        let nativeScriptSwiftUIVersion: String
        let preview: HanlinImportPreview?
        let error: String?
    }
}
