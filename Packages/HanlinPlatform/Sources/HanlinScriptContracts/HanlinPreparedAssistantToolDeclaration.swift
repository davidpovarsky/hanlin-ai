import Foundation
import HanlinPlatformContracts

/// One installed prepared action exposed through the normal assistant tool route.
/// This declaration carries metadata only; the original runtime executes its handler.
public struct HanlinPreparedAssistantToolDeclaration: Hashable, Sendable {
    public let action: HanlinActionDescriptor
    public let summary: LocalizedValue

    public init(
        manifest: HanlinScriptingManifest,
        entrypoint: HanlinPackageEntrypointDescriptor,
        entrypoints: [HanlinPackageEntrypointDescriptor]
    ) throws {
        guard entrypoint.kind == .assistantTool,
              [.hanlinExpo, .hanlinNativeScript].contains(entrypoint.runtimeProfile),
              entrypoint.runtimePolicyID == "prepared-foreground-action-v1",
              entrypoint.supportedContexts.contains(.mainApplication),
              entrypoints.filter({ $0.kind == .app &&
                  $0.runtimeProfile == entrypoint.runtimeProfile &&
                  $0.sourcePath == entrypoint.sourcePath }).count == 1,
              let name = entrypoint.exportedSymbol, !name.isEmpty,
              case let .array(items)? = manifest.unknownFields["actions"] else {
            throw HanlinPreparedAssistantToolError.invalidDeclaration
        }
        let actionID = try HanlinActionID(validating: name)
        let matching = items.compactMap { item -> HanlinObject<HanlinJSONValue>? in
            guard case let .object(fields) = item, fields["id"] == .string(name) else { return nil }
            return fields
        }
        guard matching.count == 1, let fields = matching.first else {
            throw HanlinPreparedAssistantToolError.invalidDeclaration
        }
        let declaredHandler: String?
        if case let .string(value)? = fields["handler"] { declaredHandler = value }
        else if case let .string(value)? = fields["entrypoint"] { declaredHandler = value }
        else { declaredHandler = nil }
        guard let declaredHandler,
              declaredHandler == entrypoint.sourcePath || "source/" + declaredHandler == entrypoint.sourcePath,
              let inputRoot = fields["inputSchema"],
              case let .object(inputMembers) = inputRoot,
              inputMembers["type"] == .string("object") else {
            throw HanlinPreparedAssistantToolError.invalidDeclaration
        }
        let inputSchema = try HanlinJSONSchemaDocument.decodeCanonicalJSON(
            inputRoot.canonicalJSONData(), defaultDialect: .draft2020_12)
        let outputSchema = try fields["outputSchema"].map {
            try HanlinJSONSchemaDocument.decodeCanonicalJSON(
                $0.canonicalJSONData(), defaultDialect: .draft2020_12)
        }
        let titleText: String
        if case let .string(value)? = fields["title"] { titleText = value }
        else { titleText = name }
        let summaryText: String
        if case let .string(value)? = fields["summary"] { summaryText = value }
        else if case let .string(value)? = fields["description"] { summaryText = value }
        else { summaryText = titleText }
        let capability: HanlinCapabilityID
        if let value = fields["capability"] {
            guard case let .string(raw) = value else { throw HanlinPreparedAssistantToolError.invalidDeclaration }
            capability = try HanlinCapabilityID(validating: raw)
        } else {
            capability = try HanlinCapabilityID(validating: "inter-app.share")
        }
        action = HanlinActionDescriptor(
            id: actionID, title: try LocalizedValue(["en": titleText]),
            inputSchema: inputSchema, outputSchema: outputSchema, capabilities: [capability],
            handler: entrypoint.sourcePath, risk: .read)
        summary = try LocalizedValue(["en": summaryText])
    }
}

public enum HanlinPreparedAssistantToolError: Error, Equatable, LocalizedError, Sendable {
    case invalidDeclaration
    case invalidArguments
    case staleInstallation

    public var errorDescription: String? {
        switch self {
        case .invalidDeclaration:
            "An assistantTool must name one prepared foreground action with inputSchema.type set to object. Its optional outputSchema is a JSON Schema document and may describe any JSON result."
        case .invalidArguments:
            "Mini app tool arguments must be a JSON object matching the declared inputSchema."
        case .staleInstallation:
            "This installed mini app tool has changed or is no longer enabled. Refresh the tool catalog."
        }
    }
}
