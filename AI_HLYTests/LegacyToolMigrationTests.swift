import Foundation
import HanlinPlatformContracts
import Testing

@testable import AI_Hanlin

@Suite("Legacy Tool Canonical Migration Tests", .serialized)
struct LegacyToolMigrationTests {

    @MainActor
    @Test("LegacyToolCanonicalAdapter matches exact buildMemoryTools source truth (24 tools)")
    func legacyAdapterMatchesSourceTruth() throws {
        // Derive authoritative source truth directly from buildMemoryTools
        let sourceTools = buildMemoryTools(
            memoryEnabled: true,
            mapEnabled: true,
            calendarEnabled: true,
            searchEnabled: true,
            knowledgeEnabled: true,
            codeEnabled: true,
            healthEnabled: true,
            weatherEnabled: true,
            canvasEnabled: true
        )

        let sourceNames = Set(sourceTools.compactMap { tool -> String? in
            (tool["function"] as? [String: Any])?["name"] as? String
        })

        #expect(sourceNames.count == 24)

        let sources = LegacyToolCanonicalAdapter.sources(
            memoryEnabled: true,
            mapEnabled: true,
            calendarEnabled: true,
            searchEnabled: true,
            knowledgeEnabled: true,
            codeEnabled: true,
            healthEnabled: true,
            weatherEnabled: true,
            canvasEnabled: true
        )

        #expect(sources.count == 24)

        let canonicalNames = Set(sources.map(\.toolName))
        #expect(canonicalNames == sourceNames)

        for source in sources {
            #expect(source.presentationProfile.result?.rendererKind == .legacyExisting)
            #expect(source.descriptor.logicalID.providerInstanceID.rawValue == "hanlin-legacy")
        }
    }

    @MainActor
    @Test("Category toggles correctly filter legacy tool sources")
    func legacyAdapterCategoryFiltering() throws {
        let allSources = LegacyToolCanonicalAdapter.sources()
        #expect(allSources.count == 24)

        // Memory toggle
        let noMemory = LegacyToolCanonicalAdapter.sources(memoryEnabled: false)
        let memoryNames = ["save_memory", "retrieve_memory", "update_memory"]
        for name in memoryNames {
            #expect(!noMemory.contains(where: { $0.toolName == name }))
        }
        #expect(noMemory.count == 21)

        // Weather toggle
        let noWeather = LegacyToolCanonicalAdapter.sources(weatherEnabled: false)
        #expect(!noWeather.contains(where: { $0.toolName == "query_weather" }))
        #expect(noWeather.count == 23)

        // Calendar toggle
        let noCalendar = LegacyToolCanonicalAdapter.sources(calendarEnabled: false)
        let calendarNames = ["search_calendar_and_reminders", "write_system_event"]
        for name in calendarNames {
            #expect(!noCalendar.contains(where: { $0.toolName == name }))
        }
        #expect(noCalendar.count == 22)

        // Map toggle
        let noMap = LegacyToolCanonicalAdapter.sources(mapEnabled: false)
        let mapNames = ["query_location", "get_current_location", "search_nearby_locations", "get_route"]
        for name in mapNames {
            #expect(!noMap.contains(where: { $0.toolName == name }))
        }
        #expect(noMap.count == 20)

        // Health toggle
        let noHealth = LegacyToolCanonicalAdapter.sources(healthEnabled: false)
        let healthNames = ["fetch_step_details", "fetch_energy_details", "fetch_nutrition_details", "make_nutrition_data"]
        for name in healthNames {
            #expect(!noHealth.contains(where: { $0.toolName == name }))
        }
        #expect(noHealth.count == 20)
    }

    @MainActor
    @Test("Canonical authority indexes all 24 legacy sources and routes backend correctly")
    func canonicalAuthorityLegacyIndexing() throws {
        let sources = LegacyToolCanonicalAdapter.sources()

        let authority = try HanlinCanonicalToolAuthority.build(
            nativeSources: [],
            mcpTools: [],
            legacySources: sources
        )

        #expect(authority.catalog.entries.count == 24)
        #expect(authority.routingTable.routes.count == 24)

        let searchRes = authority.resolution(alias: "search_online")
        if case let .legacy(toolName)? = searchRes?.backend {
            #expect(toolName == "search_online")
        } else {
            Issue.record("search_online did not resolve to legacy backend")
        }

        let weatherRes = authority.resolution(alias: "query_weather")
        if case let .legacy(toolName)? = weatherRes?.backend {
            #expect(toolName == "query_weather")
        } else {
            Issue.record("query_weather did not resolve to legacy backend")
        }
    }

    @MainActor
    @Test("PreparedTools searches legacy tools by keyword and filters schemas by exposed aliases")
    func preparedToolsSearchAndSchemaFiltering() throws {
        let sources = LegacyToolCanonicalAdapter.sources()

        let authority = try HanlinCanonicalToolAuthority.build(
            nativeSources: [],
            mcpTools: [],
            legacySources: sources
        )

        let prepared = AssistantToolBridge.PreparedTools(authority: authority)

        let weatherMatches = prepared.search(query: "forecast temperature", limit: 5)
        #expect(!weatherMatches.isEmpty)
        let weatherAliases = weatherMatches.map(\.alias)
        #expect(weatherAliases.contains("query_weather"))

        let memoryMatches = prepared.search(query: "memory", limit: 5)
        #expect(memoryMatches.contains(where: { $0.alias.contains("memory") }))

        // Verify schemas for exposed subset
        let subsetSchemas = prepared.schemas(for: Set(["save_memory", "get_route"]))
        #expect(subsetSchemas.count == 2)
    }

    @MainActor
    @Test("Legacy tool canonical execution cutover routes to legacy executor and fails truthfully when unconfigured")
    func legacyToolCanonicalExecutionCutover() async throws {
        let sources = LegacyToolCanonicalAdapter.sources()
        let authority = try HanlinCanonicalToolAuthority.build(
            nativeSources: [],
            mcpTools: [],
            legacySources: sources
        )

        var executedTool: String?
        let context = NativeToolExecutionContext(localeIdentifier: "en")

        // 1. Configured legacy executor executes faithfully
        let configuredExecutors = AssistantToolBridge.Executors(
            executeNative: { _, _, _, _ in NativeToolResult(modelText: "native", outcome: .succeeded) },
            executeScripting: { _, _ in NativeToolResult(modelText: "script", outcome: .succeeded) },
            executeLegacy: { toolName, argsJSON, _ in
                executedTool = toolName
                return NativeToolResult(modelText: "Executed \(toolName)", outcome: .succeeded)
            }
        )
        let preparedConfigured = AssistantToolBridge.PreparedTools(authority: authority, executors: configuredExecutors)
        let result = await preparedConfigured.execute(alias: "save_memory", argumentsJSON: "{}", context: context)

        #expect(executedTool == "save_memory")
        #expect(result?.modelText == "Executed save_memory")
        #expect(result?.outcome == .succeeded)

        // 2. Unconfigured legacy executor fails truthfully (no dummy success)
        let unconfiguredExecutors = AssistantToolBridge.Executors(
            executeNative: { _, _, _, _ in NativeToolResult(modelText: "native", outcome: .succeeded) },
            executeScripting: { _, _ in NativeToolResult(modelText: "script", outcome: .succeeded) }
        )
        let preparedUnconfigured = AssistantToolBridge.PreparedTools(authority: authority, executors: unconfiguredExecutors)
        let failResult = await preparedUnconfigured.execute(alias: "save_memory", argumentsJSON: "{}", context: context)

        #expect(failResult?.outcome == .failed)
        #expect(failResult?.modelText.contains("not configured") == true)
    }
}
