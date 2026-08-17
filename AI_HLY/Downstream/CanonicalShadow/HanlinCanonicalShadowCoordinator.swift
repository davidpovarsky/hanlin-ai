import Foundation
import HanlinPlatformContracts

@MainActor
struct HanlinCanonicalShadowCoordinator {
    static let environmentKey = "HANLIN_CANONICAL_SHADOW_CHECKS"

    struct NativeApplicationSource {
        let manifest: NativeAppManifest
        let capabilities: [NativeCapabilityRequest]
    }

    struct NativeToolSource {
        let tool: any NativeTool
        let entry: NativeToolCatalogEntry
    }

    struct MCPRuntimeSource {
        let snapshot: MCPRuntimeSnapshot
        let sessionID: HanlinRuntimeSessionID
        let createdAt: Date
        let observedAt: Date
    }

    struct MCPSource {
        let servers: [MCPServerDescriptor]
        let tools: [MCPToolDescriptor]?
        let runtime: MCPRuntimeSource?
    }

    enum ToolBackend: String, Sendable {
        case native
        case mcp
    }

    struct ToolRouteSource: Sendable {
        let logicalIdentity: String
        let alias: String
        let backend: ToolBackend
        let backendProviderIdentity: String
        let targetExists: Bool
    }

    struct CombinedToolSource {
        let nativeTools: [NativeToolSource]
        let mcpTools: [MCPToolDescriptor]
        let authoritativeCatalog: HanlinToolCatalogSnapshot
        let repeatedCatalog: HanlinToolCatalogSnapshot
        let routingTable: HanlinToolRoutingTable
        let repeatedRoutingTable: HanlinToolRoutingTable
        let routes: [ToolRouteSource]
    }

    struct RuntimeSource {
        let snapshot: RuntimeSnapshot
        let sessionID: HanlinRuntimeSessionID
        let providerInstanceID: HanlinProviderInstanceID
        let createdAt: Date
        let observedAt: Date
    }

    struct Sources {
        var nativeApplications: [NativeApplicationSource]?
        var nativeTools: [NativeToolSource]?
        var mcp: MCPSource?
        var combinedTools: CombinedToolSource?
        var runtimeCore: [RuntimeSource]?

        init(
            nativeApplications: [NativeApplicationSource]? = nil,
            nativeTools: [NativeToolSource]? = nil,
            mcp: MCPSource? = nil,
            combinedTools: CombinedToolSource? = nil,
            runtimeCore: [RuntimeSource]? = nil
        ) {
            self.nativeApplications = nativeApplications
            self.nativeTools = nativeTools
            self.mcp = mcp
            self.combinedTools = combinedTools
            self.runtimeCore = runtimeCore
        }
    }

    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment[environmentKey] == "1"
    }

    static func runIfEnabled(sources: Sources) -> CanonicalShadowReport? {
        guard isEnabled else { return nil }
        let report = run(sources: sources)
        print("HANLIN_CANONICAL_SHADOW \(report.summaryLine)")
        return report
    }

    static func run(sources: Sources) -> CanonicalShadowReport {
        let descriptorRevision: HanlinDescriptorRevision
        do {
            descriptorRevision = try HanlinDescriptorRevision(1)
        } catch {
            return CanonicalShadowReport(domains: [
                projectionFailure(
                    domain: .crossDomainTools,
                    code: "canonical.shadow.invalidRevision"
                )
            ])
        }
        let revision = HanlinCatalogRevision(1)

        let nativeApplications = projectNativeApplications(
            sources.nativeApplications,
            descriptorRevision: descriptorRevision
        )
        let nativeTools = projectNativeTools(
            sources.nativeTools,
            descriptorRevision: descriptorRevision
        )
        let mcp = projectMCP(
            sources.mcp,
            revision: revision,
            descriptorRevision: descriptorRevision
        )
        let runtime = projectRuntimeCore(sources.runtimeCore)
        let crossDomain = projectCombinedTools(sources.combinedTools)

        return CanonicalShadowReport(domains: [
            .skipped(.foundationJSON, code: "foundation.json.directTestsOnly"),
            nativeApplications.report,
            nativeTools.report,
            mcp.report,
            runtime,
            crossDomain
        ])
    }

    private static func projectNativeApplications(
        _ sources: [NativeApplicationSource]?,
        descriptorRevision: HanlinDescriptorRevision
    ) -> (report: CanonicalShadowDomainReport, items: [CanonicalShadowItem]?) {
        guard let sources else {
            return (
                .skipped(
                    .nativeApplications,
                    code: "native.applications.notObservable"
                ),
                nil
            )
        }
        do {
            let version = try HanlinPackageVersion(validating: "0.7.3")
            let first = try sources.map {
                try NativeAppCanonicalShadowAdapter.project(
                    manifest: $0.manifest,
                    capabilities: $0.capabilities,
                    hostVersion: version,
                    descriptorRevision: descriptorRevision
                )
            }
            let repeated = try sources.map {
                try NativeAppCanonicalShadowAdapter.project(
                    manifest: $0.manifest,
                    capabilities: $0.capabilities,
                    hostVersion: version,
                    descriptorRevision: descriptorRevision
                )
            }
            let sourceItems = sources.map {
                CanonicalShadowItem(identity: $0.manifest.id)
            }
            let firstItems = first.map {
                CanonicalShadowItem(
                    identity: $0.descriptor.id.rawValue,
                    descriptorRevision: $0.descriptor.descriptorRevision.rawValue
                )
            }
            let repeatedItems = repeated.map {
                CanonicalShadowItem(
                    identity: $0.descriptor.id.rawValue,
                    descriptorRevision: $0.descriptor.descriptorRevision.rawValue
                )
            }
            let findings = first.flatMap(\.findings).map {
                CanonicalShadowFinding(
                    severity: $0.severity == .warning ? .warning : .information,
                    code: "native.applications.projectionOmission",
                    path: $0.path,
                    message: "A native-only field is intentionally not projected."
                )
            }
            return (
                CanonicalShadowComparison.compare(
                    domain: .nativeApplications,
                    source: sourceItems,
                    projected: firstItems,
                    repeatedProjection: repeatedItems,
                    additionalFindings: findings
                ),
                firstItems
            )
        } catch {
            return (
                projectionFailure(
                    domain: .nativeApplications,
                    code: "native.applications.projectionFailed"
                ),
                nil
            )
        }
    }

    private static func projectNativeTools(
        _ sources: [NativeToolSource]?,
        descriptorRevision: HanlinDescriptorRevision
    ) -> (report: CanonicalShadowDomainReport, items: [CanonicalShadowItem]?) {
        guard let sources else {
            return (
                .skipped(.nativeTools, code: "native.tools.notObservable"),
                nil
            )
        }
        do {
            let first = try sources.map {
                try NativeToolCanonicalShadowAdapter.project(
                    tool: $0.tool,
                    entry: $0.entry,
                    descriptorRevision: descriptorRevision
                )
            }
            let repeated = try sources.map {
                try NativeToolCanonicalShadowAdapter.project(
                    tool: $0.tool,
                    entry: $0.entry,
                    descriptorRevision: descriptorRevision
                )
            }
            let sourceItems = try sources.map { source in
                let provider = try nativeProviderIdentity(for: source.entry)
                return CanonicalShadowItem(
                    identity: logicalIdentity(provider: provider, local: source.entry.name),
                    alias: source.entry.name,
                    providerIdentity: provider
                )
            }
            let firstItems = first.map(toolItem)
            let repeatedItems = repeated.map(toolItem)
            let findings = first.flatMap(\.findings).map {
                CanonicalShadowFinding(
                    severity: $0.severity == .warning ? .warning : .information,
                    code: "native.tools.projectionOmission",
                    path: $0.path,
                    message: "A native-only field is intentionally not projected."
                )
            }
            return (
                CanonicalShadowComparison.compare(
                    domain: .nativeTools,
                    source: sourceItems,
                    projected: firstItems,
                    repeatedProjection: repeatedItems,
                    additionalFindings: findings
                ),
                firstItems
            )
        } catch {
            return (
                projectionFailure(
                    domain: .nativeTools,
                    code: "native.tools.projectionFailed"
                ),
                nil
            )
        }
    }

    private static func projectMCP(
        _ source: MCPSource?,
        revision: HanlinCatalogRevision,
        descriptorRevision: HanlinDescriptorRevision
    ) -> (report: CanonicalShadowDomainReport, items: [CanonicalShadowItem]?) {
        guard let source else {
            return (.skipped(.mcp, code: "mcp.notObservable"), nil)
        }
        do {
            let firstProviders = try source.servers.map(
                MCPCanonicalShadowAdapter.projectProvider
            )
            let repeatedProviders = try source.servers.map(
                MCPCanonicalShadowAdapter.projectProvider
            )
            let sourceProviderItems = source.servers.map {
                CanonicalShadowItem(identity: $0.id.uuidString.lowercased())
            }
            let firstProviderItems = firstProviders.map {
                CanonicalShadowItem(
                    identity: $0.id.rawValue,
                    providerIdentity: $0.providerID.rawValue
                )
            }
            let repeatedProviderItems = repeatedProviders.map {
                CanonicalShadowItem(
                    identity: $0.id.rawValue,
                    providerIdentity: $0.providerID.rawValue
                )
            }
            var providerFindings: [CanonicalShadowFinding] = []
            if firstProviders.contains(where: { $0.providerID.rawValue != "mcp" }) {
                providerFindings.append(.init(
                    severity: .mismatch,
                    code: "mcp.providerMismatch",
                    path: "mcp/providers",
                    message: "An MCP source projected to a non-MCP provider identity."
                ))
            }
            let providerReport = CanonicalShadowComparison.compare(
                domain: .mcp,
                source: sourceProviderItems,
                projected: firstProviderItems,
                repeatedProjection: repeatedProviderItems,
                additionalFindings: providerFindings
            )

            guard let tools = source.tools else {
                let warning = CanonicalShadowFinding(
                    severity: .warning,
                    code: "mcp.tools.notObservable",
                    path: "mcp/tools",
                    message: "No already-discovered MCP tool snapshot was available."
                )
                return (
                    .init(
                        domain: .mcp,
                        sourceCount: providerReport.sourceCount,
                        projectedCount: providerReport.projectedCount,
                        findings: providerReport.findings + [warning]
                    ),
                    nil
                )
            }

            let firstTools = try MCPCanonicalShadowAdapter.projectTools(
                tools,
                revision: revision,
                descriptorRevision: descriptorRevision
            )
            let repeatedTools = try MCPCanonicalShadowAdapter.projectTools(
                tools,
                revision: revision,
                descriptorRevision: descriptorRevision
            )
            let sourceToolItems = tools.map {
                let provider = $0.serverID.uuidString.lowercased()
                return CanonicalShadowItem(
                    identity: logicalIdentity(provider: provider, local: $0.originalName),
                    alias: $0.exposedName,
                    providerIdentity: provider
                )
            }
            let firstToolItems = firstTools.entries.map(toolItem)
            let repeatedToolItems = repeatedTools.entries.map(toolItem)
            let toolReport = CanonicalShadowComparison.compare(
                domain: .mcp,
                source: sourceToolItems,
                projected: firstToolItems,
                repeatedProjection: repeatedToolItems
            )

            var runtimeFindings: [CanonicalShadowFinding] = []
            if let runtime = source.runtime {
                let first = try MCPCanonicalShadowAdapter.projectRuntime(
                    runtime.snapshot,
                    sessionID: runtime.sessionID,
                    createdAt: runtime.createdAt,
                    observedAt: runtime.observedAt
                )
                let repeated = try MCPCanonicalShadowAdapter.projectRuntime(
                    runtime.snapshot,
                    sessionID: runtime.sessionID,
                    createdAt: runtime.createdAt,
                    observedAt: runtime.observedAt
                )
                if first != repeated {
                    runtimeFindings.append(.init(
                        severity: .mismatch,
                        code: "mcp.runtime.identityInstability",
                        path: "mcp/runtime/\(runtime.sessionID.rawValue)",
                        message: "Repeated MCP runtime projection was not stable."
                    ))
                }
            }

            return (
                .init(
                    domain: .mcp,
                    sourceCount: (providerReport.sourceCount ?? 0) + (toolReport.sourceCount ?? 0),
                    projectedCount: (providerReport.projectedCount ?? 0)
                        + (toolReport.projectedCount ?? 0),
                    findings: providerReport.findings
                        + toolReport.findings
                        + runtimeFindings
                ),
                firstToolItems
            )
        } catch {
            return (
                projectionFailure(domain: .mcp, code: "mcp.projectionFailed"),
                nil
            )
        }
    }

    private static func projectRuntimeCore(
        _ sources: [RuntimeSource]?
    ) -> CanonicalShadowDomainReport {
        guard let sources else {
            return .skipped(.runtimeCore, code: "runtime.core.notObservable")
        }
        let sourceItems = sources.map {
            CanonicalShadowItem(
                identity: $0.sessionID.rawValue,
                providerIdentity: $0.providerInstanceID.rawValue
            )
        }
        let first = sources.map {
            RuntimeCoreCanonicalShadowAdapter.project(
                $0.snapshot,
                sessionID: $0.sessionID,
                providerInstanceID: $0.providerInstanceID,
                createdAt: $0.createdAt,
                observedAt: $0.observedAt
            )
        }
        let repeated = sources.map {
            RuntimeCoreCanonicalShadowAdapter.project(
                $0.snapshot,
                sessionID: $0.sessionID,
                providerInstanceID: $0.providerInstanceID,
                createdAt: $0.createdAt,
                observedAt: $0.observedAt
            )
        }
        return CanonicalShadowComparison.compare(
            domain: .runtimeCore,
            source: sourceItems,
            projected: first.map(runtimeItem),
            repeatedProjection: repeated.map(runtimeItem)
        )
    }

    private static func projectCombinedTools(
        _ source: CombinedToolSource?
    ) -> CanonicalShadowDomainReport {
        guard let source else {
            return .skipped(
                .crossDomainTools,
                code: "cross-domain.tools.notObservable"
            )
        }
        do {
            let sourceItems = try source.nativeTools.map { native in
                let provider = try NativeToolCanonicalShadowAdapter
                    .providerInstanceID(for: native.entry).rawValue
                return CanonicalShadowItem(
                    identity: logicalIdentity(
                        provider: provider,
                        local: native.entry.name
                    ),
                    alias: native.entry.name,
                    providerIdentity: provider
                )
            } + source.mcpTools.map { tool in
                let provider = tool.serverID.uuidString.lowercased()
                return CanonicalShadowItem(
                    identity: logicalIdentity(
                        provider: provider,
                        local: tool.originalName
                    ),
                    alias: tool.exposedName,
                    providerIdentity: provider
                )
            }
            let projectedItems = source.authoritativeCatalog.entries.map(toolItem)
            let repeatedItems = source.repeatedCatalog.entries.map(toolItem)

            return CanonicalShadowComparison.compare(
                domain: .crossDomainTools,
                source: sourceItems,
                projected: projectedItems,
                repeatedProjection: repeatedItems,
                compareAliases: true,
                compareProviders: true,
                additionalFindings: routeFindings(
                    projectedItems: projectedItems,
                    catalogRevision: source.authoritativeCatalog.revision,
                    routingTable: source.routingTable,
                    repeatedRoutingTable: source.repeatedRoutingTable,
                    routes: source.routes
                )
            )
        } catch {
            return projectionFailure(
                domain: .crossDomainTools,
                code: "cross-domain.tools.projectionFailed"
            )
        }
    }

    private static func routeFindings(
        projectedItems: [CanonicalShadowItem],
        catalogRevision: HanlinCatalogRevision,
        routingTable: HanlinToolRoutingTable,
        repeatedRoutingTable: HanlinToolRoutingTable,
        routes: [ToolRouteSource]
    ) -> [CanonicalShadowFinding] {
        var findings: [CanonicalShadowFinding] = []
        let projectedIdentities = Set(projectedItems.map(\.identity))
        let projectedAliases = Set(projectedItems.compactMap(\.alias))
        let routesByIdentity = Dictionary(grouping: routes, by: \.logicalIdentity)
        let routesByAlias = Dictionary(grouping: routes, by: \.alias)

        if routingTable.revision != catalogRevision {
            findings.append(.init(
                severity: .mismatch,
                code: "cross-domain.tools.routeRevisionMismatch",
                path: "cross-domain.tools/routes",
                message: "The catalog and routing table revisions differ."
            ))
        }
        if routingTable != repeatedRoutingTable {
            findings.append(.init(
                severity: .mismatch,
                code: "cross-domain.tools.routeInstability",
                path: "cross-domain.tools/routes",
                message: "Repeated routing-table construction was not stable."
            ))
        }
        let canonicalRoutePairs = Set(routingTable.routes.map {
            "\($0.alias)|\(logicalIdentity(
                provider: $0.logicalToolID.providerInstanceID.rawValue,
                local: $0.logicalToolID.localToolID.rawValue
            ))"
        })
        let backendRoutePairs = Set(routes.map {
            "\($0.alias)|\($0.logicalIdentity)"
        })
        if canonicalRoutePairs != backendRoutePairs {
            findings.append(.init(
                severity: .mismatch,
                code: "cross-domain.tools.backendRouteIndexMismatch",
                path: "cross-domain.tools/routes",
                message: "The canonical routing table and backend route index differ."
            ))
        }

        for identity in projectedIdentities.sorted()
        where routesByIdentity[identity]?.count != 1 {
            findings.append(.init(
                severity: .mismatch,
                code: "cross-domain.tools.routeCountMismatch",
                path: "cross-domain.tools/routes/\(identity)",
                message: "Every exposed canonical tool must have exactly one backend route."
            ))
        }
        for identity in routesByIdentity.keys.sorted()
        where !projectedIdentities.contains(identity) {
            findings.append(.init(
                severity: .mismatch,
                code: "cross-domain.tools.orphanedRoute",
                path: "cross-domain.tools/routes/\(identity)",
                message: "A backend route does not belong to an exposed canonical tool."
            ))
        }
        for alias in routesByAlias.keys.sorted() where routesByAlias[alias]?.count != 1 {
            findings.append(.init(
                severity: .mismatch,
                code: "cross-domain.tools.routeAliasCollision",
                path: "cross-domain.tools/routes/aliases/\(alias)",
                message: "A model-facing alias must resolve to exactly one backend route."
            ))
        }
        for alias in routesByAlias.keys.sorted() where !projectedAliases.contains(alias) {
            findings.append(.init(
                severity: .mismatch,
                code: "cross-domain.tools.routeAliasMismatch",
                path: "cross-domain.tools/routes/aliases/\(alias)",
                message: "A backend route alias is not exposed by the canonical projection."
            ))
        }
        for route in routes.sorted(by: { $0.alias < $1.alias }) {
            if !route.targetExists {
                findings.append(.init(
                    severity: .mismatch,
                    code: "cross-domain.tools.missingRouteTarget",
                    path: "cross-domain.tools/routes/\(route.logicalIdentity)",
                    message: "The selected backend route target does not exist."
                ))
            }
            let provider = route.logicalIdentity.split(
                separator: "|",
                maxSplits: 1
            ).first.map(String.init)
            if provider != route.backendProviderIdentity
                || (route.backend == .native
                    && route.backendProviderIdentity.hasPrefix("native.") == false)
                || (route.backend == .mcp
                    && route.backendProviderIdentity.hasPrefix("native.")) {
                findings.append(.init(
                    severity: .mismatch,
                    code: "cross-domain.tools.backendProviderMismatch",
                    path: "cross-domain.tools/routes/\(route.logicalIdentity)",
                    message: "A backend route does not match its canonical provider identity."
                ))
            }
        }
        return findings
    }

    private static func projectionFailure(
        domain: CanonicalShadowDomain,
        code: String
    ) -> CanonicalShadowDomainReport {
        .init(
            domain: domain,
            findings: [
                .init(
                    severity: .mismatch,
                    code: code,
                    path: domain.rawValue,
                    message: "The read-only canonical projection failed."
                )
            ]
        )
    }

    private static func toolItem(
        _ projection: NativeToolCanonicalShadowProjection
    ) -> CanonicalShadowItem {
        toolItem(
            HanlinToolCatalogEntry(
                descriptor: projection.descriptor,
                availability: .available,
                modelAlias: projection.descriptor.logicalID.localToolID.rawValue
            )
        )
    }

    private static func toolItem(_ entry: HanlinToolCatalogEntry) -> CanonicalShadowItem {
        let logicalID = entry.descriptor.logicalID
        return CanonicalShadowItem(
            identity: logicalIdentity(
                provider: logicalID.providerInstanceID.rawValue,
                local: logicalID.localToolID.rawValue
            ),
            alias: entry.modelAlias,
            providerIdentity: logicalID.providerInstanceID.rawValue,
            descriptorRevision: entry.descriptor.descriptorRevision.rawValue
        )
    }

    private static func runtimeItem(
        _ descriptor: HanlinRuntimeSessionDescriptor
    ) -> CanonicalShadowItem {
        CanonicalShadowItem(
            identity: descriptor.id.rawValue,
            providerIdentity: descriptor.providerInstanceID.rawValue
        )
    }

    private static func nativeProviderIdentity(
        for entry: NativeToolCatalogEntry
    ) throws -> String {
        if let sourceAppID = entry.sourceAppID {
            return try HanlinProviderInstanceID(
                validating: "native.app.\(sourceAppID)"
            ).rawValue
        }
        return "native.system"
    }

    private static func logicalIdentity(provider: String, local: String) -> String {
        "\(provider)|\(local)"
    }
}
