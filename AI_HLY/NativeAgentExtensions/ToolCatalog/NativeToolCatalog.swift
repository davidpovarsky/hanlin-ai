//
//  NativeToolCatalog.swift
//  AI_HLY
//
//  Unified registry for built-in and Native App assistant tools.
//

import Foundation

@MainActor
final class NativeToolCatalog {
    static let shared = NativeToolCatalog()

    private struct RegisteredTool {
        let tool: NativeTool
        let entry: NativeToolCatalogEntry
        let schema: [String: Any]
    }

    private var toolsByName: [String: RegisteredTool] = [:]
    private var didRegisterBuiltins = false
    private let enabledStore = NativeToolEnabledStore()

    private init() {}

    func ensureBuiltinsRegistered() {
        guard !didRegisterBuiltins else { return }
        didRegisterBuiltins = true
        register(QuickCalculateTool())
        registerNativeAppTools()
    }

    @discardableResult
    func register(_ tool: NativeTool, sourceApp: NativeAppManifest? = nil) -> Bool {
        let name = tool.name
        guard Self.isValidCanonicalName(name) else {
            let message = "Invalid canonical assistant tool name '\(name)'. Names must match [a-z][a-z0-9_]* and must not use app_."
            NativeToolTraceLogger.shared.log(
                "tool_registration_invalid_name",
                ["toolName": name, "sourceAppID": sourceApp?.id as Any, "reason": message]
            )
            assertionFailure(message)
            return false
        }

        let schema = tool.openAIToolSchema()
        guard let function = schema["function"] as? [String: Any],
              let schemaName = function["name"] as? String,
              schemaName == name else {
            let message = "Assistant tool '\(name)' must expose the same canonical name in its schema."
            NativeToolTraceLogger.shared.log(
                "tool_registration_schema_name_mismatch",
                ["toolName": name, "sourceAppID": sourceApp?.id as Any, "reason": message]
            )
            assertionFailure(message)
            return false
        }

        guard let existing = toolsByName[name] else {
            var entry = tool.catalogEntry
            entry.name = name
            if let sourceApp {
                entry.sourceAppID = sourceApp.id
                entry.sourceAppTitle = sourceApp.title
                if entry.systemImage == "wrench.and.screwdriver" {
                    entry.systemImage = sourceApp.systemImage
                }
            }
            toolsByName[name] = RegisteredTool(tool: tool, entry: entry, schema: schema)
            NativeToolTraceLogger.shared.log(
                "assistant_tool_discovered",
                [
                    "toolName": name,
                    "sourceAppID": entry.sourceAppID as Any,
                    "enabled": enabledStore.isEnabled(entry)
                ]
            )
            return true
        }

        let message = "Duplicate assistant tool '\(name)' from '\(sourceApp?.id ?? "Hanlin")'; already registered by '\(existing.entry.sourceAppID ?? "Hanlin")'."
        NativeToolTraceLogger.shared.log(
            "duplicate_tool_registration_failed",
            [
                "toolName": name,
                "sourceAppID": sourceApp?.id as Any,
                "existingSourceAppID": existing.entry.sourceAppID as Any
            ]
        )
        assertionFailure(message)
        return false
    }

    func tool(named name: String, enabledOnly: Bool = true) -> NativeTool? {
        ensureBuiltinsRegistered()
        guard let registered = toolsByName[name] else { return nil }
        guard !enabledOnly || enabledStore.isEnabled(registered.entry) else { return nil }
        return registered.tool
    }

    func entry(named name: String) -> NativeToolCatalogEntry? {
        ensureBuiltinsRegistered()
        return toolsByName[name]?.entry
    }

    func allEntries() -> [NativeToolCatalogEntry] {
        ensureBuiltinsRegistered()
        return toolsByName.values.map(\.entry).sorted { $0.name < $1.name }
    }

    func settingsEntries() -> [NativeToolCatalogEntry] {
        allEntries().filter { entry in
            entry.sourceAppID != nil && entry.isVisibleInSettings
        }
    }

    func schemasForEnabledTools() -> [[String: Any]] {
        ensureBuiltinsRegistered()
        let registrations = toolsByName.values.sorted { $0.entry.name < $1.entry.name }
        let enabled = registrations.filter { enabledStore.isEnabled($0.entry) }
        let disabled = registrations.filter { !enabledStore.isEnabled($0.entry) }
        let schemas = enabled.map(\.schema)

        NativeToolTraceLogger.shared.log(
            "schemas_for_request_completed",
            [
                "schemaCount": schemas.count,
                "enabledToolNames": enabled.map(\.entry.name),
                "disabledToolNames": disabled.map(\.entry.name),
                "includedToolNames": enabled.map(\.entry.name)
            ]
        )
        return schemas
    }

    func isEnabled(_ entry: NativeToolCatalogEntry) -> Bool {
        enabledStore.isEnabled(entry)
    }

    func setEnabled(_ enabled: Bool, for entry: NativeToolCatalogEntry) {
        enabledStore.setEnabled(enabled, for: entry)
        NativeToolTraceLogger.shared.log(
            "tool_enabled_state_changed",
            ["toolName": entry.name, "enabled": enabled, "sourceAppID": entry.sourceAppID as Any]
        )
    }

    private static func isValidCanonicalName(_ name: String) -> Bool {
        guard !name.isEmpty, !name.hasPrefix("app_") else { return false }
        return name.range(of: "^[a-z][a-z0-9_]*$", options: .regularExpression) != nil
    }
}

private final class NativeToolEnabledStore {
    private let defaults: UserDefaults
    private let migrationKey = "assistantTools.canonicalNameMigration.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        migrateLegacyNamesIfNeeded()
    }

    func isEnabled(_ entry: NativeToolCatalogEntry) -> Bool {
        let key = preferenceKey(entry.name)
        guard defaults.object(forKey: key) != nil else { return entry.isEnabledByDefault }
        return defaults.bool(forKey: key)
    }

    func setEnabled(_ enabled: Bool, for entry: NativeToolCatalogEntry) {
        defaults.set(enabled, forKey: preferenceKey(entry.name))
    }

    private func preferenceKey(_ name: String) -> String {
        "toolEnabled.\(name)"
    }

    private func migrateLegacyNamesIfNeeded() {
        guard !defaults.bool(forKey: migrationKey) else { return }
        let migrations = [
            "app_sefaria_search": "sefaria_search",
            "app_sefaria_get_source": "sefaria_get_source",
            "app_wikipedia_search": "wikipedia_search",
            "app_wikipedia_summary": "wikipedia_get_summary",
            "app_text_analyze": "text_analyze",
            "app_text_transform": "text_transform"
        ]

        for (oldName, newName) in migrations {
            let oldKey = preferenceKey(oldName)
            let newKey = preferenceKey(newName)
            if defaults.object(forKey: newKey) == nil, let oldValue = defaults.object(forKey: oldKey) {
                defaults.set(oldValue, forKey: newKey)
            }
            defaults.removeObject(forKey: oldKey)
        }
        defaults.set(true, forKey: migrationKey)
    }
}
