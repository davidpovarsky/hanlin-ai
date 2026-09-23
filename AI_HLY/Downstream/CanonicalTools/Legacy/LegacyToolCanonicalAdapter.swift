import Foundation
import HanlinPlatformContracts

enum LegacyToolCanonicalAdapter {
    static let providerInstanceIDString = "hanlin-legacy"

    /// Categorizes legacy tools for metadata and search hints.
    static func category(for toolName: String) -> String {
        switch toolName {
        case "save_memory", "retrieve_memory", "update_memory":
            return "memory"
        case "search_calendar_and_reminders", "write_system_event":
            return "calendar"
        case "query_location", "get_current_location", "search_nearby_locations", "get_route":
            return "map"
        case "query_weather":
            return "weather"
        case "search_online", "read_web_page", "search_arxiv_papers", "extract_remote_file_content":
            return "search"
        case "search_knowledge_bag", "create_knowledge_document":
            return "knowledge"
        case "create_canvas", "edit_canvas":
            return "canvas"
        case "create_web_view", "execute_remote_python_code", "execute_python_code":
            return "code"
        case "fetch_step_details", "fetch_energy_details", "fetch_nutrition_details", "make_nutrition_data":
            return "health"
        default:
            return "general"
        }
    }

    /// Provides keywords for tool search ranking.
    static func keywords(for toolName: String) -> [String] {
        var words = [toolName, category(for: toolName)]
        switch toolName {
        case "save_memory", "retrieve_memory", "update_memory":
            words += ["remember", "notes", "fact", "preference", "recall"]
        case "search_calendar_and_reminders", "write_system_event":
            words += ["schedule", "event", "meeting", "task", "reminder", "appointment"]
        case "query_location", "get_current_location", "search_nearby_locations", "get_route":
            words += ["place", "poi", "navigate", "directions", "coordinates", "gps"]
        case "query_weather":
            words += ["forecast", "temperature", "rain", "climate"]
        case "search_online", "read_web_page", "search_arxiv_papers", "extract_remote_file_content":
            words += ["web", "google", "browse", "article", "paper", "pdf", "file"]
        case "search_knowledge_bag", "create_knowledge_document":
            words += ["document", "docs", "notes", "backpack", "markdown"]
        case "create_canvas", "edit_canvas":
            words += ["markdown", "html", "preview", "editor"]
        case "create_web_view", "execute_remote_python_code", "execute_python_code":
            words += ["python", "script", "html", "css", "sandbox"]
        case "fetch_step_details", "fetch_energy_details", "fetch_nutrition_details", "make_nutrition_data":
            words += ["health", "steps", "calories", "food", "diet", "nutrition"]
        default:
            break
        }
        return words
    }

    /// Converts active legacy tools into canonical tool authority sources.
    static func sources(
        memoryEnabled: Bool = true,
        mapEnabled: Bool = true,
        calendarEnabled: Bool = true,
        searchEnabled: Bool = true,
        knowledgeEnabled: Bool = true,
        codeEnabled: Bool = true,
        healthEnabled: Bool = true,
        weatherEnabled: Bool = true,
        canvasEnabled: Bool = true
    ) -> [HanlinCanonicalToolAuthority.LegacySource] {
        let tools = buildMemoryTools(
            memoryEnabled: memoryEnabled,
            mapEnabled: mapEnabled,
            calendarEnabled: calendarEnabled,
            searchEnabled: searchEnabled,
            knowledgeEnabled: knowledgeEnabled,
            codeEnabled: codeEnabled,
            healthEnabled: healthEnabled,
            weatherEnabled: weatherEnabled,
            canvasEnabled: canvasEnabled
        )

        guard let providerInstanceID = try? HanlinProviderInstanceID(validating: providerInstanceIDString) else {
            return []
        }

        return tools.compactMap { toolDict -> HanlinCanonicalToolAuthority.LegacySource? in
            guard let function = toolDict["function"] as? [String: Any],
                  let name = function["name"] as? String else {
                return nil
            }
            guard let localToolID = try? HanlinToolID(validating: name) else {
                return nil
            }

            let description = (function["description"] as? String) ?? name
            let logicalID = HanlinLogicalToolID(
                providerInstanceID: providerInstanceID,
                localToolID: localToolID
            )

            let presentationProfile = LegacyToolPresentationAdapter.profile(for: name) ?? .generic(toolName: name)
            let presentationDesc = HanlinToolPresentationDescriptor(
                compactStyle: .automatic,
                executionPresentation: nil,
                embeddedPresentation: presentationProfile.canonicalEmbeddedPresentation
            )

            guard let revision = try? HanlinDescriptorRevision(1),
                  let titleVal = try? LocalizedValue(["en": name]),
                  let summaryVal = try? LocalizedValue(["en": description]) else {
                return nil
            }

            let parameters = function["parameters"] ?? ["type": "object", "properties": [String: Any]()]
            let root = (try? HanlinFoundationJSONShadowAdapter.project(parameters)) ?? .object([:])
            guard let document = try? HanlinJSONSchemaDocument(
                dialect: .draft2020_12,
                root: root,
                sourceProviderInstanceID: providerInstanceID
            ) else {
                return nil
            }

            let toolDesc = HanlinToolDescriptor(
                logicalID: logicalID,
                descriptorRevision: revision,
                owner: .system,
                title: titleVal,
                summary: summaryVal,
                inputSchema: document,
                outputSchema: nil,
                capabilities: [],
                risk: .read,
                presentation: presentationDesc
            )

            return HanlinCanonicalToolAuthority.LegacySource(
                descriptor: toolDesc,
                preferredAlias: name,
                modelSchema: toolDict,
                toolName: name,
                presentationProfile: presentationProfile,
                resultTitle: name
            )
        }
    }
}
