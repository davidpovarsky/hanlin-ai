import CryptoKit
import SwiftData
import Testing
@testable import AI_Hanlin

@MainActor
@Suite("Runtime autonomy V3 persistence", .serialized)
struct RuntimeAutonomyV3Tests {
    @Test func defaultSchemaExposureDoesNotHideToolsPastOldBudgets() {
        let aliases = (0..<64).map { "tool_\($0)" }
        let sizes = Dictionary(uniqueKeysWithValues: aliases.map { ($0, 1024) })
        let decision = AssistantToolExposurePlanner().plan(candidateAliases: aliases, schemaSizes: sizes)
        #expect(decision.exposedAliases == aliases)
        #expect(decision.deferredAliases.isEmpty)
        #expect(decision.totalExposedBytes == 65536)
    }

    @Test func fullResultsExceedOldCountAndByteCapsAndSurviveReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ToolResultStore(directory: directory)
        let payload = String(repeating: "שלום 👨‍👩‍👧‍👦\n", count: 8192)
        let digest = SHA256.hash(data: Data(payload.utf8))
        var references: [String] = []
        for _ in 0..<64 { references.append(try #require(store.store(payload))) }
        #expect(store.currentTotalBytes > 10 * 1024 * 1024)
        let reopened = ToolResultStore(directory: directory)
        for reference in references {
            let full = try #require(reopened.fullPayload(for: reference))
            #expect(SHA256.hash(data: Data(full.utf8)) == digest)
        }
        let reference = try #require(references.first)
        var reconstructed = ""
        var offset = 0
        while true {
            let slice = try #require(reopened.read(reference: reference, offset: offset, limit: 4093))
            reconstructed += slice.chunk
            if !slice.hasMore { break }
            offset = slice.offset + slice.sliceLength
        }
        #expect(reconstructed == payload)
        #expect(reopened.read(reference: "../../private") == nil)
    }

    @Test func finishingRunKeepsHistoryReferencesButNotExposedSchemas() throws {
        let session = AssistantCapabilitySession()
        defer { session.resultStore.clear() }
        session.exposeTools(aliases: ["private_run_tool"])
        let reference = try #require(session.resultStore.store("saved result שלום"))
        session.finishRun()
        session.reset()
        #expect(!session.isToolExposed("private_run_tool"))
        #expect(session.resultStore.fullPayload(for: reference) == "saved result שלום")
    }

    @Test func capabilityReportNeverPromotesStoppedOrFailedEnginesToReady() throws {
        var failed = RuntimeSnapshot.stopped(.node)
        failed.state = .failed
        failed.lastErrorCode = "startup_failed"
        let report = RuntimeCapabilityContract(snapshots: [.stopped(.localPython), failed])
        let encoded = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(RuntimeCapabilityContract.self, from: encoded)
        #expect(decoded.snapshots[0].state == .stopped)
        #expect(decoded.snapshots[0].version == nil)
        #expect(decoded.snapshots[1].state == .failed)
        #expect(decoded.snapshots[1].lastErrorCode == "startup_failed")
    }
}
