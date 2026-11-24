import Foundation

/// Metadata for a dedicated MiniApp assistant entrypoint. Loading this metadata
/// is sufficient for selection; executing its source is reserved for a tool call.
public struct HanlinAssistantToolDeclaration: Codable, Hashable, Sendable {
    public var title: String
    public var summary: String
    public var actions: [HanlinAssistantToolAction]
    public var configuration: HanlinComposerConfiguration?

    public init(
        title: String,
        summary: String,
        actions: [HanlinAssistantToolAction],
        configuration: HanlinComposerConfiguration? = nil
    ) {
        self.title = title
        self.summary = summary
        self.actions = actions
        self.configuration = configuration
    }

    public func validateDefinition() throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !actions.isEmpty else {
            throw HanlinContractError.invalidSchema(reason: "assistantTool requires a title, summary and at least one action")
        }
        var identifiers = Set<String>()
        for action in actions {
            guard HanlinActionID(rawValue: action.id) != nil, identifiers.insert(action.id).inserted,
                  !action.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !action.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  action.exportedSymbol?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != true,
                  action.embeddedResultID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != true else {
                throw HanlinContractError.invalidSchema(reason: "assistantTool actions require unique valid IDs, a title, summary and a nonempty handler")
            }
            guard case let .object(schema) = action.inputSchema.root,
                  case .string("object")? = schema["type"] else {
                throw HanlinContractError.invalidSchema(reason: "assistantTool action inputSchema must describe an object")
            }
        }
        try configuration?.validateDefinition()
    }
}

/// Uses the canonical JSON Schema type internally and ordinary JSON Schema
/// objects in script.json so authors do not need the native Codable envelope.
public struct HanlinAssistantToolAction: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var summary: String
    public var inputSchema: HanlinJSONSchemaDocument
    public var outputSchema: HanlinJSONSchemaDocument?
    /// Registered Host Services action name. If absent, use this action's ID.
    public var exportedSymbol: String?
    /// Exact declared embeddedResult entrypoint used by the existing rich-result host.
    public var embeddedResultID: String?

    public init(
        id: String,
        title: String,
        summary: String,
        inputSchema: HanlinJSONSchemaDocument,
        outputSchema: HanlinJSONSchemaDocument? = nil,
        exportedSymbol: String? = nil,
        embeddedResultID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema
        self.exportedSymbol = exportedSymbol
        self.embeddedResultID = embeddedResultID
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, summary, inputSchema, outputSchema, exportedSymbol, embeddedResultID
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        summary = try values.decode(String.self, forKey: .summary)
        inputSchema = try Self.schema(values.decode(HanlinJSONValue.self, forKey: .inputSchema))
        outputSchema = try values.decodeIfPresent(HanlinJSONValue.self, forKey: .outputSchema).map(Self.schema)
        exportedSymbol = try values.decodeIfPresent(String.self, forKey: .exportedSymbol)
        embeddedResultID = try values.decodeIfPresent(String.self, forKey: .embeddedResultID)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(title, forKey: .title)
        try values.encode(summary, forKey: .summary)
        try values.encode(inputSchema.root, forKey: .inputSchema)
        try values.encodeIfPresent(outputSchema?.root, forKey: .outputSchema)
        try values.encodeIfPresent(exportedSymbol, forKey: .exportedSymbol)
        try values.encodeIfPresent(embeddedResultID, forKey: .embeddedResultID)
    }

    private static func schema(_ root: HanlinJSONValue) throws -> HanlinJSONSchemaDocument {
        try HanlinJSONSchemaDocument.decodeCanonicalJSON(
            root.canonicalJSONData(), defaultDialect: .draft2020_12
        )
    }
}
