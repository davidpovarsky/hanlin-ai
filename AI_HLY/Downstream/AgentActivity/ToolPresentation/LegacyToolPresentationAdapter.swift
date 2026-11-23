import HanlinLocalization
import Foundation
import HanlinPlatformContracts

enum LegacyToolPresentationAdapter {
    private static let resultTools: Set<String> = [
        "write_system_event",
        "query_location", "get_current_location", "search_nearby_locations", "get_route",
        "search_online", "search_arxiv_papers", "read_web_page",
        "search_knowledge_bag", "create_knowledge_document", "create_canvas", "edit_canvas",
        "create_web_view", "execute_remote_python_code", "execute_python_code", "make_nutrition_data"
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
            resultDisplayPolicy: hasResult ? .modelControlled : .never,
            canonicalEmbeddedPresentation: normalized == "create_web_view"
                ? HanlinEmbeddedPresentationDescriptor(
                    handler: "legacy.web:legacy_web_view",
                    sizing: HanlinEmbeddedSizingPreference(preset: .regular),
                    expansion: HanlinExpansionDescriptor(supportedModes: [.sheet, .fullScreen])
                )
                : nil
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
        "create_canvas", "edit_canvas", "create_web_view", "execute_remote_python_code", "execute_python_code",
        "fetch_step_details", "fetch_energy_details", "fetch_nutrition_details", "make_nutrition_data"
    ]

    private static func activityDescriptor(for name: String) -> ToolActivityPresentationDescriptor {
        // Exact built-in semantics precede broad words such as "search".
        // A nearby-place or calendar search is not a web-search operation.
        switch name {
        case "get_current_location":
            return descriptor(.navigate, "location", HanlinLocalization.resource("Checking your location"), HanlinLocalization.resource("Checked your location"), [])
        case "query_location":
            return descriptor(.navigate, "map", HanlinLocalization.resource("Searching locations"), HanlinLocalization.resource("Searched locations"), ["keyword"])
        case "search_nearby_locations":
            return descriptor(.navigate, "map", HanlinLocalization.resource("Searching nearby places"), HanlinLocalization.resource("Searched nearby places"), ["keyword", "coordinate"])
        case "get_route":
            return descriptor(.navigate, "map", HanlinLocalization.resource("Planning a route"), HanlinLocalization.resource("Planned a route"), ["start", "end", "mode"])
        case "query_weather":
            return descriptor(.inspect, "cloud.sun", HanlinLocalization.resource("Checking the weather"), HanlinLocalization.resource("Checked the weather"), ["latitude", "longitude", "timeRange"])
        case "search_calendar_and_reminders":
            return descriptor(.inspect, "calendar", HanlinLocalization.resource("Searching the calendar"), HanlinLocalization.resource("Searched the calendar"), ["keyword", "start_date", "end_date"])
        case "write_system_event":
            return descriptor(.write, "calendar", HanlinLocalization.resource("Updating the calendar"), HanlinLocalization.resource("Updated the calendar"), ["title", "start_date", "end_date"])
        default: break
        }
        if name.contains("search") {
            return descriptor(.search, "magnifyingglass", HanlinLocalization.resource("Searching the web"), HanlinLocalization.resource("Searched the web"), ["query", "keyword"])
        }
        if name.contains("read") || name.contains("extract") || name.contains("retrieve") {
            return descriptor(.read, "doc.text", HanlinLocalization.resource("Reading a source"), HanlinLocalization.resource("Read a source"), ["url", "keyword"])
        }
        if name.contains("code") || name.contains("python") {
            return descriptor(.execute, "terminal", HanlinLocalization.resource("Running code"), HanlinLocalization.resource("Ran code"), ["code"])
        }
        if name.contains("route") || name.contains("location") || name.contains("weather") {
            return descriptor(.navigate, "map", HanlinLocalization.resource("Searching locations"), HanlinLocalization.resource("Searched locations"), ["keyword", "query"])
        }
        if name.contains("calendar") || name.contains("event") {
            return descriptor(.inspect, "calendar", HanlinLocalization.resource("Checking the calendar"), HanlinLocalization.resource("Checked the calendar"), ["title", "start_date", "end_date"])
        }
        if name.contains("calculate") {
            return descriptor(.calculate, "function", HanlinLocalization.resource("Calculating"), HanlinLocalization.resource("Calculated"), ["expression"])
        }
        if name.contains("save") || name.contains("write") || name.contains("create") || name.contains("edit") || name.contains("update") || name.contains("make") {
            return descriptor(.write, "square.and.pencil", HanlinLocalization.resource("Working…"), HanlinLocalization.resource("Done"), ["title"])
        }
        return descriptor(.generic, "sparkles", HanlinLocalization.resource("Using a tool"), HanlinLocalization.resource("Used a tool"), [])
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
            failedTitle: String(localized: "Tool failed", bundle: HanlinLocalization.bundle),
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
