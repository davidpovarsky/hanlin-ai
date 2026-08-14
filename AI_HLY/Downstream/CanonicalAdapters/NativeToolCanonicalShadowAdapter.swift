import Foundation
import HanlinPlatformContracts

/// Projects NativeAgentExtensions discovery state into a read-only canonical
/// tool snapshot. `NativeToolCatalog` remains the executor and settings owner.
///
/// Legacy sources: `NativeToolCatalogEntry`, `NativeTool.openAIToolSchema()`.
/// Canonical targets: `HanlinToolDescriptor` and `HanlinToolCatalogSnapshot`.
/// Missing/malformed function schemas fail; output schemas and rich presentation
/// profiles are reported as findings, never fabricated. Delete after native tools
/// publish canonical descriptors directly.
@MainActor
enum NativeToolCanonicalShadowAdapter {
    static func projectCatalog(
        revision: HanlinCatalogRevision,
        descriptorRevision: HanlinDescriptorRevision
    ) throws -> (HanlinToolCatalogSnapshot, [HanlinShadowFinding]) {
        let catalog = NativeToolCatalog.shared
        let entries = catalog.allEntries()
        var findings: [HanlinShadowFinding] = []
        let projected = try entries.map { entry -> HanlinToolCatalogEntry in
            guard let tool = catalog.tool(named: entry.name, enabledOnly: false) else {
                throw HanlinContractError.invalidSchema(
                    reason: "native catalog entry '\(entry.name)' has no executable source"
                )
            }
            let descriptor = try project(
                tool: tool,
                entry: entry,
                descriptorRevision: descriptorRevision,
                findings: &findings
            )
            return HanlinToolCatalogEntry(
                descriptor: descriptor,
                availability: catalog.isEffectivelyEnabled(entry) ? .available : .disabled,
                modelAlias: entry.name
            )
        }
        return (
            HanlinToolCatalogSnapshot(
                revision: revision,
                generatedAt: .now,
                entries: projected
            ),
            findings
        )
    }

    private static func project(
        tool: NativeTool,
        entry: NativeToolCatalogEntry,
        descriptorRevision: HanlinDescriptorRevision,
        findings: inout [HanlinShadowFinding]
    ) throws -> HanlinToolDescriptor {
        let schema = tool.openAIToolSchema()
        guard let function = schema["function"] as? [String: Any],
              let name = function["name"] as? String,
              name == entry.name,
              let parameters = function["parameters"]
        else {
            throw HanlinContractError.invalidSchema(
                reason: "native tool '\(entry.name)' has an invalid function schema"
            )
        }
        let providerInstanceID: HanlinProviderInstanceID
        let owner: HanlinToolOwner
        if let sourceAppID = entry.sourceAppID {
            let appID = try HanlinAppID(validating: sourceAppID)
            providerInstanceID = try HanlinProviderInstanceID(
                validating: "native.app.\(sourceAppID)"
            )
            owner = .app(appID)
        } else {
            providerInstanceID = try HanlinProviderInstanceID(validating: "native.system")
            owner = .system
        }
        let root = try HanlinFoundationJSONShadowAdapter.project(parameters)
        let document = try HanlinJSONSchemaDocument(
            dialect: .draft2020_12,
            root: root,
            sourceProviderInstanceID: providerInstanceID
        )
        findings.append(.init(
            severity: .information,
            path: "tools/\(entry.name)/outputSchema",
            message: "NativeTool has no declared output schema; no output schema was synthesized."
        ))
        findings.append(.init(
            severity: .information,
            path: "tools/\(entry.name)/presentation",
            message: "The live ToolPresentationProfile remains authoritative and is represented only as an automatic hint."
        ))
        return HanlinToolDescriptor(
            logicalID: HanlinLogicalToolID(
                providerInstanceID: providerInstanceID,
                localToolID: try HanlinToolID(validating: entry.name)
            ),
            descriptorRevision: descriptorRevision,
            owner: owner,
            title: try LocalizedValue(["en": entry.title]),
            summary: try LocalizedValue(["en": entry.summary]),
            inputSchema: document,
            outputSchema: nil,
            risk: entry.isSensitive ? .sensitiveRead : .read,
            presentation: .init(compactStyle: .automatic)
        )
    }
}
