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
                   - A memory success confirms only that memory operation. It does not update a reminder, calendar note, task, or any other app.
                   - When a request also changes a calendar item, load the calendar skill and execute its update tool separately.
                   - Report an action as completed only after receiving a successful result for that exact action. If a requested action has not run, complete it or state what remains; never infer completion from an intention or a different tool's success.
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
                   summary: "Search, create, update, move, complete and delete system events, reminders, calendars and lists; manage recurrence, alarms and public EventKit fields.",
                   instructions: .inline("""
                   Coordinate user calendar and tasks:
                   - Call `search_calendar_and_reminders` with date ranges or keywords to check availability.
                   - `manage_calendar` exposes public EventKit operations: permissions, sources/accounts, calendars/reminder lists, event/reminder CRUD, moves, completion/reopening, recurrence, alarms, external identifiers, and refresh. Its schema lists the full supported parameters.
                   - Search or get the existing item and use its returned identifier for update/delete/complete/reopen. Preserve omitted fields. A missing identifier is an error; never create a replacement when asked to edit.
                   - Use `manage_calendar` with operation=update_reminder and item.notes to change reminder notes. `save_memory` and MCP memory entity operations cannot change EventKit items.
                   - `write_system_event` is CREATE ONLY. Use complete ISO-8601 timestamps with timezones; never use it to repair an alleged failed update.
                   - Date-only end_date includes that entire local day. Recurring event changes require the returned occurrence_date and an explicit this_event/future_events choice matching the user's intent.
                   - Report changes only after a successful result with committed=true for the matching operation and identifier. Search, memory, and failed/denied/cancelled calls provide no proof of a calendar change. Check every requested action before your final answer.
                   - Calendar/account IDs and item IDs are distinct. Attendees, organizer, event status, source metadata and system identifiers are read-only. Reminders tags, subtasks, invitation sending and sharing administration are not writable public iOS EventKit capabilities.
                   """),
                   keywords: ["schedule", "event", "meeting", "reminder", "appointment", "calendar"],
                   preferredToolIDs: ["search_calendar_and_reminders", "manage_calendar", "write_system_event"]
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
            let coordinateGuidance = mapEnabled
                ? """
                - For the user's current location, call `get_current_location` with `query` set to `local`; honor the tool approval and device location permission result.
                - For a named city or place, call `query_location` with its name as `keyword` and use the returned coordinates.
                - If location access fails or is declined, ask for a location the user chooses to share. Do not invent coordinates or claim device location is unavailable before trying the available tool.
                """
                : """
                - Map and device-location tools are disabled. Use coordinates already supplied in the conversation, or ask the user to provide coordinates; do not call disabled location tools.
                """
            if let skillID = try? HanlinSkillID(validating: "weather"),
               let desc = try? HanlinSkillDescriptor(
                   id: skillID,
                   title: "Weather Forecast",
                   summary: "Inspect current weather conditions, forecasts, and atmospheric observations.",
                   instructions: .inline("""
                   Retrieve meteorological data:
                   - Call `query_weather` with numeric `latitude`, numeric `longitude`, and `timeRange` (`now`, `3d`, `7d`, `10d`, `15d`, or `30d`). A city or location name is not a valid argument to this tool.
                   \(coordinateGuidance)
                   """),
                   keywords: ["weather", "temperature", "forecast", "rain", "climate", "conditions"],
                   preferredToolIDs: mapEnabled
                       ? ["query_weather", "get_current_location", "query_location"]
                       : ["query_weather"]
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
                   - IMPORTANT: `web_research` is a skill_id for `load_skill`, NOT a callable tool name. Never call `web_research` as a tool.
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
                   title: "Code Execution & Runtime Tools",
                   summary: "Execute Python scripts, calculations, JavaScript/TypeScript, terminal shell commands, inspect runtime capabilities, manage Python/Node packages, and render interactive web views.",
                   instructions: .inline("""
                   Code, scripting, and runtime workflow:
                   - Call `get_runtime_capabilities` to inspect Python, Node, TypeScript, JSC, Shell, and MCP runtime states.
                   - Call `execute_local_python_code` for data analysis, math, file processing, and computations. Local Python starts automatically when needed.
                   - Call `quick_calculate` for simple single-expression math.
                   - Call `execute_javascript_code` or `execute_typescript_code` for JS/TS scripts.
                   - Call `execute_shell_command` for terminal commands when permitted.
                   - Call `manage_runtime_packages` to list, preview, install, probe, or uninstall Python and Node packages. Python supports standard requirements with extras/markers, compatible source backends and local sources.
                   - Third-party Python packages, including `requests`, are not preinstalled. Check installed packages before importing; use Python's standard-library `urllib.request` for HTTP when sufficient. On ModuleNotFoundError, verify the distribution name and use the package manager's preview/install/probe workflow. Do not repeat the same failing import or rerun earlier side effects blindly.
                   - Long Node/Python/TypeScript executions have durable job IDs and full output files. Call `get_runtime_job` to read status/output or explicitly cancel; never replay side effects merely because a client disconnected.
                   - Call `execute_skill_resource` to run bundled skill scripts.
                   - Call `create_web_view` to render HTML/JavaScript previews.
                   """),
                   keywords: ["code", "python", "script", "compute", "execute", "math", "javascript", "typescript", "shell", "terminal", "packages", "npm", "pip", "runtime", "html"],
                   preferredToolIDs: [
                       "execute_local_python_code",
                       "get_runtime_capabilities",
                       "quick_calculate",
                       "execute_javascript_code",
                       "execute_typescript_code",
                       "execute_shell_command",
                       "manage_runtime_packages",
                       "get_runtime_job",
                       "execute_skill_resource",
                       "create_web_view"
                   ]
               ) {
                descriptors.append(desc)
            }

            if let mcpSkillID = try? HanlinSkillID(validating: "mcp_servers"),
               let mcpDesc = try? HanlinSkillDescriptor(
                   id: mcpSkillID,
                   title: "MCP Server Management & Tools",
                   summary: "Inspect, preview, install, enable, select for chat, start, stop, restart, list tools, and uninstall local Model Context Protocol (MCP) servers.",
                   instructions: .inline("""
                   MCP server lifecycle and tool execution workflow:
                   - Never claim that MCP installation or inspection is unavailable without checking `manage_mcp_servers`.
                   - Call `manage_mcp_servers(action: "status")` or `manage_mcp_servers(action: "list")` to inspect whether MCP is globally enabled, which servers are installed, whether they are selected for the current chat, and whether their worker is running.
                   - Call `manage_mcp_servers(action: "preview", package_spec: "<npm-spec>")` or `manage_mcp_servers(action: "install", package_spec: "<npm-spec>")` to preview or install an npm MCP server on device.
                   - Call `manage_mcp_servers(action: "enable", server: "<slug>")`, `select_for_chat`, `start`, or `list_tools` to activate a server and discover its exposed `mcp__<slug>__<tool>` tools.
                   """),
                   keywords: ["mcp", "server", "modelcontextprotocol", "install", "tools", "plugin", "npm"],
                   preferredToolIDs: [
                       "manage_mcp_servers",
                       "list_tools",
                       "get_runtime_capabilities"
                   ]
               ) {
                descriptors.append(mcpDesc)
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
