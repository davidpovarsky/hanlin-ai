import Foundation
import Testing
#if canImport(HanlinCacheProof)
@testable import HanlinCacheProof
#elseif canImport(HanlinChatDiagnosticsProof)
@testable import HanlinChatDiagnosticsProof
#else
@testable import AI_Hanlin
#endif

@Suite("Provider cache diagnostics accounting")
struct AgentTokenUsageCacheTests {
    @Test func unavailableAndPartialMeasurementsDoNotInventTotals() {
        #expect(AgentTokenUsage.unavailable.totalTokens == nil)
        #expect(AgentTokenUsage(inputTokens: 10, source: .providerReported).totalTokens == nil)
        #expect(AgentTokenUsage(outputTokens: 20, source: .providerReported).totalTokens == nil)
        #expect(AgentTokenUsage(inputTokens: 0, outputTokens: 0, source: .providerReported).totalTokens == 0)
        #expect(AgentTokenUsage(totalTokens: 17, source: .providerReported).totalTokens == 17)
    }

    @Test func cacheReadAndWriteAreSubsetsNotAdditionalTokenCharges() {
        let usage = AgentTokenUsage(
            inputTokens: 1_000, outputTokens: 100, reasoningTokens: 20,
            cachedInputTokens: 600, cacheWriteTokens: 300, source: .providerReported
        )
        #expect(usage.totalTokens == 1_100)
        let summary = AgentPromptCacheSummary(usages: [usage])
        #expect(summary.cachedInputTokens == 600 && summary.cacheWriteTokens == 300)
        #expect(summary.cacheReadFraction == 0.6)
    }

    @Test func legacyJSONAndRoundTripPreserveMissingAndReportedCacheValues() throws {
        let old = Data(#"{"inputTokens":10,"outputTokens":3,"totalTokens":13,"source":"providerReported"}"#.utf8)
        let legacy = try JSONDecoder().decode(AgentTokenUsage.self, from: old)
        #expect(legacy.cachedInputTokens == nil && legacy.cacheWriteTokens == nil)
        let usage = AgentTokenUsage(inputTokens: 100, outputTokens: 25, cachedInputTokens: 40,
                                    cacheWriteTokens: 30, source: .providerReported)
        let reopened = try JSONDecoder().decode(AgentTokenUsage.self, from: JSONEncoder().encode(usage))
        #expect(reopened == usage)
        #expect(AgentPromptCacheSummary(usages: [legacy]).cacheReadFraction == nil)
    }

    @Test func aggregateFractionRequiresCompleteProviderMeasurementCoverage() {
        let reported = AgentTokenUsage(inputTokens: 100, outputTokens: 10,
                                       cachedInputTokens: 80, cacheWriteTokens: 20, source: .providerReported)
        let missing = AgentTokenUsage(inputTokens: 200, outputTokens: 10, source: .providerReported)
        let summary = AgentPromptCacheSummary(usages: [reported, missing])
        #expect(summary.cachedInputTokens == 80 && summary.cacheWriteTokens == 20)
        #expect(summary.readReportedRoundCount == 1 && summary.writeReportedRoundCount == 1)
        #expect(summary.roundCount == 2 && summary.cacheReadFraction == nil)
        let estimated = AgentTokenUsage(inputTokens: 100, outputTokens: 10, source: .locallyEstimated)
        #expect(AgentPromptCacheSummary(usages: [reported, estimated]).cacheReadFraction == nil)
        #expect(AgentPromptCacheSummary(usages: []).cachedInputTokens == nil)
    }

    @Test func genuineZeroDiffersFromMissingAndInconsistentMeasurements() {
        let zero = AgentTokenUsage(inputTokens: 100, outputTokens: 10, cachedInputTokens: 0,
                                   cacheWriteTokens: 0, source: .providerReported)
        #expect(AgentPromptCacheSummary(usages: [zero]).cacheReadFraction == 0)
        let impossible = AgentTokenUsage(inputTokens: 50, cachedInputTokens: 60, source: .providerReported)
        #expect(AgentPromptCacheSummary(usages: [impossible]).cacheReadFraction == nil)
        let negative = AgentTokenUsage(inputTokens: 50, cachedInputTokens: -1, source: .providerReported)
        #expect(AgentPromptCacheSummary(usages: [negative]).cachedInputTokens == nil)
        let noInput = AgentTokenUsage(inputTokens: 0, cachedInputTokens: 0, source: .providerReported)
        #expect(AgentPromptCacheSummary(usages: [noInput]).cacheReadFraction == nil)
    }

    @Test func completeRoundAggregationRetainsWritesAndUsesWeightedReadFraction() {
        let first = AgentTokenUsage(inputTokens: 100, outputTokens: 10, cachedInputTokens: 80,
                                    cacheWriteTokens: 20, source: .providerReported)
        let second = AgentTokenUsage(inputTokens: 300, outputTokens: 30, cachedInputTokens: 120,
                                     cacheWriteTokens: 180, source: .providerReported)
        let aggregate = [first, second].reduce(AgentTokenUsage.unavailable, +)
        #expect(aggregate.cacheWriteTokens == 200 && aggregate.cachedInputTokens == 200)
        #expect(aggregate.totalTokens == 440)
        let summary = AgentPromptCacheSummary(usages: [first, second])
        #expect(summary.cacheReadFraction == 0.5)
        #expect(summary.readReportedRoundCount == 2 && summary.writeReportedRoundCount == 2)
    }

    @Test func readableReportIncludesCoverageAndKeepsUnknownUnavailable() {
        let missing = AgentPromptCacheSummary(usages: [.unavailable])
        let unknown = missing.readableLines.joined(separator: "\n")
        #expect(unknown.contains("unavailable") && unknown.contains("0/1 rounds"))
        let known = AgentPromptCacheSummary(usages: [
            .init(inputTokens: 1_000, outputTokens: 10, cachedInputTokens: 600,
                  cacheWriteTokens: 200, source: .providerReported)
        ]).readableLines.joined(separator: "\n")
        #expect(known.contains("600") && known.contains("200") && known.contains("60.0%"))
    }
}
