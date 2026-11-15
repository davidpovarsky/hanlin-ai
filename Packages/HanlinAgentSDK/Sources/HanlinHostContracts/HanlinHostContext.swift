import Foundation
import HanlinPlatformContracts

public enum HanlinHostError: String, Error, Codable, Sendable, LocalizedError {
    case unsupportedVersion, invalidContext, staleContext, unknownTool, duplicateAlias
    case unsupportedConditionalWrite, invalidArguments, denied, cancelled, deadlineExceeded
    case duplicateInvocation, idempotencyConflict, resultMismatch, outputLimitExceeded
    case unresolvedWrite, unsupportedProviderCapability, storeConflict, invalidRecord, storageLimitExceeded
    public var errorDescription: String? {
        switch self {
        case .staleContext, .invalidContext: "The original account, Space, document or scene is no longer current."
        case .unsupportedConditionalWrite: "This host cannot perform an atomic conditional edit. No write was dispatched."
        case .unresolvedWrite: "A previous operation may have committed. Reconcile it in the original context before retrying."
        case .denied: "The host denied this operation."
        case .cancelled: "The operation was cancelled; a dispatched write may still need reconciliation."
        case .unknownTool, .duplicateAlias: "The scoped tool catalog is unavailable or invalid."
        case .duplicateInvocation, .idempotencyConflict: "This call is already reserved or conflicts with an earlier call. It was not repeated."
        case .unsupportedVersion: "This host or conversation format version is not supported."
        case .invalidArguments: "The requested arguments are not valid for this operation."
        case .deadlineExceeded: "The host operation exceeded its deadline."
        case .resultMismatch: "The host result does not match the original request."
        case .outputLimitExceeded: "The host result exceeds the allowed output size."
        case .unsupportedProviderCapability: "The selected provider does not support this request."
        case .storeConflict: "The conversation changed during saving. Reload it before continuing."
        case .invalidRecord: "The stored conversation could not be validated. Original data was preserved."
        case .storageLimitExceeded: "The conversation exceeds the configured storage limit."
        }
    }
}

/// Exact opaque identity, never sanitized into a different account or Space.
public struct HanlinConversationNamespace: Codable, Hashable, Sendable {
    public let app: String
    public let account: String
    public let workspace: String
    public let space: String

    public init(app: String, account: String, workspace: String, space: String) throws {
        guard [app, account, workspace, space].allSatisfy({ !$0.isEmpty && $0.utf8.count <= 128 }) else {
            throw HanlinHostError.invalidContext
        }
        self.app = app; self.account = account; self.workspace = workspace; self.space = space
    }

    private enum CodingKeys: String, CodingKey { case app, account, workspace, space }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(app: c.decode(String.self, forKey: .app), account: c.decode(String.self, forKey: .account),
                      workspace: c.decode(String.self, forKey: .workspace), space: c.decode(String.self, forKey: .space))
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        zip([lhs.app, lhs.account, lhs.workspace, lhs.space], [rhs.app, rhs.account, rhs.workspace, rhs.space])
            .allSatisfy { $0.utf8.elementsEqual($1.utf8) }
    }
    public func hash(into hasher: inout Hasher) {
        for value in [app, account, workspace, space] { hasher.combine(Data(value.utf8)) }
    }
}

/// Issued by the presenting host. Changing auth/Space/selection must invalidate generation.
/// A local source revision is freshness evidence, not a native compare-and-swap guarantee.
public struct HanlinHostContext: Codable, Hashable, Sendable {
    public let namespace: HanlinConversationNamespace
    public let sceneID: UUID
    public let generation: UUID
    public let objectReference: String?
    public let selectionReferences: [String]
    public let sourceRevision: String?
    public let localeIdentifier: String

    public init(namespace: HanlinConversationNamespace, sceneID: UUID, generation: UUID,
                objectReference: String? = nil, selectionReferences: [String] = [],
                sourceRevision: String? = nil, localeIdentifier: String = "en") {
        self.namespace = namespace; self.sceneID = sceneID; self.generation = generation
        self.objectReference = objectReference; self.selectionReferences = selectionReferences
        self.sourceRevision = sourceRevision; self.localeIdentifier = localeIdentifier
    }
    public func matchesRevision(_ revision: String?) -> Bool { sourceRevision.map { Data($0.utf8) } == revision.map { Data($0.utf8) } }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.namespace == rhs.namespace && lhs.sceneID == rhs.sceneID && lhs.generation == rhs.generation &&
        lhs.objectReference.map { Data($0.utf8) } == rhs.objectReference.map { Data($0.utf8) } &&
        lhs.selectionReferences.map { Data($0.utf8) } == rhs.selectionReferences.map { Data($0.utf8) } &&
        lhs.matchesRevision(rhs.sourceRevision) && lhs.localeIdentifier.utf8.elementsEqual(rhs.localeIdentifier.utf8)
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(namespace); hasher.combine(sceneID); hasher.combine(generation)
        hasher.combine(objectReference.map { Data($0.utf8) }); hasher.combine(selectionReferences.map { Data($0.utf8) })
        hasher.combine(sourceRevision.map { Data($0.utf8) }); hasher.combine(Data(localeIdentifier.utf8))
    }
}

public struct HanlinHostSession: Codable, Hashable, Sendable {
    public let id: UUID
    public let conversationID: UUID
    public let context: HanlinHostContext
    public init(id: UUID = UUID(), conversationID: UUID, context: HanlinHostContext) {
        self.id = id; self.conversationID = conversationID; self.context = context
    }
}

public enum HanlinHostWriteGuarantee: String, Codable, Sendable {
    case readOnly, independentObjectCreation, atomicRevisionMutation
    /// General/external mutation delegated to the original host. No CAS, remote
    /// idempotency or rollback is promised; ambiguous post-dispatch outcomes are uncertain.
    case hostManagedMutation
}

public struct HanlinHostTool: Sendable {
    public let route: HanlinToolRoute
    public let descriptor: HanlinToolDescriptor
    public let writeGuarantee: HanlinHostWriteGuarantee
    /// Optional original host schema before the portable descriptor projection. This is not
    /// evidence of an external provider's source fidelity; the Host owns that provenance check.
    public let originalInputSchemaJSON: Data?
    public init(route: HanlinToolRoute, descriptor: HanlinToolDescriptor, writeGuarantee: HanlinHostWriteGuarantee,
                originalInputSchemaJSON: Data? = nil) {
        self.originalInputSchemaJSON = originalInputSchemaJSON
        self.route = route; self.descriptor = descriptor; self.writeGuarantee = writeGuarantee
    }
}

/// A scoped projection of host authority, not another registry or permission store.
public struct HanlinHostCatalog: Sendable {
    public let apiVersion: HanlinAPIVersion
    public let revision: HanlinCatalogRevision
    public let context: HanlinHostContext
    public let tools: [HanlinHostTool]
    public init(apiVersion: HanlinAPIVersion = .init(major: 1, minor: 0), revision: HanlinCatalogRevision,
                context: HanlinHostContext, tools: [HanlinHostTool]) {
        self.apiVersion = apiVersion; self.revision = revision; self.context = context; self.tools = tools
    }

    public func validate() throws {
        guard apiVersion.major == 1 else { throw HanlinHostError.unsupportedVersion }
        guard apiVersion.minor >= 1 || !tools.contains(where: { $0.writeGuarantee == .hostManagedMutation }) else {
            throw HanlinHostError.unsupportedVersion
        }
        var aliases = Set<String>()
        var identities = Set<HanlinLogicalToolID>()
        for tool in tools {
            guard !tool.route.alias.isEmpty, tool.route.alias.utf8.count <= 128,
                  aliases.insert(tool.route.alias).inserted,
                  identities.insert(tool.route.logicalToolID).inserted else { throw HanlinHostError.duplicateAlias }
            guard tool.route.logicalToolID == tool.descriptor.logicalID,
                  tool.route.descriptorRevision == tool.descriptor.descriptorRevision else { throw HanlinHostError.invalidArguments }
            if tool.writeGuarantee == .readOnly && ![.passive, .read, .sensitiveRead].contains(tool.descriptor.risk) {
                throw HanlinHostError.invalidArguments
            }
        }
    }
}
