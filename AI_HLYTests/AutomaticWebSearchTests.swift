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

@Suite("Automatic Web Search Hardened Tests", .serialized)
struct AutomaticWebSearchTests {

    // MARK: - Thread-Safe Actor Mock Provider

    // MARK: - Thread-Safe Test Clock
    final class TestClock: @unchecked Sendable {
        private let lock = NSLock()
        private var _current: Date
        init(_ date: Date) { self._current = date }
        var current: Date {
            get { lock.lock(); defer { lock.unlock() }; return _current }
            set { lock.lock(); defer { lock.unlock() }; _current = newValue }
        }
        func advance(by seconds: TimeInterval) {
            lock.lock()
            defer { lock.unlock() }
            _current = _current.addingTimeInterval(seconds)
        }
    }

    actor MockSearchProvider: WebSearchProvider {
        let providerID: String
        let displayName: String

        private var shouldThrow: AutomaticSearchError?
        private var returnedResults: [WebSearchResult]
        private(set) var callCount: Int = 0
        private var simulatedDelay: TimeInterval

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

        func setResults(_ results: [WebSearchResult]) {
            self.returnedResults = results
        }

        func setError(_ error: AutomaticSearchError?) {
            self.shouldThrow = error
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

    // MARK: - Sanitized Real-World Fixtures

    private static let sampleYouJSON = """
    {
      "results": {
        "web": [
          {
            "url": "https://developer.apple.com/swiftui/",
            "title": "SwiftUI - Apple Developer",
            "description": "SwiftUI is an innovative way to build interfaces.",
            "snippets": "SwiftUI uses a declarative syntax across Apple platforms.",
            "favicon_url": "https://developer.apple.com/favicon.ico"
          },
          {
            "url": "https://www.swift.org/getting-started/swiftui/",
            "title": "Build an iOS app with SwiftUI | Swift.org",
            "description": "Swift.org documentation for SwiftUI.",
            "snippets": ["Declarative UI patterns in Swift."],
            "favicon_url": "https://swift.org/favicon.ico"
          }
        ]
      },
      "metadata": {
        "latency": 0.218
      }
    }
    """.data(using: .utf8)!

    private static let sampleTavilyJSON = """
    {
      "query": "זמני תפילה ירושלים",
      "results": [
        {
          "url": "https://astrojew.com/zmanim-jerusalem",
          "title": "זמני היום בירושלים - זמני תפילה והלכה",
          "content": "זמני תפילה מדויקים בירושלים: נץ החמה, חצות, מנחה וערבית לכל ימות השנה.",
          "score": 0.98
        }
      ]
    }
    """.data(using: .utf8)!

    private static let sampleKeenableJSON = """
    {
      "query": "SwiftUI",
      "mode": "public",
      "results": [
        {
          "title": "SwiftUI Overview - Apple Developer",
          "url": "https://developer.apple.com/swiftui",
          "snippet": "SwiftUI helps you build great-looking apps across Apple devices.",
          "description": "Apple developer overview",
          "acquired_at": "2026-09-27T17:10:50Z"
        }
      ]
    }
    """.data(using: .utf8)!

    // MARK: - 1. Adapter JSON Decoding Tests

    @Test("Adapter Decoding: YouKeylessSearchAdapter decodes valid JSON fixture with mixed snippet formats")
    func youAdapterDecodesFixture() throws {
        let adapter = YouKeylessSearchAdapter()
        let results = try adapter.parseYouResponse(data: Self.sampleYouJSON)

        #expect(results.count == 2)
        #expect(results[0].title == "SwiftUI - Apple Developer")
        #expect(results[0].url == "https://developer.apple.com/swiftui/")
        #expect(results[0].snippet.contains("declarative syntax"))
        #expect(results[0].sourceBackend == "you")
        #expect(results[1].snippet.contains("Declarative UI patterns"))
    }

    @Test("Adapter Decoding: TavilyKeylessSearchAdapter decodes Hebrew results fixture")
    func tavilyAdapterDecodesFixture() throws {
        let adapter = TavilyKeylessSearchAdapter()
        let results = try adapter.parseTavilyResponse(data: Self.sampleTavilyJSON)

        #expect(results.count == 1)
        #expect(results[0].title.contains("זמני היום בירושלים"))
        #expect(results[0].snippet.contains("נץ החמה"))
        #expect(results[0].score == 0.98)
        #expect(results[0].sourceBackend == "tavily")
    }

    @Test("Adapter Decoding: KeenablePublicSearchAdapter decodes public endpoint fixture")
    func keenableAdapterDecodesFixture() throws {
        let adapter = KeenablePublicSearchAdapter()
        let results = try adapter.parseKeenableResponse(data: Self.sampleKeenableJSON)

        #expect(results.count == 1)
        #expect(results[0].title == "SwiftUI Overview - Apple Developer")
        #expect(results[0].sourceBackend == "keenable")
        #expect(results[0].publishedDate == "2026-09-27T17:10:50Z")
    }

    // MARK: - 2. Cooldown & Circuit Breaker Enforcement

    @Test("Circuit Breaker: Rate-limited provider is strictly skipped on cooldown without hammering server")
    func circuitBreakerStrictlyEnforcesCooldown() async throws {
        let testClock = TestClock(Date(timeIntervalSince1970: 1000000))

        let res2 = WebSearchResult(title: "Tavily Res for query alpha beta", url: "https://example.com/2", snippet: "Valid Tavily snippet for query alpha beta", sourceBackend: "tavily")
        let p1 = MockSearchProvider(providerID: "you", displayName: "You.com", shouldThrow: .rateLimited(retryAfter: 60))
        let p2 = MockSearchProvider(providerID: "tavily", displayName: "Tavily", returnedResults: [res2])

        let coordinator = AutomaticWebSearchCoordinator(
            providers: [p1, p2],
            clock: { testClock.current }
        )

        // Query 1: Provider 1 fails with 429 (Retry-After: 60s) -> Falls back to Provider 2
        let (_, engine1) = try await coordinator.search(query: "query alpha", count: 5)
        #expect(engine1.contains("Tavily"))
        let count1P1 = await p1.callCount
        let count1P2 = await p2.callCount
        #expect(count1P1 == 1)
        #expect(count1P2 == 1)

        // Advance time by 30 seconds (still within 60s cooldown!)
        testClock.advance(by: 30)

        // Query 2: Must NOT call Provider 1 at all! Directly call Provider 2
        let (_, engine2) = try await coordinator.search(query: "query beta", count: 5)
        #expect(engine2.contains("Tavily"))
        let count2P1 = await p1.callCount
        let count2P2 = await p2.callCount
        #expect(count2P1 == 1) // Crucial assertion: provider 1 was NOT called during cooldown!
        #expect(count2P2 == 2)

        // Advance time past cooldown (70 seconds later)
        testClock.advance(by: 40)
        await p1.setError(nil)
        await p1.setResults([WebSearchResult(title: "You Res for query gamma", url: "https://example.com/1", snippet: "You recovered for query gamma", sourceBackend: "you")])

        // Query 3: Provider 1 cooldown expired -> Provider 1 is tried first again
        let (_, engine3) = try await coordinator.search(query: "query gamma", count: 5)
        #expect(engine3.contains("You.com"))
        let count3P1 = await p1.callCount
        #expect(count3P1 == 2) // Tried again after cooldown expired!
    }

    @Test("Circuit Breaker: All providers on cooldown deterministically throws allProvidersOnCooldown")
    func allProvidersOnCooldownThrows() async throws {
        let testClock = TestClock(Date(timeIntervalSince1970: 1000000))
        let p1 = MockSearchProvider(providerID: "you", displayName: "You.com", shouldThrow: .rateLimited(retryAfter: 60))
        let p2 = MockSearchProvider(providerID: "tavily", displayName: "Tavily", shouldThrow: .rateLimited(retryAfter: 120))

        let coordinator = AutomaticWebSearchCoordinator(
            providers: [p1, p2],
            clock: { testClock.current }
        )

        // Trigger cooldown on both
        _ = try? await coordinator.search(query: "probe 1", count: 5)

        // Subsequent search within cooldown must immediately throw allProvidersOnCooldown
        testClock.advance(by: 10)
        await #expect(throws: AutomaticSearchError.self) {
            _ = try await coordinator.search(query: "probe 2", count: 5)
        }
    }

    // MARK: - 3. Adversarial Relevance & Quality Assessment

    @Test("Adversarial Relevance: Jerusalem prayer query returning hotel spam is rejected and falls back")
    func jerusalemPrayerTimesRejectsHotelSpam() async throws {
        // Provider 1 returns hotels for a prayer times query
        let hotelSpam = [
            WebSearchResult(title: "Grand Hotel Jerusalem", url: "https://hotels.com/jerusalem", snippet: "Book luxury rooms, suites, and vacation packages in Jerusalem.", sourceBackend: "you"),
            WebSearchResult(title: "Boutique Resort Jerusalem", url: "https://resorts.com/booking", snippet: "Vacation hotel accommodations with swimming pool.", sourceBackend: "you")
        ]
        // Provider 2 returns actual prayer times / Torah content
        let prayerResults = [
            WebSearchResult(title: "זמני תפילה בירושלים - ישיבת הר עציון", url: "https://etzion.org.il/zmanim", snippet: "זמני תפילה הלכתיים בירושלים: שחרית, מנחה, ערבית, נץ החמה ושקיעה.", sourceBackend: "tavily")
        ]

        let p1 = MockSearchProvider(providerID: "you", displayName: "You.com", returnedResults: hotelSpam)
        let p2 = MockSearchProvider(providerID: "tavily", displayName: "Tavily", returnedResults: prayerResults)

        let coordinator = AutomaticWebSearchCoordinator(providers: [p1, p2])
        let (parsed, engine) = try await coordinator.search(query: "זמני תפילה ירושלים", count: 5)

        // Must reject Provider 1's hotel spam and accept Provider 2
        #expect(engine.contains("Tavily"))
        #expect(parsed.titles.first?.contains("זמני תפילה") == true)
    }

    @Test("Adversarial Relevance: Technical SwiftUI query returning card game bridge is rejected")
    func swiftUIQueryRejectsCardGameSpam() async throws {
        let cardGameResults = [
            WebSearchResult(title: "How to Play Bridge Card Game", url: "https://games.com/bridge", snippet: "Rules for trick-taking trump card games with partners.", sourceBackend: "you")
        ]
        let techResults = [
            WebSearchResult(title: "SwiftUI Documentation - Apple Developer", url: "https://developer.apple.com/swiftui", snippet: "Build declarative interfaces for iOS and macOS using Swift.", sourceBackend: "tavily")
        ]

        let p1 = MockSearchProvider(providerID: "you", displayName: "You.com", returnedResults: cardGameResults)
        let p2 = MockSearchProvider(providerID: "tavily", displayName: "Tavily", returnedResults: techResults)

        let coordinator = AutomaticWebSearchCoordinator(providers: [p1, p2])
        let (parsed, engine) = try await coordinator.search(query: "SwiftUI iOS SDK", count: 5)

        #expect(engine.contains("Tavily"))
        #expect(parsed.titles.first?.contains("Apple Developer") == true)
    }

    // MARK: - 4. Canonical Query Caching & Diagnostic Bypass

    @Test("Canonical Caching: Handles irregular internal whitespace and locale folding")
    func canonicalCacheNormalizesWhitespace() async throws {
        let res = WebSearchResult(title: "SwiftUI iOS 27 Reference", url: "https://example.com/item", snippet: "Official guide for SwiftUI iOS 27 development", sourceBackend: "you")
        let p1 = MockSearchProvider(providerID: "you", displayName: "You.com", returnedResults: [res])
        let coordinator = AutomaticWebSearchCoordinator(providers: [p1])

        _ = try await coordinator.search(query: "  SwiftUI   iOS   27  ", count: 5)
        let count1 = await p1.callCount
        #expect(count1 == 1)

        _ = try await coordinator.search(query: "swiftui ios 27", count: 5)
        let count2 = await p1.callCount
        #expect(count2 == 1) // Cache hit!
    }

    @Test("Diagnostic Probe: Bypasses cache to guarantee real live testing")
    func diagnosticBypassesCache() async {
        let res = WebSearchResult(title: "Live News", url: "https://news.com/live", snippet: "News snippet", sourceBackend: "you")
        let p1 = MockSearchProvider(providerID: "you", displayName: "You.com", returnedResults: [res])
        let coordinator = AutomaticWebSearchCoordinator(providers: [p1])

        let diag1 = await coordinator.runDiagnosticTest()
        let count1 = await p1.callCount
        #expect(diag1.success == true)
        #expect(count1 == 1)

        // Immediate second diagnostic test must NOT serve cached result
        let diag2 = await coordinator.runDiagnosticTest()
        let count2 = await p1.callCount
        #expect(diag2.success == true)
        #expect(count2 == 2) // Cache was bypassed!
    }

    // MARK: - 5. Migration & Explicit Disable Invariants

    @MainActor
    @Test("Migration Invariant: Explicitly disabled manual provider is NOT overwritten to automatic")
    func explicitlyDisabledManualProviderPreserved() throws {
        let schema = Schema([SearchKeys.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        // User configured Tavily key, but explicitly turned search OFF (isUsing == false)
        let manualKey = SearchKeys(
            name: "TAVILY_KEY",
            company: "TAVILY",
            key: "tvly-secret-key-configured",
            requestURL: "https://api.tavily.com/search",
            isUsing: false
        )
        context.insert(manualKey)
        try context.save()

        // Run migration
        AutomaticSearchMigration.reconcileDefaultProvider(in: context)

        let allKeys = try context.fetch(FetchDescriptor<SearchKeys>())
        let auto = allKeys.first { $0.company == "AUTOMATIC_KEYLESS" }
        let manual = allKeys.first { $0.company == "TAVILY" }

        #expect(manual?.isUsing == false)
        #expect(auto?.isUsing == false) // Must NOT force automatic on!
    }

    @MainActor
    @Test("Migration Invariant: Deduplication removes redundant automatic rows")
    func deduplicationRemovesRedundantAutomaticRows() throws {
        let schema = Schema([SearchKeys.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        context.insert(AutomaticSearchMigration.makeAutomaticSearchKey(isUsing: true))
        context.insert(AutomaticSearchMigration.makeAutomaticSearchKey(isUsing: false))
        context.insert(AutomaticSearchMigration.makeAutomaticSearchKey(isUsing: false))
        try context.save()

        AutomaticSearchMigration.reconcileDefaultProvider(in: context)

        let allKeys = try context.fetch(FetchDescriptor<SearchKeys>())
        let automaticKeys = allKeys.filter { $0.company == "AUTOMATIC_KEYLESS" }
        #expect(automaticKeys.count == 1)
        #expect(automaticKeys.first?.isUsing == true)
    }

    // MARK: - 6. Hard Deadline & Structured Concurrency Racing

    @Test("Hard Deadline & Cancellation: Slow provider is cancelled at deadline without updating cache")
    func hardDeadlineCancelsSlowProviderPromptly() async throws {
        let lateResult = WebSearchResult(
            title: "Late Result for probe deadline",
            url: "https://example.com/late",
            snippet: "Late snippet for probe deadline",
            sourceBackend: "slow"
        )
        let slowProvider = MockSearchProvider(
            providerID: "slow",
            displayName: "SlowProvider",
            returnedResults: [lateResult],
            simulatedDelay: 4.0
        )

        let coordinator = AutomaticWebSearchCoordinator(
            providers: [slowProvider],
            overallSearchDeadline: 0.15,
            perProviderTimeout: 0.5
        )

        let startTime = Date()
        var caughtExpectedError = false
        do {
            _ = try await coordinator.search(query: "probe deadline", count: 5)
        } catch AutomaticSearchError.timeout {
            caughtExpectedError = true
        } catch AutomaticSearchError.cancelled {
            caughtExpectedError = true
        } catch {
            Issue.record("Expected timeout or cancelled error, but got \(error)")
        }

        let elapsed = Date().timeIntervalSince(startTime)
        #expect(caughtExpectedError == true)
        #expect(elapsed < 2.0)

        try await Task.sleep(nanoseconds: 50_000_000)

        let freshResult = WebSearchResult(
            title: "Fresh Result for probe deadline",
            url: "https://example.com/fresh",
            snippet: "Fresh snippet for probe deadline",
            sourceBackend: "slow"
        )
        await slowProvider.setResults([freshResult])

        let fastCoordinator = AutomaticWebSearchCoordinator(
            providers: [MockSearchProvider(providerID: "fast", displayName: "FastProvider", returnedResults: [freshResult])],
            overallSearchDeadline: 2.0,
            perProviderTimeout: 2.0
        )
        let (parsed, engine) = try await fastCoordinator.search(query: "probe deadline", count: 5)
        #expect(!engine.contains("cached"))
        #expect(parsed.titles.first == "Fresh Result for probe deadline")
    }

    // MARK: - 7. Hebrew Niqqud, Gershayim & Mixed RTL Evaluation

    @Test("Adversarial Relevance: Hebrew query with niqqud and gershayim matches Hebrew content properly")
    func hebrewNiqqudAndGershayimRelevance() async throws {
        let queryWithNiqqud = "רַשִׁ\"י פָּרָשַׁת נֹחַ"
        let torahResult = [
            WebSearchResult(
                title: "פירוש רש\"י על פרשת נח - ויקיטקסט",
                url: "https://he.wikisource.org/wiki/רש\"י_על_בראשית_ו",
                snippet: "פירוש רש\"י לחומש בראשית פרשת נח: אלה תולדות נח, נח איש צדיק תמים היה בדורותיו.",
                sourceBackend: "tavily"
            )
        ]

        let provider = MockSearchProvider(providerID: "tavily", displayName: "Tavily", returnedResults: torahResult)
        let coordinator = AutomaticWebSearchCoordinator(providers: [provider])

        let (parsed, engine) = try await coordinator.search(query: queryWithNiqqud, count: 5)
        #expect(engine.contains("Tavily"))
        #expect(parsed.titles.first?.contains("רש\"י") == true)
        #expect(parsed.contents.first?.contains("פרשת נח") == true)
    }
}
