import Foundation
import HanlinPlatformContracts

/// Downstream provider of built-in lightweight Skills for Hanlin's legacy capability domains.
/// Provides instructions and preferred tool hints without embedding full tool schemas.
@MainActor
public enum SystemSkillsProvider {

    public static func systemSkills(
        memoryEnabled: Bool = true,
        mapEnabled: Bool = true,
        calendarEnabled: Bool = true,
        searchEnabled: Bool = true,
        knowledgeEnabled: Bool = true,
        codeEnabled: Bool = true,
        healthEnabled: Bool = true,
        weatherEnabled: Bool = true,
        canvasEnabled: Bool = true
    ) -> [HanlinSkillDescriptor] {
        var descriptors: [HanlinSkillDescriptor] = []

        if memoryEnabled {
            if let skillID = try? HanlinSkillID(validating: "memory"),
               let desc = try? HanlinSkillDescriptor(
                   id: skillID,
                   title: "Long-term Memory",
                   summary: "Store, retrieve, and update user preferences, biographical facts, and persistent conversation context.",
                   instructions: .inline("""
                   Use memory tools to maintain persistent knowledge across sessions:
                   - Call `retrieve_memory` to verify existing facts before answering personal queries.
                   - Call `save_memory` when the user explicitly requests to remember something or provides enduring personal preferences.
                   - Call `update_memory` to correct obsolete memory items.
                   """),
                   keywords: ["remember", "memory", "recall", "preferences", "facts"],
                   preferredToolIDs: ["save_memory", "retrieve_memory", "update_memory"]
               ) {
                descriptors.append(desc)
            }
        }

        if calendarEnabled {
            if let skillID = try? HanlinSkillID(validating: "calendar"),
               let desc = try? HanlinSkillDescriptor(
                   id: skillID,
                   title: "Calendar & Reminders",
                   summary: "Search, inspect, and schedule system calendar events and reminder tasks.",
                   instructions: .inline("""
                   Coordinate user calendar and tasks:
                   - Call `search_calendar_and_reminders` with date ranges or keywords to check availability.
                   - Call `write_system_event` with complete ISO-8601 timestamps and timezones to record appointments or reminders.
                   """),
                   keywords: ["schedule", "event", "meeting", "reminder", "appointment", "calendar"],
                   preferredToolIDs: ["search_calendar_and_reminders", "write_system_event"]
               ) {
                descriptors.append(desc)
            }
        }

        if mapEnabled {
            if let skillID = try? HanlinSkillID(validating: "maps_location"),
               let desc = try? HanlinSkillDescriptor(
                   id: skillID,
                   title: "Maps & Navigation",
                   summary: "Query locations, search nearby places, and calculate turn-by-turn navigation routes.",
                   instructions: .inline("""
                   Location and routing workflows:
                   - Call `get_current_location` or `query_location` to resolve geographical coordinates.
                   - Call `search_nearby_locations` to find points of interest.
                   - Call `get_route` for transit, driving, or walking directions.
                   """),
                   keywords: ["maps", "location", "navigate", "directions", "poi", "gps", "route"],
                   preferredToolIDs: ["query_location", "get_current_location", "search_nearby_locations", "get_route"]
               ) {
                descriptors.append(desc)
            }
        }

        if weatherEnabled {
            if let skillID = try? HanlinSkillID(validating: "weather"),
               let desc = try? HanlinSkillDescriptor(
                   id: skillID,
                   title: "Weather Forecast",
                   summary: "Inspect current weather conditions, forecasts, and atmospheric observations.",
                   instructions: .inline("""
                   Retrieve meteorological data:
                   - Call `query_weather` with city, location name, or coordinates.
                   """),
                   keywords: ["weather", "temperature", "forecast", "rain", "climate", "conditions"],
                   preferredToolIDs: ["query_weather"]
               ) {
                descriptors.append(desc)
            }
        }

        if searchEnabled {
            if let skillID = try? HanlinSkillID(validating: "web_research"),
               let desc = try? HanlinSkillDescriptor(
                   id: skillID,
                   title: "Web & Research",
                   summary: "Search the web, read online web pages, search arXiv academic papers, and inspect remote documents.",
                   instructions: .inline("""
                   Web discovery and research workflow:
                   - Call `search_online` to find authoritative web results.
                   - Call `read_web_page` to extract full text content from promising URLs.
                   - Call `search_arxiv_papers` for scholarly preprints.
                   - Call `extract_remote_file_content` for remote documents.
                   """),
                   keywords: ["web", "search", "browse", "article", "arxiv", "paper", "google"],
                   preferredToolIDs: ["search_online", "read_web_page", "search_arxiv_papers", "extract_remote_file_content"]
               ) {
                descriptors.append(desc)
            }
        }

        if knowledgeEnabled {
            if let skillID = try? HanlinSkillID(validating: "knowledge"),
               let desc = try? HanlinSkillDescriptor(
                   id: skillID,
                   title: "Knowledge Base",
                   summary: "Search knowledge bags, retrieve stored documentation chunks, and create knowledge documents.",
                   instructions: .inline("""
                   Knowledge base workflows:
                   - Call `search_knowledge_bag` to find relevant documents and chunks.
                   - Call `create_knowledge_document` to save synthesized notes or references into the knowledge base.
                   """),
                   keywords: ["knowledge", "notes", "docs", "rag", "backpack", "documentation"],
                   preferredToolIDs: ["search_knowledge_bag", "create_knowledge_document"]
               ) {
                descriptors.append(desc)
            }
        }

        if canvasEnabled {
            if let skillID = try? HanlinSkillID(validating: "canvas"),
               let desc = try? HanlinSkillDescriptor(
                   id: skillID,
                   title: "Interactive Canvas",
                   summary: "Create and edit interactive visual canvases for diagrams, layouts, and markdown rendering.",
                   instructions: .inline("""
                   Interactive canvas editing:
                   - Call `create_canvas` to initialize a new visual canvas.
                   - Call `edit_canvas` to modify existing canvas documents.
                   """),
                   keywords: ["canvas", "visual", "diagram", "draw", "layout", "render"],
                   preferredToolIDs: ["create_canvas", "edit_canvas"]
               ) {
                descriptors.append(desc)
            }
        }

        if codeEnabled {
            if let skillID = try? HanlinSkillID(validating: "code"),
               let desc = try? HanlinSkillDescriptor(
                   id: skillID,
                   title: "Code Execution",
                   summary: "Execute sandboxed Python scripts and render interactive web views.",
                   instructions: .inline("""
                   Code and computation workflow:
                   - Call `execute_remote_python_code` for data analysis, computations, and programmatic tasks.
                   - Call `create_web_view` to render HTML/JavaScript previews.
                   """),
                   keywords: ["code", "python", "script", "compute", "execute", "html"],
                   preferredToolIDs: ["create_web_view", "execute_remote_python_code"]
               ) {
                descriptors.append(desc)
            }
        }

        if healthEnabled {
            if let skillID = try? HanlinSkillID(validating: "health"),
               let desc = try? HanlinSkillDescriptor(
                   id: skillID,
                   title: "Health & Fitness",
                   summary: "Query Apple Health metrics including step counts, active energy burned, and nutrition details.",
                   instructions: .inline("""
                   Health and wellness analytics:
                   - Call `fetch_step_details` for daily and hourly walking steps.
                   - Call `fetch_energy_details` for active calories.
                   - Call `fetch_nutrition_details` or `make_nutrition_data` for dietary macronutrients.
                   """),
                   keywords: ["health", "steps", "calories", "nutrition", "diet", "fitness", "apple health"],
                   preferredToolIDs: ["fetch_step_details", "fetch_energy_details", "fetch_nutrition_details", "make_nutrition_data"]
               ) {
                descriptors.append(desc)
            }
        }

        return descriptors
    }
}
