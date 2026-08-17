import CryptoKit
import Foundation
import HanlinPlatformContracts

enum HanlinCanonicalToolAuthorityError: LocalizedError {
    case duplicateLogicalTool(String)
    case invalidAlias(String)
    case invalidModelSchema(String)
    case routeInvariant(String)

    var errorDescription: String? {
        switch self {
        case .duplicateLogicalTool(let identity):
            "Duplicate canonical logical tool: \(identity)"
        case .invalidAlias(let alias):
            "Invalid model-facing tool alias: \(alias)"
        case .invalidModelSchema(let identity):
            "Invalid model schema for canonical tool: \(identity)"
        case .routeInvariant(let reason):
            "Canonical tool route invariant failed: \(reason)"
        }
    }
}

/// The process-local backend route selected by the canonical catalog.
/// Executable objects and runtime sessions never enter portable contracts.
enum HanlinCanonicalToolBackendRoute: Hashable, Sendable {
    case native(providerInstanceID: HanlinProviderInstanceID, toolName: String)
    case mcp(serverID: UUID, toolName: String)

    var providerIdentity: String {
        switch self {
        case .native(let providerInstanceID, _):
            providerInstanceID.rawValue
        case .mcp(let serverID, _):
            serverID.uuidString.lowercased()
        }
    }
}

struct HanlinCanonicalToolBackendTarget: Hashable, Sendable {
    let backend: HanlinCanonicalToolBackendRoute
    let presentationProfile: ToolPresentationProfile
    let resultTitle: String?
}

struct HanlinCanonicalToolBackendRecord: Hashable, Sendable {
    let logicalToolID: HanlinLogicalToolID
    let target: HanlinCanonicalToolBackendTarget
}

struct HanlinCanonicalToolBackendRouteIndex: Sendable {
    let revision: HanlinCatalogRevision
    let records: [HanlinCanonicalToolBackendRecord]

    private let targetsByLogicalID: [
        HanlinLogicalToolID: HanlinCanonicalToolBackendTarget
    ]

    init(
        revision: HanlinCatalogRevision,
        catalog: HanlinToolCatalogSnapshot,
        records: [HanlinCanonicalToolBackendRecord]
    ) throws {
        guard revision == catalog.revision else {
            throw HanlinCanonicalToolAuthorityError.routeInvariant(
                "backend route generation does not match the catalog"
            )
        }
        let grouped = Dictionary(grouping: records, by: \.logicalToolID)
        guard grouped.values.allSatisfy({ $0.count == 1 }) else {
            throw HanlinCanonicalToolAuthorityError.routeInvariant(
                "duplicate backend route"
            )
        }
        let catalogIDs = Set(catalog.entries.map { $0.descriptor.logicalID })
        let backendIDs = Set(grouped.keys)
        guard catalogIDs.count == catalog.entries.count,
              catalogIDs == backendIDs else {
            throw HanlinCanonicalToolAuthorityError.routeInvariant(
                "backend routes are missing or orphaned"
            )
        }
        for record in records where record.target.backend.providerIdentity
            != record.logicalToolID.providerInstanceID.rawValue {
            throw HanlinCanonicalToolAuthorityError.routeInvariant(
                "backend provider does not match \(Self.identity(record.logicalToolID))"
            )
        }

        self.revision = revision
        self.records = records.sorted {
            Self.identity($0.logicalToolID) < Self.identity($1.logicalToolID)
        }
        targetsByLogicalID = Dictionary(uniqueKeysWithValues: records.map {
            ($0.logicalToolID, $0.target)
        })
    }

    func target(
        logicalToolID: HanlinLogicalToolID
    ) -> HanlinCanonicalToolBackendTarget? {
        targetsByLogicalID[logicalToolID]
    }

    private static func identity(_ logicalID: HanlinLogicalToolID) -> String {
        "\(logicalID.providerInstanceID.rawValue)|\(logicalID.localToolID.rawValue)"
    }
}

@MainActor
struct HanlinCanonicalToolAuthority {
    struct NativeSource {
        let entry: NativeToolCatalogEntry
        let canonicalSchema: [String: Any]
        let modelSchema: [String: Any]
        let preferredAlias: String

        init(
            entry: NativeToolCatalogEntry,
            canonicalSchema: [String: Any],
            modelSchema: [String: Any],
            preferredAlias: String? = nil
        ) {
            self.entry = entry
            self.canonicalSchema = canonicalSchema
            self.modelSchema = modelSchema
            self.preferredAlias = preferredAlias ?? entry.name
        }
    }

    struct Resolution {
        let route: HanlinToolRoute
        let backend: HanlinCanonicalToolBackendRoute
        let presentationProfile: ToolPresentationProfile
        let resultTitle: String?
    }

    struct BackendRouteEntry: Hashable, Sendable {
        let route: HanlinToolRoute
        let backend: HanlinCanonicalToolBackendRoute
    }

    let catalog: HanlinToolCatalogSnapshot
    let routingTable: HanlinToolRoutingTable
    let backendRouteIndex: HanlinCanonicalToolBackendRouteIndex
    let modelSchemas: [[String: Any]]

    var backendRoutes: [BackendRouteEntry] {
        routingTable.routes.compactMap { route in
            backendRouteIndex.target(logicalToolID: route.logicalToolID).map {
                BackendRouteEntry(route: route, backend: $0.backend)
            }
        }
    }

    func resolution(alias: String) -> Resolution? {
        guard let route = routingTable.route(alias: alias),
              let target = backendRouteIndex.target(
                logicalToolID: route.logicalToolID
              ) else {
            return nil
        }
        return Resolution(
            route: route,
            backend: target.backend,
            presentationProfile: target.presentationProfile,
            resultTitle: target.resultTitle
        )
    }

    static func build(
        nativeSources: [NativeSource],
        mcpTools: [MCPToolDescriptor],
        generatedAt: Date = .now
    ) throws -> Self {
        let descriptorRevision = try HanlinDescriptorRevision(1)
        var candidates: [Candidate] = []

        for source in nativeSources.sorted(by: { $0.entry.name < $1.entry.name }) {
            let projection = try NativeToolCanonicalShadowAdapter.project(
                schema: source.canonicalSchema,
                entry: source.entry,
                descriptorRevision: descriptorRevision
            )
            let provider = projection.descriptor.logicalID.providerInstanceID
            candidates.append(Candidate(
                descriptor: projection.descriptor,
                preferredAlias: source.preferredAlias,
                modelSchema: source.modelSchema,
                backend: .native(
                    providerInstanceID: provider,
                    toolName: source.entry.name
                ),
                presentationProfile: source.entry.presentationProfile,
                resultTitle: nil,
                precedence: 0,
                discriminator: source.entry.name
            ))
        }

        for tool in mcpTools {
            let descriptor = try MCPCanonicalShadowAdapter.projectTool(
                tool,
                descriptorRevision: descriptorRevision
            )
            let discriminator = "\(tool.serverID.uuidString):\(tool.originalName)"
            let preferredAlias = MCPToolNameCodec.exposedName(
                serverSlug: tool.serverSlug,
                toolName: tool.originalName,
                discriminator: discriminator
            )
            candidates.append(Candidate(
                descriptor: descriptor,
                preferredAlias: preferredAlias,
                modelSchema: try tool.openAIToolSchema(),
                backend: .mcp(
                    serverID: tool.serverID,
                    toolName: tool.originalName
                ),
                presentationProfile: MCPToolBridge.presentationProfile(descriptor: tool),
                resultTitle: tool.title ?? tool.originalName,
                precedence: 1,
                discriminator: discriminator
            ))
        }

        candidates.sort(by: Candidate.precedes)
        try validateLogicalIdentities(candidates)

        var allocatedAliases: Set<String> = []
        var resolved: [ResolvedCandidate] = []
        for candidate in candidates {
            let alias = try allocateAlias(
                for: candidate,
                allocatedAliases: &allocatedAliases
            )
            resolved.append(ResolvedCandidate(
                candidate: candidate,
                alias: alias,
                modelSchema: try schema(candidate.modelSchema, replacingNameWith: alias)
            ))
        }

        let revision = try catalogRevision(for: resolved)
        let entries = resolved.map {
            HanlinToolCatalogEntry(
                descriptor: $0.candidate.descriptor,
                availability: .available,
                modelAlias: $0.alias
            )
        }
        let routes = resolved.map {
            HanlinToolRoute(
                alias: $0.alias,
                logicalToolID: $0.candidate.descriptor.logicalID,
                descriptorRevision: $0.candidate.descriptor.descriptorRevision
            )
        }
        let routingTable = try HanlinToolRoutingTable(
            revision: revision,
            routes: routes
        )
        let catalog = HanlinToolCatalogSnapshot(
            revision: revision,
            generatedAt: generatedAt,
            entries: entries
        )
        let backendRouteIndex = try HanlinCanonicalToolBackendRouteIndex(
            revision: revision,
            catalog: catalog,
            records: resolved.map {
                HanlinCanonicalToolBackendRecord(
                    logicalToolID: $0.candidate.descriptor.logicalID,
                    target: HanlinCanonicalToolBackendTarget(
                        backend: $0.candidate.backend,
                        presentationProfile: $0.candidate.presentationProfile,
                        resultTitle: $0.candidate.resultTitle
                    )
                )
            }
        )
        guard routes.count == entries.count,
              Set(routes.map(\.logicalToolID))
                == Set(entries.map { $0.descriptor.logicalID }) else {
            throw HanlinCanonicalToolAuthorityError.routeInvariant(
                "canonical alias routes do not close over the catalog"
            )
        }
        return Self(
            catalog: catalog,
            routingTable: routingTable,
            backendRouteIndex: backendRouteIndex,
            modelSchemas: resolved.map(\.modelSchema)
        )
    }

    private struct Candidate {
        let descriptor: HanlinToolDescriptor
        let preferredAlias: String
        let modelSchema: [String: Any]
        let backend: HanlinCanonicalToolBackendRoute
        let presentationProfile: ToolPresentationProfile
        let resultTitle: String?
        let precedence: Int
        let discriminator: String

        static func precedes(_ left: Self, _ right: Self) -> Bool {
            if left.precedence != right.precedence {
                return left.precedence < right.precedence
            }
            if left.preferredAlias != right.preferredAlias {
                return left.preferredAlias < right.preferredAlias
            }
            let leftIdentity = "\(left.descriptor.logicalID.providerInstanceID.rawValue)"
                + "|\(left.descriptor.logicalID.localToolID.rawValue)"
            let rightIdentity = "\(right.descriptor.logicalID.providerInstanceID.rawValue)"
                + "|\(right.descriptor.logicalID.localToolID.rawValue)"
            return leftIdentity < rightIdentity
        }
    }

    private struct ResolvedCandidate {
        let candidate: Candidate
        let alias: String
        let modelSchema: [String: Any]
    }

    private static func allocateAlias(
        for candidate: Candidate,
        allocatedAliases: inout Set<String>
    ) throws -> String {
        try validateAlias(candidate.preferredAlias)
        if allocatedAliases.insert(candidate.preferredAlias).inserted {
            return candidate.preferredAlias
        }
        guard case .mcp = candidate.backend else {
            throw HanlinCanonicalToolAuthorityError.routeInvariant(
                "native alias collision at \(candidate.preferredAlias)"
            )
        }

        var attempt = 0
        while true {
            let discriminator = attempt == 0
                ? candidate.discriminator
                : "\(candidate.discriminator):\(attempt)"
            let alias = MCPToolNameCodec.collisionName(
                candidate.preferredAlias,
                discriminator: discriminator
            )
            try validateAlias(alias)
            if allocatedAliases.insert(alias).inserted {
                return alias
            }
            attempt += 1
        }
    }

    private static func validateLogicalIdentities(_ candidates: [Candidate]) throws {
        let grouped = Dictionary(grouping: candidates) {
            identity($0.descriptor.logicalID)
        }
        if let duplicate = grouped.first(where: { $0.value.count != 1 })?.key {
            throw HanlinCanonicalToolAuthorityError.duplicateLogicalTool(duplicate)
        }
    }

    private static func schema(
        _ schema: [String: Any],
        replacingNameWith alias: String
    ) throws -> [String: Any] {
        var result = schema
        guard var function = result["function"] as? [String: Any],
              function["name"] is String,
              function["parameters"] != nil else {
            throw HanlinCanonicalToolAuthorityError.invalidModelSchema(alias)
        }
        function["name"] = alias
        result["function"] = function
        guard JSONSerialization.isValidJSONObject(result) else {
            throw HanlinCanonicalToolAuthorityError.invalidModelSchema(alias)
        }
        return result
    }

    private static func validateAlias(_ alias: String) throws {
        guard alias.range(
            of: #"^[A-Za-z0-9_-]{1,64}$"#,
            options: .regularExpression
        ) != nil else {
            throw HanlinCanonicalToolAuthorityError.invalidAlias(alias)
        }
    }

    private static func catalogRevision(
        for candidates: [ResolvedCandidate]
    ) throws -> HanlinCatalogRevision {
        var material = Data()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for candidate in candidates {
            let descriptor = candidate.candidate.descriptor
            material.append(Data(identity(descriptor.logicalID).utf8))
            material.append(0)
            material.append(Data(candidate.alias.utf8))
            material.append(0)
            material.append(try encoder.encode(descriptor))
            material.append(0)
            material.append(try JSONSerialization.data(
                withJSONObject: candidate.modelSchema,
                options: [.sortedKeys]
            ))
            material.append(0)
        }
        var value: UInt64 = 0
        for byte in SHA256.hash(data: material).prefix(8) {
            value = (value << 8) | UInt64(byte)
        }
        return HanlinCatalogRevision(value == 0 ? 1 : value)
    }

    private static func identity(_ logicalID: HanlinLogicalToolID) -> String {
        "\(logicalID.providerInstanceID.rawValue)|\(logicalID.localToolID.rawValue)"
    }
}
