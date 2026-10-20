//
//  AutomaticWebSearchTests.swift
//  AI_HLYTests
//
//  Created for Hanlin AI Automatic Web Search on 2026-10-21.
//

import Foundation
import SwiftData
import Testing

@testable import AI_Hanlin

@Suite("Automatic Web Search Tests", .serialized)
struct AutomaticWebSearchTests {
    
    // MARK: - Test Mock Provider
    
    final class MockSearchProvider: WebSearchProvider, @unchecked Sendable {
        let providerID: String
        let displayName: String
        
        var shouldThrow: AutomaticSearchError? = nil
        var returnedResults: [WebSearchResult] = []
        var callCount: Int = 0
        var simulatedDelay: TimeInterval = 0.0
        
        init(
            providerID: String,
            displayName: String,
            returnedResults: [WebSearchResult] = [],
            shouldThrow: AutomaticSearchError? = nil,
            simulatedDelay: TimeInterval = 0.0
        ) {
            self.providerID = providerID
            self.displayName = displayName
            self.returnedResults = returnedResults
            self.shouldThrow = shouldThrow
            self.simulatedDelay = simulatedDelay
        }
        
        func search(query: String, count: Int, timeout: TimeInterval) async throws -> [WebSearchResult] {
            callCount += 1
            if simulatedDelay > 0 {
                try await Task.sleep(nanoseconds: UInt64(simulatedDelay * 1_000_000_000))
            }
            if let error = shouldThrow {
                throw error
            }
            return returnedResults
        }
    }
    
    // MARK: - Fixture Data
    
    private let sampleYouJSON = """
    {
      "results": {
        "web": [
          {
            "url": "https://developer.apple.com/swiftui/",
            "title": "SwiftUI - Apple Developer",
            "description": "SwiftUI description",
            "snippets": "SwiftUI declarative syntax snippet",
            "favicon_url": "https://developer.apple.com/favicon.ico"
          },
          {
            "url": "https://www.swift.org/getting-started/swiftui/",
            "title": "Build an iOS app with SwiftUI | Swift.org",
            "description": "Swift.org description",
            "snippets": "Swift.org snippet text",
            "favicon_url": "https://swift.org/favicon.ico"
          }
        ]
      },
      "metadata": {
        "latency": 0.25
      }
    }
    """.data(using: .utf8)!
    
    private let sampleTavilyJSON = """
    {
      "query": "SwiftUI",
      "results": [
        {
          "url": "https://en.wikipedia.org/wiki/SwiftUI",
          "title": "SwiftUI - Wikipedia",
          "content": "SwiftUI is declarative framework by Apple.",
          "score": 0.95
        }
      ]
    }
    """.data(using: .utf8)!
    
    private let sampleKeenableJSON = """
    {
      "query": "SwiftUI",
      "mode": "public",
      "results": [
        {
          "title": "SwiftUI Guide",
          "url": "https://example.com/swiftui-guide",
          "snippet": "A comprehensive guide to SwiftUI.",
          "description": "Backup description",
          "acquired_at": "2026-10-20T12:00:00Z"
        }
      ]
    }
    """.data(using: .utf8)!

    // MARK: - Unit Tests: Fallback Sequence
    
    @Test("Fallback Sequence: Provider 1 succeeds, subsequent providers are not invoked")
    func provider1Succeeds() async throws {
        let result1 = WebSearchResult(title: "Result 1", url: "https://example.com/1", snippet: "Snippet 1", sourceBackend: "you")
        let p1 = MockSearchProvider(providerID: "you", displayName: "You.com", returnedResults: [result1])
        let p2 = MockSearchProvider(providerID: "tavily", displayName: "Tavily")
        let p3 = MockSearchProvider(providerID: "keenable", displayName: "Keenable")
        
        let coordinator = AutomaticWebSearchCoordinator(providers: [p1, p2, p3])
        let (parsed, engineName) = try await coordinator.search(query: "SwiftUI iOS 27", count: 5)
        
        #expect(p1.callCount == 1)
        #expect(p2.callCount == 0)
        #expect(p3.callCount == 0)
        #expect(parsed.titles.count == 1)
        #expect(parsed.titles.first == "Result 1")
        #expect(engineName.contains("You.com"))
    }
    
    @Test("Fallback Sequence: Provider 1 fails with 429, falls back to Provider 2")
    func provider1FailsRateLimitFallsBackToProvider2() async throws {
        let result2 = WebSearchResult(title: "Tavily Result", url: "https://example.com/tavily", snippet: "Tavily snippet", sourceBackend: "tavily")
        let p1 = MockSearchProvider(providerID: "you", displayName: "You.com", shouldThrow: .rateLimited(retryAfter: 60))
        let p2 = MockSearchProvider(providerID: "tavily", displayName: "Tavily", returnedResults: [result2])
        let p3 = MockSearchProvider(providerID: "keenable", displayName: "Keenable")
        
        let coordinator = AutomaticWebSearchCoordinator(providers: [p1, p2, p3])
        let (parsed, engineName) = try await coordinator.search(query: "זמני תפילה ירושלים", count: 5)
        
        #expect(p1.callCount == 1)
        #expect(p2.callCount == 1)
        #expect(p3.callCount == 0)
        #expect(parsed.titles.first == "Tavily Result")
        #expect(engineName.contains("Tavily"))
    }
    
    @Test("Fallback Sequence: Provider 1 & 2 fail, falls back to Provider 3")
    func provider1And2FailFallsBackToProvider3() async throws {
        let result3 = WebSearchResult(title: "Keenable Result", url: "https://example.com/keenable", snippet: "Keenable snippet", sourceBackend: "keenable")
        let p1 = MockSearchProvider(providerID: "you", displayName: "You.com", shouldThrow: .networkError("Connection refused"))
        let p2 = MockSearchProvider(providerID: "tavily", displayName: "Tavily", shouldThrow: .httpError(statusCode: 500, message: "Internal error"))
        let p3 = MockSearchProvider(providerID: "keenable", displayName: "Keenable", returnedResults: [result3])
        
        let coordinator = AutomaticWebSearchCoordinator(providers: [p1, p2, p3])
        let (parsed, engineName) = try await coordinator.search(query: "רש\"י פרשת נח", count: 5)
        
        #expect(p1.callCount == 1)
        #expect(p2.callCount == 1)
        #expect(p3.callCount == 1)
        #expect(parsed.titles.first == "Keenable Result")
        #expect(engineName.contains("Keenable"))
    }
    
    @Test("Fallback Sequence: All providers fail throws structured error without fabricating citations")
    func allProvidersFailThrowsStructuredError() async throws {
        let p1 = MockSearchProvider(providerID: "you", displayName: "You.com", shouldThrow: .networkError("Timeout"))
        let p2 = MockSearchProvider(providerID: "tavily", displayName: "Tavily", shouldThrow: .rateLimited(retryAfter: 30))
        let p3 = MockSearchProvider(providerID: "keenable", displayName: "Keenable", shouldThrow: .emptyResults)
        
        let coordinator = AutomaticWebSearchCoordinator(providers: [p1, p2, p3])
        
        await #expect(throws: AutomaticSearchError.self) {
            _ = try await coordinator.search(query: "NASA Artemis II", count: 5)
        }
    }
    
    // MARK: - Unit Tests: Query Caching
    
    @Test("Query Caching: Duplicate normalized query returns cached results without invoking network")
    func queryCachingAvoidsDuplicateCalls() async throws {
        let result1 = WebSearchResult(title: "Cached Title", url: "https://example.com/cached", snippet: "Cached snippet", sourceBackend: "you")
        let p1 = MockSearchProvider(providerID: "you", displayName: "You.com", returnedResults: [result1])
        let coordinator = AutomaticWebSearchCoordinator(providers: [p1])
        
        // First call
        let (res1, _) = try await coordinator.search(query: "  SwiftUI iOS 27  ", count: 5)
        #expect(p1.callCount == 1)
        #expect(res1.titles.first == "Cached Title")
        
        // Second call with different casing and whitespace
        let (res2, engine2) = try await coordinator.search(query: "swiftui ios 27", count: 5)
        #expect(p1.callCount == 1) // Did not increment!
        #expect(res2.titles.first == "Cached Title")
        #expect(engine2.contains("cached"))
    }
    
    // MARK: - Unit Tests: Canonical Deduplication & Normalization
    
    @Test("Canonical Deduplication: Removes tracking queries and duplicate paths")
    func canonicalDeduplication() {
        let item1 = WebSearchResult(title: "Apple SwiftUI", url: "https://developer.apple.com/swiftui/?utm_source=twitter&utm_medium=social", snippet: "Desc 1")
        let item2 = WebSearchResult(title: "Apple SwiftUI Alt", url: "https://developer.apple.com/swiftui", snippet: "Desc 2")
        let item3 = WebSearchResult(title: "Different Page", url: "https://developer.apple.com/xcode", snippet: "Desc 3")
        
        #expect(item1.canonicalURLString == item2.canonicalURLString)
        #expect(item1.canonicalURLString != item3.canonicalURLString)
    }
    
    @Test("ParsedSearchResult Synchronization: Parallel arrays match in count")
    func parsedSearchResultSynchronization() {
        let items = [
            WebSearchResult(title: "T1", url: "https://example.com/1", snippet: "S1", icon: "https://icon.com/1"),
            WebSearchResult(title: "T2", url: "https://example.com/2", snippet: "S2", icon: ""),
            WebSearchResult(title: "", url: "https://invalid.com", snippet: "Empty title"), // Invalid, filtered
            WebSearchResult(title: "T3", url: "https://example.com/3", snippet: "S3", icon: "https://icon.com/3")
        ]
        
        let parsed = WebSearchResult.toParsedSearchResult(items, defaultIcon: "https://default.com/icon.png")
        
        #expect(parsed.titles.count == 3)
        #expect(parsed.links.count == 3)
        #expect(parsed.contents.count == 3)
        #expect(parsed.icons.count == 3)
        #expect(parsed.icons[1] == "https://default.com/icon.png")
    }
    
    // MARK: - Unit Tests: Hebrew & RTL Query Handling
    
    @Test("Hebrew Query: Unicode and percent-encoding preservation")
    func hebrewQueryHandling() throws {
        let query = "זמני תפילה בירושלים ליום כיפור"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            Issue.record("Failed to percent encode Hebrew query")
            return
        }
        
        #expect(encoded.contains("%D7%96"))
        let decoded = encoded.removingPercentEncoding
        #expect(decoded == query)
    }
    
    // MARK: - Unit Tests: Diagnostic Test
    
    @Test("Diagnostic Probe: Captures honest timing, provider identity and top source")
    func diagnosticProbeSuccess() async {
        let result = WebSearchResult(title: "News Headline", url: "https://news.com/article", snippet: "Breaking news", sourceBackend: "you")
        let p1 = MockSearchProvider(providerID: "you", displayName: "You.com", returnedResults: [result])
        let coordinator = AutomaticWebSearchCoordinator(providers: [p1])
        
        let diag = await coordinator.runDiagnosticTest()
        
        #expect(diag.success == true)
        #expect(diag.providerUsed.contains("You.com"))
        #expect(diag.topSourceTitle == "News Headline")
        #expect(diag.topSourceURL == "https://news.com/article")
        #expect(diag.errorMessage == nil)
        #expect(diag.duration >= 0.0)
    }
    
    @Test("Diagnostic Probe: Captures honest failure without fake connected state")
    func diagnosticProbeFailure() async {
        let p1 = MockSearchProvider(providerID: "you", displayName: "You.com", shouldThrow: .rateLimited(retryAfter: 60))
        let coordinator = AutomaticWebSearchCoordinator(providers: [p1])
        
        let diag = await coordinator.runDiagnosticTest()
        
        #expect(diag.success == false)
        #expect(diag.providerUsed == "None")
        #expect(diag.topSourceTitle.isEmpty)
        #expect(diag.errorMessage != nil)
    }

    // MARK: - Unit Tests: Migration & Bootstrap
    
    @MainActor
    @Test("Migration Logic: Fresh install enables Automatic search key as active")
    func freshInstallEnablesAutomaticSearch() throws {
        let schema = Schema([SearchKeys.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        // Run migration on empty store
        AutomaticSearchMigration.reconcileDefaultProvider(in: context)
        
        let descriptor = FetchDescriptor<SearchKeys>()
        let keys = try context.fetch(descriptor)
        
        #expect(keys.count == 1)
        #expect(keys.first?.company == "AUTOMATIC_KEYLESS")
        #expect(keys.first?.isUsing == true)
    }
    
    @MainActor
    @Test("Migration Logic: Existing install with valid manual provider preserves selection")
    func existingValidManualProviderPreserved() throws {
        let schema = Schema([SearchKeys.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        // Insert active configured manual key
        let manualKey = SearchKeys(
            name: "TAVILY_KEY",
            company: "TAVILY",
            key: "tvly-valid-key-12345",
            requestURL: "https://api.tavily.com/search",
            isUsing: true
        )
        context.insert(manualKey)
        
        // Run migration
        AutomaticSearchMigration.reconcileDefaultProvider(in: context)
        
        let descriptor = FetchDescriptor<SearchKeys>()
        let keys = try context.fetch(descriptor)
        
        let tavily = keys.first { $0.company == "TAVILY" }
        let auto = keys.first { $0.company == "AUTOMATIC_KEYLESS" }
        
        #expect(tavily?.isUsing == true)
        #expect(auto?.isUsing == false)
    }
    
    @MainActor
    @Test("Migration Logic: Existing install with unconfigured/empty manual provider switches to automatic")
    func existingUnconfiguredManualProviderSwitchesToAutomatic() throws {
        let schema = Schema([SearchKeys.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        
        // Insert unconfigured manual key with empty apiKey
        let emptyKey = SearchKeys(
            name: "ZHIPUAI_SEARCH_KEY",
            company: "ZHIPUAI",
            key: "",
            requestURL: "https://open.bigmodel.cn/api/paas/v4/web_search",
            isUsing: true
        )
        context.insert(emptyKey)
        
        // Run migration
        AutomaticSearchMigration.reconcileDefaultProvider(in: context)
        
        let descriptor = FetchDescriptor<SearchKeys>()
        let keys = try context.fetch(descriptor)
        
        let zhipu = keys.first { $0.company == "ZHIPUAI" }
        let auto = keys.first { $0.company == "AUTOMATIC_KEYLESS" }
        
        #expect(zhipu?.isUsing == false)
        #expect(auto?.isUsing == true)
    }
}
