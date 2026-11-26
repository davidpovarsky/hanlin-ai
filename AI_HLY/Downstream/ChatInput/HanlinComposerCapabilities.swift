import CryptoKit
import Foundation
import HanlinPlatformContracts

/// Projects existing registries into one picker. Reading this catalog does not
/// start a MiniApp, connect an MCP server, run a Skill, or change preferences.
@MainActor
enum HanlinComposerCapabilities {
    static func messageText(for row: ChatMessages) -> String {
        let text = row.text ?? ""
        guard row.role == "user", let data = row.capabilityAttachmentsData,
              let attachments = try? JSONDecoder().decode([HanlinCapabilityAttachment].self, from: data),
              !attachments.isEmpty else { return text }
        // Keep the durable typed codec in storage, and project ordinary JSON
        // for the model just as the active request's selection instruction does.
        let selections = HanlinJSONValue.array(attachments.map { attachment in
            .object([
                "attachmentID": .string(attachment.id.uuidString),
                "kind": .string(attachment.reference.kind.rawValue),
                "sourceID": .string(attachment.reference.sourceID),
                "capabilityID": .string(attachment.reference.capabilityID),
                "revision": attachment.reference.revision.map(HanlinJSONValue.string) ?? .null,
                "title": .string(attachment.title),
                "actionID": attachment.actionID.map(HanlinJSONValue.string) ?? .null,
                "configuration": attachment.configuration
            ])
        })
        guard let projection = try? selections.canonicalJSONData() else { return text }
        return text + "\n\n[Capabilities explicitly attached to this message; selection metadata, not execution results]\n"
            + String(decoding: projection, as: UTF8.self)
    }

    static func catalog() -> [HanlinComposerCapabilityDescriptor] {
        let native = NativeToolCatalog.shared
        let entries = native.allEntries().filter(\.isVisibleInSettings)
        var result = entries.compactMap { entry -> HanlinComposerCapabilityDescriptor? in
            guard let provider = try? NativeToolCanonicalShadowAdapter.providerInstanceID(for: entry) else { return nil }
            return .init(reference: .init(kind: .tool, sourceID: provider.rawValue, capabilityID: entry.name),
                title: entry.title, summary: entry.summary, systemImage: entry.systemImage,
                configuration: entry.composerConfiguration)
        }
        for source in LegacyToolCanonicalAdapter.sources() {
            let name = source.toolName
            result.append(.init(reference: .init(kind: .tool,
                sourceID: LegacyToolCanonicalAdapter.providerInstanceIDString, capabilityID: name),
                title: source.descriptor.title.preferredValue(), summary: source.descriptor.summary.preferredValue(),
                systemImage: LegacyToolCanonicalAdapter.category(for: name) == "map" ? "map" : "wrench.and.screwdriver",
                configuration: name == "search_nearby_locations" ? .init(panels: [
                    .init(id: "region", title: "Search area", fields: [
                        .init(key: "location", title: "Search area", kind: .location, required: true)
                    ])
                ]) : nil))
        }
        for group in native.settingsGroups() {
            result.append(.init(reference: .init(kind: .miniApp, sourceID: group.id, capabilityID: "assistantTools"),
                title: group.title, summary: group.summary, systemImage: group.systemImage,
                actions: group.toolEntries.map { .init(id: $0.name, title: $0.title, summary: $0.summary) },
                configuration: group.toolEntries.compactMap(\.composerConfiguration).first))
        }
        result += HanlinMiniAppAssistantToolExports.descriptors()
        let skills = HanlinSkillCatalog.shared
        for skill in skills.allSkills() where SkillStore.shared.isSkillEnabled(id: skill.id) {
            // A changed installed skill must be reselected instead of silently
            // replacing the instructions the user chose for an unsent draft.
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            var bytes = (try? encoder.encode(skill)) ?? Data(skill.id.rawValue.utf8)
            if let document = skills.markdownDocument(for: skill.id) { bytes.append(document.originalSource) }
            let revision = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            result.append(.init(reference: .init(kind: .skill, sourceID: "hanlin.skills",
                capabilityID: skill.id.rawValue, revision: revision), title: skill.title.preferredValue(),
                summary: skill.summary.preferredValue(), systemImage: "sparkles"))
        }
        let mcp = MCPRuntimeProvider.shared
        if mcp.configuration.isEnabled {
            for server in mcp.servers where server.isGloballyEnabled {
                result.append(.init(reference: .init(kind: .mcp, sourceID: server.id.uuidString.lowercased(),
                    capabilityID: "*"), title: server.displayName, summary: server.packageName,
                    systemImage: "server.rack"))
            }
        }
        #if DEBUG || HANLIN_TESTING
        if ProcessInfo.processInfo.environment["HANLIN_COMPOSER_CAPABILITY_UI_FIXTURES"] == "1" {
            // UI-only data for real control gestures. No executor, network call,
            // runtime-success marker or replacement product behavior is installed.
            result.append(.init(reference: .init(kind: .tool, sourceID: "hanlin.ui.acceptance", capabilityID: "library-region"),
                title: "Composer Catalog & Map", systemImage: "map",
                configuration: .init(panels: [
                    .init(id: "catalog", title: "Catalog", fields: [
                        .init(key: "collections", title: "Collections", kind: .catalog,
                              defaultValue: .array([.string("tanakh")]), options: [
                                .init(id: "tanakh", title: "Tanakh"), .init(id: "talmud", title: "Talmud")])
                    ]),
                    .init(id: "region", title: "Region", fields: [
                        .init(key: "location", title: "Search area", kind: .location, required: true,
                              defaultValue: .object(["latitude": .number(31.78), "longitude": .number(35.23), "radiusMeters": .integer(1000)]),
                              minimum: 100, maximum: 20000)
                    ])
                ])))
        }
        #endif
        return result.sorted {
            let order = $0.title.localizedStandardCompare($1.title)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    /// Validate the value snapshot against current declarations, before admitting
    /// any provider work. Also used by SDK callers without mounting the composer.
    static func validate(_ attachments: [HanlinCapabilityAttachment],
                         catalog: [HanlinComposerCapabilityDescriptor]? = nil) throws {
        guard !attachments.isEmpty else { return }
        let available = catalog ?? self.catalog()
        var identities = Set<String>()
        var ids = Set<UUID>()
        for attachment in attachments {
            guard ids.insert(attachment.id).inserted,
                  identities.insert(attachment.selectionKey).inserted else {
                throw HanlinComposerCapabilityError.invalid("The same capability is attached more than once.")
            }
            guard let descriptor = available.first(where: { $0.id == attachment.reference.id }) else {
                throw HanlinComposerCapabilityError.unavailable(attachment.title)
            }
            let issues = descriptor.validationIssues(for: attachment)
            guard issues.isEmpty else {
                throw HanlinComposerCapabilityError.invalid(issues.map(\.message).joined(separator: " "))
            }
        }
    }

    static func scope(_ original: AssistantToolRequestScope,
                      attachments: [HanlinCapabilityAttachment],
                      catalog: [HanlinComposerCapabilityDescriptor]? = nil) throws -> AssistantToolRequestScope {
        try validate(attachments, catalog: catalog)
        var scope = original
        scope.capabilityAttachments = attachments
        for attachment in attachments where attachment.reference.kind == .mcp {
            guard scope.mcpGloballyEnabled,
                  let id = UUID(uuidString: attachment.reference.sourceID) else {
                throw HanlinComposerCapabilityError.unavailable(attachment.title)
            }
            // Selection for this message only: never mutate the per-chat or
            // new-conversation MCP selection store.
            scope.mcpServerIDs.insert(id)
        }
        return scope
    }

    static func explicitNativeNames(in attachments: [HanlinCapabilityAttachment]) -> Set<String> {
        let catalog = NativeToolCatalog.shared
        var names = Set<String>()
        for attachment in attachments {
            switch attachment.reference.kind {
            case .tool:
                if let entry = catalog.entry(named: attachment.reference.capabilityID),
                   let provider = try? NativeToolCanonicalShadowAdapter.providerInstanceID(for: entry),
                   provider.rawValue == attachment.reference.sourceID {
                    names.insert(entry.name)
                }
            case .miniApp where attachment.reference.capabilityID == "assistantTools":
                for entry in catalog.allEntries() where entry.sourceAppID == attachment.reference.sourceID {
                    if attachment.actionID == nil || attachment.actionID == entry.name { names.insert(entry.name) }
                }
            default: break
            }
        }
        return names
    }

    static func explicitLegacySources(in attachments: [HanlinCapabilityAttachment]) -> [HanlinCanonicalToolAuthority.LegacySource] {
        let names = Set(attachments.filter {
            $0.reference.kind == .tool && $0.reference.sourceID == LegacyToolCanonicalAdapter.providerInstanceIDString
        }.map { $0.reference.capabilityID })
        guard !names.isEmpty else { return [] }
        return LegacyToolCanonicalAdapter.sources().filter { names.contains($0.toolName) }
    }
}
