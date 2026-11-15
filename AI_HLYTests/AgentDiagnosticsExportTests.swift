import CryptoKit
import Foundation
import Testing
import ZIPFoundation
#if canImport(HanlinChatDiagnosticsProof)
@testable import HanlinChatDiagnosticsProof
#else
@testable import AI_Hanlin
#endif

@Suite("Local diagnostic export privacy and coverage")
struct AgentDiagnosticsExportTests {
    @Test func archiveRedactsAgainExcludesRawAndAuthenticatesExportedBytes() throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let base = directory.appending(path: "agent-session-fixture")
        try Data(#"{"modelID":"fixture","rounds":[{"authorization":"Bearer NEVER_HEADER","content":"שלום🙂","payload":"{\"api_key\":\"NEVER_NESTED\"}"}]}"#.utf8).write(to: base.appendingPathExtension("json"))
        try Data("Conversation שלום🙂\nAuthorization: Bearer NEVER_TEXT\n".utf8).write(to: base.appendingPathExtension("txt"))
        try Data(#"{"status":"failed","droppedByteCount":7,"truncated":true}"#.utf8).write(to: URL(filePath: base.path + "-manifest.json"))
        try Data("data: NEVER_RAW".utf8).write(to: URL(filePath: base.path + ".raw.enc"))
        try Data("NEVER_UNRELATED".utf8).write(to: directory.appending(path: "unrelated.txt"))
        let result = try AgentDiagnosticsExporter.prepare(sessionJSON: base.appendingPathExtension("json"))
        defer { result.discard() }
        let archive = try Archive(url: result.archive, accessMode: .read)
        let names = archive.map(\.path)
        #expect(!names.contains(where: { $0.contains("raw.enc") || $0.contains("unrelated") }))
        let manifestData = try extracted("export-manifest.json", from: archive)
        let manifest = try #require(try JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        #expect(manifest["rawIncluded"] as? Bool == false)
        #expect((manifest["capture"] as? [String: Any])?["truncated"] as? Bool == true)
        let records = try #require(manifest["files"] as? [[String: Any]])
        for record in records {
            let name = try #require(record["name"] as? String)
            let bytes = try extracted(name, from: archive)
            let text = String(decoding: bytes, as: UTF8.self)
            for secret in ["NEVER_HEADER", "NEVER_NESTED", "NEVER_TEXT", "NEVER_RAW", "NEVER_UNRELATED"] {
                #expect(!text.contains(secret))
            }
            #expect(record["sha256"] as? String == SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
            #expect(record["bytes"] as? Int == bytes.count)
        }
        #expect(result.conversationPreview.contains("שלום🙂"))
        #expect(result.missingFiles.count == 2)
        result.discard()
        #expect(!FileManager.default.fileExists(atPath: result.directory.path))
        #expect(FileManager.default.fileExists(atPath: base.path + ".raw.enc"))
    }

    @Test func symlinksAndOversizedAssetsFailInsteadOfEscapingOrTruncating() throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "agent-session-fixture.json")
        let target = directory.appending(path: "private.json")
        try Data("{}".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: source, withDestinationURL: target)
        #expect(throws: (any Error).self) { _ = try AgentDiagnosticsExporter.prepare(sessionJSON: source) }
        try FileManager.default.removeItem(at: source)
        try Data().write(to: source)
        let handle = try FileHandle(forWritingTo: source)
        try handle.truncate(atOffset: 64 * 1024 * 1024 + 1)
        try handle.close()
        #expect(throws: (any Error).self) { _ = try AgentDiagnosticsExporter.prepare(sessionJSON: source) }
    }

    @Test func crashTailIsExplicitAndMalformedCompleteRecordsFail() throws {
        let directory = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "agent-session-fixture.json")
        let events = directory.appending(path: "agent-session-fixture-stage-events.jsonl")
        try Data("{}".utf8).write(to: source)
        try Data("{\"sequence\":1}\n{\"secret\":\"PARTIAL_SECRET".utf8).write(to: events)
        let result = try AgentDiagnosticsExporter.prepare(sessionJSON: source)
        defer { result.discard() }
        #expect(result.missingFiles.contains(where: { $0.contains("incomplete final event") }))
        let archive = try Archive(url: result.archive, accessMode: .read)
        let bytes = try extracted(events.lastPathComponent, from: archive)
        #expect(!String(decoding: bytes, as: UTF8.self).contains("PARTIAL_SECRET"))
        try Data("{broken}\n".utf8).write(to: events)
        #expect(throws: (any Error).self) { _ = try AgentDiagnosticsExporter.prepare(sessionJSON: source) }
    }

    @Test func upgradeStopsLegacyDeletionAndRespectsSubsequentExplicitChoice() throws {
        let name = "hanlin-diagnostic-retention-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(50, forKey: AgentDiagnosticsConfiguration.retentionKey)
        #expect(AgentDiagnosticsConfiguration.retentionLimit(in: defaults) == 0)
        defaults.set(10, forKey: AgentDiagnosticsConfiguration.retentionKey)
        #expect(AgentDiagnosticsConfiguration.retentionLimit(in: defaults) == 10)
    }

    private func fixtureDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private func extracted(_ name: String, from archive: Archive) throws -> Data {
        let entry = try #require(archive[name])
        var result = Data()
        _ = try archive.extract(entry) { result.append($0) }
        return result
    }
}
