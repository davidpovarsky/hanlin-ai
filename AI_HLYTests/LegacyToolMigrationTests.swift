import Foundation
import HanlinPlatformContracts
import Testing

@testable import AI_Hanlin

@Suite("Legacy Tool Canonical Migration Tests", .serialized)
struct LegacyToolMigrationTests {

    @MainActor
    @Test("LegacyToolCanonicalAdapter generates all 23 canonical legacy sources")
    func legacyAdapterGeneratesAll23Tools() throws {
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

        #expect(sources.count == 23)

        let names = Set(sources.map(\.toolName))
        let expectedNames: Set<String> = [
            "save_memory", "retrieve_memory", "update_memory", "delete_memory",
            "search_online", "search_arxiv_papers", "read_web_page",
            "query_location", "get_current_location", "search_nearby_locations", "get_route",
            "write_system_event", "create_web_view", "show_calendar_events",
            "make_nutrition_data", "execute_remote_python_code", "execute_python_code",
            "create_knowledge_document", "search_knowledge_bag",
            "create_canvas", "edit_canvas",
            "get_future_weather", "get_hourly_weather"
        ]

        #expect(names == expectedNames)

        for source in sources {
            #expect(source.presentationProfile.result?.rendererKind == .legacyExisting)
            #expect(source.descriptor.logicalID.providerInstanceID.rawValue == "hanlin-legacy")
        }
    }

    @MainActor
    @Test("Category toggles correctly filter legacy tool sources")
    func legacyAdapterCategoryFiltering() throws {
        let noMemory = LegacyToolCanonicalAdapter.sources(
            memoryEnabled: false,
            mapEnabled: true,
            calendarEnabled: true,
            searchEnabled: true,
            knowledgeEnabled: true,
            codeEnabled: true,
            healthEnabled: true,
            weatherEnabled: true,
            canvasEnabled: true
        )
        let memoryNames = ["save_memory", "retrieve_memory", "update_memory", "delete_memory"]
        for name in memoryNames {
            #expect(!noMemory.contains(where: { $0.toolName == name }))
        }
        #expect(noMemory.count == 19)

        let noWeather = LegacyToolCanonicalAdapter.sources(
            memoryEnabled: true,
            mapEnabled: true,
            calendarEnabled: true,
            searchEnabled: true,
            knowledgeEnabled: true,
            codeEnabled: true,
            healthEnabled: true,
            weatherEnabled: false,
            canvasEnabled: true
        )
        #expect(!noWeather.contains(where: { $0.toolName == "get_future_weather" }))
        #expect(!noWeather.contains(where: { $0.toolName == "get_hourly_weather" }))
        #expect(noWeather.count == 21)
    }

    @MainActor
    @Test("Canonical authority indexes legacy sources and routes backend correctly")
    func canonicalAuthorityLegacyIndexing() throws {
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

        let authority = try HanlinCanonicalToolAuthority.build(
            nativeSources: [],
            mcpTools: [],
            legacySources: sources
        )

        #expect(authority.catalog.entries.count == 23)
        #expect(authority.routingTable.routes.count == 23)

        let searchRes = authority.resolution(alias: "search_online")
        if case let .legacy(toolName)? = searchRes?.backend {
            #expect(toolName == "search_online")
        } else {
            Issue.record("search_online did not resolve to legacy backend")
        }

        let weatherRes = authority.resolution(alias: "get_future_weather")
        if case let .legacy(toolName)? = weatherRes?.backend {
            #expect(toolName == "get_future_weather")
        } else {
            Issue.record("get_future_weather did not resolve to legacy backend")
        }
    }

    @MainActor
    @Test("PreparedTools searches legacy tools by keyword and filters schemas by exposed aliases")
    func preparedToolsSearchAndSchemaFiltering() throws {
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

        let authority = try HanlinCanonicalToolAuthority.build(
            nativeSources: [],
            mcpTools: [],
            legacySources: sources
        )

        let prepared = AssistantToolBridge.PreparedTools(authority: authority)

        let weatherMatches = prepared.search(query: "forecast temperature", limit: 5)
        #expect(!weatherMatches.isEmpty)
        let aliases = weatherMatches.map(\.alias)
        #expect(aliases.contains("get_future_weather") || aliases.contains("get_hourly_weather"))

        let memoryMatches = prepared.search(query: "memory", limit: 5)
        #expect(memoryMatches.contains(where: { $0.alias.contains("memory") }))

        // Verify schemas for exposed subset
        let subsetSchemas = prepared.schemas(for: Set(["save_memory", "get_route"]))
        #expect(subsetSchemas.count == 2)
    }
}
