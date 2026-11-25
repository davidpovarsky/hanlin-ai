import HanlinLocalization
import Foundation
import HanlinPlatformContracts

public enum LegacyToolPresentationAdapter {
    private static let resultTools: Set<String> = [
        "write_system_event", "manage_calendar",
        "query_location", "get_current_location", "search_nearby_locations", "get_route",
        "search_online", "search_arxiv_papers", "read_web_page",
        "search_knowledge_bag", "create_knowledge_document", "create_canvas", "edit_canvas",
        "create_web_view", "execute_remote_python_code", "execute_python_code", "make_nutrition_data"
    ]

    public static func profile(for toolName: String, argumentsJSON: String? = nil) -> ToolPresentationProfile? {
        let normalized = toolName.lowercased()
        let domain = domainActivity(for: normalized, argumentsJSON: argumentsJSON)
        let activity = domain?.activity ?? activityDescriptor(for: normalized)
        guard knownToolNames.contains(normalized) else { return nil }
        let hasResult = resultTools.contains(normalized)
        return ToolPresentationProfile(
            identity: "legacy.\(normalized)",
            activity: activity,
            result: hasResult
                ? ToolResultPresentationDescriptor(rendererKind: .legacyExisting, supportsCard: true)
                : nil,
            resultDisplayPolicy: hasResult ? .modelControlled : .never,
            canonicalExecutionPresentation: domain.map {
                HanlinToolExecutionPresentationDescriptor(familyID: $0.family, systemImage: $0.activity.systemImage, animation: .common)
            },
            canonicalEmbeddedPresentation: normalized == "create_web_view"
                ? HanlinEmbeddedPresentationDescriptor(
                    handler: "legacy.web:legacy_web_view",
                    sizing: HanlinEmbeddedSizingPreference(preset: .regular),
                    expansion: HanlinExpansionDescriptor(supportedModes: [.sheet, .fullScreen])
                )
                : nil
        )
    }

    public static func semanticFallback(for toolName: String) -> ToolPresentationProfile? {
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
        "search_calendar_and_reminders", "write_system_event", "manage_calendar",
        "query_location", "get_current_location", "search_nearby_locations", "get_route",
        "query_weather", "search_online", "read_web_page", "search_arxiv_papers",
        "extract_remote_file_content", "search_knowledge_bag", "create_knowledge_document",
        "create_canvas", "edit_canvas", "create_web_view", "execute_remote_python_code", "execute_python_code",
        "fetch_step_details", "fetch_energy_details", "fetch_nutrition_details", "make_nutrition_data"
    ]


    /// Only exact built-in tools and their real operation argument may select
    /// these host-owned animations. They never imply execution or completion.
    private static func domainActivity(
        for name: String,
        argumentsJSON: String?
    ) -> (activity: ToolActivityPresentationDescriptor, family: HanlinExecutionPresentationFamilyID)? {
        switch name {
        case "save_memory":
            return (descriptor(.write, "brain.head.profile", HanlinLocalization.resource("Saving memory"), HanlinLocalization.resource("Saved memory"), ["content"]), .memorySave)
        case "retrieve_memory":
            return (descriptor(.read, "brain.head.profile", HanlinLocalization.resource("Recalling memory"), HanlinLocalization.resource("Recalled memory"), ["query", "keyword"]), .memoryRecall)
        case "update_memory":
            return (descriptor(.write, "brain.head.profile", HanlinLocalization.resource("Updating memory"), HanlinLocalization.resource("Updated memory"), ["content"]), .memoryUpdate)
        case "search_calendar_and_reminders":
            return (descriptor(.inspect, "calendar", HanlinLocalization.resource("Searching the calendar"), HanlinLocalization.resource("Searched the calendar"), ["keyword", "start_date", "end_date"]), .calendarSearch)
        case "write_system_event":
            return (descriptor(.write, "calendar.badge.plus", HanlinLocalization.resource("Creating a calendar item"), HanlinLocalization.resource("Created a calendar item"), ["title", "start_date", "due_date"]), .calendarCreate)
        case "manage_calendar":
            let arguments = argumentsJSON.flatMap {
                (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any]
            }
            let operation = arguments?["operation"] as? String ?? ""
            let keys = ["operation", "identifier", "title"]
            switch operation {
            case "create_event", "create_reminder", "create_calendar":
                return (descriptor(.write, "calendar.badge.plus", HanlinLocalization.resource("Creating a calendar item"), HanlinLocalization.resource("Created a calendar item"), keys), .calendarCreate)
            case "update_event", "update_reminder", "update_calendar", "reopen_reminder":
                return (descriptor(.write, "square.and.pencil", HanlinLocalization.resource("Updating the calendar"), HanlinLocalization.resource("Updated the calendar"), keys), .calendarUpdate)
            case "delete_event", "delete_reminder", "delete_calendar":
                return (descriptor(.write, "calendar.badge.minus", HanlinLocalization.resource("Deleting a calendar item"), HanlinLocalization.resource("Deleted a calendar item"), keys), .calendarDelete)
            case "complete_reminder":
                return (descriptor(.write, "checkmark.circle", HanlinLocalization.resource("Completing a reminder"), HanlinLocalization.resource("Completed a reminder"), keys), .calendarComplete)
            case "request_access", "authorization_status":
                return (descriptor(.inspect, "lock.shield", HanlinLocalization.resource("Checking calendar access"), HanlinLocalization.resource("Checked calendar access"), ["operation", "entity_type"]), .calendarAccess)
            case "list_events", "list_reminders", "find_by_external_identifier":
                return (descriptor(.inspect, "calendar", HanlinLocalization.resource("Searching the calendar"), HanlinLocalization.resource("Searched the calendar"), keys + ["start_date", "end_date"]), .calendarSearch)
            default:
                return (descriptor(.inspect, "calendar", HanlinLocalization.resource("Reading the calendar"), HanlinLocalization.resource("Read the calendar"), keys), .calendarRead)
            }
        default:
            return nil
        }
    }

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
            return descriptor(.write, "calendar.badge.plus", HanlinLocalization.resource("Creating a calendar item"), HanlinLocalization.resource("Created a calendar item"), ["title", "start_date", "due_date"])
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

public enum ToolPresentationProfileRegistry {
    public static func resolve(
        toolName: String,
        explicitProfile: ToolPresentationProfile? = nil,
        argumentsJSON: String? = nil
    ) -> ToolPresentationProfile {
        if let explicitProfile {
            // Preserve provider/MCP authority. Refine only the exact built-in
            // legacy profile, retaining its result and embedded presentation.
            if let argumentsJSON,
               explicitProfile.identity == "legacy.\(toolName.lowercased())",
               let invocation = LegacyToolPresentationAdapter.profile(for: toolName, argumentsJSON: argumentsJSON) {
                var refined = explicitProfile
                refined.activity = invocation.activity
                refined.canonicalExecutionPresentation = invocation.canonicalExecutionPresentation
                return refined
            }
            return explicitProfile
        }
        if let legacy = LegacyToolPresentationAdapter.profile(for: toolName, argumentsJSON: argumentsJSON) { return legacy }
        if let semantic = LegacyToolPresentationAdapter.semanticFallback(for: toolName) { return semantic }
        return .generic(toolName: toolName)
    }
}
