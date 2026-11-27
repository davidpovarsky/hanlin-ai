import Foundation
import HanlinPlatformContracts
import Testing

@testable import AI_Hanlin

@Suite("Legacy Tool Canonical Migration Tests", .serialized)
struct LegacyToolMigrationTests {

    private static let expectedToolNames: Set<String> = [
        "save_memory", "retrieve_memory", "update_memory",
        "manage_calendar", "search_calendar_and_reminders", "write_system_event",
        "query_location", "get_current_location", "search_nearby_locations", "get_route",
        "query_weather", "search_online", "read_web_page", "search_arxiv_papers",
        "extract_remote_file_content", "search_knowledge_bag", "create_knowledge_document",
        "create_canvas", "edit_canvas", "create_web_view", "execute_remote_python_code",
        "fetch_step_details", "fetch_energy_details", "fetch_nutrition_details", "make_nutrition_data"
    ]

    @MainActor
    @Test("LegacyToolCanonicalAdapter matches exact buildMemoryTools source truth (25 tools)")
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

        #expect(sourceNames.count == 25)
        #expect(sourceNames == Self.expectedToolNames)

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

        #expect(sources.count == 25)

        let canonicalNames = Set(sources.map(\.toolName))
        #expect(canonicalNames == sourceNames)

        for source in sources {
            if let result = source.presentationProfile.result {
                #expect(result.rendererKind == .legacyExisting)
            }
            #expect(source.descriptor.logicalID.providerInstanceID.rawValue == "hanlin-legacy")
        }
    }

    @MainActor
    @Test("Category toggles correctly filter legacy tool sources")
    func legacyAdapterCategoryFiltering() throws {
        let allSources = LegacyToolCanonicalAdapter.sources()
        #expect(allSources.count == 25)

        // Memory toggle
        let noMemory = LegacyToolCanonicalAdapter.sources(memoryEnabled: false)
        let memoryNames = ["save_memory", "retrieve_memory", "update_memory"]
        for name in memoryNames {
            #expect(!noMemory.contains(where: { $0.toolName == name }))
        }
        #expect(noMemory.count == 22)

        // Weather toggle
        let noWeather = LegacyToolCanonicalAdapter.sources(weatherEnabled: false)
        #expect(!noWeather.contains(where: { $0.toolName == "query_weather" }))
        #expect(noWeather.count == 24)

        // Calendar toggle
        let noCalendar = LegacyToolCanonicalAdapter.sources(calendarEnabled: false)
        let calendarNames = ["search_calendar_and_reminders", "write_system_event", "manage_calendar"]
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
        #expect(noMap.count == 21)

        // Health toggle
        let noHealth = LegacyToolCanonicalAdapter.sources(healthEnabled: false)
        let healthNames = ["fetch_step_details", "fetch_energy_details", "fetch_nutrition_details", "make_nutrition_data"]
        for name in healthNames {
            #expect(!noHealth.contains(where: { $0.toolName == name }))
        }
        #expect(noHealth.count == 21)
    }

    @MainActor
    @Test("Canonical authority indexes all 25 legacy sources and routes backend correctly")
    func canonicalAuthorityLegacyIndexing() throws {
        let sources = LegacyToolCanonicalAdapter.sources()

        let authority = try HanlinCanonicalToolAuthority.build(
            nativeSources: [],
            mcpTools: [],
            legacySources: sources
        )

        #expect(authority.catalog.entries.count == 25)
        #expect(authority.routingTable.routes.count == 25)
        #expect(Set(authority.routingTable.routes.map(\.alias)) == Self.expectedToolNames)

        let searchRes = authority.resolution(alias: "search_online")
        if case let .legacy(toolName)? = searchRes?.backend {
            #expect(toolName == "search_online")
        } else {
            Issue.record("search_online did not resolve to legacy backend")
        }

        let calendarRes = authority.resolution(alias: "manage_calendar")
        if case let .legacy(toolName)? = calendarRes?.backend {
            #expect(toolName == "manage_calendar")
        } else {
            Issue.record("manage_calendar did not resolve to legacy backend")
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

        let calendarSchemas = prepared.schemas(for: Set(["manage_calendar"]))
        #expect(calendarSchemas.count == 1)
        let calendarFunction = try #require(calendarSchemas.first?["function"] as? [String: Any])
        #expect((calendarFunction["name"] as? String) == "manage_calendar")
        let calendarParameters = try #require(calendarFunction["parameters"] as? [String: Any])
        #expect((calendarParameters["required"] as? [String]) == ["operation"])
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
