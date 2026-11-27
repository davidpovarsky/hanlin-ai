import CryptoKit
import Foundation
import HanlinAgentCore
import HanlinChatCore
import HanlinHostContracts
import HanlinPlatformContracts

/// The original application's catalog projection and canonical revision hash.
/// Both hosts use these exact descriptors and original schema bytes.
@MainActor
enum HanlinOriginalToolCatalog {
    static func make(source: (any HanlinOriginalToolSource)?, context: HanlinHostContext,
                     additionalTools: [HanlinHostTool] = []) throws
        -> (catalog: HanlinHostCatalog, definitions: [String: HanlinAISDKToolDefinition]) {
        let available = try source?.allToolDefinitions().sorted { $0.name < $1.name } ?? []
        guard Set(available.map(\.name)).count == available.count else { throw HanlinHostError.duplicateAlias }
        var tools = try available.map { definition -> HanlinHostTool in
            let source = source?.descriptor(for: definition.name)
            let isMeta = [LoadSkillTool.toolName, ReadSkillResourceTool.toolName, ToolSearchTool.toolName,
                ReadToolResultTool.toolName, ToolSchemaDecorator.reportProgressName].contains(definition.name)
            guard source != nil || isMeta else { throw HanlinHostError.unknownTool }
            // Meta tools already have one implementation in the same adapter. Give that existing
            // implementation a stable canonical identity; do not create another meta-tool registry.
            let logical = try source?.logicalID ?? HanlinLogicalToolID(
                providerInstanceID: .init(validating: "hanlin.meta"), localToolID: .init(validating: definition.name))
            let revision = try source?.descriptorRevision ?? HanlinDescriptorRevision(1)
            let input = try HanlinJSONSchemaDocument.decodeCanonicalJSON(definition.inputSchemaData, defaultDialect: .draft2020_12)
            let descriptor = try HanlinToolDescriptor(logicalID: logical, descriptorRevision: revision,
                owner: source?.owner ?? .system, title: source?.title ?? .init(["en": definition.name]),
                summary: source?.summary ?? .init(["en": definition.description]), inputSchema: input,
                outputSchema: source?.outputSchema, capabilities: source?.capabilities ?? [],
                risk: source?.risk ?? .read, presentation: source?.presentation ?? .init(),
                approval: source?.approval)
            // The legacy shadow catalog's .read risk does not establish write behavior
            // (e.g. manage_calendar can write). These two original native MiniApp tools
            // only read SDK/project inputs: validate returns before source/package emission.
            // A compiler diagnostic is a failed read, so preserve its model-visible report
            // instead of converting it into an uncertain write that prevents repair.
            let isMiniAppRead = logical.providerInstanceID.rawValue == "native.system"
                && ["get_miniapp_sdk", "validate_miniapp"].contains(logical.localToolID.rawValue)
            return .init(route: .init(alias: definition.name, logicalToolID: logical, descriptorRevision: revision),
                descriptor: descriptor, writeGuarantee: (isMeta || isMiniAppRead) ? .readOnly : .hostManagedMutation,
                originalInputSchemaJSON: definition.inputSchemaData)
        }
        tools.append(contentsOf: additionalTools)
        guard Set(tools.map { $0.route.alias }).count == tools.count else { throw HanlinHostError.duplicateAlias }
        // JSON dictionaries must be canonical before hashing or unchanged schemas spuriously
        // change the catalog generation. No process-random Hasher is used for public revision.
        let canonicalTools = try tools.map { tool in HanlinJSONValue.object([
            "alias": .string(tool.route.alias),
            // Definition bytes are emitted with sorted keys at the existing declaration boundary.
            // Bind their exact numeric/key content too; the portable descriptor may be lossy.
            "originalSchemaBase64": .string(tool.originalInputSchemaJSON?.base64EncodedString() ?? ""),
            "descriptor": try HanlinJSONValue.decodeCanonicalJSON(JSONEncoder().encode(tool.descriptor))
        ]) }
        let digestInput = try HanlinJSONValue.array(canonicalTools).canonicalJSONData()
        let value = SHA256.hash(data: digestInput).prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        let definitions = Dictionary(uniqueKeysWithValues: available.map { ($0.name, $0) })
        let catalog = HanlinHostCatalog(apiVersion: .init(major: 1, minor: 1), revision: .init(value), context: context, tools: tools)
        try catalog.validate()
        return (catalog, definitions)
    }
}
