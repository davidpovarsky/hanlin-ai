import Foundation

enum LegacyToolPresentationAdapter {
    private static let resultTools: Set<String> = [
        "write_system_event",
        "query_location", "get_current_location", "search_nearby_locations", "get_route",
        "search_online", "search_arxiv_papers", "read_web_page",
        "search_knowledge_bag", "create_knowledge_document", "create_canvas", "edit_canvas",
        "create_web_view", "execute_python_code", "make_nutrition_data"
    ]

    static func profile(for toolName: String) -> ToolPresentationProfile? {
        let normalized = toolName.lowercased()
        let activity = activityDescriptor(for: normalized)
        guard knownToolNames.contains(normalized) else { return nil }
        let hasResult = resultTools.contains(normalized)
        return ToolPresentationProfile(
            identity: "legacy.\(normalized)",
            activity: activity,
            result: hasResult
                ? ToolResultPresentationDescriptor(rendererKind: .legacyExisting, supportsCard: true)
                : nil,
            resultDisplayPolicy: hasResult ? .modelControlled : .never
        )
    }

    static func semanticFallback(for toolName: String) -> ToolPresentationProfile? {
        let normalized = toolName.lowercased()
        let markers = ["search", "read", "retrieve", "code", "python", "calculate", "map", "route", "calendar", "write", "create", "generate"]
        guard markers.contains(where: normalized.contains) else { return nil }
        return ToolPresentationProfile(
            identity: "semantic.\(normalized)",
            activity: activityDescriptor(for: normalized),
            result: nil,
            resultDisplayPolicy: .never
        )
    }

    private static let knownToolNames: Set<String> = [
        "save_memory", "retrieve_memory", "update_memory",
        "search_calendar_and_reminders", "write_system_event",
        "query_location", "get_current_location", "search_nearby_locations", "get_route",
        "query_weather", "search_online", "read_web_page", "search_arxiv_papers",
        "extract_remote_file_content", "search_knowledge_bag", "create_knowledge_document",
        "create_canvas", "edit_canvas", "create_web_view", "execute_python_code",
        "fetch_step_details", "fetch_energy_details", "fetch_nutrition_details", "make_nutrition_data"
    ]

    private static func activityDescriptor(for name: String) -> ToolActivityPresentationDescriptor {
        if name.contains("search") {
            return descriptor(.search, "magnifyingglass", "Searching the web", "Searched the web", ["query", "keyword"])
        }
        if name.contains("read") || name.contains("extract") || name.contains("retrieve") {
            return descriptor(.read, "doc.text", "Reading a source", "Read a source", ["url", "keyword"])
        }
        if name.contains("code") || name.contains("python") {
            return descriptor(.execute, "terminal", "Running code", "Ran code", ["code"])
        }
        if name.contains("route") || name.contains("location") || name.contains("weather") {
            return descriptor(.navigate, "map", "Searching locations", "Searched locations", ["keyword", "query"])
        }
        if name.contains("calendar") || name.contains("event") {
            return descriptor(.inspect, "calendar", "Checking the calendar", "Checked the calendar", ["title", "start_date", "end_date"])
        }
        if name.contains("calculate") {
            return descriptor(.calculate, "function", "Calculating", "Calculated", ["expression"])
        }
        if name.contains("save") || name.contains("write") || name.contains("create") || name.contains("edit") || name.contains("update") || name.contains("make") {
            return descriptor(.write, "square.and.pencil", "Working…", "Done", ["title"])
        }
        return descriptor(.generic, "sparkles", "Using a tool", "Used a tool", [])
    }

    private static func descriptor(
        _ kind: ToolActivityPresentationKind,
        _ image: String,
        _ running: LocalizedStringResource,
        _ completed: LocalizedStringResource,
        _ keys: [String]
    ) -> ToolActivityPresentationDescriptor {
        ToolActivityPresentationDescriptor(
            kind: kind,
            systemImage: image,
            runningTitle: String(localized: running),
            completedTitle: String(localized: completed),
            failedTitle: String(localized: "Tool failed"),
            visibleArgumentKeys: keys
        )
    }
}

enum ToolPresentationProfileRegistry {
    static func resolve(
        toolName: String,
        explicitProfile: ToolPresentationProfile? = nil
    ) -> ToolPresentationProfile {
        if let explicitProfile { return explicitProfile }
        if let legacy = LegacyToolPresentationAdapter.profile(for: toolName) { return legacy }
        if let semantic = LegacyToolPresentationAdapter.semanticFallback(for: toolName) { return semantic }
        return .generic(toolName: toolName)
    }
}
