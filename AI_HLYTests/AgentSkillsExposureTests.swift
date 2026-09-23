import Foundation
import HanlinPlatformContracts
import Testing

@testable import AI_Hanlin

@Suite("Agent Skills and Deferred Tool Exposure Tests", .serialized)
struct AgentSkillsExposureTests {

    @MainActor
    @Test("Skill Catalog registration and instruction resolution")
    func skillCatalogRegistration() async throws {
        let catalog = HanlinSkillCatalog()
        let skillID = try HanlinSkillID(validating: "data_analysis")
        let descriptor = try HanlinSkillDescriptor(
            id: skillID,
            title: "Data Analysis",
            summary: "Analyze tabular data and generate plots",
            instructions: .inline("Always verify data distributions before plotting."),
            preferredToolIDs: ["run_python_code"]
        )

        catalog.register(descriptor: descriptor)

        #expect(catalog.allSkills().count == 1)
        let resolved = catalog.resolve(id: skillID)
        #expect(resolved?.id == skillID)
        #expect(resolved?.title.preferredValue() == "Data Analysis")

        let resolvedByRaw = catalog.resolve(rawID: "data_analysis")
        #expect(resolvedByRaw?.id == skillID)

        let instructions = await catalog.loadInstructions(for: descriptor)
        #expect(instructions == "Always verify data distributions before plotting.")
    }

    @MainActor
    @Test("Skill Index prompt generation produces compact markdown index")
    func skillIndexPrompt() throws {
        let skills = [
            try HanlinSkillDescriptor(
                id: HanlinSkillID(validating: "weather_expert"),
                title: "Weather Expert",
                summary: "Retrieve current and future weather forecasts",
                instructions: .inline("Weather instructions")
            ),
            try HanlinSkillDescriptor(
                id: HanlinSkillID(validating: "code_runner"),
                title: "Code Runner",
                summary: "Execute safe sandboxed Python code",
                instructions: .inline("Code instructions")
            )
        ]

        let prompt = HanlinSkillIndex.prompt(for: skills)
        #expect(prompt.contains("Available Skills"))
        #expect(prompt.contains("`weather_expert`"))
        #expect(prompt.contains("Retrieve current and future weather forecasts"))
        #expect(prompt.contains("`code_runner`"))
        #expect(prompt.contains("`load_skill`"))

        let emptyPrompt = HanlinSkillIndex.prompt(for: [])
        #expect(emptyPrompt.isEmpty)
    }

    @MainActor
    @Test("Tool exposure planner enforces byte budget and defers overflow tools")
    func toolExposurePlannerBudget() throws {
        let planner = AssistantToolExposurePlanner(maxSchemaBytes: 1000)
        let sizes: [String: Int] = [
            "tool_a": 400,
            "tool_b": 400,
            "tool_c": 400
        ]

        let plan = planner.plan(
            candidateAliases: ["tool_a", "tool_b", "tool_c"],
            schemaSizes: sizes,
            currentlyExposedAliases: []
        )

        #expect(plan.exposedAliases.contains("tool_a"))
        #expect(plan.exposedAliases.contains("tool_b"))
        #expect(plan.deferredAliases.contains("tool_c"))
        #expect(!plan.exposedAliases.contains("tool_c"))
    }

    @MainActor
    @Test("AssistantCapabilitySession isolates turns and manages tool exposure")
    func capabilitySessionIsolation() throws {
        let session1 = AssistantCapabilitySession()
        let session2 = AssistantCapabilitySession()

        session1.exposeTools(aliases: ["search_online", "get_route"])
        #expect(session1.exposedToolAliases.contains("search_online"))
        #expect(session1.exposedToolAliases.contains("get_route"))
        #expect(!session2.exposedToolAliases.contains("search_online"))
        #expect(!session2.exposedToolAliases.contains("get_route"))

        let skillID = try HanlinSkillID(validating: "test_skill")
        session1.recordSkillLoaded(id: skillID, instructionText: "test instructions")
        #expect(session1.loadedSkillIDs.contains(skillID))
        #expect(!session2.loadedSkillIDs.contains(skillID))
    }

    @MainActor
    @Test("LoadSkillTool execution loads instructions, exposes tools and reports deferred")
    func loadSkillToolExecution() async throws {
        let catalog = HanlinSkillCatalog()
        let skillID = try HanlinSkillID(validating: "math_solver")
        let descriptor = try HanlinSkillDescriptor(
            id: skillID,
            title: "Math Solver",
            summary: "Solve symbolic mathematics",
            instructions: .inline("Use precise formulas."),
            preferredToolIDs: ["calculate_integral", "solve_equation"]
        )
        catalog.register(descriptor: descriptor)

        let session = AssistantCapabilitySession()
        let planner = AssistantToolExposurePlanner(maxSchemaBytes: 500)
        let schemaSizes = [
            "calculate_integral": 300,
            "solve_equation": 300
        ]

        let result = await LoadSkillTool.execute(
            argumentsJSON: "{\"skill_id\": \"math_solver\"}",
            session: session,
            catalog: catalog,
            planner: planner,
            schemaSizes: schemaSizes
        )

        #expect(session.loadedSkillIDs.contains(skillID))
        #expect(session.exposedToolAliases.contains("calculate_integral"))
        #expect(result.contains("Math Solver"))
        #expect(result.contains("calculate_integral"))
        #expect(result.contains("solve_equation"))
    }

    @MainActor
    @Test("ToolSearchTool searches metadata, exposes matching tools and formats response")
    func toolSearchToolExecution() throws {
        let session = AssistantCapabilitySession()
        let records = [
            CanonicalToolSearchRecord(
                alias: "get_future_weather",
                title: "Future Weather",
                summary: "Forecast for upcoming days",
                source: "legacy",
                keywords: ["weather", "forecast", "future"]
            ),
            CanonicalToolSearchRecord(
                alias: "get_hourly_weather",
                title: "Hourly Weather",
                summary: "Forecast by hour",
                source: "legacy",
                keywords: ["weather", "hourly", "temperature"]
            )
        ]

        let result = ToolSearchTool.execute(
            argumentsJSON: "{\"query\": \"weather\", \"limit\": 5}",
            session: session,
            searchProvider: { query, limit in
                records.filter { $0.keywords.contains(query.lowercased()) }
            }
        )

        #expect(session.exposedToolAliases.contains("get_future_weather"))
        #expect(session.exposedToolAliases.contains("get_hourly_weather"))
        #expect(result.contains("get_future_weather"))
        #expect(result.contains("get_hourly_weather"))
    }

    @MainActor
    @Test("ReadToolResultTool supports offset and limit pagination over BoundedToolResultStore")
    func readToolResultToolPagination() throws {
        let session = AssistantCapabilitySession()
        let largeContent = String(repeating: "0123456789ABCDEF", count: 100)
        let ref = session.resultStore.store(largeContent)

        let slice1 = ReadToolResultTool.execute(
            argumentsJSON: "{\"reference\": \"\(ref)\", \"offset\": 0, \"limit\": 100}",
            session: session
        )
        #expect(slice1.contains("offset: 0"))
        #expect(slice1.contains("100/1600"))
        #expect(slice1.contains("more bytes available"))

        let slice2 = ReadToolResultTool.execute(
            argumentsJSON: "{\"reference\": \"\(ref)\", \"offset\": 1500, \"limit\": 200}",
            session: session
        )
        #expect(slice2.contains("offset: 1500"))
        #expect(!slice2.contains("more bytes available"))

        let missing = ReadToolResultTool.execute(
            argumentsJSON: "{\"reference\": \"invalid_ref\"}",
            session: session
        )
        #expect(missing.contains("not found or has expired"))
    }
}
